package com.saklaz.assistant.platform

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.saklaz.assistant.bridge.DocumentResultMessage
import com.saklaz.assistant.bridge.FileHostApi
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * Dosya ve fotoğraf okuma — tamamen cihazda:
 *  - Metin dosyaları: doğrudan okunur.
 *  - PDF: PdfRenderer ile sayfa görüntüsü -> ML Kit OCR (ilk 5 sayfa).
 *  - Görseller: ML Kit OCR (Latin/Türkçe) + görüntü etiketleme.
 * Görüntü cihazdan çıkmaz; yerel modele yalnızca çıkarılan metin/etiketler verilir.
 * CAMERA izni İSTENMEZ: sistem kamera uygulaması kullanılır.
 */
class FileController(private val bridge: ActivityBridge) : FileHostApi {
    private val activity get() = bridge.activity

    override suspend fun pickAndRead(): DocumentResultMessage? {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/*", "application/pdf", "image/*", "application/json"))
        val (code, data) = bridge.startForResult(intent)
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) return null
        val mime = activity.contentResolver.getType(uri) ?: ""
        val name = displayName(uri)
        return withContext(Dispatchers.IO) {
            when {
                mime.startsWith("image/") -> analyzeImage(InputImage.fromFilePath(activity, uri), name)
                mime == "application/pdf" -> readPdf(uri, name)
                else -> DocumentResultMessage(kind = "text", name = name, text = readText(uri), labels = emptyList())
            }
        }
    }

    override suspend fun captureImage(fromCamera: Boolean): DocumentResultMessage? {
        if (fromCamera) {
            val dir = File(activity.cacheDir, "captures").apply { mkdirs() }
            val file = File(dir, "capture.jpg").apply { delete() }
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", file)
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                .putExtra(MediaStore.EXTRA_OUTPUT, uri)
                .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val (code, _) = bridge.startForResult(intent)
            if (code != Activity.RESULT_OK || !file.exists() || file.length() == 0L) return null
            return try {
                withContext(Dispatchers.IO) { analyzeImage(InputImage.fromFilePath(activity, uri), "Kamera fotoğrafı") }
            } finally {
                file.delete() // fotoğraf saklanmaz
            }
        }
        val (code, data) = bridge.startForResult(Intent(MediaStore.ACTION_PICK_IMAGES))
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) return null
        return withContext(Dispatchers.IO) { analyzeImage(InputImage.fromFilePath(activity, uri), displayName(uri)) }
    }

    private suspend fun analyzeImage(image: InputImage, name: String?): DocumentResultMessage {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val labeler = ImageLabeling.getClient(ImageLabelerOptions.Builder().setConfidenceThreshold(0.6f).build())
        try {
            val text = recognizer.process(image).await().text
            val labels = labeler.process(image).await().take(8).map { "${it.text} ${"%.2f".format(it.confidence)}" }
            return DocumentResultMessage(kind = "image", name = name, text = text.take(MAX_CHARS), labels = labels)
        } finally {
            recognizer.close()
            labeler.close()
        }
    }

    private suspend fun readPdf(uri: Uri, name: String?): DocumentResultMessage {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val sb = StringBuilder()
        try {
            val pfd: ParcelFileDescriptor = activity.contentResolver.openFileDescriptor(uri, "r")
                ?: return DocumentResultMessage(kind = "pdf", name = name, text = "", labels = emptyList())
            pfd.use { fd ->
                PdfRenderer(fd).use { pdf ->
                    for (i in 0 until minOf(pdf.pageCount, MAX_PDF_PAGES)) {
                        pdf.openPage(i).use { page ->
                            val scale = 2
                            val bmp = Bitmap.createBitmap(page.width * scale, page.height * scale, Bitmap.Config.ARGB_8888)
                            bmp.eraseColor(Color.WHITE)
                            page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            sb.append(recognizer.process(InputImage.fromBitmap(bmp, 0)).await().text).append("\n\n")
                            bmp.recycle()
                        }
                        if (sb.length > MAX_CHARS) break
                    }
                }
            }
        } finally {
            recognizer.close()
        }
        return DocumentResultMessage(kind = "pdf", name = name, text = sb.toString().trim().take(MAX_CHARS), labels = emptyList())
    }

    private fun readText(uri: Uri): String =
        activity.contentResolver.openInputStream(uri)?.use { input ->
            val bytes = input.readNBytes(MAX_CHARS * 4)
            String(bytes, Charsets.UTF_8).take(MAX_CHARS)
        } ?: ""

    private fun displayName(uri: Uri): String? =
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }

    private suspend fun <T> Task<T>.await(): T = suspendCancellableCoroutine { cont ->
        addOnSuccessListener { cont.resume(it) }
        addOnFailureListener { cont.resumeWithException(it) }
    }

    private companion object {
        const val MAX_CHARS = 20_000
        const val MAX_PDF_PAGES = 5
    }
}
