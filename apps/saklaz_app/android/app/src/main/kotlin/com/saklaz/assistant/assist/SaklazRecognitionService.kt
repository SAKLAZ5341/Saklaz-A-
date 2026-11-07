package com.saklaz.assistant.assist

import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.SpeechRecognizer
import android.util.Log
import com.saklaz.assistant.voice.RecognizerFactory

/**
 * Vekil (proxy) tanıma servisi.
 *
 * Neden var? `interaction_service.xml` bir recognitionService ister ve SAKLAZ
 * asistan rolünü aldığında Android, sistemin varsayılan ses tanıma servisini
 * BU servise yönlendirir. Boş bir servis olsaydı klavye mikrofonu gibi diğer
 * uygulamaların sesli girişi bozulurdu. Bu yüzden istekler cihazdaki gerçek bir
 * tanıyıcıya (Google / Samsung) aynen iletilir.
 *
 * Gizlilik: SAKLAZ bu yolla gelen diğer uygulamaların seslerini/metinlerini
 * saklamaz, loglamaz, Flutter tarafına iletmez.
 */
class SaklazRecognitionService : RecognitionService() {

    private var delegate: SpeechRecognizer? = null

    override fun onStartListening(recognizerIntent: Intent, listener: Callback) {
        releaseDelegate()
        val recognizer = RecognizerFactory.createDelegateRecognizer(this)
        if (recognizer == null) {
            Log.w(TAG, "Vekalet edilecek tanıyıcı bulunamadı.")
            listener.error(SpeechRecognizer.ERROR_CLIENT)
            return
        }
        delegate = recognizer
        recognizer.setRecognitionListener(ForwardingListener(listener))
        recognizer.startListening(recognizerIntent)
    }

    override fun onStopListening(listener: Callback) {
        delegate?.stopListening()
    }

    override fun onCancel(listener: Callback) {
        releaseDelegate()
    }

    override fun onDestroy() {
        releaseDelegate()
        super.onDestroy()
    }

    private fun releaseDelegate() {
        delegate?.let {
            it.cancel()
            it.destroy()
        }
        delegate = null
    }

    private class ForwardingListener(private val cb: Callback) : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = cb.readyForSpeech(params ?: Bundle())
        override fun onBeginningOfSpeech() = cb.beginningOfSpeech()
        override fun onRmsChanged(rmsdB: Float) = cb.rmsChanged(rmsdB)
        override fun onBufferReceived(buffer: ByteArray?) {
            if (buffer != null) cb.bufferReceived(buffer)
        }
        override fun onEndOfSpeech() = cb.endOfSpeech()
        override fun onError(error: Int) = cb.error(error)
        override fun onResults(results: Bundle?) = cb.results(results ?: Bundle())
        override fun onPartialResults(partialResults: Bundle?) =
            cb.partialResults(partialResults ?: Bundle())
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private companion object {
        const val TAG = "SaklazRecognition"
    }
}
