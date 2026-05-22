package org.cashu.wallet.Core

import java.math.BigInteger
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.bouncycastle.asn1.sec.SECNamedCurves

internal object NIP44 {
    private val secureRandom = SecureRandom()
    private val params = SECNamedCurves.getByName("secp256k1")
    private val curve = params.curve
    private val order = params.n

    fun encrypt(
        plaintext: String,
        senderPrivateKey: ByteArray,
        recipientPubkeyHex: String,
    ): String {
        val conversationKey = conversationKey(senderPrivateKey, recipientPubkeyHex)
        val nonce = ByteArray(32).also(secureRandom::nextBytes)
        return encrypt(plaintext, conversationKey, nonce)
    }

    fun decrypt(
        payload: String,
        recipientPrivateKey: ByteArray,
        senderPubkeyHex: String,
    ): String {
        val conversationKey = conversationKey(recipientPrivateKey, senderPubkeyHex)
        return decrypt(payload, conversationKey)
    }

    internal fun conversationKey(privateKey: ByteArray, pubkeyHex: String): ByteArray {
        val pubkeyBytes = hexToBytes(pubkeyHex)
        require(pubkeyBytes.size == 32) { "Invalid Nostr public key." }
        val secret = privateKey.toPositiveBigInteger()
        require(privateKey.size == 32 && secret > BigInteger.ZERO && secret < order) { "Invalid Nostr private key." }
        val publicPoint = curve.decodePoint(byteArrayOf(0x02) + pubkeyBytes)
        val sharedPoint = publicPoint.multiply(secret).normalize()
        val sharedX = sharedPoint.affineXCoord.encoded.toFixedSize(32)
        return hmacSha256("nip44-v2".toByteArray(Charsets.UTF_8), sharedX)
    }

    internal fun encrypt(plaintext: String, conversationKey: ByteArray, nonce: ByteArray): String {
        val plaintextBytes = plaintext.toByteArray(Charsets.UTF_8)
        require(plaintextBytes.size in 1..65_535) { "NIP-44 plaintext size is invalid." }
        val (chachaKey, chachaNonce, hmacKey) = derive(conversationKey, nonce)
        val padded = pad(plaintextBytes)
        val ciphertext = ChaCha20.process(chachaKey, chachaNonce, padded)
        val mac = hmacSha256(hmacKey, nonce + ciphertext)
        val payload = byteArrayOf(0x02) + nonce + ciphertext + mac
        return Base64.getEncoder().encodeToString(payload)
    }

    internal fun decrypt(payload: String, conversationKey: ByteArray): String {
        val raw = Base64.getDecoder().decode(payload)
        require(raw.size >= 65) { "Invalid NIP-44 payload." }
        require(raw[0] == 0x02.toByte()) { "Invalid NIP-44 version." }
        val nonce = raw.copyOfRange(1, 33)
        val ciphertext = raw.copyOfRange(33, raw.size - 32)
        val mac = raw.copyOfRange(raw.size - 32, raw.size)
        val (chachaKey, chachaNonce, hmacKey) = derive(conversationKey, nonce)
        val expected = hmacSha256(hmacKey, nonce + ciphertext)
        require(constantTimeEquals(expected, mac)) { "NIP-44 MAC mismatch." }
        val padded = ChaCha20.process(chachaKey, chachaNonce, ciphertext)
        return unpad(padded)
    }

    internal fun pad(plaintext: ByteArray): ByteArray {
        val paddedLength = paddedLength(plaintext.size)
        return ByteArray(2 + paddedLength).also { out ->
            out[0] = ((plaintext.size ushr 8) and 0xff).toByte()
            out[1] = (plaintext.size and 0xff).toByte()
            plaintext.copyInto(out, destinationOffset = 2)
        }
    }

    internal fun unpad(padded: ByteArray): String {
        require(padded.size >= 2) { "Invalid NIP-44 padding." }
        val length = ((padded[0].toInt() and 0xff) shl 8) or (padded[1].toInt() and 0xff)
        require(length in 1..(padded.size - 2)) { "Invalid NIP-44 length." }
        require(padded.size == 2 + paddedLength(length)) { "Invalid NIP-44 padded length." }
        return padded.copyOfRange(2, 2 + length).toString(Charsets.UTF_8)
    }

    internal fun paddedLength(length: Int): Int {
        require(length > 0) { "NIP-44 plaintext must not be empty." }
        if (length <= 32) return 32
        val nextPower = Integer.highestOneBit(length - 1) shl 1
        val chunk = if (nextPower <= 256) 32 else nextPower / 8
        return chunk * (((length - 1) / chunk) + 1)
    }

    private data class DerivedKeys(
        val chachaKey: ByteArray,
        val chachaNonce: ByteArray,
        val hmacKey: ByteArray,
    )

