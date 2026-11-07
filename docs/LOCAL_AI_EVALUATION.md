# Yerel AI Değerlendirmesi — Samsung Galaxy Z Fold 7

Tarih: 2026-11-08 · Durum: **Seçim yapıldı, cihazda doğrulanmadı**

## Donanım (genel bilgi — cihazda uygulama içinden ölçülecek)
- SoC: Snapdragon 8 Elite for Galaxy (arm64-v8a)
- RAM: 12 GB (1 TB modelde 16 GB)
- Uygulama, Ayarlar → Yerel zekâ → **Cihaz kapasitesi** satırında gerçek değerleri
  (`ActivityManager.MemoryInfo`, `Build.SOC_MODEL`) gösterir.

## Değerlendirilen seçenekler

| Seçenek | Model boyutu | Uygulama RAM'i | Türkçe | Artı | Eksi | Karar |
|---|---|---|---|---|---|---|
| **Gemini Nano (ML Kit GenAI Prompt API)** | APK'da yok; sistem (AICore) yönetir | Uygulama sürecine yüklenmez | Belgelerde Türkçe dil listesi bulunamadı → **deneysel** | İndirme/güncelleme sistemde; NPU hızlandırma; Fold7 destek listesinde görünüyor | Beta API (`genai-prompt:1.0.0-beta1`); cihaz/sürüm bağımlı; ön planda çalışır | ✅ **Seçildi** |
| Gemma 3 1B int4 (LiteRT-LM) | ~557 MB indirme | ~1,0–1,2 GB tepe (S24 Ultra ölçümü) | Çok dilli, sınırlı | Tam kontrol, çevrimdışı | Model dağıtımı + lisans kabulü; APK/depolama yükü | ⏸ Yedek seçenek (yüklenmedi) |
| Gemma 3n E2B/E4B | 2–4 GB+ | 2–3 GB+ | Daha iyi | Daha güçlü | Telefonu zorlar, pil/ısı | ❌ Bu aşamada uygun değil |
| llama.cpp + GGUF 1–3B | 0,7–2 GB | 1–3 GB | Modele bağlı | Esnek | FFI + bakım yükü, NPU yok | ❌ |

## Uygulanan mimari
- `LocalLlm` arayüzü (`packages/saklaz_ai_core`) — Android uygulaması `AndroidLocalLlm` (Pigeon → `LocalAiController.kt`).
- Model **asla kendiliğinden indirilmez**; durum "indirilebilir" ise kullanıcı onayıyla indirilir.
- Model yoksa: kural tabanlı yerel motor (saat, tarih, selam, hafıza) çalışmaya devam eder.
- Yerel modele giden istem cihazdan çıkmaz; ilgili kayıtlı kişisel bilgiler (en fazla 3) yerel bağlama eklenebilir.
- Cevap uzunluğu 16–512 token ile sınırlı.

## Cihazda yapılacak doğrulamalar (docs/DEVICE_TEST_PHASE2.md L1–L4)
1. `checkStatus()` sonucu (AVAILABLE / DOWNLOADABLE / UNAVAILABLE) ve `getBaseModelName()`.
2. 10 Türkçe istemde yanıt kalitesi ve dil tutarlılığı.
3. İlk yanıt süresi ve toplam süre.
4. Uygulama bellek kullanımı (`adb shell dumpsys meminfo com.saklaz.assistant`).

Türkçe kalitesi yetersizse: yerel model yalnızca basit sohbette kullanılır veya kapatılır
(Ayarlar → "Cihaz içi dil modelini kullan"), Gemma 3 1B seçeneği ayrı bir onayla değerlendirilir.

## Kaynaklar
- LiteRT-LM genel bakış: https://ai.google.dev/edge/litert-lm/overview
- Gemma3-1B-IT (LiteRT) model kartı: https://huggingface.co/litert-community/Gemma3-1B-IT
- ML Kit GenAI API'leri: https://developers.google.com/ml-kit/genai
- Prompt API başlangıç: https://developers.google.com/ml-kit/genai/prompt/android/get-started
- `GenerativeModel` referansı: https://developers.google.com/android/reference/kotlin/com/google/mlkit/genai/prompt/GenerativeModel
