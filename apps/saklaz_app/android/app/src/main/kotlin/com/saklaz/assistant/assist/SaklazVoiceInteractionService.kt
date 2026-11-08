package com.saklaz.assistant.assist

import android.service.voice.VoiceInteractionService
import android.util.Log

/**
 * Android dijital asistan altyapısının ana servisi. Sürekli dinleme / uyandırma
 * kelimesi YOKTUR; mikrofon yalnızca yan tuşla panel açıldığında çalışır.
 */
class SaklazVoiceInteractionService : VoiceInteractionService() {

    override fun onReady() {
        super.onReady()
        Log.i(TAG, "VoiceInteractionService hazır (SAKLAZ aktif asistan).")
        // Yan tuş paneli anında açılsın diye motoru önceden ısıt.
        runCatching { OverlayEngine.get(this) }.onFailure { Log.w(TAG, "Panel motoru ısıtılamadı", it) }
    }

    override fun onShutdown() {
        Log.i(TAG, "VoiceInteractionService kapatıldı.")
        super.onShutdown()
    }

    private companion object {
        const val TAG = "SaklazVIS"
    }
}
