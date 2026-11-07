# SAKLAZ AI

Türkçe konuşan, gizlilik odaklı kişisel yapay zekâ asistanı.

> **Durum:** Phase 0 — Ortam analizi ve mimari dokümantasyon. Henüz çalışan uygulama kodu yoktur.

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
