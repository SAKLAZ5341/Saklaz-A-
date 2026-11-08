package com.saklaz.assistant.reminders

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import com.saklaz.assistant.MainActivity
import com.saklaz.assistant.R

/** Hatırlatma zamanı geldiğinde bildirim gösterir. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getLongExtra(ReminderScheduler.EXTRA_ID, -1)
        val text = intent.getStringExtra(ReminderScheduler.EXTRA_TEXT) ?: "Hatırlatma"
        ReminderScheduler.savePending(context, ReminderScheduler.loadPending(context).filterNot { it.id == id })
        if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        ReminderScheduler.ensureChannel(context)
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val n = Notification.Builder(context, ReminderScheduler.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_saklaz)
            .setContentTitle("SAKLAZ hatırlatması")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        context.getSystemService(NotificationManager::class.java).notify(id.toInt(), n)
    }
}

/** Yeniden başlatma sonrası bekleyen hatırlatıcıları yeniden kurar. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val now = System.currentTimeMillis()
        ReminderScheduler.loadPending(context).forEach {
            // Kapalıyken kaçırılanlar hemen bildirilir.
            ReminderScheduler.arm(context, it.copy(at = maxOf(it.at, now + 5_000)))
        }
    }
}
