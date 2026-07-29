package com.cashu.me.ui.journeys

import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.cashu.me.test.UiFailureArtifactsRule
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FakeWalletGateway
import com.cashu.me.test.fixtures.FixtureMode
import com.cashu.me.test.fixtures.LaunchedFixture
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Small real-CDK boundary check. Required CI enables it after starting the
 * local Nutshell mint; it never points at public financial infrastructure.
 */
@RunWith(AndroidJUnit4::class)
class LiveLocalMintMainActivityJourneyTest {
    @get:Rule(order = 0)
    val compose = createEmptyComposeRule()

    @get:Rule(order = 1)
    val failureArtifacts = UiFailureArtifactsRule(compose) { launched?.close() }

    private val robot by lazy { WalletJourneyRobot(compose) }
    private var launched: LaunchedFixture? = null

    @Test
    fun addLocalNutshellMintThroughProductionUi() {
        val arguments = InstrumentationRegistry.getArguments()
        assumeTrue(
            "Enable with cashu.liveUiLocalMintEnabled=true after starting the local mint.",
            arguments.getString("cashu.liveUiLocalMintEnabled") == "true",
        )
        val mintUrl = arguments.getString("cashu.nutshellMintUrl")
            ?.trim()
            ?.trimEnd('/')
            .orEmpty()
            .ifBlank { FakeWalletGateway.TestMintUrl }
        launched = AppTestFixture.launch(FixtureMode.LiveSeededWithoutMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapText("Mints")
            .tapText("Add mint")
            .awaitTag(UiTestTags.AddMintSheet)
            .typeIntoTag(UiTestTags.AddMintUrl, mintUrl)
            .tapTag(UiTestTags.AddMintSubmit)
            .awaitTag(UiTestTags.mintRow(mintUrl), timeoutMillis = 20_000)
    }
}
