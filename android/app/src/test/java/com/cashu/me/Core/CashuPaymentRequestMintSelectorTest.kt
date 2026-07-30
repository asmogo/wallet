package com.cashu.me.Core

import com.cashu.me.Models.MintInfo
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

class CashuPaymentRequestMintSelectorTest {
    @Test
    fun selectedCompatibleMintWinsWhenAffordable() {
        val request = request(mints = listOf("https://mint.example.com/"))
        val mint = mint("https://mint.example.com", balance = 100)

        assertEquals(
            mint,
            selectMintForCashuPaymentRequest(
                request = request,
                mints = listOf(mint),
                selectedMintUrl = "https://mint.example.com/",
                activeMintUrl = null,
                amountSats = 25,
            ),
        )
    }

    @Test
    fun activeCompatibleMintWinsBeforeBalanceFallback() {
        val active = mint("https://active.example.com", balance = 30)
        val largest = mint("https://largest.example.com", balance = 100)
        val request = request(mints = listOf(active.url, largest.url))

        assertEquals(
            active,
            selectMintForCashuPaymentRequest(
                request = request,
                mints = listOf(largest, active),
                selectedMintUrl = "https://other.example.com",
                activeMintUrl = active.url,
                amountSats = 20,
            ),
        )
    }

    @Test
    fun fallsBackToLargestAffordableCompatibleMint() {
        val smaller = mint("https://smaller.example.com", balance = 50)
        val larger = mint("https://larger.example.com", balance = 80)
        val request = request(mints = listOf(smaller.url, larger.url))

        assertEquals(
            larger,
            selectMintForCashuPaymentRequest(
                request = request,
                mints = listOf(smaller, larger),
                selectedMintUrl = null,
                activeMintUrl = null,
                amountSats = 20,
            ),
        )
    }

    @Test
    fun returnsNullWhenNoCompatibleMintCanAffordAmount() {
        val request = request(mints = listOf("https://mint.example.com"))

        assertNull(
            selectMintForCashuPaymentRequest(
                request = request,
                mints = listOf(mint("https://mint.example.com", balance = 10)),
                selectedMintUrl = null,
                activeMintUrl = null,
                amountSats = 20,
            ),
        )
    }

    @Test
    fun emptyRequestMintListAcceptsAnyTrackedMint() {
        val active = mint("https://active.example.com", balance = 10)
        val request = request(mints = emptyList())

        assertEquals(
            active,
            selectMintForCashuPaymentRequest(
                request = request,
                mints = listOf(active),
                selectedMintUrl = null,
                activeMintUrl = active.url,
                amountSats = null,
            ),
        )
    }

    @Test
    fun routeRejectsUnsupportedUnits() {
        val route = routeForCashuPaymentRequest(
            rawRequest = "creqa-test",
            request = request(mints = emptyList()).copy(unit = "eur", amount = 10),
            mints = listOf(mint("https://mint.example.com", balance = 100)),
            selectedMintUrl = null,
            activeMintUrl = null,
            amountSats = null,
        )

        assertEquals(CashuPaymentRequestRoute.UnsupportedUnit("eur"), route)
    }

    @Test
    fun routeRequiresAmountForAmountlessRequests() {
        val route = routeForCashuPaymentRequest(
            rawRequest = "creqa-test",
            request = request(mints = emptyList()),
            mints = listOf(mint("https://mint.example.com", balance = 100)),
            selectedMintUrl = null,
            activeMintUrl = null,
            amountSats = null,
        )

        assertEquals(CashuPaymentRequestRoute.MissingAmount, route)
    }

    @Test
    fun routePaysWithAffordableCompatibleMint() {
        val mint = mint("https://mint.example.com", balance = 100)
        val route = routeForCashuPaymentRequest(
            rawRequest = "creqa-test",
            request = request(mints = listOf(mint.url)).copy(amount = 25),
            mints = listOf(mint),
            selectedMintUrl = null,
            activeMintUrl = mint.url,
            amountSats = null,
        )

        assertEquals(CashuPaymentRequestRoute.PayWithEcash(mint, 25), route)
    }

    @Test
    fun routeOffersAddMintWhenRequestedMintIsNotTracked() {
        val route = routeForCashuPaymentRequest(
            rawRequest = "creqa-test",
            request = request(mints = listOf("https://target.example.com")).copy(amount = 25),
            mints = listOf(mint("https://other.example.com", balance = 100)),
            selectedMintUrl = null,
            activeMintUrl = null,
            amountSats = null,
        )

        assertEquals(
            CashuPaymentRequestRoute.AddMintToPay(listOf("https://target.example.com"), 25),
            route,
        )
    }

    @Test
    fun routeRequestsTopUpWhenCompatibleMintCannotAffordAmount() {
        val mint = mint("https://target.example.com", balance = 10)
        val route = routeForCashuPaymentRequest(
            rawRequest = "creqa-test",
            request = request(mints = listOf(mint.url)).copy(amount = 25),
            mints = listOf(mint),
            selectedMintUrl = null,
            activeMintUrl = mint.url,
            amountSats = null,
        )

        assertEquals(CashuPaymentRequestRoute.NeedsExternalTopUp(mint.url, 25), route)
    }

    @Test
    fun routeUsesLightningFallbackBeforeAddMint() {
        val route = routeForCashuPaymentRequest(
            rawRequest = "bitcoin:bc1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9e75rs?lightning=lnbc10u1ptest&creq=creqa-test",
            request = request(mints = listOf("https://target.example.com")).copy(amount = 25),
            mints = listOf(mint("https://other.example.com", balance = 100)),
            selectedMintUrl = null,
            activeMintUrl = null,
            amountSats = null,
        )

        assertTrue(route is CashuPaymentRequestRoute.PayBolt11Fallback)
    }

    @Test
    fun paymentWarningCopyUsesPlatformNeutralProductLanguage() {
        val unsupportedUnit = stringResource("send_cashu_request_unsupported_unit")
        val lightningFallback = stringResource("send_cashu_request_lightning_fallback")

        assertEquals(
            "Cashu Wallet can only pay sat-denominated Cashu Requests.",
            unsupportedUnit,
        )
        assertEquals(
            "The requested Cashu mint is unavailable. " +
                "Cashu Wallet can pay this request using Lightning instead.",
            lightningFallback,
        )
        listOf(unsupportedUnit, lightningFallback).forEach { message ->
            assertFalse(Regex("""\b(?:android|ios)\b""", RegexOption.IGNORE_CASE).containsMatchIn(message))
        }
    }

    private fun stringResource(name: String): String {
        val strings = sourceFile(
            "src/main/res/values/strings.xml",
            "app/src/main/res/values/strings.xml",
        )
        val resources = DocumentBuilderFactory.newInstance()
            .newDocumentBuilder()
            .parse(strings)
            .documentElement
            .getElementsByTagName("string")
        return (0 until resources.length)
            .map { resources.item(it) as Element }
            .first { it.getAttribute("name") == name }
            .textContent
    }

    private fun sourceFile(vararg candidates: String): File {
        val roots = generateSequence(File("").absoluteFile) { it.parentFile }
        return roots
            .flatMap { root -> candidates.asSequence().map { File(root, it) } }
            .firstOrNull { it.exists() }
            ?: error("Missing test fixture: ${candidates.joinToString()}")
    }

    private fun request(mints: List<String>) = CashuPaymentRequestSummary(
        encoded = "creqa-test",
        amount = null,
        unit = "sat",
        description = null,
        mints = mints,
    )

    private fun mint(url: String, balance: Long) = MintInfo(
        url = url,
        name = url.substringAfter("//").substringBefore("."),
        balance = balance,
    )
}
