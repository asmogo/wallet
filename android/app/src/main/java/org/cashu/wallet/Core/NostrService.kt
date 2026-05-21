package org.cashu.wallet.Core

import java.math.BigInteger
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.bouncycastle.asn1.sec.SECNamedCurves
import org.bouncycastle.math.ec.ECPoint
import org.cashu.wallet.Core.Protocols.SecureStorage
import org.cashu.wallet.Core.Protocols.StorageKeys

enum class NostrSignerType(val rawValue: String, val displayName: String) {
    Seed("SEED", "Wallet Seed"),
    PrivateKey("PRIVATEKEY", "Custom Key");

    companion object {
        fun fromRaw(value: String?): NostrSignerType = entries.firstOrNull { it.rawValue == value } ?: Seed
    }
}

data class NostrState(
    val publicKeyHex: String = "",
    val npub: String = "",
    val nsec: String = "",
    val isInitialized: Boolean = false,
    val signerType: NostrSignerType = NostrSignerType.Seed,
)

class NostrService(
    private val secureStorage: SecureStorage,
    private val settingsStore: SettingsStore,
) {
    private val mutableState = MutableStateFlow(NostrState(signerType = NostrSignerType.fromRaw(settingsStore.nostrSignerType)))
    val state: StateFlow<NostrState> = mutableState.asStateFlow()
    private var privateKeyBytes: ByteArray? = null
    private var seedPrivateKeyBytes: ByteArray? = null
    private var currentSeed: ByteArray? = null
    private val secureRandom = SecureRandom()

    fun deriveKeypairFromSeed(seed: ByteArray): NostrState {
        require(seed.size >= 32) { "Nostr seed must contain at least 32 bytes." }
        currentSeed = seed.copyOf()
        val seedKey = seed.copyOfRange(0, 32)
        seedPrivateKeyBytes = seedKey.takeIf { isValidSecret(it) }?.copyOf()
        val customKey = secureStorage.loadString(StorageKeys.secureNostrPrivateKey)
        return if (NostrSignerType.fromRaw(settingsStore.nostrSignerType) == NostrSignerType.PrivateKey && customKey != null) {
            setPrivateKey(hexToBytes(customKey), NostrSignerType.PrivateKey, persistCustomKey = false)
        } else {
            settingsStore.nostrSignerType = NostrSignerType.Seed.rawValue
            setPrivateKey(seedKey, NostrSignerType.Seed, persistCustomKey = false)
        }
    }

    fun currentPrivateKey(): String? = privateKeyBytes?.toHex() ?: secureStorage.loadString(StorageKeys.secureNostrPrivateKey)

    fun importNsec(nsec: String): NostrState {
        val key = Bech32.decode("nsec", nsec)
        require(key.size == 32) { "Invalid nsec private key length." }
        return setPrivateKey(key, NostrSignerType.PrivateKey, persistCustomKey = true)
    }

    fun generateRandomKeypair(): NostrState {
        val key = ByteArray(32)
        do {
            secureRandom.nextBytes(key)
        } while (!isValidSecret(key))
        return setPrivateKey(key, NostrSignerType.PrivateKey, persistCustomKey = true)
    }

    fun resetToSeedKey(): NostrState {
        val seed = currentSeed ?: throw IllegalStateException("No wallet seed is available for Nostr reset.")
        secureStorage.delete(StorageKeys.secureNostrPrivateKey)
        settingsStore.nostrSignerType = NostrSignerType.Seed.rawValue
        return setPrivateKey(seed.copyOfRange(0, 32), NostrSignerType.Seed, persistCustomKey = false)
    }

    fun switchSignerType(type: NostrSignerType): NostrState = when (type) {
        NostrSignerType.Seed -> resetToSeedKey()
        NostrSignerType.PrivateKey -> {
            secureStorage.loadString(StorageKeys.secureNostrPrivateKey)
                ?.let { setPrivateKey(hexToBytes(it), NostrSignerType.PrivateKey, persistCustomKey = false) }
                ?: generateRandomKeypair()
        }
    }

    fun hasCustomPrivateKey(): Boolean = secureStorage.contains(StorageKeys.secureNostrPrivateKey)

    fun lightningAddress(domain: String): String = state.value.npub.takeIf { it.isNotBlank() }?.let { "$it@$domain" }.orEmpty()

    fun hasSeedDerivedKey(): Boolean = seedPrivateKeyBytes != null

    fun seedDerivedPublicKeyHex(): String =
        seedPrivateKeyBytes?.let { publicKeyXOnly(it).toHex() }.orEmpty()

    fun seedDerivedNpub(): String =
        seedPrivateKeyBytes?.let { Bech32.encode("npub", publicKeyXOnly(it)) }.orEmpty()

    fun seedDerivedLightningAddress(domain: String): String =
        seedDerivedNpub().takeIf { it.isNotBlank() }?.let { "$it@$domain" }.orEmpty()

    fun generateNip98AuthHeader(url: String, method: String): String {
        val key = privateKeyBytes ?: throw IllegalStateException("Nostr key is not initialized.")
        return generateNip98AuthHeader(key, url, method)
    }

    fun generateSeedNip98AuthHeader(url: String, method: String): String {
        val key = seedPrivateKeyBytes ?: throw IllegalStateException("Nostr seed key is not initialized.")
        return generateNip98AuthHeader(key, url, method)
    }

    private fun generateNip98AuthHeader(key: ByteArray, url: String, method: String): String {
        val publicKey = publicKeyXOnly(key).toHex()
        val createdAt = System.currentTimeMillis() / 1000
        val tags = nip98Tags(url, method)
        val eventId = calculateEventId(publicKey, createdAt, 27235, tags, "")
        val auxRand = ByteArray(32).also(secureRandom::nextBytes)
        val signature = schnorrSign(hexToBytes(eventId), key, auxRand).toHex()
        val json = signedNip98EventJson(
            eventId = eventId,
            publicKey = publicKey,
            createdAt = createdAt,
            tags = tags,
            signature = signature,
        )
        return Base64.getEncoder().encodeToString(json.toByteArray(Charsets.UTF_8))
    }

    fun resetForWalletBoundary(deleteStoredKey: Boolean) {
        if (deleteStoredKey) secureStorage.delete(StorageKeys.secureNostrPrivateKey)
        settingsStore.nostrSignerType = NostrSignerType.Seed.rawValue
        privateKeyBytes = null
        seedPrivateKeyBytes = null
        currentSeed = null
        mutableState.value = NostrState(signerType = NostrSignerType.Seed)
    }

    private fun setPrivateKey(key: ByteArray, signerType: NostrSignerType, persistCustomKey: Boolean): NostrState {
        require(key.size == 32 && isValidSecret(key)) { "Invalid Nostr private key." }
        if (persistCustomKey) secureStorage.saveString(StorageKeys.secureNostrPrivateKey, key.toHex())
        settingsStore.nostrSignerType = signerType.rawValue
        privateKeyBytes = key.copyOf()
        val publicKey = publicKeyXOnly(key)
        return NostrState(
            publicKeyHex = publicKey.toHex(),
            npub = Bech32.encode("npub", publicKey),
            nsec = Bech32.encode("nsec", key),
            isInitialized = true,
            signerType = signerType,
        ).also { mutableState.value = it }
    }

    companion object {
        private val params = SECNamedCurves.getByName("secp256k1")
        private val curve = params.curve
        private val generator = params.g
        private val order = params.n
        private val fieldPrime = curve.field.characteristic
        private val one = BigInteger.ONE
        private val two = BigInteger.valueOf(2)

        fun publicKeyHex(privateKeyHex: String): String = publicKeyXOnly(hexToBytes(privateKeyHex)).toHex()

        internal fun nip98Tags(url: String, method: String): List<List<String>> =
            listOf(listOf("u", url), listOf("method", method.uppercase()))

        internal fun eventCommitmentJson(
            pubkey: String,
            createdAt: Long,
            kind: Int,
            tags: List<List<String>>,
            content: String,
        ): String = """[0,"${pubkey.escapeJson()}",$createdAt,$kind,${tags.toJsonArray()},"${content.escapeJson()}"]"""

        internal fun calculateEventId(
            pubkey: String,
            createdAt: Long,
            kind: Int,
            tags: List<List<String>>,
            content: String,
        ): String = sha256(eventCommitmentJson(pubkey, createdAt, kind, tags, content).toByteArray(Charsets.UTF_8)).toHex()

        internal fun signedNip98EventJson(
            eventId: String,
            publicKey: String,
            createdAt: Long,
            tags: List<List<String>>,
            signature: String,
        ): String =
            """{"id":"${eventId.escapeJson()}","pubkey":"${publicKey.escapeJson()}","content":"","kind":27235,"created_at":$createdAt,"tags":${tags.toJsonArray()},"sig":"${signature.escapeJson()}"}"""

        fun publicKeyXOnly(secret: ByteArray): ByteArray {
            val point = generator.multiply(secret.toPositiveBigInteger()).normalize()
            return point.affineXCoord.encoded.toFixedSize(32)
        }

        fun schnorrSign(message: ByteArray, secret: ByteArray, auxRand: ByteArray = ByteArray(32)): ByteArray {
            require(message.size == 32) { "BIP-340 messages must be 32 bytes." }
            require(secret.size == 32 && isValidSecret(secret)) { "Invalid Schnorr private key." }
            require(auxRand.size == 32) { "Auxiliary randomness must be 32 bytes." }
            val secretInt = secret.toPositiveBigInteger()
            val publicPoint = generator.multiply(secretInt).normalize()
            val d = if (publicPoint.hasOddY()) order.subtract(secretInt) else secretInt
            val publicX = publicPoint.affineXCoord.encoded.toFixedSize(32)
            val t = d.toFixedBytes().xorBytes(taggedHash("BIP0340/aux", auxRand))
            val nonceBytes = taggedHash("BIP0340/nonce", t + publicX + message)
            val kPrime = nonceBytes.toPositiveBigInteger().mod(order)
            require(kPrime != BigInteger.ZERO) { "Invalid Schnorr nonce." }
            val rPoint = generator.multiply(kPrime).normalize()
            val k = if (rPoint.hasOddY()) order.subtract(kPrime) else kPrime
            val r = rPoint.affineXCoord.encoded.toFixedSize(32)
            val e = taggedHash("BIP0340/challenge", r + publicX + message).toPositiveBigInteger().mod(order)
            val s = k.add(e.multiply(d)).mod(order)
            return r + s.toFixedBytes()
        }

        fun verifySchnorr(message: ByteArray, publicKeyXOnly: ByteArray, signature: ByteArray): Boolean {
            if (message.size != 32 || publicKeyXOnly.size != 32 || signature.size != 64) return false
            val r = signature.copyOfRange(0, 32).toPositiveBigInteger()
            val s = signature.copyOfRange(32, 64).toPositiveBigInteger()
            if (r >= fieldPrime || s >= order) return false
            val publicKey = liftX(publicKeyXOnly.toPositiveBigInteger()) ?: return false
            val e = taggedHash("BIP0340/challenge", signature.copyOfRange(0, 32) + publicKeyXOnly + message)
                .toPositiveBigInteger()
                .mod(order)
            val point = generator.multiply(s).subtract(publicKey.multiply(e)).normalize()
            if (point.isInfinity || point.hasOddY()) return false
            return point.affineXCoord.toBigInteger() == r
        }

        fun hexToBytes(hex: String): ByteArray {
            val clean = hex.trim().removePrefix("0x")
            require(clean.length % 2 == 0) { "Hex string must have an even length." }
            return clean.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        }

        private fun isValidSecret(secret: ByteArray): Boolean {
            val value = secret.toPositiveBigInteger()
            return value > BigInteger.ZERO && value < order
        }

        private fun liftX(x: BigInteger): ECPoint? {
            if (x >= fieldPrime) return null
            val ySquared = x.modPow(BigInteger.valueOf(3), fieldPrime).add(BigInteger.valueOf(7)).mod(fieldPrime)
            val y = ySquared.modPow(fieldPrime.add(one).divide(BigInteger.valueOf(4)), fieldPrime)
            if (y.modPow(two, fieldPrime) != ySquared) return null
            val evenY = if (y.testBit(0)) fieldPrime.subtract(y) else y
            return curve.createPoint(x, evenY)
        }

        private fun taggedHash(tag: String, data: ByteArray): ByteArray {
            val tagHash = sha256(tag.toByteArray(Charsets.UTF_8))
            return sha256(tagHash + tagHash + data)
        }

        private fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)

        private fun ByteArray.toPositiveBigInteger(): BigInteger = BigInteger(1, this)
        private fun BigInteger.toFixedBytes(): ByteArray = toByteArray().toFixedSize(32)
        private fun ByteArray.toFixedSize(size: Int): ByteArray {
            val positive = if (isNotEmpty() && first() == 0.toByte()) drop(1).toByteArray() else this
            require(positive.size <= size) { "Value does not fit in $size bytes." }
            return ByteArray(size - positive.size) + positive
        }

        private fun ECPoint.hasOddY(): Boolean = affineYCoord.toBigInteger().testBit(0)

        private fun ByteArray.xorBytes(other: ByteArray): ByteArray =
            ByteArray(size) { index -> (this[index].toInt() xor other[index].toInt()).toByte() }

        private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

        private fun List<List<String>>.toJsonArray(): String =
            joinToString(separator = ",", prefix = "[", postfix = "]") { row ->
                row.joinToString(separator = ",", prefix = "[", postfix = "]") { "\"${it.escapeJson()}\"" }
            }

        private fun String.escapeJson(): String = buildString {
            this@escapeJson.forEach { char ->
                when (char) {
                    '\\' -> append("\\\\")
                    '"' -> append("\\\"")
                    '\b' -> append("\\b")
                    '\u000C' -> append("\\f")
                    '\n' -> append("\\n")
                    '\r' -> append("\\r")
                    '\t' -> append("\\t")
                    else -> {
                        if (char < ' ') {
                            append("\\u")
                            append(char.code.toString(16).padStart(4, '0'))
                        } else {
                            append(char)
                        }
                    }
                }
            }
        }
    }
}
