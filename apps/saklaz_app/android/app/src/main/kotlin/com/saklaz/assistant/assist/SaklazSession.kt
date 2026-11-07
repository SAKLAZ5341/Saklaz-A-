package com.saklaz.assistant.assist

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.util.Log
import com.saklaz.assistant.MainActivity

/**
 * Yan tuş (Samsung: Yan tuş -> Basılı tut -> Dijital asistan), ana ekran tuşuna
 * uzun basma veya hareket ile asistan çağrıldığında gösterilen oturum.
 *
 * Oturumun kendi penceresini kullanmak yerine Flutter arayüzünü taşıyan
 * [MainActivity]'yi `startAssistantActivity` ile açar (Android'in asistan
 * katmanında, resmi yöntem) ve oturum penceresini gizler.
 *
 * Gizlilik: Ekran içeriği (assist structure / ekran görüntüsü) İSTENMEZ ve
 * işlenmez. onHandleAssist geçersiz kılınmamıştır.
 */
class SaklazSession(context: Context) : VoiceInteractionSession(context) {

    override fun onCreate() {
        super.onCreate()
        // Ekran içeriği ve ekran görüntüsü toplanmasını kapat.
        setDisabledShowContext(SHOW_WITH_ASSIST or SHOW_WITH_SCREENSHOT)
    }

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        Log.i(TAG, "Asistan oturumu gösterildi (showFlags=$showFlags)")

        val intent = Intent(context, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_ASSIST_SOURCE, MainActivity.SOURCE_SESSION)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        try {
            startAssistantActivity(intent)
        } catch (e: RuntimeException) {
            Log.w(TAG, "startAssistantActivity başarısız, normal başlatma deneniyor", e)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
        // Oturum penceresi boş; dokunmaları engellememesi için gizle.
        hide()
    }

    private companion object {
        const val TAG = "SaklazSession"
    }
}
