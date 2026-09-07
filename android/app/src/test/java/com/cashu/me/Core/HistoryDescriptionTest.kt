package com.cashu.me.Core

import com.cashu.me.Models.CashuRequest
import com.cashu.me.Models.CashuRequestPayment
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.Models.restoringDescription
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HistoryDescriptionTest {
    private val offer = "lno1pg95xmmxvejk2g8sn7xtz93pqfumuen7l8wthtz45p3ftn58pvrs9xlumvkuu2xet8egzkcklqtes"
    private val description = "Coffee 🌱"
    private val request = CashuRequest(
        id = "request", encoded = offer, quoteId = "quote", quoteKind = "bolt12",
        mints = listOf("https://mint.example"),
    )
    private fun payment(id: String = "payment", type: TransactionType = TransactionType.Incoming) = WalletTransaction(
        id = id, amount = 21, type = type, kind = TransactionKind.Lightning,
        dateEpochMillis = 1, status = TransactionStatus.Completed, quoteId = "quote",
        mintUrl = "https://mint.example/",
    )

    @Test fun paidReusableRequestAndEveryReceiptKeepDescriptionAfterReload() {
        val paid = request.copy(receivedPayments = listOf(
            CashuRequestPayment("first", 21, 1), CashuRequestPayment("second", 42, 2),
        ))
        val reloaded = Json.decodeFromString<CashuRequest>(Json.encodeToString(paid))
        assertEquals(description, reloaded.displayDescription)
        for (id in listOf("first", "second")) {
            val receipt = payment(id).restoringDescription(listOf(reloaded))
            val restored = Json.decodeFromString<WalletTransaction>(Json.encodeToString(receipt))
            assertEquals(description, restored.memo)
            assertEquals(description, TransactionDisplay.detailFields(restored).single { it.label == "Memo" }.value)
        }
    }

    @Test fun outgoingInvoiceRecoversDescriptionWithoutLocalRequest() {
        val receipt = payment(type = TransactionType.Outgoing).copy(invoice = offer)
            .restoringDescription(emptyList())
        assertEquals(description, receipt.memo)
        assertEquals(description, receipt.copy(status = TransactionStatus.Pending).displayDescription)
    }

    @Test fun quoteLinkDoesNotCopyMemoFromAnotherMintUnitOrDirection() {
        for (receipt in listOf(payment().copy(mintUrl = "https://other.example"),
            payment().copy(unit = "usd"), payment(type = TransactionType.Outgoing))) {
            assertNull(receipt.restoringDescription(listOf(request)).memo)
        }
    }

    @Test fun localMemoTakesPrecedenceAndEmptyDescriptionsStayHidden() {
        assertEquals("Personal memo", payment().copy(memo = "Personal memo", invoice = offer).displayDescription)
        assertNull(payment().copy(memo = " \n ").displayDescription)
        assertNull(request.copy(encoded = "invalid", memo = " ").displayDescription)
    }

    @Test fun hashedDescriptionUsesTruncatedCopyableRowWithoutChangingStoredText() {
        val hash = "0123456789abcdef".repeat(4)
        for (type in listOf(TransactionType.Incoming, TransactionType.Outgoing)) {
            val receipt = payment(type = type).copy(memo = "Hash: $hash", preimage = "proof")
            assertEquals(hash, receipt.descriptionHash)
            assertEquals(receipt.memo, receipt.displayDescription)
            val fields = TransactionDisplay.detailFields(receipt)
            assertEquals(listOf("Status", "Date", "Mint", "Hash", "Payment Proof"), fields.map { it.label })
            assertEquals(TransactionDetailField("Hash", "01234567…abcdef", hash), fields.single { it.label == "Hash" })
            assertEquals(hash.uppercase(), receipt.copy(memo = " \nHash:\n${hash.uppercase()} \n").descriptionHash)
        }
    }

    @Test fun ordinaryDescriptionsAreNotMistakenForHashReferences() {
        val hash = "a".repeat(64)
        for (memo in listOf("Hash: breakfast", "Hash: $hash extra", "Hash: ${hash.dropLast(1)}",
            "Hash: ${"g".repeat(64)}", hash, "Personal memo")) {
            val receipt = payment().copy(memo = memo)
            assertNull(receipt.descriptionHash)
            assertEquals(memo, TransactionDisplay.detailFields(receipt).single { it.label == "Memo" }.value)
        }
        assertNull(payment().copy(kind = TransactionKind.Ecash, memo = "Hash: $hash").descriptionHash)
    }

    @Test fun cashuRequestDescriptionSurvivesClaimedReceiptWithoutInvoice() {
        val encoded = PaymentRequestBuilder.build(id = "cashu", amount = 21, unit = "sat",
            mints = listOf("https://mint.example"), description = description,
            nostrPubkeyHex = "1".repeat(64), relays = emptyList())
        val cashu = CashuRequest(id = "cashu", encoded = encoded,
            receivedPayments = listOf(CashuRequestPayment("payment", 21, 1)))
        assertEquals(description, cashu.displayDescription)
        assertEquals(description, payment().copy(kind = TransactionKind.Ecash, quoteId = null)
            .restoringDescription(listOf(cashu)).memo)
    }
}
