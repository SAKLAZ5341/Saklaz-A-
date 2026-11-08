package com.saklaz.assistant.ai

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.StatFs
import android.util.Log
import com.saklaz.assistant.bridge.DeviceCapabilityMessage
import com.saklaz.assistant.bridge.DownloadProgressMessage
import com.saklaz.assistant.bridge.DownloadState
import com.saklaz.assistant.bridge.FlutterError
import com.saklaz.assistant.bridge.InstalledModelMessage
import com.saklaz.assistant.bridge.ModelHostApi
import com.saklaz.assistant.bridge.ModelSpecMessage
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Model indirme ve yönetimi.
 *  - Yalnızca HTTPS ve yalnızca izinli alan adı (huggingface.co).
 *  - Kaldığı yerden devam (HTTP Range), boş alan kontrolü.
 *  - Bitince SHA-256 doğrulaması; eşleşmezse dosya silinir.
 *  - Modeller noBackupFilesDir/models altında (yedeklenmez).
 */
class ModelController(
    private val context: Context,
    private val emit: (DownloadProgressMessage) -> Unit,
) : ModelHostApi {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val jobs = ConcurrentHashMap<String, Job>()

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
            freeStorageMb = StatFs(modelsDir(context).absolutePath).availableBytes / MB,
        )
    }

    override fun listInstalled(): List<InstalledModelMessage> =
        modelsDir(context).listFiles { f -> f.isFile && f.name.endsWith(".litertlm") }
            ?.map { InstalledModelMessage(fileName = it.name, sizeBytes = it.length()) }
            ?: emptyList()

    override fun startDownload(spec: ModelSpecMessage) {
        val url = URL(spec.url)
        if (url.protocol != "https" || url.host !in ALLOWED_HOSTS) {
            throw FlutterError("bad-url", "Yalnızca güvenilir HTTPS kaynaklardan indirilebilir.", null)
        }
        if (!SAFE_NAME.matches(spec.fileName)) throw FlutterError("bad-name", "Geçersiz dosya adı.", null)
        if (jobs[spec.id]?.isActive == true) return
        jobs[spec.id] = scope.launch { download(spec) }
    }

    override fun cancelDownload(id: String) {
        jobs.remove(id)?.cancel()
        emit(DownloadProgressMessage(id = id, state = DownloadState.CANCELLED, receivedBytes = 0, totalBytes = 0))
    }

    override fun deleteModel(fileName: String) {
        if (!SAFE_NAME.matches(fileName)) return
        modelFile(context, fileName).delete()
        File(modelsDir(context), "$fileName.part").delete()
    }

    private fun progress(spec: ModelSpecMessage, state: DownloadState, received: Long, error: String? = null) =
        emit(DownloadProgressMessage(id = spec.id, state = state, receivedBytes = received, totalBytes = spec.sizeBytes, error = error))

    private suspend fun download(spec: ModelSpecMessage) {
        val dir = modelsDir(context)
        val target = modelFile(context, spec.fileName)
        val part = File(dir, "${spec.fileName}.part")
        try {
            if (target.exists() && target.length() == spec.sizeBytes) {
                progress(spec, DownloadState.VERIFYING, spec.sizeBytes)
                verifyOrDelete(spec, target)
                return
            }
            val already = if (part.exists()) part.length() else 0L
            val needed = spec.sizeBytes - already
            val free = StatFs(dir.absolutePath).availableBytes
            if (free < needed + RESERVE_BYTES) {
                progress(spec, DownloadState.FAILED, already, "Yetersiz depolama: ${needed / MB} MB gerekli, ${free / MB} MB boş")
                return
            }
            var conn = open(spec.url, already)
            var code = conn.responseCode
            // Sunucu Range desteklemiyorsa baştan başla.
            val append = already > 0 && code == HttpURLConnection.HTTP_PARTIAL
            if (!append && already > 0) {
                part.delete()
                conn.disconnect()
                conn = open(spec.url, 0)
                code = conn.responseCode
            }
            if (code !in 200..299) {
                progress(spec, DownloadState.FAILED, 0, "Sunucu hatası: HTTP $code")
                return
            }
            var received = if (append) already else 0L
            var lastEmit = 0L
            conn.inputStream.use { input ->
                FileOutputStream(part, append).use { out ->
                    val buf = ByteArray(256 * 1024)
                    while (true) {
                        if (!currentCoroutineContext().isActive) return
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        received += n
                        val now = System.currentTimeMillis()
                        if (now - lastEmit > 400) {
                            lastEmit = now
                            progress(spec, DownloadState.RUNNING, received)
                        }
                    }
                }
            }
            conn.disconnect()
            if (received != spec.sizeBytes) {
                progress(spec, DownloadState.FAILED, received, "Eksik indirme ($received / ${spec.sizeBytes} bayt). Tekrar deneyin; kaldığı yerden devam eder.")
                return
            }
            progress(spec, DownloadState.VERIFYING, received)
            if (!part.renameTo(target)) {
                progress(spec, DownloadState.FAILED, received, "Dosya taşınamadı")
                return
            }
            verifyOrDelete(spec, target)
        } catch (t: Throwable) {
            if (t is kotlinx.coroutines.CancellationException) return
            Log.w(TAG, "İndirme hatası", t)
            progress(spec, DownloadState.FAILED, if (part.exists()) part.length() else 0, t.message ?: t.javaClass.simpleName)
        } finally {
            jobs.remove(spec.id)
        }
    }

    private fun verifyOrDelete(spec: ModelSpecMessage, file: File) {
        val actual = sha256(file)
        if (actual.equals(spec.sha256, ignoreCase = true)) {
            progress(spec, DownloadState.COMPLETED, file.length())
        } else {
            file.delete()
            progress(spec, DownloadState.FAILED, 0, "Bütünlük doğrulaması başarısız (SHA-256 eşleşmedi). Dosya silindi.")
        }
    }

    private fun open(url: String, from: Long): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 15_000
            readTimeout = 60_000
            setRequestProperty("User-Agent", "SAKLAZ-AI/0.3 (Android)")
            if (from > 0) setRequestProperty("Range", "bytes=$from-")
        }

    fun release() {
        jobs.values.forEach { it.cancel() }
        jobs.clear()
    }

    companion object {
        private const val TAG = "SaklazModels"
        private const val MB = 1024L * 1024L
        private const val RESERVE_BYTES = 300L * MB
        private val SAFE_NAME = Regex("^[A-Za-z0-9._-]{1,128}\\.litertlm$")

        // Hugging Face yönlendirmeleri CDN alt alan adlarına gidebilir; ilk istek izinli olmalı.
        private val ALLOWED_HOSTS = setOf("huggingface.co")

        fun modelsDir(context: Context): File = File(context.noBackupFilesDir, "models").apply { mkdirs() }

        fun modelFile(context: Context, fileName: String): File = File(modelsDir(context), fileName)

        fun sha256(file: File): String {
            val md = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buf = ByteArray(1024 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    md.update(buf, 0, n)
                }
            }
            return md.digest().joinToString("") { "%02x".format(it) }
        }
    }
}
