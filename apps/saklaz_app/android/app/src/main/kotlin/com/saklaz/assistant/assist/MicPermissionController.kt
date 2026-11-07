package com.saklaz.assistant.assist

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import com.saklaz.assistant.bridge.MicPermissionState
import com.saklaz.assistant.bridge.PermissionHostApi
import kotlinx.coroutines.CompletableDeferred

/** Mikrofon izni: yalnızca kullanıcı bir sesli özelliği ilk kullandığında istenir. */
class MicPermissionController(private val activity: Activity) : PermissionHostApi {

    private var pending: CompletableDeferred<Unit>? = null
    private val prefs = activity.getSharedPreferences("saklaz_permissions", Activity.MODE_PRIVATE)

    override fun getMicrophonePermission(): MicPermissionState {
        if (activity.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED) {
            return MicPermissionState.GRANTED
        }
        val askedBefore = prefs.getBoolean(KEY_ASKED, false)
        // Daha önce sorulduysa ve sistem gerekçe göstermiyorsa: "bir daha sorma" durumu.
        return if (askedBefore && !activity.shouldShowRequestPermissionRationale(PERMISSION)) {
            MicPermissionState.PERMANENTLY_DENIED
        } else {
            MicPermissionState.DENIED
        }
    }

    override suspend fun requestMicrophonePermission(): MicPermissionState {
        if (getMicrophonePermission() == MicPermissionState.GRANTED) return MicPermissionState.GRANTED
        val deferred = CompletableDeferred<Unit>()
        pending = deferred
        activity.requestPermissions(arrayOf(PERMISSION), REQUEST_CODE)
        deferred.await()
        prefs.edit().putBoolean(KEY_ASKED, true).apply()
        return getMicrophonePermission()
    }

    override fun openAppSettings() {
        activity.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", activity.packageName, null)),
        )
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pending?.complete(Unit)
        pending = null
        return true
    }

    companion object {
        private const val PERMISSION = Manifest.permission.RECORD_AUDIO
        private const val KEY_ASKED = "mic_asked"
        const val REQUEST_CODE = 0x5A02
    }
}
