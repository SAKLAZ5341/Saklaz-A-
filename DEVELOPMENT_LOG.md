# SAKLAZ AI — Geliştirme Günlüğü

---

## 2026-11-08 — Sürüm 1.0.1: Donma düzeltmesi ve yan tuş paneli

**Kullanıcı bildirimi:** "Program telefonu donduruyor." ve "Yan tuşa basınca uygulama açılıyor; Gemini gibi
alttan çıkıp beni dinlemesini ve söylediğimi yapmasını istiyorum."
**Teslim:** `C:\Users\fatih\Desktop\SAKLAZ-AI-GUNCEL-2.apk` (69,7 MB, SHA-256 `cabb56d0a355036f362d1f1ed03b32f755f3f74b8d976b147aeab585658eb8de`)

### Donma: olası nedenler ve önlemler (cihaz logu alınamadı — kesin neden DOĞRULANMADI)
| Olası neden | Önlem |
|---|---|
| Açılışta ~1 GB model otomatik yükleniyordu | Tembel yükleme: model ilk yerel AI sorusunda arka planda yüklenir |
| Önce GPU arka ucu deneniyordu (sürücü kilitlenmesi riski) | Varsayılan CPU; GPU ayarlardan "deneysel" olarak açılabilir |
| Tüm CPU çekirdekleri kullanılıyordu | 4 iş parçacığı |
| 4096 token KV önbelleği | 2048 token |
| Arka planda model bellekte kalıyordu | `onTrimMemory(BACKGROUND)` → model bırakılır |
| Küre animasyonu boştayken sürekli çiziliyordu | Boştayken durur |

### Yan tuş paneli (Gemini benzeri)
- `SaklazSession` artık uygulamayı AÇMAZ; `VoiceInteractionSession` penceresinde saydam bir Flutter paneli
  (`assistantOverlayMain`, ayrı motor, `OverlayEngine`) ekranın altından çıkar ve **hemen dinler**.
- Motor `VoiceInteractionService.onReady`'de önceden ısıtılır (anında açılış).
- Yerel model ve indirme yöneticisi süreç genelinde tek örnek (`AiServices`): panel ve uygulama aynı modeli paylaşır.
- **"Söylediğimi yap":** orta riskli işlemler (not, hatırlatma, alarm, takvim, arama ekranı, uygulama/ayar açma)
  sormadan uygulanır (`autoConfirmMedium`, varsayılan açık, kapatılabilir). WhatsApp ve bildirim yanıtı HER ZAMAN ekrandan onay.
- Başka uygulama açılınca, dışarı dokununca veya sessiz kalınca (4 sn) panel kapanır.
- Panelde Activity olmadığından izin istenemez; mikrofon izni yoksa "uygulamayı bir kez açıp izin ver" uyarısı.

### Testler
core 3 · voice 11 · ai_core 53 · memory 23 · uygulama 23 (5 yeni panel testi: hemen dinleme, sormadan hatırlatma,
WhatsApp ekran onayı + panel kapanması, dışarı dokununca kapanma, izin yok uyarısı) · analyze temiz · release derlendi.

### Gerçek cihazda DOĞRULANMADI
Donmanın giderildiği, panelin Samsung yan tuşuyla açılması, panelde FlutterTextureView saydamlığı, panel içinde
ses tanıma. **Telefon bağlanırsa** `adb logcat -s SaklazOverlay SaklazSession SaklazLlm flutter` ile doğrulanmalı.

---

## 2026-11-08 — Sürüm 1.0.0: Tamamlanmış ürün (yerel AI, otomatik öğrenme, agent)

**Teslim:** `C:\Users\fatih\Desktop\SAKLAZ-AI.apk` ve `dist/SAKLAZ-AI.apk` (release, arm64, 69,7 MB,
SHA-256 `a649ae4b1d1340d22f4b741bc82f1441dfa5f760364e4f9aae39d33ebdaf598b`) · Kullanım: `KULLANIM.md`

