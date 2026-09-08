package com.cashu.me.Core.CDK

import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LightningAddressResolverTest {
    @Test
    fun acceptsAmountMatchedInvoiceWhenLnurlMetadataHashDoesNotMatch() = runBlocking {
        val transport = RecordingTransport(
            LnurlHttpResponse(
                code = 200,
                body = payRequestJson(
                    callback = "https://example.com/lnurl/callback?amount=1&memo=coffee",
                    metadata = """[["text/plain","metadata deliberately unrelated to invoice"]]""",
                ),
            ),
            LnurlHttpResponse(
                code = 200,
                body = """{"pr":"$Bolt11AmountfulCoffeeInvoice"}""",
            ),
        )

        val invoice = resolver(transport, decodedAmountMsat = InvoiceAmountMsat).resolveBolt11Invoice(
            address = "alice@example.com",
            amountMsat = InvoiceAmountMsat,
        )

        assertEquals(Bolt11AmountfulCoffeeInvoice, invoice)
        assertEquals(
            "https://example.com/.well-known/lnurlp/alice",
            transport.requestedUrls[0].toString(),
        )
        val callback = transport.requestedUrls[1]
        assertEquals(listOf(InvoiceAmountMsat.toString()), callback.queryParameterValues("amount"))
        assertEquals("coffee", callback.queryParameter("memo"))
    }

    @Test
    fun rejectsInvoiceWhoseAmountDoesNotMatchRequest() = runBlocking {
        val transport = RecordingTransport(
            LnurlHttpResponse(
                code = 200,
                body = payRequestJson(callback = "https://example.com/lnurl/callback"),
            ),
            LnurlHttpResponse(
                code = 200,
                body = """{"pr":"$Bolt11AmountfulCoffeeInvoice"}""",
            ),
        )

        val error = runCatching {
            resolver(transport, decodedAmountMsat = InvoiceAmountMsat).resolveBolt11Invoice(
                address = "alice@example.com",
                amountMsat = InvoiceAmountMsat - 1,
            )
        }.exceptionOrNull()

        assertTrue(error is LightningAddressResolutionException.Invalid)
        assertTrue(error?.message.orEmpty().contains("amount does not match"))
    }

    @Test
    fun marksMissingLnurlEndpointAsUnavailableForBip353Fallback() = runBlocking {
        val transport = RecordingTransport(LnurlHttpResponse(code = 404, body = "not found"))

        val error = runCatching {
            resolver(transport, decodedAmountMsat = InvoiceAmountMsat).resolveBolt11Invoice(
                address = "alice@example.com",
                amountMsat = InvoiceAmountMsat,
            )
        }.exceptionOrNull()

        assertTrue(error is LightningAddressResolutionException.Unavailable)
    }

    @Test
    fun acceptsDelegatedCallbackAndReplacesEveryAmountParameter() = runBlocking {
        val transport = RecordingTransport(
            LnurlHttpResponse(200, payRequestJson("https://pay.example.net/invoice?amount=1&Amount=2&memo=coffee")),
            LnurlHttpResponse(200, """{"pr":"$Bolt11AmountfulCoffeeInvoice"}"""),
        )
        assertEquals(Bolt11AmountfulCoffeeInvoice, resolver(transport, InvoiceAmountMsat)
            .resolveBolt11Invoice("alice@example.com", InvoiceAmountMsat))
        val callback = transport.requestedUrls.last()
        assertEquals("pay.example.net", callback.host)
        assertEquals(listOf(InvoiceAmountMsat.toString()), callback.queryParameterValues("amount"))
        assertEquals(emptyList<String>(), callback.queryParameterValues("Amount"))
        assertEquals("coffee", callback.queryParameter("memo"))
    }

    @Test
    fun rejectsUnsafeCallbacksBeforeRequestingAnInvoice() = runBlocking {
        listOf(
            "http://pay.example.net/invoice",
            "https://@pay.example.net/invoice",
            "https:///invoice",
            "https://bad host/invoice",
            "https://user:pass@pay.example.net/invoice",
            "https://pay.example.net/invoice#fragment",
            "not a URL",
        ).forEach { callback ->
            val transport = RecordingTransport(LnurlHttpResponse(200, payRequestJson(callback)))
            val error = runCatching {
                resolver(transport, InvoiceAmountMsat).resolveBolt11Invoice("alice@example.com", InvoiceAmountMsat)
            }.exceptionOrNull()
            assertTrue(callback, error is LightningAddressResolutionException.Invalid)
            assertEquals(1, transport.requestedUrls.size)
        }
    }

    @Test
    fun rejectsInvalidAndNonBolt11InvoicesFromDelegatedCallback() = runBlocking {
        listOf<LightningInvoiceDecoder>(
            LightningInvoiceDecoder { throw IllegalArgumentException("bad invoice") },
            LightningInvoiceDecoder { LightningInvoiceMetadata(false, InvoiceAmountMsat.toULong()) },
        ).forEach { decoder ->
            val transport = RecordingTransport(
                LnurlHttpResponse(200, payRequestJson("https://pay.example.net/invoice")),
                LnurlHttpResponse(200, """{"pr":"invalid"}"""),
            )
            val error = runCatching {
                LightningAddressResolver(transport, decoder).resolveBolt11Invoice("alice@example.com", InvoiceAmountMsat)
            }.exceptionOrNull()
            assertTrue(error is LightningAddressResolutionException.Invalid)
        }
    }

    private fun payRequestJson(
        callback: String,
        metadata: String = """[["text/plain","Coffee for Alice"]]""",
    ): String =
        """
        {
          "callback": "$callback",
          "maxSendable": 1000000000,
          "minSendable": 1,
          "metadata": ${jsonString(metadata)},
          "tag": "payRequest"
        }
        """.trimIndent()

    private fun jsonString(value: String): String =
        buildString {
            append('"')
            value.forEach { character ->
                when (character) {
                    '\\' -> append("\\\\")
                    '"' -> append("\\\"")
                    '\n' -> append("\\n")
                    '\r' -> append("\\r")
                    '\t' -> append("\\t")
                    else -> append(character)
                }
            }
            append('"')
        }

    private fun resolver(
        transport: LnurlHttpTransport,
        decodedAmountMsat: Long,
    ): LightningAddressResolver =
        LightningAddressResolver(
            transport = transport,
            invoiceDecoder = LightningInvoiceDecoder {
                LightningInvoiceMetadata(
                    isBolt11 = true,
                    amountMsat = decodedAmountMsat.toULong(),
                )
            },
        )

    private class RecordingTransport(
        vararg responses: LnurlHttpResponse,
    ) : LnurlHttpTransport {
        private val remainingResponses = ArrayDeque(responses.toList())
        val requestedUrls = mutableListOf<HttpUrl>()

        override suspend fun get(url: HttpUrl): LnurlHttpResponse {
            requestedUrls += url
            return remainingResponses.removeFirst()
        }
    }

    private companion object {
        private const val InvoiceAmountMsat = 250_000_000L

        // BOLT #11 example: fixed amount invoice for 2500 micro-bitcoin (250,000 sat).
        private const val Bolt11AmountfulCoffeeInvoice =
            "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh"
    }
}
