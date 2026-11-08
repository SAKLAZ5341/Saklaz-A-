package com.saklaz.assistant.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore'daki dışa aktarılamayan AES-256-GCM anahtarları.
 * Ayrı amaçlar için ayrı takma adlar (veritabanı, API anahtarları, hatırlatıcılar).
 */
object KekProvider {
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val VERSION: Byte = 1

    const val DB_ALIAS = "saklaz_db_kek_v1"
    const val SECRETS_ALIAS = "saklaz_secrets_kek_v1"
    const val REMINDERS_ALIAS = "saklaz_reminders_kek_v1"

    @Synchronized
    fun getOrCreate(alias: String): SecretKey {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }
        return try {
            generate(alias, strongBox = true)
        } catch (_: StrongBoxUnavailableException) {
            generate(alias, strongBox = false)
        }
    }

    private fun generate(alias: String, strongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .setIsStrongBoxBacked(strongBox)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            .apply { init(spec) }
            .generateKey()
    }

    fun isHardwareBacked(key: SecretKey): Boolean = try {
        val info = SecretKeyFactory.getInstance(key.algorithm, ANDROID_KEYSTORE)
            .getKeySpec(key, KeyInfo::class.java) as KeyInfo
        info.securityLevel == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT ||
            info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
    } catch (_: Exception) {
        false
    }

    /** Biçim: [sürüm][iv uzunluğu][iv][şifreli metin+etiket] */
    fun encrypt(key: SecretKey, plain: ByteArray): ByteArray {
        val c = Cipher.getInstance(TRANSFORMATION)
        c.init(Cipher.ENCRYPT_MODE, key)
        val iv = c.iv
        return byteArrayOf(VERSION, iv.size.toByte()) + iv + c.doFinal(plain)
    }

    fun decrypt(key: SecretKey, blob: ByteArray): ByteArray {
        require(blob.size > 2 && blob[0] == VERSION) { "Bilinmeyen şifreli veri biçimi" }
        val ivLen = blob[1].toInt()
        val c = Cipher.getInstance(TRANSFORMATION)
        c.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, blob.copyOfRange(2, 2 + ivLen)))
        return c.doFinal(blob.copyOfRange(2 + ivLen, blob.size))
    }
}
