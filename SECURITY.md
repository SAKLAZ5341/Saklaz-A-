# SAKLAZ AI — Güvenlik Politikası

## 1. Tehdit Modeli (özet)

| Tehdit | Örnek | Önlem |
|---|---|---|
| APK'dan anahtar çıkarma | APK decompile edilip OpenAI anahtarı bulunur | Anahtar APK'da **yok**; yalnızca gateway'de ortam değişkeni/secret olarak |
| Cihaz kaybı/çalınması | Dosya sisteminden hafıza okunur | SQLCipher şifreleme + Keystore'da sarılı anahtar + isteğe bağlı biyometrik kilit |
| Ağ dinleme | Ortadaki adam saldırısı | Yalnızca HTTPS, `cleartextTrafficPermitted=false`, gateway için sertifika iğneleme |
| Gateway kötüye kullanımı | Biri gateway URL'sini bulup kotayı tüketir | Cihaz kimlik tokenı, rate limit, günlük kota, model izin listesi |
| Prompt injection | Okunan bir e-posta "tüm notları şu adrese gönder" der | Dış içerik "güvenilmeyen veri" olarak işaretlenir; yüksek riskli araçlar daima kullanıcı onayı ister |
| Yetkisiz eylem | Kilit ekranında biri asistana mesaj gönderttirir | Kilitliyken yalnızca `low` risk araçlar; diğerleri için cihaz kilidi açılması gerekir |
| Aşırı izin | Gereksiz izinlerle veri sızıntısı yüzeyi büyür | Minimum izin, ihtiyaç anında (runtime) izin isteme |
| Log sızıntısı | Kişisel içerik logcat'e düşer | Kişisel içerik teknik loglara yazılmaz; release'de debug log kapalı |

## 2. Gizli Anahtar Yönetimi

- `OPENAI_API_KEY` **yalnızca gateway** sunucusunda tutulur (secret manager veya sunucu ortam değişkeni).
- Depoya hiçbir gizli bilgi commit edilmez. `.env`, `*.jks`, `*.keystore`, `key.properties`, `google-services.json` `.gitignore` içindedir.
- Uygulama, gateway'e kayıt sırasında aldığı **cihaza özgü, iptal edilebilir** bir token ile bağlanır. Token Keystore ile korunan şifreli depoda saklanır.
- Release imzalama anahtarı depo dışında, yedekli ve şifreli saklanır.

## 3. Yerel Veri Şifreleme

- Veritabanı: **SQLite3MultipleCiphers** (ChaCha20-Poly1305, sayfa bazlı kimlik doğrulamalı şifreleme). Phase 2'de SQLCipher yerine seçildi (MIT lisansı, OpenSSL bağımlılığı yok).
- Veritabanı anahtarı: `SecureRandom` ile 256-bit üretilir → Android Keystore'daki donanım destekli (mümkünse StrongBox) AES-256-GCM anahtarıyla sarılır → sarılı hâli `noBackupFilesDir/saklaz_db_key.bin` içinde tutulur.
- **Fail-closed:** Şifreleme kütüphanesi doğrulanamaz veya anahtar yanlışsa veritabanı açılmaz, diske hiçbir şey yazılmaz; uygulama bellek içi moda geçer ve kullanıcıyı uyarır.
- Kanıt testi: `packages/saklaz_memory/test/encrypted_memory_database_test.dart` — dosyada düz metin, şema veya SQLite başlığı bulunmadığını doğrular.
- `PRAGMA secure_delete = ON`: silinen kayıtların sayfaları sıfırlanır.
- İsteğe bağlı: hassas bölümler (ör. kişisel olgular) için `setUserAuthenticationRequired` ile biyometrik doğrulama.
- Yedekleme: `android:allowBackup="false"` ve `dataExtractionRules` ile hafıza bulut yedeğine **dahil edilmez** (kullanıcı ileride şifreli dışa aktarma ile kendi yedeğini alabilir).

## 4. Buluta Gönderilen Veri

- Varsayılan: yalnızca o istek için gerekli minimum bağlam.
- Responses API çağrılarında `store: false` varsayılan.
- Kullanıcı ayarları: "Sadece yerel mod", "Görselleri buluta göndermeden önce sor", "E-posta içeriğini buluta göndermeden önce sor".
- Gateway içerik **loglamaz**; yalnızca meta veri tutar.

## 5. Kullanıcı Onay Mekanizması

