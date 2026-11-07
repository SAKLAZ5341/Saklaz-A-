// Gateway yapılandırması: tamamı ortam değişkenlerinden okunur.
// OPENAI_API_KEY asla loglanmaz, yanıtlarda dönmez, istemciye gönderilmez.

export interface GatewayConfig {
  port: number;
  host: string;
  openaiApiKey: string | undefined;
  openaiBaseUrl: string;
  defaultModel: string;
  allowedModels: string[];
  /** SHA-256(hex) cihaz token özetleri. Ham tokenlar sunucuda saklanmaz. */
  deviceTokenHashes: string[];
  requestsPerMinute: number;
  dailyRequestLimit: number;
  dailyBudgetUsd: number;
  priceInputPerMTokUsd: number;
  priceOutputPerMTokUsd: number;
  maxOutputTokens: number;
  allowWebSearch: boolean;
  upstreamTimeoutMs: number;
}

function num(env: NodeJS.ProcessEnv, key: string, fallback: number): number {
  const raw = env[key];
  if (raw === undefined || raw.trim() === '') return fallback;
  const v = Number(raw);
  if (!Number.isFinite(v) || v < 0) throw new Error(`${key} geçerli bir sayı olmalı`);
  return v;
}

function list(raw: string | undefined): string[] {
  return (raw ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): GatewayConfig {
  const defaultModel = (env.SAKLAZ_DEFAULT_MODEL ?? '').trim();
  if (!defaultModel) throw new Error('SAKLAZ_DEFAULT_MODEL tanımlı olmalı');
  const allowed = list(env.SAKLAZ_ALLOWED_MODELS);
  const allowedModels = allowed.length > 0 ? allowed : [defaultModel];
  if (!allowedModels.includes(defaultModel)) allowedModels.unshift(defaultModel);

  const deviceTokenHashes = list(env.SAKLAZ_DEVICE_TOKEN_HASHES).map((h) => h.toLowerCase());
  for (const h of deviceTokenHashes) {
    if (!/^[0-9a-f]{64}$/.test(h)) throw new Error('SAKLAZ_DEVICE_TOKEN_HASHES yalnızca SHA-256 hex içermeli');
  }

  return {
    port: num(env, 'PORT', 8787),
    host: env.HOST ?? '0.0.0.0',
    openaiApiKey: env.OPENAI_API_KEY?.trim() || undefined,
    openaiBaseUrl: (env.OPENAI_BASE_URL ?? 'https://api.openai.com/v1').replace(/\/+$/, ''),
    defaultModel,
    allowedModels,
    deviceTokenHashes,
    requestsPerMinute: num(env, 'SAKLAZ_REQUESTS_PER_MINUTE', 10),
    dailyRequestLimit: num(env, 'SAKLAZ_DAILY_REQUEST_LIMIT', 200),
    dailyBudgetUsd: num(env, 'SAKLAZ_DAILY_BUDGET_USD', 1),
    priceInputPerMTokUsd: num(env, 'SAKLAZ_PRICE_INPUT_PER_MTOK_USD', 0),
    priceOutputPerMTokUsd: num(env, 'SAKLAZ_PRICE_OUTPUT_PER_MTOK_USD', 0),
    maxOutputTokens: num(env, 'SAKLAZ_MAX_OUTPUT_TOKENS', 600),
    allowWebSearch: env.SAKLAZ_ALLOW_WEB_SEARCH === 'true',
    upstreamTimeoutMs: num(env, 'SAKLAZ_UPSTREAM_TIMEOUT_MS', 45_000),
  };
}
