package com.cashu.me.Core

import com.cashu.me.Models.CashuRequest
import org.junit.Assert.assertEquals
import org.junit.Test

class CashuRequestCreationTest {
    @Test
    fun newRequestIsUnrestrictedByDefault() {
        val request = store().createNostrCashuRequest(
            id = "unrestricted",
            nostrPubkeyHex = NostrService.publicKeyHex(PRIVATE_KEY_HEX),
            relays = listOf("wss://relay.example"),
        )

        assertEquals(emptyList<String>(), request.mints)
        assertEquals(
            emptyList<String>(),
            PaymentRequestDecoder.cashuPaymentRequestSummary(request.encoded)?.mints,
        )
    }

    @Test
    fun newRequestUsesExplicitMintRestriction() {
        val request = store().createNostrCashuRequest(
            id = "restricted",
            selectedMintUrl = "https://mint.example",
            nostrPubkeyHex = NostrService.publicKeyHex(PRIVATE_KEY_HEX),
            relays = listOf("wss://relay.example"),
        )

        assertEquals(listOf("https://mint.example"), request.mints)
        assertEquals(
            listOf("https://mint.example"),
            PaymentRequestDecoder.cashuPaymentRequestSummary(request.encoded)?.mints,
        )
    }

    private fun store() = CashuRequestStore(MemoryPersistence())

    private class MemoryPersistence : CashuRequestPersistence {
        private var requests: List<CashuRequest> = emptyList()
        override var currentCashuRequestId: String? = null

        override fun loadCashuRequests(): List<CashuRequest> = requests

        override fun saveCashuRequests(requests: List<CashuRequest>) {
            this.requests = requests
        }
    }

    private companion object {
        private const val PRIVATE_KEY_HEX =
            "0000000000000000000000000000000000000000000000000000000000000001"
    }
}
