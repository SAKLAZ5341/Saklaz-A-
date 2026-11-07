# SAKLAZ Gateway

SAKLAZ uygulaması ile OpenAI **Responses API** arasındaki güvenli ara katman.
OpenAI anahtarı **yalnızca bu sunucuda** durur; uygulamada/APK'da yoktur.

## Neden?
- APK'dan anahtar çıkarılamaz (anahtar telefonda hiç yok).
- Her cihaz iptal edilebilir kendi tokenıyla bağlanır.
- İstek sınırı, günlük istek kotası ve günlük **USD bütçe** sınırı.
- İçerik loglanmaz; yalnızca meta veri (zaman, model, token sayısı, maliyet, durum).
- `store: false`: konuşmalar OpenAI tarafında saklanmaz.

## API
| Yöntem | Yol | Kimlik | Açıklama |
|---|---|---|---|
| GET | `/health` | yok | Canlılık (`{ok, version}`) |
| GET | `/v1/status` | Bearer cihaz tokenı | Model listesi, bugünkü kullanım ve bütçe. OpenAI'ı çağırmaz (ücretsiz). |
| POST | `/v1/respond` | Bearer cihaz tokenı | `{model?, instructions, messages:[{role,text}], maxOutputTokens?, webSearch?}` → `{text, model, usage, costUsd}` |

Hata gövdesi: `{"error":{"code":"...","message":"..."}}`
Kodlar: `unauthorized` 401 · `budget_exceeded` 402 · `rate_limited`/`daily_limit` 429 · `model_not_allowed` 400 · `payload_too_large` 413 · `upstream_error` 502 · `not_configured` 503.

## Çalıştırma (Node.js 24+, derleme adımı yok)
```powershell
cd gateway
npm install            # yalnızca geliştirme araçları (typescript, @types/node)
npm run new-token      # cihaz tokenı + özeti üretir
copy .env.example .env # değerleri doldurun
node --env-file=.env src/server.ts
```

## Test
```powershell
npm test               # MOCK testleri: OpenAI'a gerçek istek GÖNDERMEZ
npm run typecheck
```
Gerçek API testi: geçerli `OPENAI_API_KEY` ile sunucuyu başlatıp uygulamadan
(Ayarlar → Bulut zekâsı → Bağlantıyı test et) veya `curl` ile `/v1/respond` çağrılır.

## Yayınlama (henüz YAPILMADI)
- Sunucu **mutlaka HTTPS** arkasında çalışmalı (release APK HTTP'ye izin vermez).
  Seçenekler: VPS + Caddy/Nginx (otomatik TLS), Fly.io, Render, Railway vb.
- Günlük sayaçlar bellektedir; sunucu yeniden başlarsa sıfırlanır. Ek güvence için
  OpenAI hesabında da aylık harcama limiti tanımlayın.
- Debug APK geliştirme için yerel ağdaki `http://<bilgisayar-ip>:8787` adresine bağlanabilir.
