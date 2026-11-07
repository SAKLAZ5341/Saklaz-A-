package com.saklaz.assistant.ai

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.util.Log
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.saklaz.assistant.bridge.DeviceCapabilityMessage
import com.saklaz.assistant.bridge.FlutterError
import com.saklaz.assistant.bridge.LocalAiHostApi
import com.saklaz.assistant.bridge.LocalModelInfoMessage
import com.saklaz.assistant.bridge.LocalModelStatus
import kotlinx.coroutines.flow.first

/**
 * Yerel AI: Gemini Nano (ML Kit GenAI Prompt API, sistem AICore servisi).
 *
 * - Model ağırlıkları APK'da DEĞİLDİR; sistem tarafından yönetilir ve SAKLAZ
 *   sürecinin RAM'ine yüklenmez.
 * - Cihaz desteklemiyorsa [LocalModelStatus.UNAVAILABLE] döner; uygulama
 *   kural tabanlı yerel motorla çalışmaya devam eder.
 * - İndirme yalnızca kullanıcı açıkça isterse başlatılır.
 */
class LocalAiController(private val context: Context) : LocalAiHostApi {

    private var model: GenerativeModel? = null

    private fun client(): GenerativeModel = model ?: Generation.getClient().also { model = it }

    override fun getDeviceCapability(): DeviceCapabilityMessage {
        val am = context.getSystemService(ActivityManager::class.java)
        val mi = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        return DeviceCapabilityMessage(
            totalRamMb = mi.totalMem / MB,
            availableRamMb = mi.availMem / MB,
            lowRamDevice = am.isLowRamDevice,
            socManufacturer = Build.SOC_MANUFACTURER,
            socModel = Build.SOC_MODEL,
            abis = Build.SUPPORTED_ABIS.toList(),
            sdkInt = Build.VERSION.SDK_INT.toLong(),
        )
    }

    override suspend fun checkModel(): LocalModelInfoMessage = try {
        val m = client()
        val status = mapStatus(m.checkStatus())
        val name = if (status == LocalModelStatus.AVAILABLE) runCatching { m.getBaseModelName() }.getOrNull() else null
        LocalModelInfoMessage(status = status, baseModelName = name)
    } catch (e: Exception) {
        Log.w(TAG, "Gemini Nano durumu okunamadı", e)
        LocalModelInfoMessage(status = LocalModelStatus.ERROR, detail = e.message ?: e.javaClass.simpleName)
    }

    override suspend fun downloadModel(): LocalModelInfoMessage {
        val m = client()
        return try {
            val terminal = m.download().first {
                it is DownloadStatus.DownloadCompleted || it is DownloadStatus.DownloadFailed
            }
            if (terminal is DownloadStatus.DownloadFailed) {
                LocalModelInfoMessage(status = LocalModelStatus.ERROR, detail = terminal.e.message)
            } else {
                checkModel()
            }
        } catch (e: Exception) {
            LocalModelInfoMessage(status = LocalModelStatus.ERROR, detail = e.message ?: e.javaClass.simpleName)
        }
    }

    override suspend fun generate(prompt: String, maxOutputTokens: Long, temperature: Double): String {
        val m = client()
        if (m.checkStatus() != FeatureStatus.AVAILABLE) {
            throw FlutterError("local-model-unavailable", "Yerel model bu cihazda hazır değil.", null)
        }
        val request = generateContentRequest(TextPart(prompt)) {
            this.maxOutputTokens = maxOutputTokens.toInt().coerceIn(16, 512)
            this.temperature = temperature.toFloat().coerceIn(0f, 1f)
        }
        return try {
            m.generateContent(request).candidates.firstOrNull()?.text?.trim().orEmpty()
        } catch (e: Exception) {
            throw FlutterError("local-model-error", e.message ?: "Yerel model yanıt veremedi.", null)
        }
    }

    fun release() {
        model?.close()
        model = null
    }

    private fun mapStatus(s: Int): LocalModelStatus = when (s) {
        FeatureStatus.AVAILABLE -> LocalModelStatus.AVAILABLE
        FeatureStatus.DOWNLOADABLE -> LocalModelStatus.DOWNLOADABLE
        FeatureStatus.DOWNLOADING -> LocalModelStatus.DOWNLOADING
        else -> LocalModelStatus.UNAVAILABLE
    }

    private companion object {
        const val TAG = "SaklazLocalAi"
        const val MB = 1024L * 1024L
    }
}
