// MOCK TESTLERİ: OpenAI'a gerçek istek GÖNDERİLMEZ; `fetch` sahte bir
// fonksiyonla değiştirilir. Gerçek API testi ayrıca (anahtar ile) yapılmalıdır.
import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, beforeEach, describe, it } from 'node:test';

import { createApp } from '../src/app.ts';
import { sha256Hex } from '../src/auth.ts';
import { loadConfig } from '../src/config.ts';
import { buildResponsesPayload, extractText } from '../src/openai.ts';

const TOKEN = 'skz_test_token_0123456789abcdef';
const SECRET = 'sk-test-SECRET-should-never-leak';

interface Call {
  url: string;
  init: RequestInit;
}

let server: Server;
let base = '';
let calls: Call[] = [];
let logs: Record<string, unknown>[] = [];
let upstream: () => Response = () => new Response('{}');

function makeConfig(over: Record<string, string> = {}) {
  return loadConfig({
    SAKLAZ_DEFAULT_MODEL: 'model-a',
    SAKLAZ_ALLOWED_MODELS: 'model-a,model-b',
    SAKLAZ_DEVICE_TOKEN_HASHES: sha256Hex(TOKEN),
    OPENAI_API_KEY: SECRET,
    SAKLAZ_REQUESTS_PER_MINUTE: '3',
    SAKLAZ_DAILY_REQUEST_LIMIT: '100',
    SAKLAZ_DAILY_BUDGET_USD: '1',
    SAKLAZ_PRICE_INPUT_PER_MTOK_USD: '1',
    SAKLAZ_PRICE_OUTPUT_PER_MTOK_USD: '4',
    ...over,
  });
}

async function start(over: Record<string, string> = {}) {
  if (server) await new Promise((r) => server.close(r));
  server = createServer(
    createApp({
      config: makeConfig(over),
      fetch: async (url, init) => {
        calls.push({ url, init });
        return upstream();
      },
      log: (e) => logs.push(e),
    }),
  );
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}

function okUpstream(text = 'Merhaba, ben SAKLAZ.') {
  return () =>
    new Response(
      JSON.stringify({
        model: 'model-a',
        output: [{ type: 'message', content: [{ type: 'output_text', text }] }],
        usage: { input_tokens: 100, output_tokens: 50 },
      }),
      { status: 200 },
    );
}

const respond = (body: unknown, token: string | null = TOKEN) =>
  fetch(`${base}/v1/respond`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });

const validBody = { instructions: 'Türkçe yanıt ver', messages: [{ role: 'user', text: 'Selam' }] };

describe('SAKLAZ Gateway (mock upstream)', () => {
  before(() => start({ SAKLAZ_REQUESTS_PER_MINUTE: '1000' }));
  after(() => new Promise((r) => server.close(r)));
  beforeEach(() => {
    calls = [];
    logs = [];
    upstream = okUpstream();
  });

  it('/health kimlik doğrulamasız, sır içermez', async () => {
    const r = await fetch(`${base}/health`);
    assert.equal(r.status, 200);
    const text = await r.text();
    assert.ok(!text.includes(SECRET));
    assert.equal(r.headers.get('cache-control'), 'no-store');
  });

  it('token olmadan veya yanlış tokenla 401', async () => {
    assert.equal((await respond(validBody, null)).status, 401);
    assert.equal((await respond(validBody, 'skz_wrong_token_0123456789')).status, 401);
    assert.equal((await fetch(`${base}/v1/status`)).status, 401);
    assert.equal(calls.length, 0);
  });

  it('başarılı yanıt: Responses API doğru çağrılır, store=false, anahtar yalnızca upstream başlığında', async () => {
    const r = await respond({ ...validBody, maxOutputTokens: 5000 });
    assert.equal(r.status, 200);
    const j = (await r.json()) as { text: string; costUsd: number; usage: { outputTokens: number } };
    assert.equal(j.text, 'Merhaba, ben SAKLAZ.');
    assert.equal(j.usage.outputTokens, 50);
    assert.equal(j.costUsd, (100 * 1 + 50 * 4) / 1e6);
    const call = calls[0]!;
    assert.equal(call.url, 'https://api.openai.com/v1/responses');
    assert.equal((call.init.headers as Record<string, string>).authorization, `Bearer ${SECRET}`);
    const sent = JSON.parse(call.init.body as string);
    assert.equal(sent.store, false);
    assert.equal(sent.model, 'model-a');
    assert.equal(sent.max_output_tokens, 600, 'istemci üst sınırı aşamaz');
    assert.deepEqual(sent.input, [{ role: 'user', content: 'Selam' }]);
    assert.equal(sent.tools, undefined, 'web araması varsayılan kapalı');
    assert.ok(!JSON.stringify(j).includes(SECRET));
  });

  it('loglarda içerik ve anahtar yok, yalnızca meta veri', async () => {
    await respond({ ...validBody, messages: [{ role: 'user', text: 'GIZLI_KULLANICI_METNI' }] });
    const line = JSON.stringify(logs);
    assert.ok(!line.includes('GIZLI_KULLANICI_METNI'));
    assert.ok(!line.includes(SECRET));
    assert.ok(logs.some((l) => l.outputTokens === 50));
  });

  it('izinli olmayan model reddedilir', async () => {
    const r = await respond({ ...validBody, model: 'pahali-model' });
    assert.equal(r.status, 400);
    assert.equal(((await r.json()) as { error: { code: string } }).error.code, 'model_not_allowed');
    assert.equal(calls.length, 0);
  });

  it('geçersiz gövdeler reddedilir', async () => {
    assert.equal((await respond({ messages: [] })).status, 400);
    assert.equal((await respond({ messages: [{ role: 'system', text: 'x' }] })).status, 400);
    assert.equal((await respond({ messages: [{ role: 'user', text: 'x'.repeat(5000) }] })).status, 413);
    assert.equal(calls.length, 0);
  });

  it('upstream hata gövdesi istemciye sızmaz', async () => {
    upstream = () => new Response(JSON.stringify({ error: { message: `bad key ${SECRET}` } }), { status: 401 });
    const r = await respond(validBody);
    assert.equal(r.status, 502);
    assert.ok(!(await r.text()).includes(SECRET));
  });

  it('upstream ulaşılamazsa 502', async () => {
    upstream = () => {
      throw new TypeError('fetch failed');
    };
    assert.equal((await respond(validBody)).status, 502);
  });
});

