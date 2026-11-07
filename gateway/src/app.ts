import type { IncomingMessage, ServerResponse } from 'node:http';

import { authenticate } from './auth.ts';
import type { GatewayConfig } from './config.ts';
import { RateLimiter, UsageLedger, costUsd, estimateInputTokens } from './limits.ts';
import { UpstreamError, callResponses, type ChatMessage, type FetchLike } from './openai.ts';

export const VERSION = '0.2.0';
const MAX_BODY_BYTES = 64 * 1024;
const MAX_MESSAGES = 20;
const MAX_TEXT_CHARS = 4000;

export interface AppDeps {
  config: GatewayConfig;
  fetch: FetchLike;
  now?: () => number;
  /** Yalnızca meta veri loglanır; içerik ASLA. */
  log?: (entry: Record<string, unknown>) => void;
}

class HttpError extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

function send(res: ServerResponse, status: number, body: unknown): void {
  const json = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
    'content-length': Buffer.byteLength(json),
  });
  res.end(json);
}

async function readJson(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    const b = chunk as Buffer;
    size += b.length;
    if (size > MAX_BODY_BYTES) throw new HttpError(413, 'payload_too_large', 'İstek çok büyük');
    chunks.push(b);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HttpError(400, 'bad_request', 'Geçersiz JSON');
  }
}

interface ValidRequest {
  model: string;
  instructions: string;
  messages: ChatMessage[];
  maxOutputTokens: number;
  webSearch: boolean;
}

function validate(body: unknown, cfg: GatewayConfig): ValidRequest {
  if (typeof body !== 'object' || body === null) throw new HttpError(400, 'bad_request', 'Gövde nesne olmalı');
  const b = body as Record<string, unknown>;
  const model = typeof b.model === 'string' && b.model.trim() ? b.model.trim() : cfg.defaultModel;
  if (!cfg.allowedModels.includes(model)) throw new HttpError(400, 'model_not_allowed', 'Model izinli değil');
  const instructions = typeof b.instructions === 'string' ? b.instructions : '';
  if (instructions.length > MAX_TEXT_CHARS) throw new HttpError(413, 'payload_too_large', 'Talimat çok uzun');
  if (!Array.isArray(b.messages) || b.messages.length === 0 || b.messages.length > MAX_MESSAGES) {
    throw new HttpError(400, 'bad_request', `messages 1-${MAX_MESSAGES} öğe olmalı`);
  }
  const messages: ChatMessage[] = b.messages.map((m: unknown) => {
    const mm = m as { role?: unknown; text?: unknown };
    if ((mm.role !== 'user' && mm.role !== 'assistant') || typeof mm.text !== 'string' || !mm.text.trim()) {
      throw new HttpError(400, 'bad_request', 'Geçersiz mesaj');
    }
    if (mm.text.length > MAX_TEXT_CHARS) throw new HttpError(413, 'payload_too_large', 'Mesaj çok uzun');
    return { role: mm.role, text: mm.text };
  });
  if (messages[messages.length - 1]?.role !== 'user') throw new HttpError(400, 'bad_request', 'Son mesaj kullanıcıdan olmalı');
  const requested = typeof b.maxOutputTokens === 'number' ? Math.floor(b.maxOutputTokens) : cfg.maxOutputTokens;
  const maxOutputTokens = Math.max(16, Math.min(requested, cfg.maxOutputTokens));
  const webSearch = b.webSearch === true && cfg.allowWebSearch;
  return { model, instructions, messages, maxOutputTokens, webSearch };
}

