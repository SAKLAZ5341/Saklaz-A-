package com.saklaz.assistant.security

import android.content.Context
import com.saklaz.assistant.bridge.SecretsHostApi
import java.io.File

/**
 * API anahtarları gibi sırlar: her biri Keystore AES-GCM ile şifrelenip ayrı
 * dosyada (noBackupFilesDir/secrets) saklanır. Düz metin diske/loga yazılmaz.
 */
class SecretsController(context: Context) : SecretsHostApi {
    private val dir = File(context.noBackupFilesDir, "secrets").apply { mkdirs() }
    private val key by lazy { KekProvider.getOrCreate(KekProvider.SECRETS_ALIAS) }

    private fun file(name: String): File {
        require(Regex("^[a-z0-9_.-]{1,64}$").matches(name)) { "Geçersiz sır adı" }
        return File(dir, "$name.bin")
    }

    override fun put(name: String, value: String) {
        val f = file(name)
        val tmp = File(dir, "${f.name}.tmp")
        tmp.writeBytes(KekProvider.encrypt(key, value.toByteArray(Charsets.UTF_8)))
        check(tmp.renameTo(f)) { "Sır yazılamadı" }
    }

    override fun get(name: String): String? {
        val f = file(name)
        if (!f.exists()) return null
        return KekProvider.decrypt(key, f.readBytes()).toString(Charsets.UTF_8)
    }

    override fun delete(name: String) {
        file(name).delete()
    }

    override fun has(name: String): Boolean = file(name).exists()
}
