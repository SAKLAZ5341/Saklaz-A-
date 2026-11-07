package com.saklaz.assistant.voice

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/** SAKLAZ'ın kendi vekil servisine dönmeden gerçek bir tanıyıcı oluşturur. */
object RecognizerFactory {

    fun onDeviceAvailable(context: Context): Boolean =
        SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    fun findDelegateComponent(context: Context): ComponentName? {
        val services = context.packageManager.queryIntentServices(
            Intent(RecognitionService.SERVICE_INTERFACE),
            PackageManager.ResolveInfoFlags.of(0),
        )
        val candidates = services.mapNotNull { info ->
            info.serviceInfo?.let { RecognizerSelector.Candidate(it.packageName, it.name) }
        }
        return RecognizerSelector.choose(candidates, context.packageName)
            ?.let { ComponentName(it.packageName, it.className) }
    }

    /** Vekil servis için: varsayılan tanıyıcıya (bize) DEĞİL, gerçek motora bağlan. */
    fun createDelegateRecognizer(context: Context): SpeechRecognizer? {
        val component = findDelegateComponent(context) ?: return null
        return SpeechRecognizer.createSpeechRecognizer(context, component)
    }

    /**
     * Uygulama içi kullanım: tercih edilirse cihaz üzerinde (çevrimdışı) tanıyıcı,
     * değilse gerçek motor bileşeni.
     */
    fun create(context: Context, preferOnDevice: Boolean): Pair<SpeechRecognizer, Boolean>? {
        if (preferOnDevice && onDeviceAvailable(context)) {
            return SpeechRecognizer.createOnDeviceSpeechRecognizer(context) to true
        }
        return createDelegateRecognizer(context)?.let { it to false }
    }
}