describe('Sınırlar ve maliyet kontrolü (mock upstream)', () => {
  beforeEach(() => {
    calls = [];
    upstream = okUpstream();
  });
  after(() => new Promise((r) => server.close(r)));

  it('dakikalık istek sınırı: 4. istek 429', async () => {
    await start();
    for (let i = 0; i < 3; i++) assert.equal((await respond(validBody)).status, 200);
    assert.equal((await respond(validBody)).status, 429);
    assert.equal(calls.length, 3);
  });

  it('günlük bütçe yetersizse OpenAI çağrılmadan 402', async () => {
    await start({ SAKLAZ_DAILY_BUDGET_USD: '0.0001' });
    const r = await respond(validBody);
    assert.equal(r.status, 402);
    assert.equal(calls.length, 0);
  });

  it('OpenAI anahtarı yoksa 503 not_configured', async () => {
    await start({ OPENAI_API_KEY: '' });
    const r = await respond(validBody);
    assert.equal(r.status, 503);
    assert.equal(((await r.json()) as { error: { code: string } }).error.code, 'not_configured');
  });

  it('web araması yalnızca sunucuda izinliyse eklenir', async () => {
    await start({ SAKLAZ_ALLOW_WEB_SEARCH: 'true' });
    await respond({ ...validBody, webSearch: true });
    assert.deepEqual(JSON.parse(calls[0]!.init.body as string).tools, [{ type: 'web_search' }]);
  });

  it('/v1/status kullanım ve bütçeyi raporlar, OpenAI çağırmaz', async () => {
    await start();
    await respond(validBody);
    const r = await fetch(`${base}/v1/status`, { headers: { authorization: `Bearer ${TOKEN}` } });
    const j = (await r.json()) as { usage: { requestsToday: number; dailyBudgetUsd: number }; upstreamConfigured: boolean };
    assert.equal(j.usage.requestsToday, 1);
    assert.equal(j.usage.dailyBudgetUsd, 1);
    assert.equal(j.upstreamConfigured, true);
    assert.equal(calls.length, 1);
  });
});

describe('Yardımcılar', () => {
  it('extractText çoklu parçaları birleştirir', () => {
    assert.equal(
      extractText({ output: [{ type: 'reasoning' }, { type: 'message', content: [{ type: 'output_text', text: 'a' }, { type: 'output_text', text: 'b' }] }] }),
      'ab',
    );
    assert.equal(extractText(null), '');
  });

  it('payload asistan mesajlarını korur', () => {
    const p = buildResponsesPayload({
      model: 'm',
      instructions: 'i',
      messages: [
        { role: 'user', text: 'a' },
        { role: 'assistant', text: 'b' },
        { role: 'user', text: 'c' },
      ],
      maxOutputTokens: 100,
      webSearch: false,
    });
    assert.deepEqual(p.input, [
      { role: 'user', content: 'a' },
      { role: 'assistant', content: 'b' },
      { role: 'user', content: 'c' },
    ]);
  });

  it('yapılandırma: varsayılan model zorunlu, hash biçimi doğrulanır', () => {
    assert.throws(() => loadConfig({}));
    assert.throws(() => loadConfig({ SAKLAZ_DEFAULT_MODEL: 'm', SAKLAZ_DEVICE_TOKEN_HASHES: 'duz-token' }));
  });
});
