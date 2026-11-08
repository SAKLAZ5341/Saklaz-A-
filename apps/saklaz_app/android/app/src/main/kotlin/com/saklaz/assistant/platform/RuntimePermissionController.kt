package com.saklaz.assistant.platform

import android.Manifest
import android.content.pm.PackageManager
import com.saklaz.assistant.bridge.MicPermissionState
import com.saklaz.assistant.bridge.RuntimePermission
import com.saklaz.assistant.bridge.RuntimePermissionHostApi

/** Rehber, takvim ve bildirim izinleri — yalnızca ilgili özellik ilk kullanıldığında istenir. */
class RuntimePermissionController(private val bridge: ActivityBridge) : RuntimePermissionHostApi {
    private val activity get() = bridge.activity
    private val prefs = activity.getSharedPreferences("saklaz_permissions", 0)

    private fun names(p: RuntimePermission) = when (p) {
        RuntimePermission.CONTACTS -> arrayOf(Manifest.permission.READ_CONTACTS)
        RuntimePermission.CALENDAR -> arrayOf(Manifest.permission.READ_CALENDAR)
        RuntimePermission.NOTIFICATIONS -> arrayOf(Manifest.permission.POST_NOTIFICATIONS)
    }

    override fun check(permission: RuntimePermission): MicPermissionState {
        val perms = names(permission)
        if (perms.all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) return MicPermissionState.GRANTED
        val asked = prefs.getBoolean("asked_${permission.name}", false)
        return if (asked && perms.none { activity.shouldShowRequestPermissionRationale(it) }) {
            MicPermissionState.PERMANENTLY_DENIED
        } else {
            MicPermissionState.DENIED
        }
    }

    override suspend fun request(permission: RuntimePermission): MicPermissionState {
        if (check(permission) == MicPermissionState.GRANTED) return MicPermissionState.GRANTED
        bridge.requestPermissions(names(permission))
        prefs.edit().putBoolean("asked_${permission.name}", true).apply()
        return check(permission)
    }
}
