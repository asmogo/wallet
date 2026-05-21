package org.cashu.wallet.Core

import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TransactionDisplayTest {
    @Test
    fun outgoingLightningTransactionUsesPaymentLabels() {
        val transaction = transaction(
            kind = TransactionKind.Lightning,
            type = TransactionType.Outgoing,
            invoice = "lnbc1test",
            preimage = "proof",
            fee = 2,
        )

        assertEquals("Lightning payment", TransactionDisplay.title(transaction))
        assertEquals("Paid", TransactionDisplay.statusText(transaction))
        assertEquals("lnbc1test", TransactionDisplay.qrContent(transaction))

        val fields = TransactionDisplay.detailFields(transaction)
        assertTrue(fields.any { it.label == "Payment Proof" && it.value == "proof" })
        assertTrue(fields.any { it.label == "Fee" && it.value == "2 sat" })
    }

    @Test
    fun onchainPreimageIsShownAsTransactionId() {
        val transaction = transaction(
            kind = TransactionKind.Onchain,
            type = TransactionType.Outgoing,
            invoice = "bc1qaddress",
            preimage = "txid",
        )

        val fields = TransactionDisplay.detailFields(transaction)

        assertEquals("On-chain payment", TransactionDisplay.title(transaction))
        assertTrue(fields.any { it.label == "Address" && it.value == "bc1qaddress" })
        assertTrue(fields.any { it.label == "Transaction ID" && it.value == "txid" })
    }

    @Test
    fun tokenTakesPrecedenceForQrContent() {
        val transaction = transaction(
            kind = TransactionKind.Ecash,
            type = TransactionType.Outgoing,
            token = "cashu-token",
            invoice = "request",
        )

        assertEquals("cashu-token", TransactionDisplay.qrContent(transaction))
        assertEquals("Ecash token", TransactionDisplay.qrLabel(transaction))
    }

    private fun transaction(
        kind: TransactionKind,
        type: TransactionType,
        token: String? = null,
        invoice: String? = null,
        preimage: String? = null,
        fee: Long = 0,
    ) = WalletTransaction(
        id = "tx",
        amount = 10,
        type = type,
        kind = kind,
        dateEpochMillis = 1_700_000_000,
        status = TransactionStatus.Completed,
        mintUrl = "https://mint.example.com",
        preimage = preimage,
        token = token,
        invoice = invoice,
        fee = fee,
    )
}
