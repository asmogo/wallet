package com.cashu.me.Core

import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TransactionDisplayTest {
    @Test
    fun outgoingLightningTransactionUsesPaymentLabels() {
        val paymentProof = "0123456789abcdef0123456789abcdef"
        val transaction = transaction(
            kind = TransactionKind.Lightning,
            type = TransactionType.Outgoing,
            invoice = "lnbc1test",
            preimage = paymentProof,
            fee = 2,
        )

        assertEquals("Lightning paid", TransactionDisplay.title(transaction))
        assertEquals("Paid", TransactionDisplay.statusText(transaction))
        assertEquals("lnbc1test", TransactionDisplay.qrContent(transaction))

        // Detail canon: monochrome Status row first, Date second, Fee when > 0.
        // Payment proof is retained as a useful receipt detail.
        val fields = TransactionDisplay.detailFields(transaction)
        assertEquals("Status", fields.first().label)
        assertEquals("Date", fields[1].label)
        assertTrue(fields.any { it.label == "Fee" && it.value == "2 sat" })
        assertTrue(
            fields.any {
                it.label == "Payment Proof" &&
                    it.value == "01234567…abcdef" &&
                    it.copyValue == paymentProof
            },
        )
    }

    @Test
    fun incomingEcashHistoryDisplaysSettledFee() {
        // Incoming CDK rows carry the fee recorded by settlement. History must
        // render that value directly rather than any earlier receive preview.
        val transaction = transaction(
            kind = TransactionKind.Ecash,
            type = TransactionType.Incoming,
            fee = 7,
        )

        val fields = TransactionDisplay.detailFields(transaction)

        assertTrue(fields.any { it.label == "Fee" && it.value == "7 sat" })
        assertTrue(fields.none { it.label == "Fee" && it.value == "3 sat" })
    }

    @Test
    fun unpaidInvoiceTitlesAsInvoiceUntilPaid() {
        val unpaid = transaction(
            kind = TransactionKind.Lightning,
            type = TransactionType.Incoming,
            invoice = "lnbc1test",
        ).copy(status = TransactionStatus.Pending, isUnpaidInvoice = true)

        assertEquals("Lightning invoice", TransactionDisplay.title(unpaid))
        assertEquals("Lightning received", TransactionDisplay.title(unpaid.copy(isUnpaidInvoice = false)))
    }

    @Test
    fun expiredInvoiceRetiresQrAndReadsExpired() {
        val expired = transaction(
            kind = TransactionKind.Lightning,
            type = TransactionType.Incoming,
            invoice = "lnbc1test",
        ).copy(status = TransactionStatus.Expired, isUnpaidInvoice = true)

        assertEquals("Lightning invoice", TransactionDisplay.title(expired))
        assertEquals("Expired", TransactionDisplay.statusText(expired))
        assertTrue(!TransactionDisplay.showsQr(expired))
        assertEquals(null, TransactionDisplay.copyableContent(expired))
    }

    @Test
    fun settledArtifactsAreNotScannableButEcashKeepsCopyReceipt() {
        val settledEcash = transaction(
            kind = TransactionKind.Ecash,
            type = TransactionType.Outgoing,
            token = "cashu-token",
        )
        assertTrue(!TransactionDisplay.showsQr(settledEcash))
        assertEquals("cashu-token", TransactionDisplay.copyableContent(settledEcash))

        val pendingEcash = settledEcash.copy(status = TransactionStatus.Pending)
        assertTrue(TransactionDisplay.showsQr(pendingEcash))

        val pendingIncomingEcash = pendingEcash.copy(type = TransactionType.Incoming)
        assertTrue(!TransactionDisplay.showsQr(pendingIncomingEcash))
        assertEquals(null, TransactionDisplay.copyableContent(pendingIncomingEcash))

        val reusableOffer = transaction(
            kind = TransactionKind.Lightning,
            type = TransactionType.Incoming,
            invoice = "lno1offer",
        )
        assertTrue(TransactionDisplay.showsQr(reusableOffer))
    }

    @Test
    fun confirmedOnchainReceiveRetiresQrAndKeepsAddressInDetails() {
        val pending = transaction(
            kind = TransactionKind.Onchain,
            type = TransactionType.Incoming,
            invoice = "bc1qreceived",
        ).copy(status = TransactionStatus.Pending)
        assertTrue(TransactionDisplay.showsQr(pending))
        assertEquals("bc1qreceived", TransactionDisplay.copyableContent(pending))
        assertEquals("Bitcoin address", TransactionDisplay.qrLabel(pending))

        val received = pending.copy(
            status = TransactionStatus.Completed,
            preimage = "txid",
        )
        assertTrue(!TransactionDisplay.showsQr(received))
        assertEquals(null, TransactionDisplay.copyableContent(received))
        val fields = TransactionDisplay.detailFields(received)
        assertTrue(fields.any { it.label == "Address" && it.copyValue == "bc1qreceived" })
        assertTrue(fields.any { it.label == "Transaction ID" && it.copyValue == "txid" })
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

        assertEquals("Bitcoin sent", TransactionDisplay.title(transaction))
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

    @Test
    fun memoAppearsInHistoryDetailsOnlyWhenPresent() {
        val withMemo = transaction(
            kind = TransactionKind.Ecash,
            type = TransactionType.Incoming,
            memo = "Coffee from Alice",
        )
        val withoutMemo = withMemo.copy(memo = null)

        assertTrue(
            TransactionDisplay.detailFields(withMemo)
                .any { it.label == "Memo" && it.value == "Coffee from Alice" },
        )
        assertTrue(TransactionDisplay.detailFields(withoutMemo).none { it.label == "Memo" })
    }

    @Test
    fun paymentCodesFollowDirectionAndLifecycleForEveryRail() {
        TransactionKind.entries.forEach { kind ->
            TransactionType.entries.forEach { direction ->
                TransactionStatus.entries.forEach { status ->
                    val tx = transaction(kind = kind, type = direction,
                        token = if (kind == TransactionKind.Ecash) "cashu-token" else null,
                        invoice = if (kind == TransactionKind.Ecash) null else "one-shot-request",
                    ).copy(status = status)
                    val expected = status == TransactionStatus.Pending &&
                        if (kind == TransactionKind.Ecash) direction == TransactionType.Outgoing
                        else direction == TransactionType.Incoming
                    assertEquals("$kind $direction $status", expected, TransactionDisplay.showsQr(tx))
                }
            }
        }
    }

    @Test
    fun failedAndOutgoingReusableOfferPaymentsDoNotExposeCodes() {
        val offer = transaction(kind = TransactionKind.Lightning, type = TransactionType.Incoming,
            invoice = "LNO1offer")
        assertTrue(TransactionDisplay.showsQr(offer))
        assertTrue(!TransactionDisplay.showsQr(offer.copy(status = TransactionStatus.Failed)))
        assertTrue(!TransactionDisplay.showsQr(offer.copy(type = TransactionType.Outgoing,
            status = TransactionStatus.Pending)))
    }

    private fun transaction(
        kind: TransactionKind,
        type: TransactionType,
        token: String? = null,
        invoice: String? = null,
        preimage: String? = null,
        fee: Long = 0,
        memo: String? = null,
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
        memo = memo,
    )
}
