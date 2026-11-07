# SAKLAZ AI — Mimari

## 1. Mimari İlkeler

- **Katmanlı ve modüler:** UI, AI Core, Memory, Agent, Voice ve Entegrasyonlar ayrı Dart paketleri olarak geliştirilir. Paketler birbirine yalnızca **arayüzler (abstract class)** üzerinden bağımlıdır.
- **Platformdan bağımsız çekirdek:** Android'e özgü her şey (VoiceInteractionService, RoleManager, Keystore, bildirim dinleyici) `platform_android` katmanında kalır. Böylece Windows desteği eklenirken yalnızca yeni bir platform katmanı yazılır.
- **Önce yerel, gerekirse bulut:** Talepler önce yerel modelle değerlendirilir; karmaşık işler kullanıcı ayarına göre buluta yönlendirilir.
- **Varsayılan olarak güvenli:** Anahtar APK'da yok, hafıza şifreli, riskli eylemler onaylı.

## 2. Genel Görünüm

```
┌──────────────────────────────────────────────────────────────────┐
│                         UI (Flutter)                              │
│  Sohbet ekranı · Asistan overlay · Ayarlar · Onay diyalogları     │
│  Fold 7: katlı (dış ekran) / açık (iç ekran) uyarlanabilir yerleşim│
└───────────────▲──────────────────────────────────▲────────────────┘
                │ (state: Riverpod)                │
┌───────────────┴───────────┐        ┌─────────────┴──────────────┐
│        Voice              │        │       Agent                 │
│  STT · TTS · uyandırma    │        │  Planlayıcı · Araç kayıtları │
│  (Türkçe tr-TR)           │        │  Onay kapısı · Denetim logu  │
└───────────────▲───────────┘        └─────────────▲──────────────┘
                │                                  │
┌───────────────┴──────────────────────────────────┴──────────────┐
│                         AI Core                                  │
│  Router (yerel/bulut) · Prompt & bağlam yönetimi · Araç çağrıları │
│   ├─ LocalLlmProvider  (cihaz üzerinde model)                     │
│   └─ CloudLlmProvider  (Gateway → OpenAI Responses API)           │
└───────────────▲──────────────────────────────────▲──────────────┘
                │                                  │
┌───────────────┴───────────┐        ┌─────────────┴──────────────┐
│       Memory              │        │     Integrations            │
│  SQLCipher DB · Notlar    │        │  Gmail · Takvim · WhatsApp  │
│  Hatırlatıcılar · Olgular │        │  Kamera/Belge · Kişiler     │
└───────────────▲───────────┘        └─────────────▲──────────────┘
                │                                  │
┌───────────────┴──────────────────────────────────┴──────────────┐
│            platform_android (Kotlin, Pigeon kanalları)            │
│  VoiceInteractionService · RoleManager · Keystore · Alarm/Bildirim│
│  NotificationListenerService · Intent'ler                        │
└──────────────────────────────────────────────────────────────────┘

        ║ HTTPS (TLS + sertifika iğneleme) + cihaz kimlik tokenı
        ▼
┌──────────────────────────────┐        ┌──────────────────────────┐
│   SAKLAZ Gateway (sunucu)    │ ─────▶ │  OpenAI Responses API     │
│  Kimlik doğrulama · Rate limit│        │  (OPENAI_API_KEY burada)  │
│  Model izin listesi · Kota   │        └──────────────────────────┘
└──────────────────────────────┘
```

## 3. Depo (Monorepo) Yapısı — Phase 1'de oluşturulacak

Dart **pub workspaces** (Dart 3.6+) ile tek depoda birden çok paket:

```
SAKLAZ-AI/
├── apps/
│   └── saklaz_app/              # Flutter uygulaması (UI + bağımlılık enjeksiyonu)
│       └── android/             # Kotlin: VoiceInteractionService, RoleManager, Pigeon host
├── packages/
│   ├── saklaz_core/             # Ortak modeller, Result tipi, logger arayüzü, hatalar
│   ├── saklaz_ai_core/          # LlmProvider arayüzü, Router, bağlam yönetimi
│   ├── saklaz_memory/           # Şifreli DB, repository'ler
│   ├── saklaz_agent/            # Araç (tool) sistemi, onay kapısı, denetim logu
│   ├── saklaz_voice/            # STT/TTS soyutlaması
│   ├── saklaz_integrations/     # Gmail, Takvim, WhatsApp, kamera/belge
│   └── saklaz_platform/         # Pigeon ile üretilen platform arayüzleri
├── gateway/                     # Node.js (TypeScript) gateway sunucusu
├── docs/                        # Ek dokümanlar, ADR'ler (mimari karar kayıtları)
└── *.md                         # Bu doküman seti
```

**Bağımlılık kuralı:** `saklaz_core` hiçbir şeye bağımlı değildir. Diğer paketler yalnızca `saklaz_core`'a ve gerekirse birbirlerinin **arayüzlerine** bağımlıdır. Somut sınıflar `apps/saklaz_app` içinde bağlanır (composition root). UI doğrudan veritabanına veya HTTP'ye erişemez.

