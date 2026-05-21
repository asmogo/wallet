package org.cashu.wallet.Core

import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Test

class WalletTransactionMetadataTest {
    @Test
    fun storedMeltMetadataUsesQuoteIdWhenPresent() {
        val transaction = WalletTransaction(
            id = "tx-1",
            amount = 21,
            type = TransactionType.Outgoing,
            kind = TransactionKind.Lightning,
            dateEpochMillis = 1_700_000_000,
            status = TransactionStatus.Completed,
            fee = 5,
            quoteId = "quote-1",
        )

        val enriched = transaction.withStoredMeltMetadata(
            preimages = mapOf("quote-1" to "preimage"),
            meltFees = mapOf("quote-1" to 2),
        )

        assertEquals("preimage", enriched.preimage)
        assertEquals(2, enriched.fee)
    }

    @Test
    fun existingTransactionPaymentProofIsPreserved() {
        val transaction = WalletTransaction(
            id = "quote-1",
            amount = 21,
            type = TransactionType.Outgoing,
            kind = TransactionKind.Lightning,
            dateEpochMillis = 1_700_000_000,
            status = TransactionStatus.Completed,
            preimage = "remote-proof",
            fee = 5,
        )

        val enriched = transaction.withStoredMeltMetadata(
            preimages = mapOf("quote-1" to "stored-proof"),
            meltFees = mapOf("quote-1" to 2),
        )

        assertEquals("remote-proof", enriched.preimage)
        assertEquals(2, enriched.fee)
    }
}
