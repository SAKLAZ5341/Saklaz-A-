# SAKLAZ AI — Proje Planı

## 1. Vizyon
Kullanıcının telefonunda yaşayan, Türkçe konuşan, kişisel verileri cihazda şifreli tutan, gerektiğinde buluttan güç alan ve yalnızca kullanıcı onayıyla eylem yapan kişisel asistan.

## 2. Kapsam

**Kapsam içinde (v1):** Android 16 / Galaxy Z Fold 7; varsayılan asistan rolü; yan tuşla çağırma; Türkçe ses; yerel + bulut LLM; şifreli hafıza; not/hatırlatıcı; takvim; Gmail; WhatsApp (intent + bildirim yanıtı); kamera/belge analizi; onaylı Agent.

**Kapsam dışında (v1):** iOS; Play Store'da genel yayın; çok kullanıcılı hesap sistemi; WhatsApp'ta tam otomasyon; sürekli dinleme ile uyandırma kelimesi ("Hey SAKLAZ" — ileride değerlendirilecek).

## 3. Çalışma Kuralları
1. Her faz kendi dalında (`phase/N-kisa-ad`) geliştirilir, bitince `main`'e birleştirilir.
2. Commit mesajları: `tür(kapsam): açıklama` — örn. `feat(agent): onay kapısı eklendi`, `docs: phase 0 mimari dokümanları`.
3. Her faz sonunda: otomatik testler yeşil + gerçek cihaz testi + DEVELOPMENT_LOG.md kaydı + kullanıcı onayı.
4. Mimari kararlar ADR olarak `docs/adr/` altında kaydedilir.

## 4. "Tamamlandı" Tanımı (Definition of Done)
- [ ] Kod yazıldı, `flutter analyze` uyarısız
- [ ] Birim/widget testleri yazıldı ve geçiyor
- [ ] Gerçek cihazda (Fold 7) manuel test senaryosu geçti — katlı ve açık ekranda
- [ ] Gerekli izinler ve onay akışları SECURITY.md ile uyumlu
- [ ] Kişisel veri teknik loglara düşmüyor
- [ ] DEVELOPMENT_LOG.md güncellendi
- [ ] Açıklayıcı commit atıldı

## 5. Phase 1 — Uygulanabilir İş Listesi (onay sonrası başlanacak)

**Hedef:** Yan tuşa basılı tutulduğunda Fold 7'de SAKLAZ'ın boş asistan arayüzünün açılması ve modüler iskeletin kurulması.

| # | Görev | Çıktı | Doğrulama |
|---|---|---|---|
| 1.0 | **Ön koşul:** Fold 7'de Geliştirici seçenekleri + USB hata ayıklama; `adb devices` ile görünmesi | Bağlı cihaz | `adb devices -l` |
| 1.1 | Monorepo kurulumu (pub workspaces), `analysis_options.yaml` (katı lint) | `apps/`, `packages/` | `dart analyze` |
| 1.2 | `flutter create` ile `apps/saklaz_app` (org: `com.saklaz`, yalnız Android + Windows platformu), `minSdk`/`targetSdk 36` | Çalışan boş uygulama | Fold 7'de açılıyor |
| 1.3 | Gradle/AGP/Kotlin sürümlerinin JDK 25 (Studio JBR) ile uyumunun doğrulanması | Temiz build | `flutter build apk --debug` |
| 1.4 | `saklaz_core`: Result tipi, hata tipleri, `AppLogger` arayüzü + dosya logger | Paket + testler | `dart test` |
| 1.5 | Kotlin: `SaklazVoiceInteractionService`, `SaklazSessionService`, `SaklazSession`, `SaklazRecognitionService`, `interaction_service.xml`, manifest kayıtları | Asistan bileşenleri | Ayarlar'da "Dijital asistan uygulaması" listesinde SAKLAZ görünüyor |
| 1.6 | `ASSIST` intent'li Activity (yedek giriş) | | `adb shell am start -a android.intent.action.ASSIST` |
| 1.7 | RoleManager ile "Varsayılan asistan yap" ekranı (rol durumu kontrolü + istek) | Onboarding ekranı | Rol alınıyor, `adb shell cmd role get-role-holders android.app.role.ASSISTANT` |
| 1.8 | Pigeon ile Kotlin ↔ Dart kanalı: `onAssistInvoked`, `isAssistantRoleHeld`, `requestAssistantRole` | Tip güvenli kanal | Birim + cihaz testi |
| 1.9 | Önceden ısıtılmış FlutterEngine ile asistan overlay'inin hızlı açılması | Overlay UI | Açılış süresi ölçülür (<500 ms hedef) |
| 1.10 | Fold 7 uyarlanabilir iskelet UI (dış ekran / iç ekran) | Ana ekran | Katlı/açık manuel test |
| 1.11 | **Yan tuş doğrulaması** (Samsung ayarı → Dijital asistan) | Test kaydı | Fold 7'de basılı tutunca overlay açılıyor |
| 1.12 | GitHub Actions (veya yerel script) — analyze + test | CI | Yeşil çalışma |
| 1.13 | ADR'ler, DEVELOPMENT_LOG güncellemesi, commit | Dokümanlar | — |

**Phase 1'de yapılmayacaklar:** AI, ses tanıma, veritabanı — yalnızca iskelet ve asistan giriş noktası.

**Kullanıcıdan Phase 1 öncesi beklenenler:**
1. Fold 7'de USB hata ayıklamanın açılıp bilgisayara bağlanması.
2. Uygulama paket adı onayı (öneri: `com.saklaz.assistant`).
3. Ortam önerilerinin (DEVELOPMENT_LOG.md §Öneriler) uygulanıp uygulanmayacağı kararı.
4. Kod için uzak depo (GitHub özel depo vb.) istenip istenmediği.

## 6. Sonraki Fazların Özet Kabul Kriterleri
- **Faz 2:** DB dosyası şifreli (hex dump ile okunamaz), uygulama yeniden kurulmadan anahtar kaybolmuyor, hatırlatıcı Doze modunda zamanında çalıyor.
- **Faz 3:** Türkçe 20 test cümlesinde STT doğruluğu kabul edilebilir; TTS doğal; uçtan uca gecikme ölçüldü.
- **Faz 4:** APK içinde anahtar yok (APK taraması); gateway rate limit testi; yerel model benchmark raporu.
- **Faz 5:** Tüm `high` risk araçlar onaysız çalışamıyor (otomatik test); prompt injection test senaryoları.
- **Faz 6:** Türkçe belgelerde OCR; görsel buluta onaysız gitmiyor.
