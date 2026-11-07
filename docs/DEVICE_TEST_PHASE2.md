# Phase 2 — Galaxy Z Fold 7 Cihaz Test Kılavuzu

Phase 1 testleri: [DEVICE_TEST_PHASE1.md](DEVICE_TEST_PHASE1.md). Sonuçlar `DEVELOPMENT_LOG.md`'ye işlenir.

```powershell
adb devices -l
cd C:\Users\fatih\Desktop\SAKLAZ-AI\apps\saklaz_app
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
adb logcat -s flutter SaklazSpeech SaklazLocalAi SaklazKeyVault SaklazMain
```

## A. Konuşma kontrolü
| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| M1 | Uygulamayı aç | "Mikrofon kapalı"; yeşil gizlilik noktası YOK | ☐ |
| M2 | Konuşmayı Başlat | İzin (ilk kez) → "Mikrofon açık · Dinliyor", yeşil nokta | ☐ |
| M3 | Konuşmayı Durdur | Mikrofon derhal kapanır, yeşil nokta söner | ☐ |
| M4 | Başlat → "saat kaç" → yanıt | Söylenen metin ve yanıt ekranda; yanıt okununca yeniden dinler | ☐ |
| M5 | Sesli yanıt kapalı + Başlat | Yanıt yazılı gelir, okunmaz; dinleme sürer | ☐ |
| M6 | Yanıtta "Tekrar dinle" | Yanıt yeniden okunur | ☐ |
| M7 | Dinlerken Ana ekran tuşu | Mikrofon kapanır; geri dönünce "arka plana geçtiği için durduruldu" | ☐ |
| M8 | 3 kez sessiz kal | Konuşma modu kendiliğinden kapanır | ☐ |
| M9 | Katlı ↔ açık ekran, konuşma sürerken | Taşma yok, durum korunur | ☐ |

## B. Türkçe ses tanıma
| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| S1 | 10 Türkçe cümle (ı, ğ, ş, ç, ö, ü içeren) | Doğruluk notu: __/10 | ☐ |
| S2 | Cihaz içi tanıma açık + uçak modu | Çalışıyor mu? Hata mesajı anlaşılır mı? | ☐ |

## C. Yerel AI (Gemini Nano)
| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| L1 | Ayarlar → Yerel zekâ | Durum + cihaz RAM/SoC gerçek değerler | ☐ |
| L2 | "İndirilebilir" ise Modeli indir | Onay diyaloğu → indirme → "hazır" | ☐ |
| L3 | "Bana kısa bir fıkra anlat" | "Yerel AI" etiketli Türkçe yanıt; süre: ___ s | ☐ |
| L4 | `adb shell dumpsys meminfo com.saklaz.assistant` | TOTAL PSS: ___ MB | ☐ |

## D. Hafıza
| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| H1 | Hafıza ekranı | "Şifreli ve yalnızca bu cihazda", SQLite3 Multiple Ciphers sürümü, donanım anahtarı | ☐ |
| H2 | "Hatırla ki doğum günüm 12 Mart" → Kaydet | Hafıza ekranında görünür | ☐ |
| H3 | Uygulamayı kapat/aç → "Doğum günüm ne zamandı" | "Kayıtlarıma göre: …12 Mart" | ☐ |
| H4 | Bilgi sil / geçmişi temizle | Onay sonrası silinir | ☐ |
| H5 | Şifreleme kanıtı (debug APK) | Aşağıdaki komutla çekilen dosya `SQLite format 3` ile BAŞLAMAMALI | ☐ |

```powershell
adb exec-out run-as com.saklaz.assistant cat no_backup/saklaz_memory.db > mem.db
Format-Hex mem.db | Select-Object -First 2
```

## E. Bulut (OpenAI gateway) — GERÇEK test
Ön koşul: gateway çalışıyor (`gateway/README.md`), geçerli `OPENAI_API_KEY`, cihaz tokenı.
Geliştirme: PC ile telefon aynı Wi-Fi; debug APK; adres `http://<PC-IP>:8787`.

| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| G1 | Ayarlar → Kaydet ve bağlantıyı test et | "erişilebilir, token geçerli", OpenAI anahtarı tanımlı | ☐ |
| G2 | Yanlış token | "Gateway cihaz tokenını kabul etmedi" | ☐ |
| G3 | "Kuantum ve klasik bilgisayarları karşılaştır" | Onay kartı → Gönder → "OpenAI" etiketli yanıt | ☐ |
| G4 | Onay kartında "Gönderme" | Gateway logunda istek YOK | ☐ |
| G5 | Gateway logu | İçerik yok; yalnızca token sayısı/maliyet | ☐ |

## F. İnternet kesilmesi
| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| N1 | Uçak modu → "Saat kaç" | Yerel yanıt | ☐ |
| N2 | Uçak modu → "İstanbul hava durumu" | "internet bağlantısı yok" açıklaması | ☐ |
| N3 | Uçak modu → hafıza sorusu | Yerel hafızadan yanıt | ☐ |
| N4 | Gateway kapalıyken bulut sorusu | "Gateway'e ulaşılamıyor" | ☐ |
