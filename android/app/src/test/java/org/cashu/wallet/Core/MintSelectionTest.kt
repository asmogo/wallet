package org.cashu.wallet.Core

import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.PaymentMethodKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MintSelectionTest {
    @Test
    fun recommendedSendMintPrefersActiveWhenAffordable() {
        val active = mint("https://active.example", balance = 50)
        val larger = mint("https://larger.example", balance = 100)

        assertEquals(active, recommendedSendMint(listOf(larger, active), active.url, minimumAmount = 25))
    }

    @Test
    fun recommendedSendMintFallsBackToLargestAffordableMint() {
        val active = mint("https://active.example", balance = 10)
        val larger = mint("https://larger.example", balance = 100)
        val smaller = mint("https://smaller.example", balance = 50)

        assertEquals(larger, recommendedSendMint(listOf(active, smaller, larger), active.url, minimumAmount = 25))
    }

    @Test
    fun meltSelectionFiltersByPaymentMethodAndKeepsActiveWhenAffordable() {
        val active = mint("https://active.example", balance = 40, meltMethods = listOf(PaymentMethodKind.Onchain))
        val lightningOnly = mint("https://ln.example", balance = 100, meltMethods = listOf(PaymentMethodKind.Bolt11))

        assertEquals(
            active,
            selectMintForMeltPayment(
                mints = listOf(lightningOnly, active),
                selectedMintUrl = null,
                activeMintUrl = active.url,
                paymentMethod = PaymentMethodKind.Onchain,
                minimumAmount = 25,
            ),
        )
    }

    @Test
    fun meltSelectionReturnsNullWithoutCompatibleMint() {
        assertNull(
            selectMintForMeltPayment(
                mints = listOf(mint("https://ln.example", balance = 100, meltMethods = listOf(PaymentMethodKind.Bolt11))),
                selectedMintUrl = null,
                activeMintUrl = null,
                paymentMethod = PaymentMethodKind.Onchain,
                minimumAmount = 25,
            ),
        )
    }

    @Test
    fun rankedMintsPutSelectedThenAffordableThenBalanceAndName() {
        val selected = mint("https://selected.example", name = "Zed", balance = 1)
        val beta = mint("https://beta.example", name = "Beta", balance = 50)
        val alpha = mint("https://alpha.example", name = "Alpha", balance = 50)
        val poor = mint("https://poor.example", name = "Poor", balance = 5)

        assertEquals(
            listOf(selected, alpha, beta, poor),
            rankedMintsForDisplay(
                mints = listOf(poor, beta, selected, alpha),
                selectedMintUrl = selected.url,
                minimumAmount = 25,
            ),
        )
    }

    private fun mint(
        url: String,
        name: String = url.substringAfter("//").substringBefore("."),
        balance: Long,
        meltMethods: List<PaymentMethodKind> = listOf(PaymentMethodKind.Bolt11, PaymentMethodKind.Bolt12, PaymentMethodKind.Onchain),
    ) = MintInfo(
        url = url,
        name = name,
        balance = balance,
        supportedMeltMethods = meltMethods,
    )
}
