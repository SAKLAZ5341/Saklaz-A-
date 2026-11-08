package com.saklaz.assistant.platform

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.saklaz.assistant.bridge.AppMessage
import com.saklaz.assistant.bridge.AppsHostApi
import com.saklaz.assistant.bridge.SettingsPage
import java.text.Normalizer
import java.util.Locale

/** Yüklü uygulamaları açma ve ilgili ayar ekranına yönlendirme. */
class AppsController(private val context: Context, private val launcher: () -> Context) : AppsHostApi {

    private fun norm(s: String) = Normalizer.normalize(s.lowercase(Locale.forLanguageTag("tr")), Normalizer.Form.NFD)
        .replace(Regex("\\p{M}"), "").replace('ı', 'i')

    override fun findApps(query: String, limit: Long): List<AppMessage> {
        val q = norm(query.trim())
        if (q.isEmpty()) return emptyList()
        val pm = context.packageManager
        val apps = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .map { AppMessage(label = it.loadLabel(pm).toString(), packageName = it.activityInfo.packageName) }
            .distinctBy { it.packageName }
        return apps
            .map { it to norm(it.label) }
            .filter { (_, label) -> label.contains(q) || q.contains(label) }
            .sortedBy { (_, label) -> if (label == q) 0 else if (label.startsWith(q)) 1 else 2 }
            .take(limit.toInt())
            .map { it.first }
    }

    override fun launchApp(packageName: String): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName) ?: return false
        return start(intent)
    }

    override fun openSettings(page: SettingsPage): Boolean = start(
        when (page) {
            SettingsPage.WIFI -> Intent(Settings.ACTION_WIFI_SETTINGS)
            SettingsPage.BLUETOOTH -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            SettingsPage.DISPLAY -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
            SettingsPage.SOUND -> Intent(Settings.ACTION_SOUND_SETTINGS)
            SettingsPage.BATTERY -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
            SettingsPage.LOCATION -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            SettingsPage.APPS -> Intent(Settings.ACTION_APPLICATION_SETTINGS)
            SettingsPage.NOTIFICATIONS -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            SettingsPage.APP_DETAILS -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", context.packageName, null))
            SettingsPage.MAIN -> Intent(Settings.ACTION_SETTINGS)
        },
    )

    private fun start(intent: Intent): Boolean = try {
        val ctx = launcher()
        if (ctx === context) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    }
}
