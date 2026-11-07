package com.saklaz.assistant.net

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.saklaz.assistant.bridge.NetworkHostApi

/** Doğrulanmış internet bağlantısı kontrolü (ACCESS_NETWORK_STATE, normal izin). */
class NetworkController(context: Context) : NetworkHostApi {
    private val cm = context.getSystemService(ConnectivityManager::class.java)

    override fun isOnline(): Boolean {
        val caps = cm?.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }
}
