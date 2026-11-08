package com.saklaz.assistant

import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.saklaz.assistant.ai.LiteRtLlmController
import com.saklaz.assistant.ai.ModelController
import com.saklaz.assistant.assist.AssistantRoleController
import com.saklaz.assistant.assist.MicPermissionController
import com.saklaz.assistant.bridge.AppsHostApi
import com.saklaz.assistant.bridge.AssistLaunchFlutterApi
import com.saklaz.assistant.bridge.AssistLaunchHostApi
import com.saklaz.assistant.bridge.AssistLaunchMessage
import com.saklaz.assistant.bridge.AssistLaunchSource
import com.saklaz.assistant.bridge.AssistantRoleHostApi
import com.saklaz.assistant.bridge.DevConfigHostApi
import com.saklaz.assistant.bridge.FileHostApi
import com.saklaz.assistant.bridge.KeyVaultHostApi
import com.saklaz.assistant.bridge.LocalLlmHostApi
import com.saklaz.assistant.bridge.ModelFlutterApi
import com.saklaz.assistant.bridge.ModelHostApi
import com.saklaz.assistant.bridge.NetworkHostApi
import com.saklaz.assistant.bridge.NotificationsHostApi
import com.saklaz.assistant.bridge.PermissionHostApi
import com.saklaz.assistant.bridge.PhoneActionsHostApi
import com.saklaz.assistant.bridge.ReminderHostApi
import com.saklaz.assistant.bridge.RuntimePermissionHostApi
import com.saklaz.assistant.bridge.SecretsHostApi
import com.saklaz.assistant.bridge.SpeechFlutterApi
import com.saklaz.assistant.bridge.SpeechHostApi
import com.saklaz.assistant.bridge.TtsFlutterApi
import com.saklaz.assistant.bridge.TtsHostApi
import com.saklaz.assistant.net.NetworkController
import com.saklaz.assistant.platform.ActivityBridge
import com.saklaz.assistant.platform.AppsController
import com.saklaz.assistant.platform.DevConfigController
import com.saklaz.assistant.platform.FileController
import com.saklaz.assistant.platform.NotificationsController
import com.saklaz.assistant.platform.PhoneActionsController
import com.saklaz.assistant.platform.RuntimePermissionController
import com.saklaz.assistant.reminders.ReminderScheduler
import com.saklaz.assistant.security.KeyVaultController
import com.saklaz.assistant.security.SecretsController
import com.saklaz.assistant.voice.SpeechController
import com.saklaz.assistant.voice.TtsController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
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
    private lateinit var bridge: ActivityBridge
    private val devConfig = DevConfigController()
    private var speech: SpeechController? = null
    private var tts: TtsController? = null
    private var llm: LiteRtLlmController? = null
    private var models: ModelController? = null
    private var assistApi: AssistLaunchFlutterApi? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        roleController = AssistantRoleController(this)
        micController = MicPermissionController(this)
        bridge = ActivityBridge(this)
        super.onCreate(savedInstanceState)
        devConfig.capture(intent)
        if (savedInstanceState == null) pendingLaunch = parseLaunch(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val app = applicationContext

        val speechApi = SpeechFlutterApi(messenger)
        val ttsApi = TtsFlutterApi(messenger)
        val modelApi = ModelFlutterApi(messenger)
        assistApi = AssistLaunchFlutterApi(messenger)

        speech = SpeechController(app) { e -> scope.launch { runCatching { speechApi.onSpeechEvent(e) } } }
        tts = TtsController(app) { e -> scope.launch { runCatching { ttsApi.onTtsEvent(e) } } }
        llm = LiteRtLlmController(app)
        models = ModelController(app) { p -> scope.launch { runCatching { modelApi.onDownloadProgress(p) } } }
        val launcher = { this as android.content.Context }

        AssistantRoleHostApi.setUp(messenger, roleController)
        PermissionHostApi.setUp(messenger, micController)
        SpeechHostApi.setUp(messenger, speech)
        TtsHostApi.setUp(messenger, tts)
        KeyVaultHostApi.setUp(messenger, KeyVaultController(app))
        NetworkHostApi.setUp(messenger, NetworkController(app))
        LocalLlmHostApi.setUp(messenger, llm)
        ModelHostApi.setUp(messenger, models)
        SecretsHostApi.setUp(messenger, SecretsController(app))
        AppsHostApi.setUp(messenger, AppsController(app, launcher))
        RuntimePermissionHostApi.setUp(messenger, RuntimePermissionController(bridge))
        PhoneActionsHostApi.setUp(messenger, PhoneActionsController(app, launcher))
        ReminderHostApi.setUp(messenger, ReminderScheduler(app))
        FileHostApi.setUp(messenger, FileController(bridge))
        NotificationsHostApi.setUp(messenger, NotificationsController(app))
        DevConfigHostApi.setUp(messenger, devConfig)
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
        tearDown(flutterEngine.dartExecutor.binaryMessenger)
        speech?.release()
        tts?.release()
        llm?.release()
        models?.release()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun tearDown(m: BinaryMessenger) {
        AssistantRoleHostApi.setUp(m, null)
        PermissionHostApi.setUp(m, null)
        SpeechHostApi.setUp(m, null)
        TtsHostApi.setUp(m, null)
        KeyVaultHostApi.setUp(m, null)
        NetworkHostApi.setUp(m, null)
        LocalLlmHostApi.setUp(m, null)
        ModelHostApi.setUp(m, null)
        SecretsHostApi.setUp(m, null)
        AppsHostApi.setUp(m, null)
        RuntimePermissionHostApi.setUp(m, null)
        PhoneActionsHostApi.setUp(m, null)
        ReminderHostApi.setUp(m, null)
        FileHostApi.setUp(m, null)
        NotificationsHostApi.setUp(m, null)
        DevConfigHostApi.setUp(m, null)
        AssistLaunchHostApi.setUp(m, null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        devConfig.capture(intent)
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
        if (roleController.onActivityResult(requestCode, resultCode)) return
        if (bridge.onActivityResult(requestCode, resultCode, data)) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (micController.onRequestPermissionsResult(requestCode)) return
        if (bridge.onRequestPermissionsResult(requestCode)) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun parseLaunch(intent: Intent?): AssistLaunchMessage? {
        intent ?: return null
        val source = when {
            intent.getStringExtra(EXTRA_ASSIST_SOURCE) == SOURCE_SESSION -> AssistLaunchSource.VOICE_INTERACTION_SESSION
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
