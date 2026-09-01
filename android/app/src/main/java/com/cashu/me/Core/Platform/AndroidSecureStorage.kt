package com.cashu.me.Core.Platform

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import com.cashu.me.Core.Protocols.SecureStorage

class AndroidSecureStorage(context: Context) : SecureStorage {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("secure_store", Context.MODE_PRIVATE)
    private val keyAlias = "cashu_wallet_secure_storage"

    override fun loadString(key: String): String? {
        val encoded = prefs.getString(key, null) ?: return null
        val parts = encoded.split(":")
        if (parts.size != 2) return null
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val cipherBytes = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
        return cipher.doFinal(cipherBytes).toString(Charsets.UTF_8)
    }

    override fun saveString(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val payload = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) +
            ":" +
            Base64.encodeToString(encrypted, Base64.NO_WRAP)
        check(prefs.edit().putString(key, payload).commit()) {
            "Failed to persist secure value."
        }
    }

    override fun delete(key: String) {
        check(prefs.edit().remove(key).commit()) {
            "Failed to remove secure value."
        }
    }

    override fun deletePrefix(prefix: String) {
        val matchingKeys = prefs.all.keys.filter { it.startsWith(prefix) }
        if (matchingKeys.isEmpty()) return
        val committed = prefs.edit().apply {
            matchingKeys.forEach(::remove)
        }.commit()
        check(committed) { "Failed to remove secure values." }
    }

    override fun contains(key: String): Boolean = prefs.contains(key)

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(false)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }
}
