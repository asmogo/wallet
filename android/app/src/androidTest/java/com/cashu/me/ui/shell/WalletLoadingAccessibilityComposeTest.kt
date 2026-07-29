package com.cashu.me.ui.shell

import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.App.AppContainer
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WalletLoadingAccessibilityComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun startupGateIdentifiesWalletLoadingAsIndeterminateProgress() {
        compose.setContent {
            CashuApp(containerFlow = MutableStateFlow<AppContainer?>(null))
        }

        val loadingNode = compose.onNodeWithContentDescription("Loading wallet…")
            .assertIsDisplayed()
            .fetchSemanticsNode()

        assertEquals(
            ProgressBarRangeInfo.Indeterminate,
            loadingNode.config[SemanticsProperties.ProgressBarRangeInfo],
        )
    }
}
