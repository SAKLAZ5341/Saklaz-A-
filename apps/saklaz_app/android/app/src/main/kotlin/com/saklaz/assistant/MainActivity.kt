package com.saklaz.assistant

import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.saklaz.assistant.assist.AssistantRoleController
import com.saklaz.assistant.assist.MicPermissionController
import com.saklaz.assistant.bridge.AssistLaunchFlutterApi
import com.saklaz.assistant.bridge.AssistLaunchHostApi
import com.saklaz.assistant.bridge.AssistLaunchMessage
import com.saklaz.assistant.bridge.AssistLaunchSource
import com.saklaz.assistant.bridge.AssistantRoleHostApi
import com.saklaz.assistant.bridge.PermissionHostApi
import com.saklaz.assistant.bridge.SpeechFlutterApi
import com.saklaz.assistant.bridge.SpeechHostApi
import com.saklaz.assistant.bridge.TtsFlutterApi
import com.saklaz.assistant.bridge.TtsHostApi
import com.saklaz.assistant.voice.SpeechController
import com.saklaz.assistant.voice.TtsController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Flutter arayüzünü taşıyan tek Activity. Üç yoldan açılabilir:
 *  1. Başlatıcı simgesi
 *  2. Asistan oturumu (yan tuş) -> SaklazSession.startAssistantActivity
 *  3. android.intent.action.ASSIST intent'i
 */
class MainActivity : FlutterActivity() {

    private val scope = MainScope()
    private var pendingLaunch: AssistLaunchMessage? = null
    private var dartReady = false

    private lateinit var roleController: AssistantRoleController
    private lateinit var micController: MicPermissionController
    private var speech: SpeechController? = null
    private var tts: TtsController? = null
    private var assistApi: AssistLaunchFlutterApi? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        roleController = AssistantRoleController(this)
        micController = MicPermissionController(this)
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            pendingLaunch = parseLaunch(intent)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val speechApi = SpeechFlutterApi(messenger)
        val ttsApi = TtsFlutterApi(messenger)
        assistApi = AssistLaunchFlutterApi(messenger)

        speech = SpeechController(applicationContext) { e ->
            scope.launch { runCatching { speechApi.onSpeechEvent(e) } }
        }
        tts = TtsController(applicationContext) { e ->
            scope.launch { runCatching { ttsApi.onTtsEvent(e) } }
        }

        AssistantRoleHostApi.setUp(messenger, roleController)
        PermissionHostApi.setUp(messenger, micController)
        SpeechHostApi.setUp(messenger, speech)
        TtsHostApi.setUp(messenger, tts)
        AssistLaunchHostApi.setUp(
            messenger,
            object : AssistLaunchHostApi {
                override fun consumePendingLaunch(): AssistLaunchMessage? {
                    dartReady = true
                    return pendingLaunch.also { pendingLaunch = null }
                }
            },
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        AssistantRoleHostApi.setUp(messenger, null)
        PermissionHostApi.setUp(messenger, null)
        SpeechHostApi.setUp(messenger, null)
        TtsHostApi.setUp(messenger, null)
        AssistLaunchHostApi.setUp(messenger, null)
        speech?.release()
        tts?.release()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val launch = parseLaunch(intent) ?: return
        if (dartReady) {
            scope.launch { runCatching { assistApi?.onAssistInvoked(launch) } }
        } else {
            pendingLaunch = launch
        }
    }

    override fun onPause() {
        super.onPause()
        // Uygulama arka plana geçince mikrofon ve konuşma derhal durdurulur.
        speech?.cancel()
        tts?.stop()
    }

    @Deprecated("FlutterActivity bir ComponentActivity değildir; klasik API kullanılır.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!roleController.onActivityResult(requestCode, resultCode)) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (!micController.onRequestPermissionsResult(requestCode)) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun parseLaunch(intent: Intent?): AssistLaunchMessage? {
        intent ?: return null
        val source = when {
            intent.getStringExtra(EXTRA_ASSIST_SOURCE) == SOURCE_SESSION ->
                AssistLaunchSource.VOICE_INTERACTION_SESSION
            intent.action == Intent.ACTION_ASSIST -> AssistLaunchSource.ASSIST_INTENT
            else -> return null
        }
        Log.i(TAG, "Asistan çağrısı: $source")
        return AssistLaunchMessage(source = source, timestampMillis = System.currentTimeMillis())
    }

    companion object {
        private const val TAG = "SaklazMain"
        const val EXTRA_ASSIST_SOURCE = "com.saklaz.assistant.ASSIST_SOURCE"
        const val SOURCE_SESSION = "voice_interaction_session"
    }
}
