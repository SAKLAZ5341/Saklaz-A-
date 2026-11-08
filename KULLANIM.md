# SAKLAZ AI — Kullanım Talimatı

## 1. Kurulum (Galaxy Z Fold 7)
1. `SAKLAZ-AI.apk` dosyasını telefona kopyala (USB, Quick Share veya bulut).
2. Dosyaya dokun → "Bilinmeyen kaynaklardan yükleme" izni iste­nirse ver → **Yükle**.
   - ADB ile: `adb install -r SAKLAZ-AI.apk`
3. SAKLAZ'ı aç. İnternet, API anahtarı veya sunucu **gerekmez**.

## 2. Yerel yapay zekâyı kur (bir kez)
1. Ana ekrandaki **"Model indirilmedi"** etiketine dokun → **Model Yönetimi**.
2. **Qwen3 1.7B (önerilen)** → **İndir** (≈977 MB, Wi-Fi önerilir).
   - İndirme kesilirse tekrar **İndir**: kaldığı yerden devam eder.
   - Bitince SHA-256 bütünlük kontrolü yapılır, model otomatik yüklenir.
3. Etiket **"Yerel AI hazır"** olunca sohbet tamamen telefonda çalışır.
   - Düşük RAM'li cihazlar için: **Qwen3 0.6B (hafif)** (≈343 MB).
   - Lisans: Apache-2.0 (Hugging Face `litert-community`).

## 3. Konuşma
- Yaz ve gönder, ya da **Konuşmayı Başlat** → konuş → SAKLAZ yanıtlar ve tekrar dinler.
- **Konuşmayı Durdur**: mikrofon ve konuşma tamamen kapanır.
- **Sesli yanıt açık/kapalı**: dinlemeden bağımsız.
- Her yanıtta **Tekrar dinle** düğmesi ve kaynak etiketi (Yerel / Hafıza / Yerel AI / Bulut).
- **+** düğmesi: fotoğraf çek, galeriden seç veya dosya (PDF/metin) oku — hepsi cihazda analiz edilir.

## 4. SAKLAZ seni tanır (otomatik öğrenme)
- "Ben satınalma yöneticisiyim ve ASEDEN ERP üzerinde çalışıyorum" de →
  sohbette **🧠 Hafızama ekledim** görünür.
- Sonra sor: "Ben hangi projeler üzerinde çalışıyorum?", "Benim mesleğim ne?",
  "Benim hakkımda ne biliyorsun?"
- Değişen bilgi (ör. yeni meslek) eskisini **"eski"** olarak arşivler.
- Şifre, kart, IBAN, TC kimlik, API anahtarı **asla otomatik kaydedilmez**.
- **Benim Hafızam** (ana ekran 🧠): ara, düzenle, sil, hepsini temizle, otomatik öğrenmeyi kapat.

## 5. Telefon komutları (onaylı)
| Söyle / yaz | Ne olur |
|---|---|
| "Yarın sabah 9'da toplantıyı hatırlat" | Onay → hatırlatma + bildirim |
| "10 dakika sonra ilacımı hatırlat" | Onay → hatırlatma |
| "Not al: süt ve ekmek" | Onay → not |
| "Yarın 6:30'a alarm kur" | Onay → Saat uygulamasında alarm |
| "Takvime cuma 14'te dişçi randevusu ekle" | Onay → Takvim'de doldurulmuş etkinlik (Kaydet'e sen basarsın) |
| "Bugün takvimimde ne var" | Takvimi okur (izin ister) |
| "Ahmet'i ara" | Onay → çevirici açılır (aramayı sen başlatırsın) |
| "Ahmet'e WhatsApp'tan geç kalacağımı yaz" | **Ekrandan** onay → WhatsApp taslağı (GÖNDER'e sen basarsın) |
| "Spotify aç" / "Wifi ayarlarını aç" | Uygulamayı / ayarı açar |
| "Bildirimlerimi oku" | Bildirim erişimi verilmişse son bildirimler |

Orta riskli işlemler sesli "evet/hayır" ile onaylanabilir; WhatsApp gibi yüksek riskli işlemler yalnızca ekrandan.
WhatsApp'a otomatik mesaj gönderilmez (resmî API yoktur); yalnızca taslak açılır.

## 6. Varsayılan asistan ve yan tuş
1. Ayarlar → **İzinler** → "Varsayılan asistan yap" (Android rolü uygulama içinden vermez; açılan ekranda **Dijital asistan uygulaması: SAKLAZ** seç).
2. Telefon Ayarları → Gelişmiş özellikler → **Yan tuş** → Basılı tut → **Dijital asistan**.

## 7. Bulut sağlayıcıları (isteğe bağlı, varsayılan KAPALI)
- Ayarlar → **API Sağlayıcıları**: OpenAI, DeepSeek, Özel (OpenAI uyumlu), SAKLAZ Gateway.
- Etkinleştir + API anahtarı gir (Keystore ile şifreli saklanır) + **Bağlantıyı test et**.
- Ayarlar → **Yapay Zekâ Ayarları** → aktif zekâyı seç. Varsayılan "her seferinde sor".
- **Ücretler sağlayıcıya göre sana aittir.** Kişisel hafıza ayrı izin olmadan gönderilmez.

## 8. Gizlilik
- Tüm kişisel veriler telefonda, SQLite3MultipleCiphers (ChaCha20-Poly1305) ile şifreli; anahtar Android Keystore'da.
- Otomatik bulut yedeklemesi kapalı; modeller ve hafıza yedeklenmez.
- Mikrofon yalnızca "Konuşmayı Başlat" ile açılır; uygulama arka plana geçince kapanır.
