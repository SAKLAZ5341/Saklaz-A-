package com.saklaz.assistant.platform

import android.app.Activity
import android.content.Intent
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred

/**
 * FlutterActivity bir ComponentActivity olmadığından klasik startActivityForResult /
 * requestPermissions API'lerini coroutine'lere çevirir.
 */
class ActivityBridge(val activity: Activity) {
    private val nextCode = AtomicInteger(0x5B00)
    private val results = HashMap<Int, CompletableDeferred<Pair<Int, Intent?>>>()
    private val permissions = HashMap<Int, CompletableDeferred<Unit>>()

    suspend fun startForResult(intent: Intent): Pair<Int, Intent?> {
        val code = nextCode.incrementAndGet()
        val d = CompletableDeferred<Pair<Int, Intent?>>()
        results[code] = d
        activity.startActivityForResult(intent, code)
        return d.await()
    }

    suspend fun requestPermissions(perms: Array<String>) {
        val code = nextCode.incrementAndGet()
        val d = CompletableDeferred<Unit>()
        permissions[code] = d
        activity.requestPermissions(perms, code)
        d.await()
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val d = results.remove(requestCode) ?: return false
        d.complete(resultCode to data)
        return true
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        val d = permissions.remove(requestCode) ?: return false
        d.complete(Unit)
        return true
    }
}
