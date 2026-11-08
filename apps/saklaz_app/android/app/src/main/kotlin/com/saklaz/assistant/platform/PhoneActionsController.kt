package com.saklaz.assistant.platform

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import com.saklaz.assistant.bridge.CalendarEventMessage
import com.saklaz.assistant.bridge.ContactMessage
import com.saklaz.assistant.bridge.FlutterError
import com.saklaz.assistant.bridge.PhoneActionsHostApi

/**
 * Telefon işlemleri. Hepsi kullanıcı onayından SONRA çağrılır ve mümkün olduğunda
 * işlemi hedef uygulamada açar (son adımı kullanıcı yapar): arama, WhatsApp, takvim.
 */
class PhoneActionsController(private val context: Context, private val launcher: () -> Context) : PhoneActionsHostApi {

    private fun start(intent: Intent): Boolean = try {
        val ctx = launcher()
        if (ctx === context) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    private fun require(permission: String) {
        if (context.checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
            throw FlutterError("permission", "İzin gerekli: $permission", null)
        }
    }

    override fun searchContacts(query: String, limit: Long): List<ContactMessage> {
        require(Manifest.permission.READ_CONTACTS)
        val out = LinkedHashMap<String, ContactMessage>()
        val uri = Uri.withAppendedPath(ContactsContract.CommonDataKinds.Phone.CONTENT_FILTER_URI, Uri.encode(query))
        context.contentResolver.query(
            uri,
            arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
            null, null, null,
        )?.use { c ->
            while (c.moveToNext() && out.size < limit) {
                val name = c.getString(0) ?: continue
                val phone = c.getString(1)?.filter { it.isDigit() || it == '+' } ?: continue
                out.putIfAbsent(name, ContactMessage(name = name, phone = phone))
            }
        }
        return out.values.toList()
    }

    override fun openDialer(phone: String): Boolean =
        start(Intent(Intent.ACTION_DIAL, Uri.parse("tel:${Uri.encode(phone)}")))

    override fun openWhatsApp(phone: String, text: String): Boolean {
        // Resmi "click to chat" bağlantısı: mesaj taslağı açılır, GÖNDER'e kullanıcı basar.
        val digits = phone.filter { it.isDigit() }.let { if (it.startsWith("0")) "90${it.drop(1)}" else it }
        val uri = Uri.parse("https://wa.me/$digits?text=${Uri.encode(text)}")
        for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            if (start(Intent(Intent.ACTION_VIEW, uri).setPackage(pkg))) return true
        }
        return start(Intent(Intent.ACTION_VIEW, uri))
    }

    override fun setAlarm(hour: Long, minute: Long, label: String): Boolean = start(
        Intent(AlarmClock.ACTION_SET_ALARM)
            .putExtra(AlarmClock.EXTRA_HOUR, hour.toInt())
            .putExtra(AlarmClock.EXTRA_MINUTES, minute.toInt())
            .putExtra(AlarmClock.EXTRA_MESSAGE, label)
            .putExtra(AlarmClock.EXTRA_SKIP_UI, true),
    )

    override fun insertCalendarEvent(title: String, beginMillis: Long, endMillis: Long): Boolean = start(
        Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, title)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, beginMillis)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMillis),
    )

    override fun readCalendar(fromMillis: Long, toMillis: Long): List<CalendarEventMessage> {
        require(Manifest.permission.READ_CALENDAR)
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, fromMillis)
        ContentUris.appendId(builder, toMillis)
        val out = mutableListOf<CalendarEventMessage>()
        context.contentResolver.query(
            builder.build(),
            arrayOf(
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.ALL_DAY,
                CalendarContract.Instances.EVENT_LOCATION,
            ),
            null, null, "${CalendarContract.Instances.BEGIN} ASC",
        )?.use { c ->
            while (c.moveToNext() && out.size < 50) {
                out += CalendarEventMessage(
                    title = c.getString(0) ?: "(başlıksız)",
                    beginMillis = c.getLong(1),
                    endMillis = c.getLong(2),
                    allDay = c.getInt(3) == 1,
                    location = c.getString(4),
                )
            }
        }
        return out
    }
}
