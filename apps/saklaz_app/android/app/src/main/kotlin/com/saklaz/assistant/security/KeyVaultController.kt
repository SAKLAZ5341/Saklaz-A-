package com.saklaz.assistant.security

import android.content.Context
import android.util.Log
import com.saklaz.assistant.bridge.DatabaseKeyMessage
import com.saklaz.assistant.bridge.KeyVaultHostApi
import java.io.File
import java.security.SecureRandom

/**
 * Veritabanı anahtarı (zarf şifreleme): 256-bit rastgele DEK, Keystore'daki
 * KEK ile şifrelenip yalnızca şifreli hâli `noBackupFilesDir` altına yazılır.
 */
class KeyVaultController(private val context: Context) : KeyVaultHostApi {

    override fun getOrCreateDatabaseKey(): DatabaseKeyMessage {
        val kek = KekProvider.getOrCreate(KekProvider.DB_ALIAS)
        val file = File(context.noBackupFilesDir, WRAPPED_FILE)
        val dek = if (file.exists()) {
            KekProvider.decrypt(kek, file.readBytes())
        } else {
            val fresh = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val tmp = File(file.parentFile, "$WRAPPED_FILE.tmp")
            tmp.writeBytes(KekProvider.encrypt(kek, fresh))
            check(tmp.renameTo(file)) { "Anahtar dosyası yazılamadı" }
            Log.i(TAG, "Yeni veritabanı anahtarı oluşturuldu.")
            fresh
        }
        return DatabaseKeyMessage(
            hexKey = dek.joinToString("") { "%02x".format(it) },
            hardwareBacked = KekProvider.isHardwareBacked(kek),
            databaseDirectory = context.noBackupFilesDir.absolutePath,
        )
    }

    private companion object {
        const val TAG = "SaklazKeyVault"
        const val WRAPPED_FILE = "saklaz_db_key.bin"
    }
}
