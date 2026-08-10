package com.cashu.me.ui.mints

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ConnectMintSheetComposeTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun setFace(
        context: ConnectMintContext,
        existingUrls: Set<String> = emptySet(),
        discoveryAvailable: Boolean = true,
        error: String? = null,
        onAdd: (String) -> Unit = {},
    ) {
        compose.setCashuContent {
            SuggestedMintsFace(
                context = context,
                existingUrls = existingUrls,
                discoveryAvailable = discoveryAvailable,
                error = error,
                enabled = true,
                onAdd = onAdd,
                onAddCustom = {},
                onDiscover = {},
            )
        }
    }

    @Test
    fun sendContextExplainsWhyTheFlowStalled() {
        setFace(ConnectMintContext.Send)

        compose.onNodeWithText("Add a mint first").assertIsDisplayed()
        compose.onNodeWithText(
            "Mints issue the ecash you send and receive. Add one to get started.",
        ).assertIsDisplayed()
    }

    @Test
    fun addMintContextDropsTheRedundantHeadline() {
        // The CTA that opened this already said "Add mint", and so does the sheet
        // title — a third restatement is what made the header read as three
        // stacked titles.
        setFace(ConnectMintContext.AddMint)

        compose.onNodeWithText("Add a mint first").assertDoesNotExist()
        compose.onNodeWithText(
            "Mints issue the ecash you send and receive. Add one to get started.",
        ).assertIsDisplayed()
    }

    @Test
    fun curatedListShowsEveryMintTheWalletDoesNotHave() {
        setFace(ConnectMintContext.AddMint)

        RecommendedMints.forEach { mint ->
            compose.onNodeWithText(mint.name).assertIsDisplayed()
        }
    }

    @Test
    fun alreadyAddedMintsAreFilteredOut() {
        val added = RecommendedMints.first()
        setFace(ConnectMintContext.AddMint, existingUrls = setOf(added.url))

        compose.onNodeWithText(added.name).assertDoesNotExist()
        RecommendedMints.drop(1).forEach { mint ->
            compose.onNodeWithText(mint.name).assertIsDisplayed()
        }
    }

    @Test
    fun tappingASuggestionAddsThatMintUrl() {
        val tapped = mutableListOf<String>()
        val target = RecommendedMints.first()
        setFace(ConnectMintContext.AddMint, onAdd = { tapped += it })

        compose.onNode(hasContentDescription("Add ${target.name}")).performClick()

        assertEquals(listOf(target.url), tapped)
    }

    @Test
    fun discoveryIsOfferedWhenWebsocketsAreOn() {
        setFace(ConnectMintContext.AddMint, discoveryAvailable = true)

        compose.onNodeWithTag(UiTestTags.ConnectMintAddCustom).assertIsDisplayed()
        compose.onNodeWithTag(UiTestTags.ConnectMintDiscover).assertIsDisplayed()
    }

    @Test
    fun discoveryIsHiddenWhenWebsocketsAreOff() {
        // Discovery rides Nostr relays over WebSockets; offering it with the
        // setting off could only lead to a "turn this on" dead end.
        setFace(ConnectMintContext.AddMint, discoveryAvailable = false)

        compose.onNodeWithTag(UiTestTags.ConnectMintAddCustom).assertIsDisplayed()
        compose.onNodeWithTag(UiTestTags.ConnectMintDiscover).assertDoesNotExist()
    }

    @Test
    fun quickAddFailureSurfacesInline() {
        setFace(ConnectMintContext.AddMint, error = "Couldn't reach that mint.")

        compose.onNodeWithText("Couldn't reach that mint.").assertIsDisplayed()
    }
}