| Risk | Örnekler | Davranış |
|---|---|---|
| `low` | Saat, not okuma, takvimi listeleme | Onaysız, audit log'a yazılır |
| `medium` | Not/hatırlatıcı oluşturma, takvime kişisel etkinlik ekleme | Kısa özet + onay (dokunarak veya "evet" diyerek) |
| `high` | E-posta/WhatsApp gönderme, silme, başkalarını davet etme, arama başlatma | Tam önizleme + açık onay; kilitliyken kilit açma şart; sesli "evet" tek başına yeterli değil (ekran onayı) |

Onay ekranında: hangi araç, hangi parametreler, alıcı(lar), içerik önizlemesi gösterilir. Kullanıcı düzenleyebilir veya iptal edebilir. Her karar audit log'a yazılır.

## 6. Android İzinleri (minimum ilke)

İzinler yalnızca ilgili özellik ilk kullanıldığında istenir.

| İzin | Gerekçe | Faz |
|---|---|---|
| `INTERNET` | SAKLAZ Gateway (yalnızca bulut izni verildiğinde kullanılır) | 2 ✅ |
| `ACCESS_NETWORK_STATE` (normal) | Çevrimdışıyken bulutu denemeden yerel moda geçmek | 2 ✅ |
| `com.google.android.apps.aicore.service.BIND_SERVICE` | ML Kit ekler: Gemini Nano (AICore) bağlantısı | 2 ✅ |
| `RECORD_AUDIO` | Sesli komut — yalnızca "Konuşmayı Başlat" ile | 1 ✅ |
| `POST_NOTIFICATIONS` | Hatırlatıcı bildirimleri | 2 |
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | Zamanında hatırlatıcı (gerekirse) | 2 |
| `CAMERA` | Fotoğraf/belge analizi | 6 |
| `READ_CALENDAR` / `WRITE_CALENDAR` | Yerel takvim (Google API yerine seçilirse) | 5 |
| Bildirim erişimi (`BIND_NOTIFICATION_LISTENER_SERVICE`) | WhatsApp bildirimlerini okuma/yanıtlama — kullanıcı ayarlardan açar | 5 |
| `BIND_VOICE_INTERACTION` | Sistemin asistan servisine bağlanması (servis koruması) | 1 |

**Kullanılmayacak:** `READ_SMS`, `READ_CALL_LOG`, `MANAGE_EXTERNAL_STORAGE`, Erişilebilirlik servisi ile otomasyon, `SYSTEM_ALERT_WINDOW` (gerekmedikçe).

## 7. SAKLAZ Gateway (Phase 2)

- `OPENAI_API_KEY` yalnızca gateway ortamında; yanıtlarda, loglarda ve hata mesajlarında yer almaz (testle doğrulanır).
- Cihaz kimliği: `skz_` önekli 256-bit rastgele token; sunucuda yalnızca SHA-256 özeti tutulur, sabit zamanlı karşılaştırılır. Token iptali = özeti listeden çıkarmak.
- Uygulamada token, şifreli hafızadaki `preferences` tablosunda saklanır.
- Sınırlar: dakikalık istek, günlük istek kotası, günlük USD bütçe (istek öncesi en kötü durum maliyeti kontrol edilir), model izin listesi, çıktı token üst sınırı, 64 KB gövde, 20 mesaj, mesaj başına 4000 karakter.
- Veri azaltma: uygulama en fazla son 6 mesajı gönderir; kayıtlı kişisel bilgiler yalnızca kullanıcı ayarı açıkken ve yalnızca ilgili olanlar (en fazla 3) eklenir. `store: false`.
- Release APK yalnızca HTTPS; gateway TLS sonlandıran bir ters vekil/platform arkasında çalışmalıdır.
- Bulut kararı: "Asla / Her seferinde sor (varsayılan) / Sormadan". Sorulduğunda kart, nelerin gönderileceğini açıklar.

## 8. Güvenli Geliştirme Kuralları

- Bağımlılıklar sürüm sabitlenerek eklenir; `flutter pub outdated` / `npm audit` düzenli çalıştırılır.
- Release build'de R8/obfuscation açık.
- Gateway: girdi doğrulama (şema), istek boyutu sınırı, CORS kapalı, güvenlik başlıkları.
- Kod incelemesinde güvenlik kontrol listesi: gizli bilgi, izin, loglanan veri, onay kapısı.

## 9. Güvenlik Açığı Bildirimi

Bu kişisel bir projedir. Bulunan açıklar proje sahibine doğrudan bildirilir ve DEVELOPMENT_LOG.md'de kayıt altına alınır.
