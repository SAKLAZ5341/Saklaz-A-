package com.saklaz.assistant.voice

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import com.saklaz.assistant.bridge.FlutterError
import com.saklaz.assistant.bridge.SpeechEngineInfoMessage
import com.saklaz.assistant.bridge.SpeechEventMessage
import com.saklaz.assistant.bridge.SpeechEventType
import com.saklaz.assistant.bridge.SpeechHostApi

/**
 * Türkçe konuşma tanıma. Mikrofon YALNIZCA [startListening] çağrıldığında açılır
 * ve tek bir ifade sonunda (veya stop/cancel ile) kapanır. Sürekli dinleme yok.
 * Ses verisi kaydedilmez; yalnızca tanınan metin Flutter'a iletilir.
 */
class SpeechController(
    private val context: Context,
    private val emit: (SpeechEventMessage) -> Unit,
) : SpeechHostApi {

    private var recognizer: SpeechRecognizer? = null
    private var usingOnDevice = false
    private var lastLocale = "tr-TR"
    private var fallbackTried = false

    override fun getEngineInfo(): SpeechEngineInfoMessage {
        val onDevice = RecognizerFactory.onDeviceAvailable(context)
        val component = RecognizerFactory.findDelegateComponent(context)
        return SpeechEngineInfoMessage(
            available = onDevice || component != null,
            onDevice = onDevice,
            engineComponent = component?.flattenToShortString(),
        )
    }

    override fun startListening(localeTag: String, preferOnDevice: Boolean) {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw FlutterError("mic-permission", "Mikrofon izni verilmemiş.", null)
        }
        lastLocale = localeTag
        fallbackTried = false
        start(preferOnDevice)
    }

    private fun start(preferOnDevice: Boolean) {
        release()
        val created = RecognizerFactory.create(context, preferOnDevice)
            ?: throw FlutterError("no-recognizer", "Cihazda konuşma tanıma servisi bulunamadı.", null)
        val (sr, onDevice) = created
        recognizer = sr
        usingOnDevice = onDevice
        sr.setRecognitionListener(listener)
        sr.startListening(buildIntent(lastLocale))
        Log.i(TAG, "Dinleme başladı (onDevice=$onDevice, locale=$lastLocale)")
    }

    private fun buildIntent(localeTag: String) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeTag)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, localeTag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
        }

    override fun stopListening() {
        recognizer?.stopListening()
    }

    override fun cancel() {
        release()
    }

    fun release() {
        recognizer?.let {
            it.cancel()
            it.destroy()
        }
        recognizer = null
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) =
            emit(SpeechEventMessage(type = SpeechEventType.READY_FOR_SPEECH))

        override fun onBeginningOfSpeech() =
            emit(SpeechEventMessage(type = SpeechEventType.BEGINNING_OF_SPEECH))

        override fun onRmsChanged(rmsdB: Float) =
            emit(SpeechEventMessage(type = SpeechEventType.RMS_CHANGED, rmsDb = rmsdB.toDouble()))

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() =
            emit(SpeechEventMessage(type = SpeechEventType.END_OF_SPEECH))

        override fun onError(error: Int) {
            // Cihaz içi model Türkçe'yi desteklemiyorsa bir kez sistem motoruna düş.
            val languageProblem = error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
                error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE
            if (usingOnDevice && languageProblem && !fallbackTried) {
                Log.w(TAG, "Cihaz içi tanıyıcı $lastLocale desteklemiyor; sistem motoruna geçiliyor.")
                fallbackTried = true
                try {
                    start(preferOnDevice = false)
                    return
                } catch (e: FlutterError) {
                    Log.w(TAG, "Yedek tanıyıcı başlatılamadı: ${e.message}")
                }
            }
            release()
            emit(
                SpeechEventMessage(
                    type = SpeechEventType.ERROR,
                    errorCode = error.toLong(),
                    errorMessage = describeError(error),
                ),
            )
        }

        override fun onResults(results: Bundle?) {
            val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
            emit(SpeechEventMessage(type = SpeechEventType.FINAL_RESULT, text = text ?: ""))
            release()
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull() ?: return
            emit(SpeechEventMessage(type = SpeechEventType.PARTIAL_RESULT, text = text))
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private companion object {
        const val TAG = "SaklazSpeech"

        fun describeError(code: Int): String = when (code) {
            SpeechRecognizer.ERROR_AUDIO -> "Ses kaydı hatası"
            SpeechRecognizer.ERROR_CLIENT -> "İstemci hatası"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Yetersiz izin"
            SpeechRecognizer.ERROR_NETWORK -> "Ağ hatası"
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Ağ zaman aşımı"
            SpeechRecognizer.ERROR_NO_MATCH -> "Konuşma anlaşılamadı"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Tanıyıcı meşgul"
            SpeechRecognizer.ERROR_SERVER -> "Sunucu hatası"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Konuşma algılanmadı"
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "Dil desteklenmiyor"
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "Dil paketi yüklü değil"
            SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "Çok fazla istek"
            else -> "Bilinmeyen hata ($code)"
        }
    }
}
