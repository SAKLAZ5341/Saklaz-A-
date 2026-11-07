# SAKLAZ AI

Türkçe konuşan, gizlilik odaklı kişisel yapay zekâ asistanı.

> **Durum:** Phase 2 — İki beyinli AI core, OpenAI gateway, konuşma kontrolü ve şifreli hafıza kodlandı; otomatik testler ve release APK tamam. Fold 7 ve gerçek OpenAI testi bekleniyor.

## Hedef

| Konu | Değer |
|---|---|
| İlk hedef cihaz | Samsung Galaxy Z Fold 7 |
| İşletim sistemi | Android 16 (API 36) |
| Minimum Android | Android 12 (API 31) — ileride tartışılacak |
| İleride | Windows masaüstü desteği (modüler mimari sayesinde) |

## Ana Özellikler (planlanan)

- Android **varsayılan dijital asistanı** olarak atanabilme (`RoleManager.ROLE_ASSISTANT`)
- Yan tuşa basılı tutarak çağrılabilme (Samsung *Yan tuş → Dijital asistan* ayarı üzerinden)
- Türkçe doğal sesli konuşma (STT + TTS)
- Yerel yapay zekâ (cihaz üzerinde LLM)
- OpenAI bulut zekâsı (**Responses API**, yalnızca güvenli gateway üzerinden)
- Şifreli kişisel hafıza (SQLite + SQLCipher, anahtar Android Keystore'da)
- Gmail ve Google Takvim entegrasyonu
- WhatsApp entegrasyonu (resmî ve politika uyumlu yollarla — bkz. ARCHITECTURE.md)
- Hatırlatıcı ve not yönetimi
- Kamera, fotoğraf ve belge analizi
- Kullanıcı onaylı telefon işlemleri yapan AI Agent

## Teknoloji

Flutter · Dart · Kotlin · Android SDK · SQLite/SQLCipher · OpenAI Responses API · Yerel LLM · VoiceInteractionService · RoleManager

## Doküman Haritası

| Dosya | İçerik |
|---|---|
| [PROJECT_PLAN.md](PROJECT_PLAN.md) | Kapsam, fazlar, kabul kriterleri, Phase 1 iş listesi |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Katmanlar, modüller, veri akışı, teknoloji kararları |
| [SECURITY.md](SECURITY.md) | Tehdit modeli, anahtar yönetimi, izinler, onay mekanizması |
| [ROADMAP.md](ROADMAP.md) | Faz faz yol haritası |
| [DEVELOPMENT_LOG.md](DEVELOPMENT_LOG.md) | Geliştirme günlüğü ve ortam raporu |
| [gateway/README.md](gateway/README.md) | OpenAI gateway kurulum ve API |
| [docs/LOCAL_AI_EVALUATION.md](docs/LOCAL_AI_EVALUATION.md) | Yerel model değerlendirmesi |
| [docs/DEVICE_TEST_PHASE2.md](docs/DEVICE_TEST_PHASE2.md) | Phase 2 cihaz test kılavuzu |

## Geliştirme Ortamı (Phase 0'da doğrulandı)

- Flutter 3.47.7 (stable) / Dart 3.13.5
- Android SDK: platform android-36 (Android 16) ve android-37 kurulu, build-tools 37.0.0
- JDK: Android Studio JBR (OpenJDK 25) — Flutter/Gradle bunu kullanır
- Gradle: proje bazında Gradle Wrapper ile
- Git 2.56, Node.js 24 (gateway için)

Ayrıntılar ve eksikler için: [DEVELOPMENT_LOG.md](DEVELOPMENT_LOG.md)

## Temel Kurallar

1. API anahtarları **asla** APK'ya gömülmez.
2. Kişisel veriler cihazda ve şifreli tutulur.
3. Riskli her işlem kullanıcı onayı gerektirir.
4. Gerçek cihazda test edilmeyen özellik "tamamlandı" sayılmaz.
5. Her aşama ayrı ve açıklayıcı bir Git commit'i ile kaydedilir.

## Derleme ve Çalıştırma

```powershell
cd C:\Users\fatih\Desktop\SAKLAZ-AI
flutter pub get                      # tüm workspace
flutter analyze                      # statik analiz
cd packages\saklaz_voice; dart test  # paket testleri (her paket için)
cd ..\..\apps\saklaz_app
flutter test                         # widget testleri
flutter build apk --release          # APK
flutter run --release                # bağlı cihazda çalıştır
```

Pigeon sözleşmesi değişirse: `cd packages\saklaz_android_bridge; dart run pigeon --input pigeons\saklaz_api.dart`

Cihaz test adımları: [docs/DEVICE_TEST_PHASE1.md](docs/DEVICE_TEST_PHASE1.md)

## Klasör Yapısı

```
apps/saklaz_app/          Flutter uygulaması (presentation, application, domain, infrastructure)
  android/                Kotlin: asistan servisleri, ses, Pigeon host
packages/saklaz_core/     Domain: Result, hata, logger, mesaj
packages/saklaz_voice/    STT/TTS portları + ses oturumu
packages/saklaz_ai_core/  Asistan beyni arayüzü
packages/saklaz_memory/   Hafıza deposu arayüzü
packages/saklaz_android_bridge/  Pigeon köprüsü
packages/saklaz_integrations/    Entegrasyon arayüzleri
gateway/                  Node.js/TypeScript OpenAI gateway (anahtar yalnızca burada)
docs/                     Test kılavuzları, yerel AI değerlendirmesi
```
