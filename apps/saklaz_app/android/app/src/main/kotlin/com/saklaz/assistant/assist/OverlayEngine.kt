package com.saklaz.assistant.assist

import android.content.Context
import android.util.Log
import com.saklaz.assistant.bridge.AssistLaunchFlutterApi
import com.saklaz.assistant.bridge.AssistLaunchHostApi
import com.saklaz.assistant.bridge.AssistLaunchMessage
import com.saklaz.assistant.bridge.AssistLaunchSource
import com.saklaz.assistant.bridge.AssistSessionHostApi
import com.saklaz.assistant.platform.SaklazChannels
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/**
 * Yan tuş paneli için önceden ısıtılmış Flutter motoru (`assistantOverlayMain`).
 * Uygulama açılmadan, VoiceInteractionSession penceresinde ekranın altından çıkar.
 */
object OverlayEngine {
    private const val TAG = "SaklazOverlay"
    private var engine: FlutterEngine? = null
    private var launchApi: AssistLaunchFlutterApi? = null
    private val scope = MainScope()

    /** Panelin "kapat" isteğini oturuma iletir. */
    @Volatile var onDismiss: (() -> Unit)? = null

    @Volatile private var dartReady = false
    @Volatile private var pending: AssistLaunchMessage? = null

    @Synchronized
    fun get(context: Context): FlutterEngine {
        engine?.let { return it }
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val e = FlutterEngine(app)
        val messenger = e.dartExecutor.binaryMessenger
        SaklazChannels(
            context = app,
            messenger = messenger,
            scope = scope,
            launcher = { app },
            session = object : AssistSessionHostApi {
                override fun isOverlay() = true
                override fun dismiss() {
                    onDismiss?.invoke()
                }
                override fun openMainApp() {
                    SaklazChannels.openMainApp(app)
                    onDismiss?.invoke()
                }
            },
        )
        SaklazChannels.registerReadOnlyPermissions(app, messenger)
        AssistLaunchHostApi.setUp(messenger, object : AssistLaunchHostApi {
            override fun consumePendingLaunch(): AssistLaunchMessage? {
                dartReady = true
                return pending.also { pending = null }
            }
        })
        launchApi = AssistLaunchFlutterApi(messenger)
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "assistantOverlayMain"),
        )
        engine = e
        Log.i(TAG, "Panel motoru hazır")
        return e
    }

    /** Yan tuşa basıldı: panel dinlemeye başlar. */
    fun invoke() {
        val msg = AssistLaunchMessage(AssistLaunchSource.VOICE_INTERACTION_SESSION, System.currentTimeMillis())
        if (dartReady) {
            scope.launch { runCatching { launchApi?.onAssistInvoked(msg) } }
        } else {
            pending = msg
        }
    }
}
