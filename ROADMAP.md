# SAKLAZ AI — Yol Haritası

Her faz bitiminde: testler geçer, gerçek cihazda manuel test yapılır, DEVELOPMENT_LOG.md güncellenir, açıklayıcı commit atılır ve **kullanıcı onayı alınmadan sonraki faza geçilmez.**

| Faz | Başlık | Ana Çıktılar | Durum |
|---|---|---|---|
| 0 | Ortam & Mimari | Ortam raporu, doküman seti, Git deposu | ✅ Tamamlandı (onay bekliyor) |
| 1 | İskelet & Asistan Rolü | Monorepo, Flutter app, Kotlin VoiceInteractionService, RoleManager isteği, yan tuşla açılan boş overlay, logger, CI | ⏳ |
| 2 | Şifreli Hafıza, Notlar, Hatırlatıcılar | drift+SQLCipher, Keystore anahtar sarma, not/hatırlatıcı CRUD, bildirimler | ⏳ |
| 3 | Ses (Türkçe) | STT/TTS soyutlaması, Android tr-TR STT/TTS, overlay'de sesli konuşma döngüsü | ⏳ |
| 4 | AI Core: Gateway + Bulut + Yerel LLM | Node.js gateway, Responses API akışı, CloudLlmProvider, yerel model benchmark ve LocalLlmProvider, Router | ⏳ |
| 5 | Agent & Entegrasyonlar | Tool sistemi, onay kapısı, audit log; Takvim, Gmail, WhatsApp (intent + bildirim) | ⏳ |
| 6 | Görsel Zekâ | Kamera, galeri, belge tarama, cihazda OCR, bulutta çok modlu analiz | ⏳ |
| 7 | Cilalama & Sağlamlaştırma | Fold 7 iç/dış ekran deneyimi, performans, pil, güvenlik denetimi, release imzalama | ⏳ |
| 8 | Windows (opsiyonel) | platform_windows katmanı, masaüstü UI | ⏳ |

## Kilometre Taşları

- **M1 (Faz 1 sonu):** Yan tuşa basılı tutunca SAKLAZ overlay'i Fold 7'de açılıyor.
- **M2 (Faz 3 sonu):** "SAKLAZ, yarın 9'da toplantıyı hatırlat" sesli komutuyla hatırlatıcı kuruluyor (kural tabanlı, AI'sız).
- **M3 (Faz 4 sonu):** Türkçe serbest sohbet; çevrimdışıyken yerel model, çevrimiçiyken bulut.
- **M4 (Faz 5 sonu):** "Ahmet'e WhatsApp'tan geç kalacağımı yaz" → önizleme → onay → WhatsApp'ta hazır mesaj.
- **M5 (Faz 6 sonu):** Fotoğrafı çekilen faturanın özetlenip hatırlatıcıya dönüştürülmesi.

## Riskler ve Belirsizlikler

| Risk | Etki | Azaltma |
|---|---|---|
| Samsung yan tuşun üçüncü parti asistanla davranışı | M1 | Faz 1'in ilk işi gerçek cihazda doğrulama (spike) |
| Yerel LLM'in Türkçe kalitesi/hızı | M3 | Birden çok model ölçülür; yetersizse yerel model yalnızca basit niyetlerde kullanılır |
| Gmail restricted kapsam doğrulaması | Faz 5 | Kişisel kullanımda "Testing" modu; alternatif olarak yalnızca okuma kapsamı |
| WhatsApp için resmî API olmaması | Faz 5 | Intent + bildirim yanıtı ile sınırlı ama güvenli kapsam |
| Gateway barındırma maliyeti/yönetimi | Faz 4 | Hafif sunucusuz seçenek; başlangıçta yerel ağ |