## 4. Modüller

### 4.1 UI (Flutter)
- Durum yönetimi: **Riverpod** (test edilebilir, bağımlılık enjeksiyonunu da karşılar).
- Navigasyon: `go_router`.
- Fold 7 için uyarlanabilir yerleşim: dış ekranda tek sütun, iç ekranda sohbet + bağlam paneli (iki sütun). `MediaQuery`/`LayoutBuilder` ve kırılma noktaları ile.
- Asistan overlay: yan tuşla çağrıldığında açılan, yarım ekran sesli etkileşim arayüzü.

### 4.2 Asistan Rolü ve Yan Tuş (Kotlin)
- `RoleManager.createRequestRoleIntent(RoleManager.ROLE_ASSISTANT)` ile kullanıcıdan varsayılan asistan olma izni istenir.
- Asistan rolü için gerekli bileşenler:
  - `VoiceInteractionService` (sistem tarafından bağlanılan ana servis)
  - `VoiceInteractionSessionService` + `VoiceInteractionSession` (çağrıldığında açılan oturum)
  - `RecognitionService` (meta veride zorunlu)
  - `res/xml/interaction_service.xml` meta verisi
- Ek olarak `android.intent.action.ASSIST` intent filtresi olan bir Activity (yedek giriş noktası).
- **Yan tuş:** Samsung'da *Ayarlar → Gelişmiş özellikler → Yan tuş → Basılı tut → Dijital asistan* seçildiğinde sistem varsayılan dijital asistanı çağırır. Uygulama asistan rolünü aldığında yan tuş otomatik olarak SAKLAZ'ı açar. Bu davranış **gerçek Fold 7 üzerinde doğrulanmalıdır** (emülatörde Samsung ayarı yoktur).
- Oturum açıldığında Flutter tarafına Pigeon kanalı ile `onAssistInvoked` olayı iletilir. Hızlı açılış için önceden ısıtılmış (`FlutterEngineCache`) bir Flutter engine kullanılır.

