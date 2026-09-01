package com.cashu.me.ui.send

import com.cashu.me.Core.CashuPaymentRequestRoute
import com.cashu.me.Core.cashuRequestTopUpAmount
import com.cashu.me.Core.selectCashuRequestFundingSource
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.PaymentMethodKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SendCashuRequestTopUpTest {
    @Test
    fun acquireThenPayAndLightningFallbackRemainPayable() {
        assertTrue(
            isCashuRequestPayEnabled(
                CashuPaymentRequestRoute.AcquireThenPay(
                    mintUrls = listOf("https://mint.example"),
                    targetMintUrl = "https://mint.example",
                    amountSats = 42,
                    addsNewMint = true,
                ),
            ),
        )
        assertTrue(
            isCashuRequestPayEnabled(
                CashuPaymentRequestRoute.PayBolt11Fallback("lnbc1fallback"),
            ),
        )
    }

    @Test
    fun acquireThenPayRequiresAtLeastOneRequestedMint() {
        assertFalse(
            isCashuRequestPayEnabled(
                CashuPaymentRequestRoute.AcquireThenPay(
                    mintUrls = emptyList(),
                    targetMintUrl = null,
                    amountSats = 42,
                    addsNewMint = false,
                ),
            ),
        )
    }

    @Test
    fun topUpAmountReservesTargetMintInputFees() {
        assertEquals(42, cashuRequestTopUpAmount(42, inputFeePpk = 0))
        assertEquals(43, cashuRequestTopUpAmount(42, inputFeePpk = 1))
        assertEquals(74, cashuRequestTopUpAmount(42, inputFeePpk = 1_000))
    }

    @Test
    fun fundingSourceExcludesTargetAndUnsupportedOrUnderfundedMints() {
        val target = mint("https://target.example", balance = 500)
        val unsupported = mint(
            "https://unsupported.example",
            balance = 400,
            meltMethods = emptyList(),
        )
        val underfunded = mint("https://small.example", balance = 49)
        val sufficient = mint("https://source.example", balance = 100)

        assertEquals(
            sufficient,
            selectCashuRequestFundingSource(
                mints = listOf(target, unsupported, underfunded, sufficient),
                targetMintUrl = "${target.url}/",
                requiredAmountSats = 50,
            ),
        )
    }

    @Test
    fun payButtonExplainsWhetherMintWillBeAddedOrFunded() {
        val add = CashuPaymentRequestRoute.AcquireThenPay(
            mintUrls = listOf("https://target.example"),
            targetMintUrl = "https://target.example",
            amountSats = 42,
            addsNewMint = true,
        )
        val fund = add.copy(addsNewMint = false)
        val choose = add.copy(
            mintUrls = listOf("https://one.example", "https://two.example"),
            targetMintUrl = null,
        )

        assertEquals("Add target.example & pay", cashuRequestPayButtonText(add, "Pay"))
        assertEquals("Fund target.example & pay", cashuRequestPayButtonText(fund, "Pay"))
        assertEquals("Add a mint & pay", cashuRequestPayButtonText(choose, "Pay"))
    }

    private fun mint(
        url: String,
        balance: Long,
        meltMethods: List<PaymentMethodKind>? = null,
    ) = MintInfo(
        url = url,
        name = url.substringAfter("//").substringBefore('.'),
        balance = balance,
        supportedMeltMethods = meltMethods,
    )
}
