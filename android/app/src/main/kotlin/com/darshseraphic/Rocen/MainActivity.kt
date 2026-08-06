package com.darshseraphic.Rocen

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

class MainActivity: FlutterActivity() {
    private val screenSecurityChannel = "com.darshseraphic.rocen/screen_security"
    private val deviceIntegrityChannel = "com.darshseraphic.rocen/device_integrity"
    private val secureKeystoreChannel = "com.darshseraphic.rocen/secure_keystore"

    private val defaultHwKeyAlias = "rocen_hw_master_key" // legacy fallback if a call ever omits keyAlias
    private val androidKeyStoreProvider = "AndroidKeyStore"
    private val cachedTiers = mutableMapOf<String, String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenSecurityChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "preventScreenshotOn" -> {
                    window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "preventScreenshotOff" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceIntegrityChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "isRooted" -> result.success(checkRootIndicators())
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureKeystoreChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "hwEncrypt" -> {
                    try {
                        val alias = call.argument<String>("keyAlias") ?: defaultHwKeyAlias
                        val plainB64 = call.argument<String>("plaintext") ?: ""
                        val plainBytes = Base64.decode(plainB64, Base64.NO_WRAP)
                        val key = getOrCreateHwKey(alias)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.ENCRYPT_MODE, key)
                        val cipherBytes = cipher.doFinal(plainBytes)
                        result.success(mapOf(
                            "iv" to Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
                            "ciphertext" to Base64.encodeToString(cipherBytes, Base64.NO_WRAP),
                            "tier" to (cachedTiers[alias] ?: "tee")
                        ))
                    } catch (e: Exception) {
                        result.error("HW_ENCRYPT_FAILED", e.message, null)
                    }
                }
                "hwDecrypt" -> {
                    try {
                        val alias = call.argument<String>("keyAlias") ?: defaultHwKeyAlias
                        val ivBytes = Base64.decode(call.argument<String>("iv") ?: "", Base64.NO_WRAP)
                        val cipherBytes = Base64.decode(call.argument<String>("ciphertext") ?: "", Base64.NO_WRAP)
                        val key = getOrCreateHwKey(alias)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, ivBytes))
                        val plainBytes = cipher.doFinal(cipherBytes)
                        result.success(mapOf("plaintext" to Base64.encodeToString(plainBytes, Base64.NO_WRAP)))
                    } catch (e: Exception) {
                        result.error("HW_DECRYPT_FAILED", e.message, null)
                    }
                }
                "keyTier" -> {
                    try {
                        val alias = call.argument<String>("keyAlias") ?: defaultHwKeyAlias
                        getOrCreateHwKey(alias)
                        result.success(cachedTiers[alias] ?: "tee")
                    } catch (e: Exception) {
                        result.error("HW_KEY_UNAVAILABLE", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Returns the hardware-backed AES key for the given alias, generating it once per
    // alias (StrongBox first, falling back to TEE) and reusing it on every later call.
    // Separate aliases (password vs GitHub token) get separate, independent keys - the
    // key material itself never leaves AndroidKeyStore, only ciphertext crosses the
    // platform channel.
    private fun getOrCreateHwKey(alias: String): SecretKey {
        val keyStore = KeyStore.getInstance(androidKeyStoreProvider)
        keyStore.load(null)

        val existing = keyStore.getKey(alias, null) as? SecretKey
        if (existing != null) {
            if (cachedTiers[alias] == null) cachedTiers[alias] = detectTier(existing)
            return existing
        }

        val key = try {
            val generated = generateHwKey(alias, strongBox = true)
            cachedTiers[alias] = "strongbox"
            generated
        } catch (e: StrongBoxUnavailableException) {
            val generated = generateHwKey(alias, strongBox = false)
            cachedTiers[alias] = "tee"
            generated
        } catch (e: Exception) {
            val generated = generateHwKey(alias, strongBox = false)
            cachedTiers[alias] = "tee"
            generated
        }

        cachedTiers[alias] = detectTier(key)
        return key
    }

    private fun generateHwKey(alias: String, strongBox: Boolean): SecretKey {
        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, androidKeyStoreProvider)
        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)

        if (strongBox && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }

        keyGenerator.init(builder.build())
        return keyGenerator.generateKey()
    }

    private fun detectTier(key: SecretKey): String {
        return try {
            val factory = SecretKeyFactory.getInstance(key.algorithm, androidKeyStoreProvider)
            val keyInfo = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                when (keyInfo.securityLevel) {
                    android.security.keystore.KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                    android.security.keystore.KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "tee"
                    else -> "software_fallback"
                }
            } else {
                if (keyInfo.isInsideSecureHardware) "tee" else "software_fallback"
            }
        } catch (e: Exception) {
            "tee"
        }
    }

    private fun checkRootIndicators(): Boolean {
        val suPaths = arrayOf(
            "/system/bin/su",
            "/system/xbin/su",
            "/sbin/su",
            "/system/su",
            "/system/bin/.ext/.su",
            "/system/usr/we-need-root/su-backup",
            "/system/xbin/mu"
        )
        for (path in suPaths) {
            if (File(path).exists()) return true
        }

        val buildTags = android.os.Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) return true

        val rootPackages = arrayOf(
            "com.topjohnwu.magisk",
            "eu.chainfire.supersu",
            "com.noshufou.android.su",
            "com.koushikdutta.superuser",
            "com.thirdparty.superuser",
            "com.yellowes.su"
        )
        for (pkg in rootPackages) {
            try {
                packageManager.getPackageInfo(pkg, 0)
                return true
            } catch (e: Exception) {
            }
        }

        return false
    }
}