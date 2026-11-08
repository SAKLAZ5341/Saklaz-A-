package com.saklaz.assistant.assist

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import com.saklaz.assistant.MainActivity
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView

/**
 * Yan tuşla açılan SAKLAZ paneli (Gemini benzeri): uygulama AÇILMAZ; mevcut ekranın
 * üzerinde, alttan çıkan saydam bir Flutter paneli gösterilir ve hemen dinlemeye başlar.
 *
 * Gizlilik: Ekran içeriği / ekran görüntüsü İSTENMEZ.
 */
class SaklazSession(context: Context) : VoiceInteractionSession(context) {

    private var flutterView: FlutterView? = null

    override fun onCreate() {
        super.onCreate()
        setDisabledShowContext(SHOW_WITH_ASSIST or SHOW_WITH_SCREENSHOT)
        window.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        }
    }

    override fun onCreateContentView(): View? = try {
        val engine = OverlayEngine.get(context)
        val view = FlutterView(context, FlutterTextureView(context).apply { isOpaque = false })
        view.attachToFlutterEngine(engine)
        flutterView = view
        FrameLayout(context).apply {
            setBackgroundColor(Color.TRANSPARENT)
            addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }
    } catch (t: Throwable) {
        Log.e(TAG, "Panel oluşturulamadı; tam uygulama açılacak", t)
        null
    }

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        if (flutterView == null) {
            // Yedek yol: panel kurulamazsa tam uygulamayı aç.
            val intent = Intent(context, MainActivity::class.java)
                .putExtra(MainActivity.EXTRA_ASSIST_SOURCE, MainActivity.SOURCE_SESSION)
            runCatching { startAssistantActivity(intent) }
            hide()
            return
        }
        OverlayEngine.onDismiss = { hide() }
        OverlayEngine.get(context).lifecycleChannel.appIsResumed()
        OverlayEngine.invoke()
        Log.i(TAG, "Panel gösterildi")
    }

    override fun onHide() {
        runCatching { OverlayEngine.get(context).lifecycleChannel.appIsPaused() }
        super.onHide()
    }

    override fun onDestroy() {
        flutterView?.detachFromFlutterEngine()
        flutterView = null
        OverlayEngine.onDismiss = null
        super.onDestroy()
    }

    private companion object {
        const val TAG = "SaklazSession"
    }
}
