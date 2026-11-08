package com.saklaz.assistant

import android.content.ComponentCallbacks2
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.saklaz.assistant.ai.AiServices
import com.saklaz.assistant.assist.AssistantRoleController
import com.saklaz.assistant.assist.MicPermissionController
import com.saklaz.assistant.bridge.AssistLaunchFlutterApi
import com.saklaz.assistant.bridge.AssistLaunchHostApi
import com.saklaz.assistant.bridge.AssistLaunchMessage
import com.saklaz.assistant.bridge.AssistLaunchSource
import com.saklaz.assistant.bridge.AssistSessionHostApi
import com.saklaz.assistant.bridge.AssistantRoleHostApi
import com.saklaz.assistant.bridge.DevConfigHostApi
import com.saklaz.assistant.bridge.FileHostApi
import com.saklaz.assistant.bridge.PermissionHostApi
import com.saklaz.assistant.bridge.RuntimePermissionHostApi
import com.saklaz.assistant.platform.ActivityBridge
import com.saklaz.assistant.platform.DevConfigController
import com.saklaz.assistant.platform.FileController
import com.saklaz.assistant.platform.RuntimePermissionController
import com.saklaz.assistant.platform.SaklazChannels
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Tam SAKLAZ uygulaması. Yan tuş artık bu ekranı açmaz (bkz. SaklazSession paneli);
 * ASSIST intent'i ve başlatıcı simgesi ile açılır.
 */
class MainActivity : FlutterActivity() {

    private val scope = MainScope()
    private var pendingLaunch: AssistLaunchMessage? = null
    private var dartReady = false

    private lateinit var roleController: AssistantRoleController
    private lateinit var micController: MicPermissionController
    private lateinit var bridge: ActivityBridge
    private val devConfig = DevConfigController()
    private var channels: SaklazChannels? = null
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
        assistApi = AssistLaunchFlutterApi(messenger)
        channels = SaklazChannels(
            context = this,
            messenger = messenger,
            scope = scope,
            launcher = { this },
            session = object : AssistSessionHostApi {
                override fun isOverlay() = false
                override fun dismiss() {}
                override fun openMainApp() {}
            },
        )
        AssistantRoleHostApi.setUp(messenger, roleController)
        PermissionHostApi.setUp(messenger, micController)
        RuntimePermissionHostApi.setUp(messenger, RuntimePermissionController(bridge))
        FileHostApi.setUp(messenger, FileController(bridge))
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
        val m = flutterEngine.dartExecutor.binaryMessenger
        channels?.tearDown()
        channels = null
        AssistantRoleHostApi.setUp(m, null)
        PermissionHostApi.setUp(m, null)
        RuntimePermissionHostApi.setUp(m, null)
        FileHostApi.setUp(m, null)
        DevConfigHostApi.setUp(m, null)
        AssistLaunchHostApi.setUp(m, null)
        super.cleanUpFlutterEngine(flutterEngine)
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
        channels?.speech?.cancel()
        channels?.tts?.stop()
    }

    /** Sistem bellek isterse yerel modeli bırak (telefonun donmasını önler). */
    @Deprecated("Sistem API'si")
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        @Suppress("DEPRECATION")
        if (level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND) {
            Log.i(TAG, "Bellek baskısı ($level): yerel model bellekten bırakılıyor")
            AiServices.releaseModelMemory()
        }
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
