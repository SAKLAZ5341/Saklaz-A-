import { createServer } from 'node:http';

import { VERSION, createApp } from './app.ts';
import { loadConfig } from './config.ts';

const config = loadConfig();
const server = createServer(createApp({ config, fetch: (url, init) => fetch(url, init) }));
server.requestTimeout = 90_000;
server.headersTimeout = 15_000;

server.listen(config.port, config.host, () => {
  console.log(
    JSON.stringify({
      event: 'started',
      version: VERSION,
      port: config.port,
      defaultModel: config.defaultModel,
      allowedModels: config.allowedModels,
      devices: config.deviceTokenHashes.length,
      upstreamConfigured: Boolean(config.openaiApiKey),
      dailyBudgetUsd: config.dailyBudgetUsd,
    }),
  );
  if (config.deviceTokenHashes.length === 0) console.warn('UYARI: SAKLAZ_DEVICE_TOKEN_HASHES boş — hiçbir cihaz bağlanamaz.');
  if (!config.openaiApiKey) console.warn('UYARI: OPENAI_API_KEY tanımlı değil — /v1/respond 503 döner.');
  if (config.priceInputPerMTokUsd === 0 && config.priceOutputPerMTokUsd === 0) {
    console.warn('UYARI: Model fiyatları 0 — maliyet kontrolü yalnızca istek sayısıyla sınırlı.');
  }
});

for (const sig of ['SIGINT', 'SIGTERM'] as const) {
  process.on(sig, () => server.close(() => process.exit(0)));
}
