package org.cashu.wallet.Core

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.TokenInfo
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ModelsParityTest {
    @Test
    fun paymentMethodSymbolsMatchSwiftModel() {
        assertEquals("\u26A1", PaymentMethodKind.Bolt11.symbol)
        assertEquals("\uD83D\uDD17", PaymentMethodKind.Bolt12.symbol)
        assertEquals("\u20BF", PaymentMethodKind.Onchain.symbol)
    }

    @Test
    fun walletTransactionCarriesCashuRequestIdAndDefaultsToNull() {
        val transaction = WalletTransaction(
            id = "tx1",
            amount = 21,
            type = TransactionType.Incoming,
            kind = TransactionKind.Ecash,
            dateEpochMillis = 1_000,
            status = TransactionStatus.Completed,
            cashuRequestId = "request1",
        )

        val encoded = Json.encodeToString(transaction)
        assertEquals("request1", Json.decodeFromString<WalletTransaction>(encoded).cashuRequestId)

        val legacy = """
            {
              "id":"tx2",
              "amount":21,
              "type":"Incoming",
              "kind":"Ecash",
              "dateEpochMillis":1000,
              "status":"Completed"
            }
        """.trimIndent()
        assertNull(Json.decodeFromString<WalletTransaction>(legacy).cashuRequestId)
    }

    @Test
    fun tokenInfoParseDelegatesToTokenParser() {
        assertNull(TokenInfo.parse("not-a-token"))
    }

    @Test
    fun byteArraySha256MatchesKnownDigest() {
        assertArrayEquals(
            byteArrayOf(
                0xBA.toByte(), 0x78, 0x16, 0xBF.toByte(), 0x8F.toByte(), 0x01, 0xCF.toByte(), 0xEA.toByte(),
                0x41, 0x41, 0x40, 0xDE.toByte(), 0x5D, 0xAE.toByte(), 0x22, 0x23,
                0xB0.toByte(), 0x03, 0x61, 0xA3.toByte(), 0x96.toByte(), 0x17, 0x7A, 0x9C.toByte(),
                0xB4.toByte(), 0x10, 0xFF.toByte(), 0x61, 0xF2.toByte(), 0x00, 0x15, 0xAD.toByte(),
            ),
            "abc".toByteArray().sha256(),
        )
    }
}
