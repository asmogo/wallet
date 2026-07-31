package com.cashu.me.Core

import java.net.URI
import java.util.Base64

object PaymentRequestBuilder {
    /** Android HCE/Numo variant: NFC is the return transport, so no transport array is advertised. */
    fun buildNfc(
        id: String,
        amount: Long?,
        unit: String?,
        singleUse: Boolean? = null,
        mints: List<String>,
        description: String?,
    ): String {
        val request = buildList {
            add(Nut18Key.Text("i") to Nut18Value.Text(id))
            add(Nut18Key.Text("a") to amount?.takeIf { it > 0 }?.let { Nut18Value.UInt(it) }.orNull())
            add(Nut18Key.Text("u") to unit?.takeIf { it.isNotBlank() }?.let { Nut18Value.Text(it) }.orNull())
            add(Nut18Key.Text("s") to singleUse?.let { Nut18Value.Bool(it) }.orNull())
            if (mints.isNotEmpty()) add(Nut18Key.Text("m") to Nut18Value.Array(mints.map { Nut18Value.Text(it) }))
            add(Nut18Key.Text("d") to description?.takeIf { it.isNotBlank() }?.let { Nut18Value.Text(it) }.orNull())
        }
        val cbor = Nut18Cbor.encode(Nut18Value.Map(request))
        return "creqA" + Base64.getUrlEncoder().encodeToString(cbor)
    }

    fun build(
        id: String,
        amount: Long?,
        unit: String?,
        singleUse: Boolean? = null,
        mints: List<String>,
        description: String?,
        nostrPubkeyHex: String,
        relays: List<String>,
        nip: String = "17",
        p2pkPubkeyHex: String? = null,
    ): String {
        val nprofile = makeNprofile(nostrPubkeyHex, relays)
        val transport = listOf(
            Nut18Key.Text("t") to Nut18Value.Text("nostr"),
            Nut18Key.Text("a") to Nut18Value.Text(nprofile),
            Nut18Key.Text("g") to Nut18Value.Array(
                listOf(
                    Nut18Value.Array(
                        listOf(Nut18Value.Text("n"), Nut18Value.Text(nip)),
                    ),
                ),
            ),
        )
        val request = buildList {
            add(Nut18Key.Text("i") to Nut18Value.Text(id))
            add(Nut18Key.Text("a") to amount?.takeIf { it > 0 }?.let { Nut18Value.UInt(it) }.orNull())
            add(Nut18Key.Text("u") to unit?.takeIf { it.isNotBlank() }?.let { Nut18Value.Text(it) }.orNull())
            add(Nut18Key.Text("s") to singleUse?.let { Nut18Value.Bool(it) }.orNull())
            if (mints.isNotEmpty()) add(Nut18Key.Text("m") to Nut18Value.Array(mints.map { Nut18Value.Text(it) }))
            add(Nut18Key.Text("d") to description?.takeIf { it.isNotBlank() }?.let { Nut18Value.Text(it) }.orNull())
            add(Nut18Key.Text("t") to Nut18Value.Array(listOf(Nut18Value.Map(transport))))
            // Optional NUT-10 lock (NUT-18). A payer's wallet reads this and locks
            // the proofs it creates to the given P2PK pubkey, so only its holder
            // can redeem them. Encoded as cashu-ts does: `"nut10": {"k": kind, "d": data}`.
            if (!p2pkPubkeyHex.isNullOrBlank()) {
                add(
                    Nut18Key.Text("nut10") to Nut18Value.Map(
                        listOf(
                            Nut18Key.Text("k") to Nut18Value.Text("P2PK"),
                            Nut18Key.Text("d") to Nut18Value.Text(p2pkPubkeyHex),
                        ),
                    ),
                )
            }
        }
        val cbor = Nut18Cbor.encode(Nut18Value.Map(request))
        return "creqA" + Base64.getUrlEncoder().encodeToString(cbor)
    }

