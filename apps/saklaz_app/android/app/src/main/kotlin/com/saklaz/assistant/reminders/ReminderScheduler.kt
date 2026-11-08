package com.saklaz.assistant.reminders

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import com.saklaz.assistant.bridge.ReminderCapabilityMessage
import com.saklaz.assistant.bridge.ReminderHostApi
import com.saklaz.assistant.security.KekProvider
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/**
 * Hatırlatıcı zamanlayıcı. Ana kayıt Flutter tarafındaki şifreli veritabanındadır;
 * yeniden başlatmada (BOOT_COMPLETED) alarmları kurabilmek için bekleyen
 * hatırlatıcıların bir kopyası Keystore ile şifreli dosyada tutulur.
 */
class ReminderScheduler(private val context: Context) : ReminderHostApi {

    private val alarms = context.getSystemService(AlarmManager::class.java)

    override fun capability() = ReminderCapabilityMessage(
        exactAlarms = alarms.canScheduleExactAlarms(),
        notifications = context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED,
    )

    override fun schedule(id: Long, text: String, atMillis: Long) {
        val all = load().filterNot { it.id == id } + Pending(id, text, atMillis)
        save(all)
        arm(context, Pending(id, text, atMillis))
    }

    override fun cancel(id: Long) {
        save(load().filterNot { it.id == id })
        alarms.cancel(pendingIntent(context, id, ""))
    }

    override fun openExactAlarmSettings() {
        context.startActivity(
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                .setData(android.net.Uri.fromParts("package", context.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    data class Pending(val id: Long, val text: String, val at: Long)

    private fun load(): List<Pending> = loadPending(context)
    private fun save(list: List<Pending>) = savePending(context, list)

    companion object {
        const val CHANNEL_ID = "saklaz_reminders"
        const val EXTRA_ID = "reminder_id"
        const val EXTRA_TEXT = "reminder_text"
        private const val FILE = "reminders.bin"

        private fun file(context: Context) = File(context.noBackupFilesDir, FILE)

        fun loadPending(context: Context): List<Pending> {
            val f = file(context)
            if (!f.exists()) return emptyList()
            return try {
                val json = KekProvider.decrypt(KekProvider.getOrCreate(KekProvider.REMINDERS_ALIAS), f.readBytes())
                val arr = JSONArray(json.toString(Charsets.UTF_8))
                (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Pending(o.getLong("id"), o.getString("text"), o.getLong("at"))
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        fun savePending(context: Context, list: List<Pending>) {
            val arr = JSONArray()
            list.forEach { arr.put(JSONObject().put("id", it.id).put("text", it.text).put("at", it.at)) }
            val blob = KekProvider.encrypt(KekProvider.getOrCreate(KekProvider.REMINDERS_ALIAS), arr.toString().toByteArray())
            val tmp = File(context.noBackupFilesDir, "$FILE.tmp")
            tmp.writeBytes(blob)
            tmp.renameTo(file(context))
        }

        fun pendingIntent(context: Context, id: Long, text: String): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                id.toInt(),
                Intent(context, ReminderReceiver::class.java).putExtra(EXTRA_ID, id).putExtra(EXTRA_TEXT, text),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        fun arm(context: Context, p: Pending) {
            val am = context.getSystemService(AlarmManager::class.java)
            val pi = pendingIntent(context, p.id, p.text)
            val at = maxOf(p.at, System.currentTimeMillis() + 1_000)
            if (am.canScheduleExactAlarms()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                // Tam zamanlı alarm izni yoksa: Doze'da da çalışan, birkaç dakika sapabilen alarm.
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            }
        }

        fun ensureChannel(context: Context) {
            val nm = context.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Hatırlatmalar", NotificationManager.IMPORTANCE_HIGH)
                        .apply { description = "SAKLAZ hatırlatıcıları" },
                )
            }
        }
    }
}
