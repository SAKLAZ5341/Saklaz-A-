package com.saklaz.assistant.ai

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.ai.edge.litertlm.ThinkingConfig
import com.saklaz.assistant.bridge.ChatTurnMessage
import com.saklaz.assistant.bridge.FlutterError
import com.saklaz.assistant.bridge.LlmEngineState
import com.saklaz.assistant.bridge.LlmReplyMessage
import com.saklaz.assistant.bridge.LlmStatusMessage
import com.saklaz.assistant.bridge.LocalLlmHostApi
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Gerçek yerel LLM: LiteRT-LM (Google) ile `.litertlm` modeli cihazda çalışır.
 * Model APK'da değildir; ModelController ile indirilir.
 *
 * Bellek: tek seferde tek motor; başka model yüklenince öncekinin belleği serbest bırakılır.
 */
class LiteRtLlmController(private val context: Context) : LocalLlmHostApi {

    private val mutex = Mutex()
    private var engine: Engine? = null
    private var activeConversation: Conversation? = null
    @Volatile private var status = LlmStatusMessage(state = LlmEngineState.NOT_LOADED)

    override fun status(): LlmStatusMessage = status

    override suspend fun load(fileName: String, preferGpu: Boolean, maxTokens: Long): LlmStatusMessage =
        mutex.withLock {
            val file = ModelController.modelFile(context, fileName)
            if (!file.exists()) {
                status = LlmStatusMessage(state = LlmEngineState.FAILED, fileName = fileName, error = "Model dosyası bulunamadı")
                return@withLock status
            }
            if (status.state == LlmEngineState.READY && status.fileName == fileName && engine != null) return@withLock status
            releaseLocked()
            status = LlmStatusMessage(state = LlmEngineState.LOADING, fileName = fileName)
            val started = System.currentTimeMillis()
            // CPU: 4 iş parçacığı (arayüze ve sisteme çekirdek bırakır; telefonun donmasını önler).
            val cpu = Backend.CPU(CPU_THREADS, null)
            val backends = if (preferGpu) listOf<Backend>(Backend.GPU(), cpu) else listOf<Backend>(cpu)
            var lastError: Throwable? = null
            for (backend in backends) {
                try {
                    val e = withContext(Dispatchers.Default) {
                        Engine(
                            EngineConfig(
                                file.absolutePath,
                                backend,
                                null,
                                null,
                                maxTokens.toInt().coerceIn(512, MAX_TOKENS),
                                null,
                                File(context.cacheDir, "litertlm").apply { mkdirs() }.absolutePath,
                            ),
                        ).also { it.initialize() }
                    }
                    engine = e
                    status = LlmStatusMessage(
                        state = LlmEngineState.READY,
                        fileName = fileName,
                        backend = backend.name,
                        loadMillis = System.currentTimeMillis() - started,
                    )
                    Log.i(TAG, "Model yüklendi: $fileName (${backend.name}, ${status.loadMillis} ms)")
                    return@withLock status
                } catch (t: Throwable) {
                    Log.w(TAG, "Backend ${backend.name} başarısız", t)
                    lastError = t
                }
            }
            status = LlmStatusMessage(state = LlmEngineState.FAILED, fileName = fileName, error = lastError?.message ?: "Yüklenemedi")
            status
        }

    override fun unload() {
        // Üretim sürerken çağrılırsa önce iptal.
        activeConversation?.runCatching { cancelProcess() }
        if (mutex.tryLock()) {
            try {
                releaseLocked()
                status = LlmStatusMessage(state = LlmEngineState.NOT_LOADED)
            } finally {
                mutex.unlock()
            }
        }
    }

    override suspend fun generate(
        systemPrompt: String,
        history: List<ChatTurnMessage>,
        userText: String,
        maxOutputTokens: Long,
    ): LlmReplyMessage = mutex.withLock {
        val e = engine ?: throw FlutterError("model-not-loaded", "Yerel model yüklü değil.", null)
        val started = System.currentTimeMillis()
        val text = withContext(Dispatchers.Default) {
            val initial = history.map { if (it.fromUser) Message.user(it.text) else Message.model(it.text) }
            val config = ConversationConfig(
                Contents.of(systemPrompt),
                initial,
                emptyList(),
                SamplerConfig(40, 0.9, 0.4, 0),
                false,
                emptyList(),
                emptyMap(),
                null,
                false,
                maxOutputTokens.toInt().coerceIn(32, 1024),
                ThinkingConfig(false),
            )
            e.createConversation(config).use { conv ->
                activeConversation = conv
                try {
                    conv.sendMessage(userText).contents.contents
                        .filterIsInstance<Content.Text>()
                        .joinToString("") { it.text }
                } finally {
                    activeConversation = null
                }
            }
        }
        LlmReplyMessage(text = text, millis = System.currentTimeMillis() - started)
    }

    override fun cancel() {
        activeConversation?.runCatching { cancelProcess() }
    }

    private fun releaseLocked() {
        runCatching { engine?.close() }
        engine = null
    }

    fun release() {
        cancel()
        releaseLocked()
    }

    private companion object {
        const val TAG = "SaklazLlm"
        const val CPU_THREADS = 4

        // KV önbelleği belleği: 2048 token, 1.7B modelde ~1,5 GB tepe RAM ile sınırlı kalır.
        const val MAX_TOKENS = 2048
    }
}
