# Phase 1 — Galaxy Z Fold 7 Cihaz Test Kılavuzu

Bu testler yapılmadan Phase 1'in asistan özellikleri **tamamlandı sayılmaz**.
Sonuçlar `DEVELOPMENT_LOG.md` dosyasına işlenir.

## 0. Hazırlık

1. Fold 7: Ayarlar → Telefon hakkında → Yazılım bilgileri → **Yapım numarası**'na 7 kez dokun.
2. Ayarlar → Geliştirici seçenekleri → **USB hata ayıklama** açık.
3. USB ile bağla, telefondaki "USB hata ayıklamaya izin ver" sorusunu onayla.
4. Bilgisayarda (yeni terminal):

```powershell
adb devices -l                     # cihaz "device" olarak görünmeli
cd C:\Users\fatih\Desktop\SAKLAZ-AI\apps\saklaz_app
flutter run --release              # veya: adb install -r build\app\outputs\flutter-apk\app-release.apk
```

## 1. Kurulum ve izinler

| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| T1 | Uygulama açılışı | Koyu tema, SAKLAZ logosu, animasyonlu küre | ☐ |
| T2 | İzinler ekranı | "SAKLAZ varsayılan asistan değil" + API 36 + cihaz modeli | ☐ |
| T3 | Mikrofon düğmesi (ilk kez) | Android izin diyaloğu çıkar | ☐ |
| T4 | İzin reddedilirse | Mikrofon açılmaz, uyarı metni görünür | ☐ |
| T5 | Manifest izinleri | Yalnızca RECORD_AUDIO (release'de INTERNET yok) | ☐ |

```powershell
adb shell dumpsys package com.saklaz.assistant | Select-String "permission"
```

## 2. Varsayılan asistan rolü

| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| R1 | "Varsayılan asistan yap" | Sistem diyaloğu YA DA Varsayılan uygulamalar ayarı açılır | ☐ |
| R2 | Ayarlar → Uygulamalar → Varsayılan uygulamalar → Dijital asistan uygulaması | Listede **SAKLAZ** görünür | ☐ |
| R3 | SAKLAZ seçilip geri dönülünce | Kart yeşil: "SAKLAZ varsayılan asistan" | ☐ |
| R4 | Sistem doğrulaması | Aşağıdaki komut `com.saklaz.assistant` döndürür | ☐ |

```powershell
adb shell cmd role get-role-holders android.app.role.ASSISTANT
adb shell settings get secure voice_interaction_service
adb shell settings get secure voice_recognition_service
```

## 3. Asistan çağrısı

| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| A1 | Komutla oturum | SAKLAZ açılır ve (ayar açıksa) dinlemeye başlar | ☐ |
| A2 | ASSIST intent'i | SAKLAZ açılır | ☐ |
| A3 | Ayarlar → Gelişmiş özellikler → Yan tuş → Basılı tut → **Dijital asistan** | Seçenek mevcut | ☐ |
| A4 | **Yan tuşa basılı tut** (uygulama kapalıyken) | SAKLAZ açılır, mikrofon göstergesi "Dinliyor" | ☐ |
| A5 | Yan tuş (uygulama arka plandayken) | Mevcut ekran öne gelir, dinlemeye başlar | ☐ |
| A6 | Yan tuş (kilit ekranında) | Güvenlik gereği kilit açılması istenir | ☐ |

```powershell
adb shell cmd voiceinteraction show
adb shell am start -a android.intent.action.ASSIST
adb logcat -s SaklazVIS SaklazSession SaklazMain SaklazRole SaklazSpeech SaklazRecognition
```

## 4. Ses

| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| V1 | "Merhaba" de | Ara metin görünür; sonra "Merhaba, ben SAKLAZ…" yazılı + sesli | ☐ |
| V2 | "Saat kaç" de | Doğru saat Türkçe okunur | ☐ |
| V3 | Konuşurken mikrofon düğmesi | Konuşma durur | ☐ |
| V4 | Uygulama arka plana alınınca | Mikrofon derhal kapanır (yeşil gizlilik noktası söner) | ☐ |
| V5 | Çevrimdışı (uçak modu) + cihaz içi tanıma | Türkçe dil paketi varsa çalışır; yoksa anlaşılır hata | ☐ |
| V6 | SAKLAZ asistanken **klavyenin mikrofonu** | Diğer uygulamalarda sesle yazma çalışmaya devam eder (vekil servis) | ☐ |

## 5. Fold 7 ekranları

| # | Test | Beklenen | Sonuç |
|---|---|---|---|
| F1 | Katlı (dış ekran) | Tek sütun: küre üstte, geçmiş altta | ☐ |
| F2 | Açık (iç ekran) | İki sütun: küre solda, geçmiş sağda | ☐ |
| F3 | Uygulama açıkken katla/aç | Durum ve geçmiş korunur, taşma yok | ☐ |
| F4 | Flex modu / yatay | Taşma veya kesilme yok | ☐ |
