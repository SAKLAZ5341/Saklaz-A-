// Yeni cihaz tokenı üretir. Ham token YALNIZCA bir kez ekrana yazılır:
//  - Ham token  -> SAKLAZ uygulamasına (Ayarlar > Bulut zekâsı) girilir.
//  - SHA-256    -> gateway ortamındaki SAKLAZ_DEVICE_TOKEN_HASHES listesine eklenir.
import { randomBytes } from 'node:crypto';

import { sha256Hex } from '../src/auth.ts';

const token = `skz_${randomBytes(32).toString('base64url')}`;
console.log('Cihaz tokenı (uygulamaya girin, başka yerde saklamayın):');
console.log(`  ${token}`);
console.log('SAKLAZ_DEVICE_TOKEN_HASHES içine eklenecek özet:');
console.log(`  ${sha256Hex(token)}`);