### Yapılanlar
- **Gerçek yerel LLM:** LiteRT-LM 0.19.1 (Google). Gemini Nano kaldırıldı. Modeller APK'da yok; uygulama içinden
  Hugging Face'ten (commit'e sabitlenmiş URL) indirilir, kaldığı yerden devam eder, SHA-256 doğrulanır, `noBackupFilesDir/models`.
  Katalog: Qwen3-1.7B int4 (önerilen, 977 MB), Qwen3-0.6B int4 (343 MB), Qwen2.5-1.5B q8 (1,6 GB) — hepsi Apache-2.0.
  Gemma 3 1B: Google lisans onayı + HF girişi gerektirdiği için uygulama içinden indirilemez (katalogda yok).
- **Otomatik kişisel öğrenme:** kural tabanlı Türkçe çıkarıcı (meslek, sektör, şirket, proje, ilgi, tercih, alışkanlık,
  hedef, karar, yakınlar, konum, isim) + hassas veri filtresi (şifre/kart/IBAN/TC/API anahtarı asla otomatik kaydedilmez).
- **Hafıza v2:** kategoriler, FTS5 arama (Türkçe kök öneki), çelişki yönetimi (tek değerli kategoride eski bilgi arşivlenir),
  yinelenme önleme, geçmiş konuşma araması, notlar, hatırlatıcılar, v1→v2 kayıpsız geçiş.
- **Benim Hafızam:** ara, düzenle, sil, hepsini temizle, eski bilgileri göster, otomatik öğrenme aç/kapat.
- **Sağlayıcılar (varsayılan PASİF):** OpenAI (Responses API), DeepSeek, Özel OpenAI uyumlu, SAKLAZ Gateway.
  API anahtarları Keystore AES-GCM ile şifreli; bağlantı testi `GET /models` (metin üretmez).
- **Agent:** hatırlatıcı (AlarmManager + bildirim + yeniden başlatmada kurulum), not, alarm, takvim ekleme/okuma,
  arama (çevirici), WhatsApp taslağı (wa.me), uygulama açma, ayar ekranları, bildirim okuma/onaylı yanıt.
  Risk seviyeleri: orta → sesli "evet" yeterli; yüksek (WhatsApp, bildirim yanıtı) → yalnızca ekrandan onay.
- **Dosya/fotoğraf:** kamera (CAMERA izni yok), galeri, PDF (PdfRenderer + OCR), metin; ML Kit OCR + görüntü etiketleri → yerel model.
- **Ekranlar:** Ana ekran (yerel AI/model/hafıza/sağlayıcı durumu), Sohbet Geçmişi, Benim Hafızam, Yapay Zekâ Ayarları,
  API Sağlayıcıları, Model Yönetimi, Notlar ve Hatırlatmalar, İzinler, Ayarlar.