export function createApp(deps: AppDeps): (req: IncomingMessage, res: ServerResponse) => void {
  const { config: cfg } = deps;
  const now = deps.now ?? Date.now;
  const log = deps.log ?? ((e) => console.log(JSON.stringify(e)));
  const limiter = new RateLimiter(cfg.requestsPerMinute, now);
  const ledger = new UsageLedger(now);

  function requireAuth(req: IncomingMessage): string {
    const id = authenticate(req.headers.authorization, cfg.deviceTokenHashes);
    if (!id) throw new HttpError(401, 'unauthorized', 'Geçersiz veya eksik cihaz tokenı');
    return id;
  }

  async function handle(req: IncomingMessage, res: ServerResponse, meta: Record<string, unknown>): Promise<void> {
    const url = new URL(req.url ?? '/', 'http://gateway.local');
    meta.path = url.pathname;

    if (req.method === 'GET' && url.pathname === '/health') {
      return send(res, 200, { ok: true, service: 'saklaz-gateway', version: VERSION });
    }

    if (req.method === 'GET' && url.pathname === '/v1/status') {
      meta.device = requireAuth(req).slice(0, 8);
      const u = ledger.snapshot();
      return send(res, 200, {
        defaultModel: cfg.defaultModel,
        allowedModels: cfg.allowedModels,
        upstreamConfigured: Boolean(cfg.openaiApiKey),
        webSearchAllowed: cfg.allowWebSearch,
        usage: {
          requestsToday: u.requestsToday,
          dailyRequestLimit: cfg.dailyRequestLimit,
          costTodayUsd: Number(u.costTodayUsd.toFixed(6)),
          dailyBudgetUsd: cfg.dailyBudgetUsd,
        },
      });
    }

    if (req.method === 'POST' && url.pathname === '/v1/respond') {
      const device = requireAuth(req);
      meta.device = device.slice(0, 8);
      if (!limiter.tryAcquire(device)) throw new HttpError(429, 'rate_limited', 'Dakikalık istek sınırı aşıldı');
      const usage = ledger.snapshot();
      if (usage.requestsToday >= cfg.dailyRequestLimit) throw new HttpError(429, 'daily_limit', 'Günlük istek sınırı doldu');
      if (!cfg.openaiApiKey) throw new HttpError(503, 'not_configured', 'OpenAI anahtarı tanımlı değil');

      const body = validate(await readJson(req), cfg);
      meta.model = body.model;

      // Ön maliyet kontrolü: bu isteğin en kötü durum maliyeti bütçeyi aşıyorsa reddet.
      const chars = body.instructions.length + body.messages.reduce((n, m) => n + m.text.length, 0);
      const worst = costUsd(estimateInputTokens(chars), body.maxOutputTokens, cfg.priceInputPerMTokUsd, cfg.priceOutputPerMTokUsd);
      if (usage.costTodayUsd + worst > cfg.dailyBudgetUsd) {
        throw new HttpError(402, 'budget_exceeded', 'Günlük bütçe yetersiz');
      }

      ledger.recordRequest();
      const out = await callResponses(deps.fetch, cfg.openaiBaseUrl, cfg.openaiApiKey, body, cfg.upstreamTimeoutMs);
      const cost = costUsd(out.inputTokens, out.outputTokens, cfg.priceInputPerMTokUsd, cfg.priceOutputPerMTokUsd);
      ledger.recordCost(cost);
      Object.assign(meta, { inputTokens: out.inputTokens, outputTokens: out.outputTokens, costUsd: cost });
      if (!out.text) throw new HttpError(502, 'empty_response', 'Model boş yanıt verdi');
      return send(res, 200, {
        text: out.text,
        model: out.model,
        usage: { inputTokens: out.inputTokens, outputTokens: out.outputTokens },
        costUsd: Number(cost.toFixed(6)),
      });
    }

    throw new HttpError(404, 'not_found', 'Bulunamadı');
  }

  return (req, res) => {
    const started = now();
    const meta: Record<string, unknown> = { method: req.method };
    handle(req, res, meta)
      .catch((e: unknown) => {
        if (e instanceof HttpError) {
          send(res, e.status, { error: { code: e.code, message: e.message } });
        } else if (e instanceof UpstreamError) {
          send(res, e.status === 429 ? 429 : e.status === 504 ? 504 : 502, {
            error: { code: e.status === 429 ? 'upstream_rate_limited' : 'upstream_error', message: 'OpenAI isteği başarısız' },
          });
        } else {
          send(res, 500, { error: { code: 'internal', message: 'Sunucu hatası' } });
        }
      })
      .finally(() => {
        log({ t: new Date(started).toISOString(), ...meta, status: res.statusCode, ms: now() - started });
      });
  };
}
