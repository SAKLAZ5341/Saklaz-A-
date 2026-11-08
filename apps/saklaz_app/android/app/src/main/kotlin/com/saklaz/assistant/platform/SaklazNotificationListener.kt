package com.saklaz.assistant.platform

import android.app.Notification
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.saklaz.assistant.bridge.NotificationMessage
import com.saklaz.assistant.bridge.NotificationsHostApi

/**
 * Bildirim okuma: YALNIZCA kullanıcı "Bildirim erişimi" ayarından izin verirse çalışır.
 * Bildirimler yalnızca bellekte (son 50) tutulur; diske yazılmaz, buluta gönderilmez.
 */
class SaklazNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        instance = this
        activeNotifications?.forEach { record(it) }
    }

    override fun onListenerDisconnected() {
        if (instance === this) instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) = record(sbn)

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        synchronized(store) { store.remove(sbn.key) }
    }

    private fun record(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName || sbn.isOngoing) return
        val n = sbn.notification
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: return
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
        val appName = runCatching {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString()
        }.getOrDefault(sbn.packageName)
        synchronized(store) {
            store[sbn.key] = Entry(
                NotificationMessage(
                    key = sbn.key, appName = appName, packageName = sbn.packageName,
                    title = title, text = text.take(500), postedMillis = sbn.postTime,
                    canReply = replyAction(n) != null,
                ),
                n,
            )
            while (store.size > 50) store.remove(store.minByOrNull { it.value.msg.postedMillis }!!.key)
        }
    }

    data class Entry(val msg: NotificationMessage, val notification: Notification)

    companion object {
        @Volatile var instance: SaklazNotificationListener? = null
        val store = LinkedHashMap<String, Entry>()

        fun replyAction(n: Notification): Notification.Action? =
            n.actions?.firstOrNull { a -> a.remoteInputs?.any { it.allowFreeFormInput } == true }
    }
}

class NotificationsController(private val context: Context) : NotificationsHostApi {
    override fun isAccessGranted(): Boolean {
        val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(context, SaklazNotificationListener::class.java)
        return flat.split(':').any { ComponentName.unflattenFromString(it) == me }
    }

    override fun openAccessSettings() {
        context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    override fun recent(limit: Long): List<NotificationMessage> = synchronized(SaklazNotificationListener.store) {
        SaklazNotificationListener.store.values.map { it.msg }.sortedByDescending { it.postedMillis }.take(limit.toInt())
    }

    override fun reply(key: String, text: String): Boolean {
        val entry = synchronized(SaklazNotificationListener.store) { SaklazNotificationListener.store[key] } ?: return false
        val action = SaklazNotificationListener.replyAction(entry.notification) ?: return false
        val inputs = action.remoteInputs ?: return false
        val results = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, text) } }
        val fill = Intent()
        RemoteInput.addResultsToIntent(inputs, fill, results)
        return try {
            action.actionIntent.send(context, 0, fill)
            true
        } catch (_: Exception) {
            false
        }
    }
}
