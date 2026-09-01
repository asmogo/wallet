package com.cashu.me.ui.history

import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Test

class TransactionReceiptAmountTest {
    @Test
    fun lightningReceiptUsesHomeFiatPreference() {
        val transaction = WalletTransaction(
            id = "lightning-receive",
            amount = 1,
            type = TransactionType.Incoming,
            kind = TransactionKind.Lightning,
            dateEpochMillis = 0,
            status = TransactionStatus.Completed,
        )

        val display = transactionReceiptAmountDisplay(
            transaction = transaction,
            formatter = AmountFormatter(),
            preferredPrimary = "fiat",
            showFiat = true,
            btcPrice = 20_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
        )

        assertEquals("<$0.01", display.primary)
        assertEquals("1 sat", display.secondary)
        assertEquals(AmountDisplayPrimary.Fiat, display.effectivePrimary)
    }
}