### Gerçek model doğrulaması (bilgisayarda, gerçek motor + gerçek model — MOCK DEĞİL)
LiteRT-LM JVM 0.19.1 (Android'deki ile aynı API) + Qwen3-1.7B int4, Windows CPU:
| Test | Sonuç |
|---|---|
| Model yükleme | 5,1 sn |
| "Merhaba, kendini tanıtır mısın?" | Türkçe yanıt (9,3 sn) |
| Konuşma devamlılığı ("Az önce kaç öneri vermiştin?") | Doğru: "üç öneri" |
| Hafıza bağlamıyla "Ben hangi projeler üzerinde çalışıyorum?" | "Sen ASEDEN ERP projesi üzerinde çalışıyorsun." (istem düzeltmesinden sonra) |
| Hafıza bağlamıyla "Benim mesleğim ne?" | **Yanlış** (projeyi söyledi) → kategorili hafıza sorularının LLM'siz yanıtlanmasına karar verildi |
| LLM ile JSON bilgi çıkarımı | **Başarısız** (uydurdu) → kural tabanlı çıkarıcıya karar verildi |

### Test sonuçları (otomatik)
core 3 · voice 11 · ai_core 53 · memory 23 (gerçek SQLite3MC) · uygulama 18 widget (MOCK platform/model/ağ) ·
Kotlin 3 · gateway 16 (MOCK OpenAI) · `flutter analyze` temiz · debug + release APK derlendi.

### Gerçek cihazda DOĞRULANMADI (Fold 7 ADB'de görünmedi)
LiteRT-LM'in telefonda yüklenmesi/GPU, model indirme, Türkçe ses tanıma, hatırlatma bildirimi, rehber/takvim/WhatsApp
intent'leri, bildirim dinleyici, OCR, yan tuş. → `docs/DEVICE_TEST_PHASE2.md` + bu sürüm için KULLANIM.md adımları.

### Hata kayıtları
| # | Hata | Çözüm |
|---|---|---|
| E18 | FTS kök kuralı ("projelerim"→"projeleri*") "proje" bulamadı | İlk 5 harf önek |
| E19 | `when` Dart'ta kalıp değişkeni adı olamaz | `whenText` |
| E20 | **Gerçek hata:** diyalog kapanırken TextEditingController animasyon sırasında imha ediliyordu (çökme) | Denetleyici diyaloğun State'inde |
| E21 | **Gerçek hata:** 412 dp'de Benim Hafızam (148 px) ve Model Yönetimi (65 px) taşması | Wrap / Expanded |
| E22 | `androidx.core` 1.19.1 compileSdk 37 istedi | 1.17.0 (hedef API 36 korunur) |
| E23 | Gradle `abiFilters` Flutter tarafından yok sayıldı (APK 108 MB) | `--target-platform android-arm64` (69,7 MB) |
| E24 | İndirme döngüsünde iş haritaya eklenmeden iptal kontrolü (yarış) | `currentCoroutineContext().isActive` |

### Bilinen sınırlamalar
- APK'da LiteRT'in x86_64 kopyası (≈26 MB) kalıyor (AAR'dan geliyor; Fold 7'de kullanılmaz).
- Release APK debug anahtarıyla imzalı (yerel kurulum için). Mağaza için ayrı imza anahtarı gerekir.
- İndirme uygulama ön plandayken en güvenilir; arka planda sistem süreci durdurabilir (devam ettirilebilir).

---

## 2026-11-08 — Phase 2: AI Core + Ses Kontrolü + Şifreli Hafıza

**Durum:** Kod, otomatik testler (mock ve yerel) ve release APK tamam. **Fold 7 üzerinde Phase 2 testi YAPILMADI** — cihaz ADB'de önce `offline`, sonra hiç görünmedi. **Gerçek OpenAI testi YAPILMADI** — gateway yayınlanmadı, anahtar tanımlı değil.

### Phase 1 cihaz durumu (kullanıcı bildirimi)
- Kullanıcı: "Phase 1 APK'sı Fold 7 üzerinde kuruldu ve uygulama açıldı." → T1 kısmen doğrulandı (kullanıcı gözlemi).
- Rol, yan tuş, ses testleri (R/A/V) hâlâ kayıtlı değil.

### Yapılanlar
**A/D. Konuşma kontrolü**
- Ana ekranda ayrı **Konuşmayı Başlat** / **Konuşmayı Durdur**; açılışta mikrofon kapalı.
- Konuşma modu: dinle → yanıtla → TTS bitince yeniden dinle; Durdur her şeyi sonlandırır.
- **Sesli yanıt** aç/kapat ana ekranda, dinlemeden bağımsız ve kalıcı.
- Her SAKLAZ yanıtında **Tekrar dinle** ve kaynak etiketi (Yerel / Hafıza / Yerel AI / OpenAI / Sistem).
- Arka plana geçişte (`hidden/paused`) konuşma + mikrofon kapanır; `inactive`'de kapanmaz (izin diyaloğu akışını bozmamak için). Kotlin `onPause` ayrıca tanımayı iptal eder.
- 3 art arda sessizlik/anlaşılamama → konuşma modu kendiliğinden durur.
- "Yan tuşla açılınca dinle" varsayılanı **kapalı** yapıldı (Phase 1'de açıktı).

**B. AI Core**
- Yerel: `LocalIntentEngine` (selam, saat, tarih, kimlik, teşekkür, yardım, hatırla, hafıza sorgusu) — ağsız.
- Yerel LLM: **Gemini Nano / ML Kit GenAI Prompt API** (`genai-prompt:1.0.0-beta1`). Model APK'da yok; sistem yönetir; indirme yalnızca kullanıcı onayıyla. Ayrıntı: `docs/LOCAL_AI_EVALUATION.md`.
- Bulut: `GatewayClient` → SAKLAZ Gateway → OpenAI **Responses API** (`store:false`). Model ayarlanabilir.
- **Gateway** (`gateway/`): Node 24 + TypeScript (derleme adımı yok, çalışma zamanı bağımlılığı yok). Cihaz başına SHA-256 özetli Bearer token, dakikalık sınır, günlük istek kotası, günlük USD bütçe (ön maliyet kontrolü), model izin listesi, gövde doğrulaması, içerik loglamaz, upstream hata gövdesini sızdırmaz.

**C. Akıllı model seçimi** (`AssistantRouter`)
| İstek | Karar |
|---|---|
| Basit komut | Yerel kurallar (internet gerekmez) |
| Hafıza kaydı/sorgusu | Yerel hafıza |
| Karmaşık analiz | Bulut (izin modu: "Her seferinde sor" varsayılan) → yoksa yerel model → yoksa açıklama |
| Güncel bilgi (hava, kur, haber) | Bağlantı + izin varsa bulut; yoksa açık neden |
| Diğer genel | Önce yerel model, yoksa bulut (izinle) |
| İnternet yok | Yerel özellikler çalışır, bulut gerektirenler açıklanır |

**E. Hafıza**
- SQLite3MultipleCiphers (ChaCha20-Poly1305) — `package:sqlite3` 3.9 hook'u ile; APK'da `libsqlite3mc.so` doğrulandı.
- 256-bit anahtar `SecureRandom` ile üretilir, Android Keystore'daki AES-256-GCM anahtarıyla (StrongBox varsa) sarılır, `noBackupFilesDir`'de durur.
- **Fail-closed:** Şifreleme kütüphanesi veya anahtar doğrulanamazsa diske yazılmaz; bellek içi moda geçilir ve kullanıcı uyarılır.
- Tablolar: `messages` (en fazla 500), `facts` (yalnızca onayla), `preferences` (ayarlar, gateway tokenı).
- Hafıza ekranı: şifreleme durumu, bilgiler (ekle/sil/hepsini sil — onaylı), geçmişi temizle.

### Mimari kararlar (değişiklikler)
- Phase 0'daki "drift + SQLCipher" yerine **sqlite3 + SQLite3MultipleCiphers**: hazır imzalı ikili, MIT lisansı, OpenSSL bağımlılığı yok, kod üretimi gerektirmez.
- ML Kit iki izin ekledi: `com.google.android.apps.aicore.service.BIND_SERVICE` (AICore bağlantısı) ve AndroidX'in uygulama içi `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
- Debug yapısında HTTP'ye izin var (yerel ağdaki geliştirme gateway'i için); release HTTPS zorunlu.

### Test sonuçları
| Test | Tür | Sonuç |
|---|---|---|
| `flutter analyze` (tüm workspace) | Statik | ✅ No issues |
| saklaz_core | Birim | ✅ 3/3 |
| saklaz_voice | Birim | ✅ 11/11 |
| saklaz_ai_core (niyet, yönlendirme, motor, gateway istemcisi) | Birim (**MOCK** HTTP) | ✅ 26/26 |
| saklaz_memory (şifreleme: düz metin yok, yanlış anahtar reddi, kalıcılık) | Birim (**gerçek** SQLite3MC, Windows) | ✅ 10/10 |
| Uygulama widget testleri (Başlat/Durdur, konuşma döngüsü, sesli yanıt bağımsızlığı, arka plan, izin, bulut onayı, çevrimdışı, hafıza) | Widget (**MOCK** platform/gateway) | ✅ 22/22 |
| Kotlin birim | Birim | ✅ 3/3 |
| Gateway | **MOCK** OpenAI | ✅ 16/16 + `tsc` temiz |
| Gateway yerel süreç duman testi (gerçek HTTP; anahtar yok) | Entegrasyon | ✅ health 200, status 200, token yok 401, respond **503 not_configured**, logda içerik yok |
| `flutter build apk --release` | Derleme | ✅ 58,3 MB |
| Gerçek OpenAI Responses API çağrısı | Gerçek | ❌ **Yapılmadı** (anahtar/yayın yok) |
| Fold 7: mikrofon aç/kapat, Türkçe STT, yerel AI, internet kesilmesi | Cihaz | ❌ **Yapılmadı** (cihaz bağlı değil) |

### Hata kayıtları
| # | Hata | Neden | Çözüm |
|---|---|---|---|
| E8 | ADB: cihaz `offline`, sonra listede yok | USB hata ayıklama yetkisi/bağlantı | Kullanıcıdan telefonda onay istendi — çözülmedi |
| E9 | Hafıza testi: yeniden açılışta "Şifreleme destekli SQLite yüklenemedi" | Anahtar verilmeden önce sürüm sorgusu şifreli dosyayı okumaya çalıştı | Kütüphane kontrolü bellek içi ayrı bağlantıda; anahtar ilk okumadan önce |
| E10 | `EncryptedMemoryDatabase` iki arayüzü birden uyguluyordu | `all/add/clear` imza çakışması | Bilgiler ayrı `facts` nesnesi |
| E11 | `const Set` içinde yinelenen öğe | Durak kelime listesinde iki kez `ne` | Kaldırıldı |
| E12 | Gateway testleri: `node --test test/` modül bulunamadı | Node klasörü dosya sandı | Glob deseni |
| E13 | Gateway testlerinde beklenmeyen 429 | Test grubu dakikalık sınırı paylaşıyordu (gateway doğru davrandı) | Gruba yüksek sınır |
| E14 | Yerel süreç testi komutu reddedildi | Komut tüm `node.exe` süreçlerini öldürebilirdi | `timeout 25` ile kendi kendini kapatan süreç |
| E15 | Uzun Bash heredoc'ları yine ayrıştırılamadı (E3 tekrarı) | Çok sayıda tırnak | Write aracı |
| E16 | **Gerçek hata:** Yerel model durumu Ayarlar açılmadan okunmuyordu → yönlendirici hep "hazır değil" görüyordu | `ref.read(...).value` ilk okumada `null` | `localAiProvider.future` 3 sn zaman aşımıyla beklenir |
| E17 | Widget testinde onay kartına dokunulamadı | Kart ekran dışında (dar dış ekran) | `ensureVisible`; cihazda otomatik kaydırma var |

### Bilinen sınırlamalar
- Gateway günlük sayaçları bellekte; yeniden başlatmada sıfırlanır → OpenAI hesabında da aylık limit önerilir.
- Gateway yanıtı akışsız (streaming yok) — uzun yanıtlarda bekleme hissedilebilir.
- Gemini Nano Türkçe kalitesi bilinmiyor (belgelenmemiş).
- Kişisel bilgi sorgusu anahtar kelime eşleşmesiyle; anlamsal arama sonraki faz.

---

## 2026-11-07 — Phase 1: İskelet, Asistan Altyapısı, Arayüz, Ses

**Durum:** Kod yazıldı, otomatik testler ve derleme başarılı. **Gerçek cihaz ve emülatör testi YAPILMADI** (bkz. "Test edilemeyenler"). Bu yüzden Phase 1 tamamlanmış sayılmaz.

### Kararlar (kullanıcı onaylı)
- applicationId: `com.saklaz.assistant` · targetSdk/compileSdk 36 · minSdk 31
- Git uzak depo: https://github.com/SAKLAZ5341/Saklaz-A- (kullanıcı talebiyle)

### Ortam düzenlemeleri
| İşlem | Sonuç |
|---|---|
| `JAVA_HOME` (kullanıcı) = `C:\Program Files\Android\Android Studio\jbr` | ✅ Eklendi |
| `ANDROID_HOME` (kullanıcı) = `C:\Users\fatih\AppData\Local\Android\Sdk` | ✅ Eklendi |
| Kullanıcı PATH'ine `...\Sdk\platform-tools` eklendi | ✅ Mevcut kayıtlar korundu; yedek alındı |
| Java 1.6 | Dokunulmadı (talimat gereği) |
| GitHub CLI (`gh`) | winget ile kullanıcı kapsamında kuruldu |
| Doğrulama | JBR OpenJDK 25.0.3 ✅ · ADB 1.0.41 ✅ · Flutter 3.47.7 ✅ · Gradle 9.3.1 (wrapper) ✅ |

**Bilinen kısıt:** Sistem PATH'inde `C:\Windows\System32` kullanıcı PATH'inden önce geldiği için düz `java` komutu hâlâ Java 1.6'yı çalıştırır. Flutter/Gradle `JAVA_HOME` kullandığından derlemeyi etkilemez. Düzeltmek sistem PATH'i (yönetici) gerektirir — yapılmadı.

### Yapılanlar
1. **Monorepo** (Dart pub workspace): `apps/saklaz_app` + 6 paket.
2. **Katman eşlemesi:**
   | İstenen katman | Konum |
   |---|---|
   | presentation | `apps/saklaz_app/lib/presentation` |
   | application | `apps/saklaz_app/lib/application` (Riverpod Notifier'lar) |
   | domain | `packages/saklaz_core` (+ `lib/domain/domain.dart` erişim noktası) |
   | infrastructure | `apps/saklaz_app/lib/infrastructure/providers.dart` (composition root) |
   | ai_core | `packages/saklaz_ai_core` |
   | memory | `packages/saklaz_memory` |
   | voice | `packages/saklaz_voice` |
   | android_bridge | `packages/saklaz_android_bridge` (Dart) + `android/.../bridge` (Kotlin, Pigeon üretimi) |
   | integrations | `packages/saklaz_integrations` |
3. **Android asistan altyapısı:** `SaklazVoiceInteractionService`, `SaklazSessionService`, `SaklazSession`, vekil `SaklazRecognitionService`, `interaction_service.xml` (`supportsAssist=true`), `ASSIST` intent filtresi, `AssistantRoleController` (RoleManager).
4. **Pigeon 29.1.1:** Rol, asistan çağrısı, mikrofon izni, STT, TTS kanalları.
5. **Arayüz:** Koyu tema, animasyonlu AI küresi (duruma ve mikrofon seviyesine tepki), SAKLAZ amblemi + adaptif uygulama simgesi, mikrofon durumu göstergesi, konuşma geçmişi, Ayarlar, Asistan izinleri, Fold 7 dış/iç ekran yerleşimi.
6. **Ses:** Mikrofon izni akışı, `SpeechRecognizer` (tr-TR, cihaz içi öncelikli, dil desteklenmezse sistem motoruna düşme), `TextToSpeech` (tr-TR, `USAGE_ASSISTANT`).
7. **Zekâ:** Yapay zekâ YOK. `OfflinePlaceholderBrain` yalnızca selam/saat/tarih kalıplarına yanıt verir; diğer her şeyde AI'nın bağlı olmadığını söyler (ses hattını uçtan uca test etmek için).

### Önemli teknik bulgular
- **ROLE_ASSISTANT uygulama içinden istenemez** (AOSP: `requestable=false`). `createRequestRoleIntent` genellikle diyalog göstermeden reddedilir. Uygulama önce isteği dener, olmazsa Varsayılan uygulamalar ayarını açar. Rol durumu her zaman `RoleManager.isRoleHeld` + `VoiceInteractionService.isActiveService` ile **sistemden** okunur.
- **Asistan rolü sistem ses tanımasını devralır:** Rol alındığında `voice_recognition_service` SAKLAZ'ın servisine yönlenir. Boş servis diğer uygulamaların sesle yazmasını bozacağından `SaklazRecognitionService` gerçek bir tanıyıcıya (Google/Samsung) vekâlet eder. → Cihazda V6 testiyle doğrulanmalı.
- `SaklazSession` ekran içeriği/ekran görüntüsü toplamayı kapatır (`setDisabledShowContext`).
- Pigeon 29 Kotlin çıktısı coroutine kullanıyor → `kotlinx-coroutines-android` eklendi.

### Test sonuçları
| Test | Sonuç |
|---|---|
| `flutter analyze` (tüm workspace) | ✅ No issues found |
| Dart paket birim testleri | ✅ 18/18 (core 3, voice 8, ai_core 6, memory 1) |
| Flutter widget/uygulama testleri | ✅ 8/8 (Fold 7 kırılma noktaları, dış/iç ekran, mikrofon, mesaj+TTS, rol akışı, soğuk açılış çağrısı, izin reddi) |
| Kotlin birim testleri (`testDebugUnitTest`) | ✅ 3/3 (`RecognizerSelector`) |
| `flutter build apk --debug` | ✅ |
| `flutter build apk --release` | ✅ 48,7 MB (debug imzalı — yalnızca yerel test için) |
| ROLE_ASSISTANT kontrolü (cihazda) | ❌ **Yapılmadı** — cihaz yok |
| Gerçek cihazda asistan açılma / yan tuş | ❌ **Yapılmadı** — Fold 7 bağlı değil |
| Emülatör testi | ❌ **Yapılamadı** — donanım hızlandırma yok |

### Test edilemeyenler (Phase 1'i kapatmadan önce zorunlu)
Tümü `docs/DEVICE_TEST_PHASE1.md` içinde adım adım: kurulum/izinler (T1–T5), rol (R1–R4), asistan çağrısı ve **yan tuş** (A1–A6), ses (V1–V6), Fold 7 ekranları (F1–F4).

### Hata kayıtları
| # | Hata | Neden | Çözüm |
|---|---|---|---|
| E1 | `flutter pub add` "Failed to update packages" | Workspace üyeleri henüz çözümlenmemişti | pubspec'ler elle yazıldı, kökten `flutter pub get` |
| E2 | pubspec "Mapping values are not allowed here" | `description` içinde tırnaksız `:` | Açıklamalar tırnağa alındı |
| E3 | Bash heredoc "unexpected EOF" | Tek komutta çok sayıda heredoc/tırnak | Dosyalar Write aracıyla yazıldı |
| E4 | `Type 'Override' not found` | Riverpod 3'te `Override` `misc.dart`'a taşındı | `package:flutter_riverpod/misc.dart` import edildi |
| E5 | İzinler ekranında `RenderFlex overflowed by 135 pixels` (412 dp) | Yan tuş kartı başlığı dar ekranda taşıyordu | `Expanded` ile sarıldı — **gerçek UI hatası, test yakaladı** |
| E6 | Widget testinde `pumpAndSettle` zaman aşımı riski | Küre animasyonu sonsuz | Sabit kare ilerletme |
| E7 | Emülatör: `x86_64 emulation currently requires hardware acceleration` | Android Emulator Hypervisor Driver / WHPX kurulu değil | Çözülmedi — yönetici kurulumu gerekir (kullanıcı kararı) |

### Phase 1'de bilinçli olarak YAPILMAYANLAR
- Kalıcı/şifreli hafıza ve kalıcı ayarlar (Phase 2) — geçmiş ve ayarlar yalnızca RAM'de.
- Yerel LLM / OpenAI (Phase 4). Uygulama hiçbir ağ isteği yapmaz; release manifest'inde INTERNET izni yok.
- Dosyaya log yazma (path_provider gerektirir) — bellek içi logger + debug'da logcat.
- `go_router` (Phase 0 kararı) — 3 ekran için Navigator yeterli; gerekirse sonra eklenir.
- `saklaz_agent` paketi — Phase 5'te.

---

## 2026-11-07 — Phase 0: Ortam Analizi ve Mimari Dokümantasyon

### Yapılanlar
- Geliştirme ortamı salt-okunur komutlarla incelendi (hiçbir kurulum değiştirilmedi/silinmedi).
- Doküman seti oluşturuldu: README, PROJECT_PLAN, ARCHITECTURE, SECURITY, ROADMAP, DEVELOPMENT_LOG.
- Git deposu başlatıldı, `.gitignore` eklendi, ilk commit atıldı.

### Ortam Raporu

| # | Bileşen | Bulunan | Durum |
|---|---|---|---|
| 1 | Flutter | 3.47.7 stable (`C:\src\flutter`) | ✅ (daha yeni sürüm mevcut — opsiyonel) |
| 2 | Dart | 3.13.5 stable | ✅ |
| 3 | Android SDK | `C:\Users\fatih\AppData\Local\Android\Sdk` — platform 34, 35, **36 (Android 16)**, 37.0; build-tools 22.0.1, 36.0.0, 37.0.0; NDK 28.2; CMake; tüm lisanslar kabul edilmiş | ✅ |
| 4 | Android Studio / araçlar | Android Studio (build 262.9437…, JBR dahil); cmdline-tools 22.0; Emulator 37.2.12; AVD: `Medium_Phone_API_37.0` | ✅ |
| 5 | Java JDK | Flutter/Gradle: Studio JBR **OpenJDK 25.0.3** ✅ — ancak PATH'teki `java` → `C:\Windows\System32\java.exe` = **Java 1.6.0_29** (`C:\Program Files\Java\jre6`); `JAVA_HOME` tanımsız | ⚠️ |
| 6 | Gradle | Global kurulum yok (normal, proje Gradle Wrapper kullanır); önbellekte `gradle-9.3.1` | ✅ (JDK 25 için Gradle ≥ 9.1 gerekir; Phase 1'de doğrulanacak) |
| 7 | ADB | 1.0.41 (platform-tools 37.0.1) mevcut, ancak **PATH'te değil**; bağlı cihaz **yok** | ⚠️ |
| 8 | Git | 2.56.0; global `user.name`/`user.email` tanımlı | ✅ |
| 9 | Claude Code | 2.1.319 | ✅ |
| — | `flutter doctor` | No issues found | ✅ |
| — | Node.js / npm | v24.21.0 / 11.19.0 (gateway için yeterli) | ✅ |
| — | Python | Yok (zorunlu değil) | ℹ️ |
| — | Docker | Yok (zorunlu değil; gateway dağıtımında gerekebilir) | ℹ️ |

### Eksikler / Riskler
1. **Eski Java 1.6 PATH'te önde.** Flutter etkilenmiyor (Studio JBR'ı kullanıyor), ama terminalden doğrudan `gradlew` çalıştırıldığında veya Java isteyen başka araçlarda hata verir. Java 1.6 ayrıca güvenlik desteği çoktan bitmiş bir sürümdür.
2. **`JAVA_HOME` tanımsız.**
3. **`ANDROID_HOME` tanımsız** — Flutter SDK'yı buluyor, ancak bazı araçlar (Gradle CLI, üçüncü parti) bu değişkeni arar.
4. **`adb` PATH'te değil.**
5. **Fiziksel cihaz bağlı değil** — Fold 7 olmadan yan tuş ve Samsung'a özgü davranışlar test edilemez.
6. Emülatör imajı Android 17 (API 37); hedef Android 16 (API 36) için ayrıca bir API 36 AVD oluşturulması faydalı olur.

### Öneriler (kullanıcı onayı ile uygulanacak — Phase 0'da hiçbiri uygulanmadı)
1. Kullanıcı ortam değişkenleri:
   - `JAVA_HOME = C:\Program Files\Android\Android Studio\jbr`
   - `ANDROID_HOME = C:\Users\fatih\AppData\Local\Android\Sdk`
   - PATH'e ekle (en başa): `%JAVA_HOME%\bin`, `%ANDROID_HOME%\platform-tools`
2. Java 1.6 (`jre6`) kullanılmıyorsa Denetim Masası'ndan kaldırılması (başka eski bir program ona bağlı olabilir — kontrol edilmeli).
3. Android Studio SDK Manager ile Android 16 (API 36) sistem imajı + AVD.
4. Fold 7: Ayarlar → Telefon hakkında → Yazılım bilgileri → "Yapım numarası"na 7 kez dokun → Geliştirici seçenekleri → USB hata ayıklama.
5. İsteğe bağlı: `flutter upgrade` (Phase 1 başlamadan, tek seferde).

### Test
- Bu fazda çalışan kod yok; test edilecek özellik yok. Ortam testi: `flutter doctor -v` temiz.

### Sonraki Adım
- Kullanıcı onayı bekleniyor → Phase 1 (bkz. PROJECT_PLAN.md §5).
