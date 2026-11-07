package com.saklaz.assistant.assist

import android.service.voice.VoiceInteractionService
import android.util.Log

/**
 * Android dijital asistan altyapısının ana servisi.
 *
 * Kullanıcı SAKLAZ'ı "Dijital asistan uygulaması" olarak seçtiğinde sistem
 * (VoiceInteractionManagerService) bu servise bağlanır. Asistan her
 * çağrıldığında oturumu [SaklazSessionService] oluşturur.
 *
 * Bu sınıf kasıtlı olarak hafif tutulur: sürekli dinleme / uyandırma kelimesi
 * (hotword) YOKTUR. Mikrofon yalnızca kullanıcı asistanı çağırdığında açılır.
 */
class SaklazVoiceInteractionService : VoiceInteractionService() {

    override fun onReady() {
        super.onReady()
        Log.i(TAG, "VoiceInteractionService hazır (SAKLAZ aktif asistan).")
    }

    override fun onShutdown() {
        Log.i(TAG, "VoiceInteractionService kapatıldı.")
        super.onShutdown()
    }

    private companion object {
        const val TAG = "SaklazVIS"
    }
}
