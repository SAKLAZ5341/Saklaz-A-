package com.saklaz.assistant.ai

import android.content.Context
import com.saklaz.assistant.bridge.DownloadProgressMessage
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Süreç genelinde tek örnek: ana uygulama ve yan tuş paneli AYNI yüklü modeli ve
 * aynı indirme yöneticisini paylaşır (model belleği iki kez harcanmaz).
 */
object AiServices {
    @Volatile private var llm: LiteRtLlmController? = null
    @Volatile private var models: ModelController? = null
    private val progressListeners = CopyOnWriteArraySet<(DownloadProgressMessage) -> Unit>()

    @Synchronized
    fun llm(context: Context): LiteRtLlmController =
        llm ?: LiteRtLlmController(context.applicationContext).also { llm = it }

    @Synchronized
    fun models(context: Context): ModelController =
        models ?: ModelController(context.applicationContext) { p -> progressListeners.forEach { it(p) } }.also { models = it }

    fun addProgressListener(l: (DownloadProgressMessage) -> Unit) = progressListeners.add(l)
    fun removeProgressListener(l: (DownloadProgressMessage) -> Unit) = progressListeners.remove(l)

    /** Sistem bellek istediğinde modeli bırak (bir sonraki soruda yeniden yüklenir). */
    fun releaseModelMemory() {
        llm?.unload()
    }
}
