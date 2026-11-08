package com.saklaz.assistant.platform

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import com.saklaz.assistant.ai.AiServices
import com.saklaz.assistant.bridge.AppsHostApi
import com.saklaz.assistant.bridge.AssistSessionHostApi
import com.saklaz.assistant.bridge.DownloadProgressMessage
import com.saklaz.assistant.bridge.KeyVaultHostApi
import com.saklaz.assistant.bridge.LocalLlmHostApi
import com.saklaz.assistant.bridge.MicPermissionState
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
import com.saklaz.assistant.reminders.ReminderScheduler
import com.saklaz.assistant.security.KeyVaultController
import com.saklaz.assistant.security.SecretsController
import com.saklaz.assistant.voice.SpeechController
import com.saklaz.assistant.voice.TtsController
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Activity GEREKTİRMEYEN kanalların ortak kurulumu. Hem ana uygulama (MainActivity)
 * hem yan tuş paneli (OverlayEngine) bunu kullanır.
 */
class SaklazChannels(
    private val context: Context,
    private val messenger: BinaryMessenger,
    private val scope: CoroutineScope,
    /** Uygulama başlatmak için kullanılacak bağlam (Activity veya uygulama bağlamı). */
    launcher: () -> Context,
    session: AssistSessionHostApi,
) {
    val speech: SpeechController
    val tts: TtsController
    private val progress: (DownloadProgressMessage) -> Unit

    init {
        val app = context.applicationContext
        val speechApi = SpeechFlutterApi(messenger)
        val ttsApi = TtsFlutterApi(messenger)
        val modelApi = ModelFlutterApi(messenger)
        speech = SpeechController(app) { e -> scope.launch { runCatching { speechApi.onSpeechEvent(e) } } }
        tts = TtsController(app) { e -> scope.launch { runCatching { ttsApi.onTtsEvent(e) } } }
        progress = { p -> scope.launch { runCatching { modelApi.onDownloadProgress(p) } } }
        AiServices.addProgressListener(progress)

        SpeechHostApi.setUp(messenger, speech)
        TtsHostApi.setUp(messenger, tts)
        KeyVaultHostApi.setUp(messenger, KeyVaultController(app))
        NetworkHostApi.setUp(messenger, NetworkController(app))
        LocalLlmHostApi.setUp(messenger, AiServices.llm(app))
        ModelHostApi.setUp(messenger, AiServices.models(app))
        SecretsHostApi.setUp(messenger, SecretsController(app))
        AppsHostApi.setUp(messenger, AppsController(app, launcher))
        PhoneActionsHostApi.setUp(messenger, PhoneActionsController(app, launcher))
        ReminderHostApi.setUp(messenger, ReminderScheduler(app))
        NotificationsHostApi.setUp(messenger, NotificationsController(app))
        AssistSessionHostApi.setUp(messenger, session)
    }

    fun tearDown() {
        AiServices.removeProgressListener(progress)
        listOf<(BinaryMessenger) -> Unit>(
            { SpeechHostApi.setUp(it, null) }, { TtsHostApi.setUp(it, null) }, { KeyVaultHostApi.setUp(it, null) },
            { NetworkHostApi.setUp(it, null) }, { LocalLlmHostApi.setUp(it, null) }, { ModelHostApi.setUp(it, null) },
            { SecretsHostApi.setUp(it, null) }, { AppsHostApi.setUp(it, null) }, { PhoneActionsHostApi.setUp(it, null) },
            { ReminderHostApi.setUp(it, null) }, { NotificationsHostApi.setUp(it, null) }, { AssistSessionHostApi.setUp(it, null) },
        ).forEach { it(messenger) }
        speech.release()
        tts.release()
    }

    companion object {
        /** Panelde Activity yok: izinler yalnızca OKUNUR, istenemez (ana uygulamada istenir). */
        fun registerReadOnlyPermissions(context: Context, messenger: BinaryMessenger) {
            fun granted(p: String) = context.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
            PermissionHostApi.setUp(messenger, object : PermissionHostApi {
                override fun getMicrophonePermission() =
                    if (granted(Manifest.permission.RECORD_AUDIO)) MicPermissionState.GRANTED else MicPermissionState.DENIED
                override suspend fun requestMicrophonePermission() = getMicrophonePermission()
                override fun openAppSettings() {}
            })
            RuntimePermissionHostApi.setUp(messenger, object : RuntimePermissionHostApi {
                override fun check(permission: com.saklaz.assistant.bridge.RuntimePermission): MicPermissionState {
                    val p = when (permission) {
                        com.saklaz.assistant.bridge.RuntimePermission.CONTACTS -> Manifest.permission.READ_CONTACTS
                        com.saklaz.assistant.bridge.RuntimePermission.CALENDAR -> Manifest.permission.READ_CALENDAR
                        com.saklaz.assistant.bridge.RuntimePermission.NOTIFICATIONS -> Manifest.permission.POST_NOTIFICATIONS
                    }
                    return if (granted(p)) MicPermissionState.GRANTED else MicPermissionState.DENIED
                }
                override suspend fun request(permission: com.saklaz.assistant.bridge.RuntimePermission) = check(permission)
            })
        }

        fun openMainApp(context: Context) {
            context.startActivity(
                Intent(context, com.saklaz.assistant.MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            )
        }
    }
}