    private fun derive(conversationKey: ByteArray, nonce: ByteArray): DerivedKeys {
        require(conversationKey.size == 32) { "NIP-44 conversation key must be 32 bytes." }
        require(nonce.size == 32) { "NIP-44 nonce must be 32 bytes." }
        val derived = hkdfExpand(conversationKey, nonce, 76)
        return DerivedKeys(
            chachaKey = derived.copyOfRange(0, 32),
            chachaNonce = derived.copyOfRange(32, 44),
            hmacKey = derived.copyOfRange(44, 76),
        )
    }

    private fun hkdfExpand(prk: ByteArray, info: ByteArray, length: Int): ByteArray {
        val output = ByteArray(length)
        var previous = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < length) {
            previous = hmacSha256(prk, previous + info + counter.toByte())
            val take = minOf(previous.size, length - offset)
            previous.copyInto(output, destinationOffset = offset, endIndex = take)
            offset += take
            counter += 1
        }
        return output
    }

    private fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data)
    }

    private fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
        if (a.size != b.size) return false
        var diff = 0
        for (index in a.indices) {
            diff = diff or (a[index].toInt() xor b[index].toInt())
        }
        return diff == 0
    }

    internal fun hexToBytes(hex: String): ByteArray {
        val clean = hex.trim().removePrefix("0x")
        require(clean.length % 2 == 0) { "Hex string must have an even length." }
        return clean.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }

    private fun ByteArray.toPositiveBigInteger(): BigInteger = BigInteger(1, this)

    private fun ByteArray.toFixedSize(size: Int): ByteArray {
        val positive = if (isNotEmpty() && first() == 0.toByte()) drop(1).toByteArray() else this
        require(positive.size <= size) { "Value does not fit in $size bytes." }
        return ByteArray(size - positive.size) + positive
    }
}

private object ChaCha20 {
    fun process(key: ByteArray, nonce: ByteArray, data: ByteArray): ByteArray {
        require(key.size == 32) { "ChaCha20 key must be 32 bytes." }
        require(nonce.size == 12) { "ChaCha20 nonce must be 12 bytes." }
        val out = ByteArray(data.size)
        var counter = 0
        var offset = 0
        while (offset < data.size) {
            val block = block(key, counter, nonce)
            val take = minOf(64, data.size - offset)
            for (index in 0 until take) {
                out[offset + index] = (data[offset + index].toInt() xor block[index].toInt()).toByte()
            }
            offset += take
            counter += 1
        }
        return out
    }

    private fun block(key: ByteArray, counter: Int, nonce: ByteArray): ByteArray {
        val state = IntArray(16)
        state[0] = 0x61707865
        state[1] = 0x3320646e
        state[2] = 0x79622d32
        state[3] = 0x6b206574
        for (index in 0 until 8) {
            state[4 + index] = loadLE32(key, index * 4)
        }
        state[12] = counter
        state[13] = loadLE32(nonce, 0)
        state[14] = loadLE32(nonce, 4)
        state[15] = loadLE32(nonce, 8)
        val working = state.copyOf()
        repeat(10) {
            quarterRound(working, 0, 4, 8, 12)
            quarterRound(working, 1, 5, 9, 13)
            quarterRound(working, 2, 6, 10, 14)
            quarterRound(working, 3, 7, 11, 15)
            quarterRound(working, 0, 5, 10, 15)
            quarterRound(working, 1, 6, 11, 12)
            quarterRound(working, 2, 7, 8, 13)
            quarterRound(working, 3, 4, 9, 14)
        }
        for (index in 0 until 16) {
            working[index] += state[index]
        }
        val out = ByteArray(64)
        for (index in 0 until 16) {
            val word = working[index]
            out[index * 4] = (word and 0xff).toByte()
            out[index * 4 + 1] = ((word ushr 8) and 0xff).toByte()
            out[index * 4 + 2] = ((word ushr 16) and 0xff).toByte()
            out[index * 4 + 3] = ((word ushr 24) and 0xff).toByte()
        }
        return out
    }

    private fun quarterRound(state: IntArray, a: Int, b: Int, c: Int, d: Int) {
        state[a] += state[b]
        state[d] = Integer.rotateLeft(state[d] xor state[a], 16)
        state[c] += state[d]
        state[b] = Integer.rotateLeft(state[b] xor state[c], 12)
        state[a] += state[b]
        state[d] = Integer.rotateLeft(state[d] xor state[a], 8)
        state[c] += state[d]
        state[b] = Integer.rotateLeft(state[b] xor state[c], 7)
    }

    private fun loadLE32(data: ByteArray, offset: Int): Int =
        (data[offset].toInt() and 0xff) or
            ((data[offset + 1].toInt() and 0xff) shl 8) or
            ((data[offset + 2].toInt() and 0xff) shl 16) or
            ((data[offset + 3].toInt() and 0xff) shl 24)
}