### 4.3 AI Core
```dart
abstract interface class LlmProvider {
  Stream<LlmEvent> respond(LlmRequest request); // metin parçaları, araç çağrıları, bitiş
  Future<bool> isAvailable();
}
```
- **CloudLlmProvider:** Gateway'e bağlanır; gateway OpenAI **Responses API** (`POST /v1/responses`) çağırır. Akış (streaming) ve function/tool calling desteklenir. Eski Assistants API **kullanılmaz**. Konuşma durumu için `previous_response_id` veya istemci tarafında tutulan bağlam kullanılır (gizlilik tercihine göre, `store: false` varsayılan).
- **LocalLlmProvider:** Cihaz üzerinde model. Adaylar (Phase 4'te ölçülerek seçilecek):
  1. Google **LiteRT-LM / MediaPipe LLM Inference** + Gemma ailesi küçük model (GPU/NPU hızlandırma)
  2. **llama.cpp** (Dart FFI) + GGUF formatında küçük çok dilli model
  Seçim kriterleri: Türkçe kalitesi, ilk token süresi, token/sn, RAM, pil, model boyutu.
- **Router:** Kural tabanlı başlar (çevrimdışı mı? kullanıcı "sadece yerel" seçti mi? görev türü? hassas veri içeriyor mu?), ileride yerel model ile niyet sınıflandırmaya geçer.

### 4.4 Memory
- **drift** (tip güvenli SQLite ORM) + **SQLCipher** (AES-256 sayfa şifreleme).
- Veritabanı anahtarı: rastgele 256-bit üretilir, **Android Keystore** içindeki donanım destekli bir anahtarla sarılarak (wrap) saklanır.
- Tablolar (ilk taslak): `notes`, `reminders`, `facts` (kullanıcı hakkında hatırlanan bilgiler), `conversations`, `messages`, `audit_log`, `settings`.
- Buluta yalnızca o istek için gerekli minimum bağlam gönderilir; tüm hafıza asla toplu gönderilmez.
- İleride: yerel embedding ile anlamsal arama (sqlite-vec veya benzeri, değerlendirilecek).

### 4.5 Agent
- Her yetenek bir **Tool** olarak tanımlanır:
```dart
abstract interface class AgentTool {
  String get name;
  String get description;
  JsonSchema get parameters;
  RiskLevel get risk;          // low | medium | high
  Future<ToolResult> execute(Map<String, Object?> args, ToolContext ctx);
}
```
- **Onay kapısı (ConfirmationGate):**
  - `low` (ör. not okuma, saat sorma): onaysız çalışır, loglanır.
  - `medium` (ör. not oluşturma, hatırlatıcı kurma): özet gösterilir, tek dokunuşla/sözlü onay.
  - `high` (ör. e-posta gönderme, WhatsApp mesajı, takvime başkalarını davet, silme): tam içerik önizlemesi + açık onay. Sesli modda kilit ekranındayken **asla** otomatik çalışmaz.
- Model araç çağrısı önerir → Agent doğrular (şema + izin) → Onay kapısı → Çalıştır → Sonuç modele döner.
- Her adım `audit_log` tablosuna yazılır.

### 4.6 Voice
- **STT:** Varsayılan Android `SpeechRecognizer` (tr-TR, mümkünse cihaz üzerinde `createOnDeviceSpeechRecognizer`). Alternatif: gateway üzerinden OpenAI transkripsiyon modeli.
- **TTS:** Varsayılan Android `TextToSpeech` (Samsung/Google Türkçe ses). Alternatif: gateway üzerinden OpenAI TTS (daha doğal ses, maliyetli).
- Yarı çift yönlü akış (kullanıcı konuşur → sessizlik algılama → yanıt). Konuşma sırasında araya girme (barge-in) ileriki faz.

### 4.7 Entegrasyonlar
| Entegrasyon | Yöntem | Not |
|---|---|---|
| Gmail | Google OAuth (Android Credential Manager + AuthorizationClient), Gmail REST API | Gmail kapsamları "restricted"; kişisel kullanımda OAuth uygulaması "Testing" modunda kalabilir. Yayınlamak için Google doğrulaması gerekir. |
| Google Takvim | Google Calendar API veya Android `CalendarContract` | Yerel takvim sağlayıcısı daha az izinle çalışabilir. |
| WhatsApp | (1) `ACTION_SEND` / `wa.me` intent ile mesaj taslağı açma — kullanıcı gönder'e basar. (2) `NotificationListenerService` ile gelen bildirimleri okuma ve bildirimdeki "Yanıtla" eylemiyle yanıt (kullanıcı onaylı). | Kişisel WhatsApp için resmî API **yoktur**. Erişilebilirlik servisiyle otomatik tıklama Play politikalarına ve WhatsApp şartlarına aykırı olabilir; kullanılmayacak. |
| Hatırlatıcı | Yerel DB + `AlarmManager` (exact alarm izni gerekirse) + bildirim | |
| Kamera/Belge | `camera`/`image_picker`, ML Kit (cihazda OCR, Türkçe Latin alfabesi) + bulut çok modlu analiz (Responses API görsel girdi) | Görsel buluta yalnızca kullanıcı onayıyla gönderilir. |

### 4.8 Gateway (sunucu)
- **Node.js + TypeScript** (makinede Node 24 kurulu). Hafif bir framework (Fastify/Hono).
- Görevler: istemci kimlik doğrulama, OpenAI anahtarını saklama, model izin listesi, istek boyutu ve kota sınırları, rate limit, akışı (SSE) istemciye aktarma.
- İçerik loglanmaz; yalnızca meta veri (zaman, model, token sayısı, hata kodu).
- Barındırma seçeneği (karar kullanıcıda): kişisel VPS, Cloudflare Workers, Fly.io/Render vb. Geliştirme aşamasında yerel ağda çalıştırılabilir.

## 5. Loglama
- `saklaz_core` içinde `AppLogger` arayüzü; seviyeler: debug/info/warn/error/audit.
- Teknik loglar: dönen dosya (rotating) + debug modda logcat. **Kişisel içerik (mesaj metni, e-posta gövdesi) teknik loglara yazılmaz.**
- Denetim (audit) logu: Agent eylemleri, onaylar, bulut çağrıları — şifreli DB'de, kullanıcı uygulama içinden görüntüleyebilir ve silebilir.

## 6. Test Stratejisi
- Birim testleri: her pakette (`package:test`, `mocktail`).
- Widget testleri: UI ekranları.
- Entegrasyon testleri: `integration_test` ile gerçek cihaz/emülatör.
- Kotlin tarafı: JUnit + Android instrumented testler (asistan rolü, oturum açılması).
- Gateway: Vitest ile birim + sözleşme testleri.
- **Kabul kuralı:** Bir özellik ancak Galaxy Z Fold 7 üzerinde (veya cihaza özgü değilse Android 16 emülatöründe) manuel test senaryosu geçtikten ve sonucu DEVELOPMENT_LOG.md'ye yazıldıktan sonra tamamlanmış sayılır.

## 7. Windows'a Genişleme
- `saklaz_core`, `saklaz_ai_core`, `saklaz_memory`, `saklaz_agent` saf Dart olduğundan değişmeden kullanılır.
- Yeni `platform_windows` katmanı: global kısayol, sistem tepsisi, Windows Credential Manager/DPAPI ile anahtar saklama.
- Android'e özgü araçlar (WhatsApp bildirimi, alarm) Windows'ta kayıt dışı kalır; Agent yalnızca platformda bulunan araçları modele sunar.

## 8. Mimari Karar Kayıtları (ADR)
Önemli kararlar `docs/adr/NNNN-baslik.md` olarak kaydedilecek. Phase 0 kararları:
1. Monorepo + Dart pub workspaces
2. Riverpod durum yönetimi
3. drift + SQLCipher, anahtar Keystore'da
4. Bulut erişimi yalnızca gateway üzerinden, OpenAI Responses API
5. Kotlin ↔ Dart iletişimi için Pigeon (tip güvenli)
6. WhatsApp için yalnızca intent + bildirim yanıtı (erişilebilirlik otomasyonu yok)
