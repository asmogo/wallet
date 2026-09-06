package com.cashu.me.ui.journeys

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.test.UiFailureArtifactsRule
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FixtureMode
import com.cashu.me.test.fixtures.LaunchedFixture
import com.cashu.me.ui.testing.UiTestTags
import org.cashudevkit.decodeInvoice
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in, unfunded live-mint check. Creates offers only; never pays or mints tokens. */
@RunWith(AndroidJUnit4::class)
class LiveBolt12DescriptionJourneyTest {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { launched?.close() }
    private val robot by lazy { WalletJourneyRobot(compose) }
    private var launched: LaunchedFixture? = null

    @Test
    fun descriptionsAreEncodedAndSurviveReuseAndClearing() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("cashu.liveBolt12Descriptions") == "true")
        val mintURL = requireNotNull(args.getString("cashu.nutshellMintUrl"))
        launched = AppTestFixture.launch(FixtureMode.LiveSeededWithoutMint)
        robot.awaitTag(UiTestTags.WalletScreen).tapText("Mints").tapText("Add mint")
            .typeIntoTag(UiTestTags.AddMintUrl, mintURL).pressSystemBack()
            .tapTag(UiTestTags.AddMintSubmit)
            .awaitTag(UiTestTags.mintRow(mintURL.trimEnd('/')), 30_000)
        val mint = launched!!.container.walletManager.state.value.activeMint!!
        assertTrue(mint.supportedMintMethods.orEmpty().contains(PaymentMethodKind.Bolt12))
        assertTrue("Live mint must advertise description support", mint.supportsBolt12MintDescription)
        robot.tapText("Wallet")
        openOffer()
        val plain = copiedOffer()
        val defaultDescription = decodeInvoice(plain).description
        assertNull(decodeInvoice(plain).amountMsat)

        val description = "Coffee tips Thank you ☕"
        editDescription("  Coffee tips\nThank you ☕  ")
        val described = copiedOffer()
        assertNotEquals(plain, described)
        assertEquals(description, decodeInvoice(described).description)
        assertNull(decodeInvoice(described).amountMsat)
        robot.pressSystemBack()
        openOffer()
        assertEquals("Reopening must reuse the described offer", described, copiedOffer())

        editDescription("Updated coffee note")
        val edited = copiedOffer()
        assertNotEquals(described, edited)
        assertEquals("Updated coffee note", decodeInvoice(edited).description)

        editDescription("   ")
        val cleared = copiedOffer()
        assertEquals("Clearing should reuse the original plain offer", plain, cleared)
        assertEquals(defaultDescription, decodeInvoice(cleared).description)
        robot.pressSystemBack()
        openOffer()
        assertEquals("Clearing must survive reopening", cleared, copiedOffer())

        robot.tapText("Amount").tapDescription("2").tapDescription("1").tapText("Done")
        compose.waitUntil(30_000) { launched!!.container.cashuRequestStore.state.value.currentRequest?.amount == 21L }
        assertEquals(21_000uL, decodeInvoice(copiedOffer()).amountMsat)
        editDescription("Fixed amount coffee")
        val fixed = decodeInvoice(copiedOffer())
        assertEquals("Fixed amount coffee", fixed.description)
        assertEquals("Editing must preserve the fixed amount", 21_000uL, fixed.amountMsat)
        editDescription("   ")
        assertEquals(21_000uL, decodeInvoice(copiedOffer()).amountMsat)
        assertEquals(defaultDescription, decodeInvoice(copiedOffer()).description)
    }

    private fun openOffer() {
        robot.awaitTag(UiTestTags.WalletScreen).tapTag(UiTestTags.WalletReceive)
            .tapText("Bitcoin")
            .tapDescription("Receive method: Lightning invoice, One-time, instant")
            .tapText("Reusable invoice")
            .awaitText("Description", timeoutMillis = 30_000)
    }

    private fun editDescription(value: String) {
        compose.onNodeWithText("Description", useUnmergedTree = true).performScrollTo()
        robot.tapText("Description").replaceTextInTag("reusable-description-field", value)
            .tapTag("reusable-description-save")
            .assertTagDoesNotExist("reusable-description-field")
        // A remint keeps the old QR visible until its replacement is ready.
        robot.awaitText(value.trim().replace("\n", " ").ifEmpty { "None" }, timeoutMillis = 30_000)
    }

    private fun copiedOffer(): String {
        robot.tapText("Copy invoice")
        var copied = ""
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            copied = clipboard.primaryClip?.getItemAt(0)?.text.toString()
        }
        assertTrue("Copy must return a BOLT12 offer", copied.startsWith("lno1"))
        return copied
    }
}
