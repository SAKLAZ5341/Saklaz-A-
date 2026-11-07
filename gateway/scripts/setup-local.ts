// Yerel (geliştirme) kurulum: .env yoksa oluşturur, cihaz tokenı üretir.
// OpenAI anahtarını KULLANICI .env dosyasına kendisi yazar.
import { randomBytes } from 'node:crypto';
import { copyFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { networkInterfaces } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { sha256Hex } from '../src/auth.ts';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const envPath = join(root, '.env');
const tokenPath = join(root, 'DEVICE_TOKEN.txt');

if (!existsSync(envPath)) {
  copyFileSync(join(root, '.env.example'), envPath);
  console.log('.env oluşturuldu.');
}

let env = readFileSync(envPath, 'utf8');
let token: string;
if (existsSync(tokenPath)) {
  token = readFileSync(tokenPath, 'utf8').trim();
} else {
  token = `skz_${randomBytes(32).toString('base64url')}`;
  writeFileSync(tokenPath, `${token}\n`, { mode: 0o600 });
}
const hash = sha256Hex(token);
const m = /^SAKLAZ_DEVICE_TOKEN_HASHES=(.*)$/m.exec(env);
const hashes = (m?.[1] ?? '').split(',').map((s) => s.trim()).filter(Boolean);
if (!hashes.includes(hash)) {
  hashes.push(hash);
  env = m
    ? env.replace(/^SAKLAZ_DEVICE_TOKEN_HASHES=.*$/m, `SAKLAZ_DEVICE_TOKEN_HASHES=${hashes.join(',')}`)
    : `${env}\nSAKLAZ_DEVICE_TOKEN_HASHES=${hash}\n`;
  writeFileSync(envPath, env);
}

const hasKey = /^OPENAI_API_KEY=\S+/m.test(env);
const ips = Object.values(networkInterfaces())
  .flat()
  .filter((i) => i && i.family === 'IPv4' && !i.internal)
  .map((i) => i!.address);

console.log('\n=== SAKLAZ Gateway yerel kurulum ===');
console.log(`OpenAI anahtarı: ${hasKey ? 'TANIMLI' : 'EKSİK -> gateway\\.env içindeki OPENAI_API_KEY= satırına yazın'}`);
console.log('Uygulamada Ayarlar > Bulut zekâsı:');
for (const ip of ips) console.log(`  Gateway adresi : http://${ip}:8787   (yalnızca DEBUG APK, aynı Wi-Fi)`);
console.log(`  Cihaz tokenı   : ${token}`);
console.log(`(Token ayrıca ${tokenPath} dosyasında; bu dosya Git'e gönderilmez.)`);