    fun makeNprofile(pubkeyHex: String, relays: List<String>): String {
        val pubkey = NIP44.hexToBytes(pubkeyHex)
        require(pubkey.size == 32) { "Invalid Nostr public key." }
        val tlv = mutableListOf<Byte>()
        tlv += 0x00.toByte()
        tlv += pubkey.size.toByte()
        tlv += pubkey.toList()
        relays.forEach { relay ->
            val bytes = relay.toByteArray(Charsets.UTF_8)
            if (bytes.size <= 255) {
                tlv += 0x01.toByte()
                tlv += bytes.size.toByte()
                tlv += bytes.toList()
            }
        }
        return Bech32.encode("nprofile", tlv.toByteArray())
    }
}

sealed interface CashuRequestNostrReadiness {
    data class RequestConfiguration(
        val publicKeyHex: String,
        val relays: List<String>,
    )

    data class DeliveryNotice(
        val title: String,
        val message: String,
    )

    data class Ready(
        val publicKeyHex: String,
        val relays: List<String>,
    ) : CashuRequestNostrReadiness

    data class Blocked(
        val recoveryMessage: String,
        val requestConfiguration: RequestConfiguration? = null,
    ) : CashuRequestNostrReadiness

    fun requestConfigurationOrNull(): RequestConfiguration? = when (this) {
        is Ready -> RequestConfiguration(publicKeyHex = publicKeyHex, relays = relays)
        is Blocked -> requestConfiguration
    }

    /**
     * Contextual copy for an already-created request. It avoids the "try again"
     * wording used for creation errors because the QR remains shareable while
     * the wallet's receive path is unavailable.
     */
    fun deliveryNoticeOrNull(): DeliveryNotice? {
        val recoveryMessage = (this as? Blocked)?.recoveryMessage ?: return null
        return when (recoveryMessage) {
            NOSTR_KEY_RECOVERY -> DeliveryNotice(
                title = "Nostr key unavailable",
                message = "This wallet can't receive payments for this request. Check Settings → Nostr → Nostr key.",
            )
            RELAY_RECOVERY -> DeliveryNotice(
                title = "No usable relay",
                message = "This wallet can't receive payments for this request. Add a ws:// or wss:// relay in Settings → Nostr → Relays.",
            )
            else -> DeliveryNotice(
                title = "Payment requests are off",
                message = "You can share this request, but this wallet won't receive payments until you turn on Settings → Privacy → Listen for payment requests.",
            )
        }
    }

    companion object {
        const val NOSTR_KEY_RECOVERY =
            "Your Nostr key isn't ready. Check Settings → Nostr → Nostr key, then try again."
        const val RELAY_RECOVERY =
            "No usable Nostr relay is configured. Add a ws:// or wss:// relay in Settings → Nostr → Relays, then try again."
        const val LISTENER_RECOVERY =
            "Cashu Request listening is off. Turn on Settings → Privacy → Listen for payment requests, then try again."

        fun current(
            nostrService: NostrService,
            settingsManager: SettingsManager,
        ): CashuRequestNostrReadiness {
            val nostr = nostrService.state.value
            val settings = settingsManager.state.value
            return evaluate(
                isIdentityInitialized = nostr.isInitialized,
                publicKeyHex = nostr.publicKeyHex,
                privateKeyHex = nostrService.currentPrivateKey(),
                relays = settings.nostrRelays,
                listenerEnabled = settings.enablePaymentRequests,
            )
        }

        internal fun evaluate(
            isIdentityInitialized: Boolean,
            publicKeyHex: String,
            privateKeyHex: String?,
            relays: List<String>,
            listenerEnabled: Boolean,
        ): CashuRequestNostrReadiness {
            if (!isIdentityInitialized ||
                !publicKeyHex.isHexKey() ||
                privateKeyHex?.isHexKey() != true
            ) {
                return Blocked(NOSTR_KEY_RECOVERY)
            }
            val usableRelays = normalizedRelays(relays)
            if (usableRelays.isEmpty()) return Blocked(RELAY_RECOVERY)
            val requestConfiguration = RequestConfiguration(
                publicKeyHex = publicKeyHex,
                relays = usableRelays,
            )
            if (!listenerEnabled) return Blocked(LISTENER_RECOVERY, requestConfiguration)
            return Ready(publicKeyHex = publicKeyHex, relays = usableRelays)
        }

        internal fun normalizedRelays(relays: List<String>): List<String> =
            relays.map(String::trim)
                .filter { relay ->
                    runCatching { URI(relay) }.getOrNull()?.let { uri ->
                        uri.scheme?.lowercase() in setOf("ws", "wss") && !uri.host.isNullOrBlank()
                    } == true
                }
                .distinct()

        private fun String.isHexKey(): Boolean =
            length == 64 && all { it in '0'..'9' || it.lowercaseChar() in 'a'..'f' }
    }
}

