package org.cashu.wallet.Core

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class NIP44AndNIP17Test {
    private val json = Json { encodeDefaults = true }

    @Test
    fun nip44EncryptDecryptRoundTripBetweenTwoKeys() {
        val senderPrivateHex = "1".padStart(64, '0')
        val recipientPrivateHex = "2".padStart(64, '0')
        val senderPrivate = NIP44.hexToBytes(senderPrivateHex)
        val recipientPrivate = NIP44.hexToBytes(recipientPrivateHex)
        val recipientPubkey = NostrService.publicKeyHex(recipientPrivateHex)

        val payload = NIP44.encrypt(
            plaintext = """{"hello":"cashu"}""",
            senderPrivateKey = senderPrivate,
            recipientPubkeyHex = recipientPubkey,
        )

        assertEquals(
            """{"hello":"cashu"}""",
            NIP44.decrypt(
                payload = payload,
                recipientPrivateKey = recipientPrivate,
                senderPubkeyHex = NostrService.publicKeyHex(senderPrivateHex),
            ),
        )
    }

    @Test
    fun nip17UnwrapReturnsInnerRumor() {
        val recipientPrivateHex = "2".padStart(64, '0')
        val senderPrivateHex = "3".padStart(64, '0')
        val ephemeralPrivateHex = "4".padStart(64, '0')
        val recipientPrivate = NIP44.hexToBytes(recipientPrivateHex)
        val senderPrivate = NIP44.hexToBytes(senderPrivateHex)
        val ephemeralPrivate = NIP44.hexToBytes(ephemeralPrivateHex)
        val recipientPubkey = NostrService.publicKeyHex(recipientPrivateHex)
        val senderPubkey = NostrService.publicKeyHex(senderPrivateHex)
        val ephemeralPubkey = NostrService.publicKeyHex(ephemeralPrivateHex)
        val rumorJson = """{"id":"rumor-1","pubkey":"$senderPubkey","created_at":100,"kind":14,"tags":[],"content":"{\"id\":\"request-1\",\"mint\":\"https://mint.example.com\",\"proofs\":[]}"}"""
        val sealContent = NIP44.encrypt(
            plaintext = rumorJson,
            senderPrivateKey = senderPrivate,
            recipientPubkeyHex = recipientPubkey,
        )
        val seal = NostrIncomingEvent(
            id = "seal-1",
            pubkey = senderPubkey,
            createdAt = 101,
            kind = 13,
            tags = emptyList(),
            content = sealContent,
            sig = "seal-signature",
        )
        val giftWrap = NostrIncomingEvent(
            id = "wrap-1",
            pubkey = ephemeralPubkey,
            createdAt = 102,
            kind = 1059,
            tags = listOf(listOf("p", recipientPubkey)),
            content = NIP44.encrypt(
                plaintext = json.encodeToString(seal),
                senderPrivateKey = ephemeralPrivate,
                recipientPubkeyHex = recipientPubkey,
            ),
            sig = "wrap-signature",
        )

        val rumor = NIP17.unwrap(giftWrap, recipientPrivate)

        assertEquals("rumor-1", rumor.id)
        assertEquals(senderPubkey, rumor.pubkey)
        assertEquals(14, rumor.kind)
        assertEquals("""{"id":"request-1","mint":"https://mint.example.com","proofs":[]}""", rumor.content)
    }

    @Test
    fun nip44PaddingMatchesSpecBoundaries() {
        assertEquals(32, NIP44.paddedLength(1))
        assertEquals(32, NIP44.paddedLength(32))
        assertEquals(64, NIP44.paddedLength(33))
        assertEquals(256, NIP44.paddedLength(256))
        assertEquals(320, NIP44.paddedLength(257))
    }
}
