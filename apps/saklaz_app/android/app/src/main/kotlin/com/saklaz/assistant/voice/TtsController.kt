package com.saklaz.assistant.voice

import android.content.Context
import android.media.AudioAttributes
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.saklaz.assistant.bridge.FlutterError
import com.saklaz.assistant.bridge.TtsEventMessage
import com.saklaz.assistant.bridge.TtsEventType
import com.saklaz.assistant.bridge.TtsHostApi
import com.saklaz.assistant.bridge.TtsInitResultMessage
import java.util.Locale
import kotlinx.coroutines.CompletableDeferred

/** Android TextToSpeech ile Türkçe sesli yanıt. Cihazdaki TTS motorunu kullanır. */
class TtsController(
    private val context: Context,
    private val emit: (TtsEventMessage) -> Unit,
) : TtsHostApi {

    private var tts: TextToSpeech? = null
    private var ready = false
    private val main = Handler(Looper.getMainLooper())

    override suspend fun initialize(localeTag: String): TtsInitResultMessage {
        release()
        val status = CompletableDeferred<Int>()
        val engine = TextToSpeech(context) { status.complete(it) }
        tts = engine
        if (status.await() != TextToSpeech.SUCCESS) {
            ready = false
            return TtsInitResultMessage(ready = false, languageSupported = false)
        }
        engine.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
        )
        val lang = engine.setLanguage(Locale.forLanguageTag(localeTag))
        val supported = lang != TextToSpeech.LANG_MISSING_DATA && lang != TextToSpeech.LANG_NOT_SUPPORTED
        engine.setOnUtteranceProgressListener(progress)
        ready = true
        return TtsInitResultMessage(ready = true, languageSupported = supported, engine = engine.defaultEngine)
    }

    override fun speak(utteranceId: String, text: String, rate: Double, pitch: Double) {
        val engine = tts
        if (engine == null || !ready) throw FlutterError("tts-not-ready", "TTS hazır değil.", null)
        engine.setSpeechRate(rate.toFloat())
        engine.setPitch(pitch.toFloat())
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), utteranceId)
    }

    override fun stop() {
        tts?.stop()
    }

    fun release() {
        tts?.let {
            it.stop()
            it.shutdown()
        }
        tts = null
        ready = false
    }

    private val progress = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String) = post(TtsEventType.STARTED, utteranceId)
        override fun onDone(utteranceId: String) = post(TtsEventType.DONE, utteranceId)
        override fun onStop(utteranceId: String, interrupted: Boolean) = post(TtsEventType.STOPPED, utteranceId)

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String) = post(TtsEventType.ERROR, utteranceId)
        override fun onError(utteranceId: String, errorCode: Int) = post(TtsEventType.ERROR, utteranceId)
    }

    // UtteranceProgressListener arka plan iş parçacığında çağrılır; kanal ana iş parçacığı ister.
    private fun post(type: TtsEventType, id: String) {
        main.post { emit(TtsEventMessage(type = type, utteranceId = id)) }
    }
}
