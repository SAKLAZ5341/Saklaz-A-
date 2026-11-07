package com.saklaz.assistant.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Log
import com.saklaz.assistant.bridge.DatabaseKeyMessage
import com.saklaz.assistant.bridge.KeyVaultHostApi
import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/**
 * Veritabanı anahtarı yönetimi (zarf şifreleme):
 *  1. 256-bit rastgele veritabanı anahtarı (DEK) üretilir.
 *  2. DEK, Android Keystore'daki dışa aktarılamayan AES-256-GCM anahtarıyla (KEK)
 *     şifrelenir ve yalnızca şifreli hâli `noBackupFilesDir` altına yazılır.
 *  3. KEK cihazdan çıkarılamaz; uygulama silinince veya veri temizlenince kaybolur.
 */
class KeyVaultController(private val context: Context) : KeyVaultHostApi {

    override fun getOrCreateDatabaseKey(): DatabaseKeyMessage {
        val kek = getOrCreateKek()
        val file = File(context.noBackupFilesDir, WRAPPED_FILE)
        val dek = if (file.exists()) unwrap(kek, file.readBytes()) else createAndStore(kek, file)
        return DatabaseKeyMessage(
            hexKey = dek.toHex(),
            hardwareBacked = isHardwareBacked(kek),
            databaseDirectory = context.noBackupFilesDir.absolutePath,
        )
    }

    private fun createAndStore(kek: SecretKey, file: File): ByteArray {
        val dek = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, kek)
        val iv = cipher.iv
        val ct = cipher.doFinal(dek)
        val tmp = File(file.parentFile, "$WRAPPED_FILE.tmp")
        tmp.writeBytes(byteArrayOf(VERSION, iv.size.toByte()) + iv + ct)
        if (!tmp.renameTo(file)) throw IllegalStateException("Anahtar dosyası yazılamadı")
        Log.i(TAG, "Yeni veritabanı anahtarı oluşturuldu.")
        return dek
    }

    private fun unwrap(kek: SecretKey, blob: ByteArray): ByteArray {
        require(blob.size > 2 && blob[0] == VERSION) { "Bilinmeyen anahtar dosyası biçimi" }
        val ivLen = blob[1].toInt()
        val iv = blob.copyOfRange(2, 2 + ivLen)
        val ct = blob.copyOfRange(2 + ivLen, blob.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, kek, GCMParameterSpec(128, iv))
        return cipher.doFinal(ct)
    }

    private fun getOrCreateKek(): SecretKey {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (ks.getKey(KEK_ALIAS, null) as? SecretKey)?.let { return it }
        return try {
            generateKek(strongBox = true)
        } catch (_: StrongBoxUnavailableException) {
            generateKek(strongBox = false)
        }
    }

    private fun generateKek(strongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            KEK_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
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

    private fun isHardwareBacked(key: SecretKey): Boolean = try {
        val info = SecretKeyFactory.getInstance(key.algorithm, ANDROID_KEYSTORE)
            .getKeySpec(key, KeyInfo::class.java) as KeyInfo
        info.securityLevel == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT ||
            info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
    } catch (e: Exception) {
        Log.w(TAG, "Anahtar güvenlik seviyesi okunamadı", e)
        false
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    private companion object {
        const val TAG = "SaklazKeyVault"
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEK_ALIAS = "saklaz_db_kek_v1"
        const val WRAPPED_FILE = "saklaz_db_key.bin"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val VERSION: Byte = 1
    }
}
