# SAKLAZ AI — Geliştirme Günlüğü

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
