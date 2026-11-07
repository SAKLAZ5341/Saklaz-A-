package com.saklaz.assistant.assist

import android.app.Activity
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.voice.VoiceInteractionService
import android.util.Log
import com.saklaz.assistant.bridge.AssistantRoleHostApi
import com.saklaz.assistant.bridge.AssistantRoleStatusMessage
import com.saklaz.assistant.bridge.RoleRequestOutcome
import kotlinx.coroutines.CompletableDeferred

/**
 * ROLE_ASSISTANT durumunu RoleManager'dan okur. Uygulama rolün alındığını
 * asla varsaymaz; her sorgu sistemden gelir.
 *
 * Not: AOSP rol tanımında ROLE_ASSISTANT "requestable=false" olduğundan
 * createRequestRoleIntent çoğu cihazda diyalog göstermeden RESULT_CANCELED
 * döner. Bu durumda kullanıcı Ayarlar > Varsayılan uygulamalar > Dijital
 * asistan uygulaması yolunu kullanır ([openDefaultAssistantSettings]).
 */
class AssistantRoleController(private val activity: Activity) : AssistantRoleHostApi {

    private val roleManager = activity.getSystemService(RoleManager::class.java)
    private var pending: CompletableDeferred<Int>? = null

    override fun getStatus(): AssistantRoleStatusMessage {
        val available = roleManager?.isRoleAvailable(RoleManager.ROLE_ASSISTANT) == true
        val held = roleManager?.isRoleHeld(RoleManager.ROLE_ASSISTANT) == true
        val vis = VoiceInteractionService.isActiveService(
            activity,
            ComponentName(activity, SaklazVoiceInteractionService::class.java),
        )
        return AssistantRoleStatusMessage(
            roleAvailable = available,
            roleHeld = held,
            voiceInteractionServiceActive = vis,
            sdkInt = Build.VERSION.SDK_INT.toLong(),
            manufacturer = Build.MANUFACTURER,
            model = Build.MODEL,
        )
    }

    override suspend fun requestRole(): RoleRequestOutcome {
        val rm = roleManager ?: return RoleRequestOutcome.NOT_GRANTED
        if (rm.isRoleHeld(RoleManager.ROLE_ASSISTANT)) return RoleRequestOutcome.GRANTED
        if (!rm.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) return RoleRequestOutcome.NOT_GRANTED

        val deferred = CompletableDeferred<Int>()
        pending = deferred
        activity.startActivityForResult(
            rm.createRequestRoleIntent(RoleManager.ROLE_ASSISTANT),
            REQUEST_CODE,
        )
        val resultCode = deferred.await()
        Log.i(TAG, "Rol isteği sonucu: $resultCode")
        // Sonuç koduna değil, sistemin gerçek durumuna güven.
        return if (rm.isRoleHeld(RoleManager.ROLE_ASSISTANT)) {
            RoleRequestOutcome.GRANTED
        } else {
            RoleRequestOutcome.NOT_GRANTED
        }
    }

    override fun openDefaultAssistantSettings(): Boolean {
        val candidates = listOf(
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
            Intent(Settings.ACTION_VOICE_INPUT_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in candidates) {
            try {
                activity.startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // sıradakini dene
            }
        }
        return false
    }

    /** MainActivity.onActivityResult'tan çağrılır. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pending?.complete(resultCode)
        pending = null
        return true
    }

    companion object {
        private const val TAG = "SaklazRole"
        const val REQUEST_CODE = 0x5A01
    }
}
