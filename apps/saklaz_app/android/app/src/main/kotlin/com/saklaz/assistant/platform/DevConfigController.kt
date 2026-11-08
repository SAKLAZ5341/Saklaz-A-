package com.saklaz.assistant.platform

import android.content.Intent
import com.saklaz.assistant.BuildConfig
import com.saklaz.assistant.bridge.DevConfigHostApi
import com.saklaz.assistant.bridge.DevConfigMessage

/**
 * YALNIZCA DEBUG: adb ile gateway ayarı aktarımı.
 *   adb shell am start -n com.saklaz.assistant/.MainActivity --es saklaz_gateway_url http://... --es saklaz_gateway_token skz_...
 * Release yapısında her zaman null döner.
 */
class DevConfigController : DevConfigHostApi {
    @Volatile private var pending: DevConfigMessage? = null

    fun capture(intent: Intent?) {
        if (!BuildConfig.DEBUG || intent == null) return
        val url = intent.getStringExtra("saklaz_gateway_url")
        val token = intent.getStringExtra("saklaz_gateway_token")
        if (url != null || token != null) pending = DevConfigMessage(gatewayUrl = url, gatewayToken = token)
    }

    override fun consumeDevConfig(): DevConfigMessage? {
        if (!BuildConfig.DEBUG) return null
        return pending.also { pending = null }
    }
}