/**
 * Builds the "receive locked ecash" artifact: a NUT-18 Cashu payment request that
 * locks any payment to the wallet's primary (seed-derived) P2PK key and routes the
 * proofs back over Nostr. Anyone who pays it sends ecash that only this wallet can
 * redeem. Shared by the Locked Ecash settings hub (iOS LockedReceiveRequest).
 */
object LockedReceiveRequest {
    fun build(
        nostrService: NostrService,
        settingsManager: SettingsManager,
        amount: Long? = null,
    ): String? {
        val readiness = CashuRequestNostrReadiness.current(nostrService, settingsManager)
        if (readiness !is CashuRequestNostrReadiness.Ready) return null
        val primary = settingsManager.primaryP2PKKeyInfo() ?: return null
        return runCatching {
            PaymentRequestBuilder.build(
                id = com.cashu.me.Models.CashuRequest.newId(),
                amount = amount,
                unit = "sat",
                mints = emptyList(),
                description = null,
                nostrPubkeyHex = readiness.publicKeyHex,
                relays = readiness.relays,
                p2pkPubkeyHex = primary.publicKey,
            )
        }.getOrNull()
    }
}

private sealed interface Nut18Key {
    data class Text(val value: String) : Nut18Key
}

private sealed interface Nut18Value {
    data class Text(val value: String) : Nut18Value
    data class UInt(val value: Long) : Nut18Value
    data class Bool(val value: Boolean) : Nut18Value
    data class Array(val values: List<Nut18Value>) : Nut18Value
    data class Map(val values: List<Pair<Nut18Key, Nut18Value>>) : Nut18Value
    data object Null : Nut18Value
}

private fun Nut18Value?.orNull(): Nut18Value = this ?: Nut18Value.Null

private object Nut18Cbor {
    fun encode(value: Nut18Value): ByteArray {
        val output = mutableListOf<Byte>()
        encodeInto(value, output)
        return output.toByteArray()
    }

    private fun encodeInto(value: Nut18Value, output: MutableList<Byte>) {
        when (value) {
            is Nut18Value.Text -> {
                val bytes = value.value.toByteArray(Charsets.UTF_8)
                writeHeader(majorType = 3, length = bytes.size.toLong(), output)
                output += bytes.toList()
            }
            is Nut18Value.UInt -> writeHeader(majorType = 0, length = value.value, output)
            is Nut18Value.Bool -> output += if (value.value) 0xF5.toByte() else 0xF4.toByte()
            Nut18Value.Null -> output += 0xF6.toByte()
            is Nut18Value.Array -> {
                writeHeader(majorType = 4, length = value.values.size.toLong(), output)
                value.values.forEach { encodeInto(it, output) }
            }
            is Nut18Value.Map -> {
                writeHeader(majorType = 5, length = value.values.size.toLong(), output)
                value.values.forEach { (key, nestedValue) ->
                    when (key) {
                        is Nut18Key.Text -> encodeInto(Nut18Value.Text(key.value), output)
                    }
                    encodeInto(nestedValue, output)
                }
            }
        }
    }

    private fun writeHeader(majorType: Int, length: Long, output: MutableList<Byte>) {
        require(length >= 0) { "CBOR length cannot be negative." }
        val major = majorType shl 5
        when {
            length < 24 -> output += (major or length.toInt()).toByte()
            length < 0x100 -> {
                output += (major or 24).toByte()
                output += length.toByte()
            }
            length < 0x10000 -> {
                output += (major or 25).toByte()
                output += ((length shr 8) and 0xFF).toByte()
                output += (length and 0xFF).toByte()
            }
            length < 0x1_0000_0000L -> {
                output += (major or 26).toByte()
                for (shift in 24 downTo 0 step 8) output += ((length shr shift) and 0xFF).toByte()
            }
            else -> {
                output += (major or 27).toByte()
                for (shift in 56 downTo 0 step 8) output += ((length shr shift) and 0xFF).toByte()
            }
        }
    }
}
