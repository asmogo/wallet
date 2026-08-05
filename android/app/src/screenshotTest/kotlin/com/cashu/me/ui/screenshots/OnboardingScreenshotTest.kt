package com.cashu.me.ui.screenshots

import android.content.res.Configuration
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.android.tools.screenshot.PreviewTest
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.onboarding.ChassisAction
import com.cashu.me.ui.onboarding.ChassisButtonStyle
import com.cashu.me.ui.onboarding.FirstMintSelectionState
import com.cashu.me.ui.onboarding.FirstMintStageContent
import com.cashu.me.ui.onboarding.OnboardingBackButton
import com.cashu.me.ui.onboarding.OnboardingChassisModel
import com.cashu.me.ui.onboarding.OnboardingScaffold
import com.cashu.me.ui.onboarding.OnboardingStepHeader
import com.cashu.me.ui.onboarding.SeedAcknowledgeRow
import com.cashu.me.ui.onboarding.SeedPhraseReveal
import com.cashu.me.ui.onboarding.ShowMnemonicStageContent
import com.cashu.me.ui.onboarding.WelcomeStageContent
import com.cashu.me.ui.onboarding.WelcomeStagePiece
import com.cashu.me.ui.onboarding.welcomeChassis
import com.cashu.me.ui.restore.RestoreMintPhase
import com.cashu.me.ui.restore.RestoreMintsStageContent
import com.cashu.me.ui.restore.RestoreProgressRows
import com.cashu.me.ui.restore.RestoreRecoveredTotal
import com.cashu.me.ui.restore.RestoreSeedStageContent
import com.cashu.me.Models.RestoreMintResult
import com.cashu.me.ui.theme.CashuTheme

// ---------------------------------------------------------------------------
// Pixel-regression baselines for the onboarding chassis + stages (restyle
// brief §8.3 — these steps previously had zero screenshot coverage). Every
// composition goes through the production OnboardingScaffold with synthetic
// fixture data only: the BIP-39 test vector words, example.com mints, and
// round numbers. Never a real seed, key, token, or balance.
// ---------------------------------------------------------------------------

// The abandon-…-about BIP-39 test vector — the canonical synthetic phrase.
private val FixtureWords = listOf(
    "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
    "abandon", "abandon", "abandon", "abandon", "abandon", "about",
)

@PreviewTest
@Preview(name = "onboarding-welcome-light", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingWelcomeLightScreenshot() {
    OnboardingFrame {
        OnboardingScaffold(
            chassis = welcomeChassis(
                creating = false,
                retryingStartup = false,
                onCreate = {},
                onRestore = {},
                onInfo = {},
            ),
        ) {
            WelcomeStageContent(
                startupFailure = null,
                retryingStartup = false,
                errorText = null,
                onRetryStartup = {},
            )
        }
    }
}

@PreviewTest
@Preview(
    name = "onboarding-welcome-dark",
    widthDp = 390,
    heightDp = 844,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
fun onboardingWelcomeDarkScreenshot() {
    OnboardingFrame(darkTheme = true) {
        OnboardingScaffold(
            chassis = welcomeChassis(
                creating = false,
                retryingStartup = false,
                onCreate = {},
                onRestore = {},
                onInfo = {},
            ),
        ) {
            WelcomeStageContent(
                startupFailure = null,
                retryingStartup = false,
                errorText = null,
                onRetryStartup = {},
            )
        }
    }
}

@PreviewTest
@Preview(name = "onboarding-welcome-large-font", widthDp = 390, heightDp = 844, fontScale = 2f, showBackground = true)
@Composable
fun onboardingWelcomeLargeFontScreenshot() {
    OnboardingFrame {
        OnboardingScaffold(
            chassis = welcomeChassis(
                creating = false,
                retryingStartup = false,
                onCreate = {},
                onRestore = {},
                onInfo = {},
            ),
        ) {
            WelcomeStageContent(
                startupFailure = null,
                retryingStartup = false,
                errorText = null,
                onRetryStartup = {},
            )
        }
    }
}

@PreviewTest
@Preview(name = "onboarding-seed-hidden", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingSeedHiddenScreenshot() {
    OnboardingFrame {
        OnboardingScaffold(
            chassis = seedChassis(acknowledged = false),
            accessory = { SeedAcknowledgeRow(acknowledged = false, onToggle = {}) },
        ) {
            ShowMnemonicStageContent(
                mnemonic = FixtureWords.joinToString(" "),
                onBack = {},
            )
        }
    }
}

@PreviewTest
@Preview(name = "onboarding-seed-revealed", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingSeedRevealedScreenshot() {
    OnboardingFrame {
        OnboardingScaffold(
            chassis = seedChassis(acknowledged = true),
            accessory = { SeedAcknowledgeRow(acknowledged = true, onToggle = {}) },
        ) {
            Column(Modifier.fillMaxSize()) {
                OnboardingStepHeader(
                    title = "Your Seed Phrase.",
                    subhead = "Write these 12 words down in order. This is the only way to recover your wallet.",
                    modifier = Modifier.padding(top = 16.dp),
                )
                SeedPhraseReveal(
                    words = FixtureWords,
                    revealed = true,
                    onReveal = {},
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 28.dp, vertical = 32.dp),
                )
            }
        }
    }
}

@PreviewTest
@Preview(name = "onboarding-first-mint", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingFirstMintScreenshot() {
    OnboardingFrame {
        val state = remember {
            FirstMintSelectionState().apply { toggle("https://mint.example.com") }
        }
        OnboardingScaffold(
            chassis = OnboardingChassisModel(
                primary = ChassisAction("Continue", onClick = {}),
                tertiary = ChassisAction("Skip for now", onClick = {}, style = ChassisButtonStyle.Ghost),
            ),
        ) {
            FirstMintStageContent(
                state = state,
                busy = false,
                addingMintUrl = null,
                errorText = null,
                onBack = {},
            )
        }
    }
}

@PreviewTest
@Preview(name = "onboarding-restore-method", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingRestoreMethodScreenshot() {
    OnboardingFrame {
        OnboardingScaffold(
            chassis = OnboardingChassisModel(
                primary = ChassisAction("Use Seed Phrase", onClick = {}, style = ChassisButtonStyle.Secondary),
            ),
        ) {
            Column(Modifier.fillMaxSize()) {
                OnboardingBackButton(onBack = {}, modifier = Modifier.padding(start = 16.dp, top = 8.dp))
                OnboardingStepHeader(
                    title = "Restore Wallet",
                    subhead = "Choose how to recover your wallet.",
                    modifier = Modifier.padding(top = 12.dp),
                )
                WelcomeStagePiece(
                    Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    quiet = true,
                )
            }
        }
    }
}

@PreviewTest
@Preview(name = "onboarding-restore-input", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingRestoreInputScreenshot() {
    OnboardingFrame {
        val partial = FixtureWords.take(6).joinToString(" ")
        OnboardingScaffold(
            chassis = OnboardingChassisModel(
                primary = ChassisAction("Next", onClick = {}, enabled = false),
            ),
        ) {
            Column(Modifier.fillMaxSize()) {
                OnboardingBackButton(onBack = {}, modifier = Modifier.padding(start = 16.dp, top = 8.dp))
                OnboardingStepHeader(
                    title = "Restore Wallet.",
                    subhead = "Enter your 12 words in order.",
                    modifier = Modifier.padding(top = 12.dp),
                )
                RestoreSeedStageContent(
                    input = partial,
                    onInputChange = {},
                    wordCount = 6,
                    invalidCount = 0,
                    errorText = null,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                )
            }
        }
    }
}

@PreviewTest
@Preview(name = "onboarding-restore-mints", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingRestoreMintsScreenshot() {
    OnboardingFrame {
        val staged = listOf("https://mint.example.com", "https://cash.example.org")
        OnboardingScaffold(
            chassis = OnboardingChassisModel(
                primary = ChassisAction("Restore from 2 mints", onClick = {}),
            ),
        ) {
            Column(Modifier.fillMaxSize()) {
                OnboardingBackButton(onBack = {}, modifier = Modifier.padding(start = 16.dp, top = 8.dp))
                OnboardingStepHeader(
                    title = "Recover Funds.",
                    subhead = "Add the mints you used before to recover funds from this seed.",
                    modifier = Modifier.padding(top = 12.dp),
                )
                RestoreMintsStageContent(
                input = "",
                staged = staged,
                previews = emptyMap(),
                notice = "Added 2 mints.",
                noticeSeverity = NoticeSeverity.Info,
                searching = false,
                onInputChange = {},
                onAdd = {},
                onPaste = {},
                onNostr = {},
                    onRemove = {},
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(top = 16.dp),
                )
            }
        }
    }
}

@PreviewTest
@Preview(name = "onboarding-restore-progress", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingRestoreProgressScreenshot() {
    OnboardingFrame {
        val urls = listOf(
            "https://mint.example.com",
            "https://cash.example.org",
            "https://notes.example.net",
        )
        val phases = mapOf<String, RestoreMintPhase>(
            urls[0] to RestoreMintPhase.Recovered(
                RestoreMintResult(
                    mintUrl = urls[0],
                    mintName = "Example Mint",
                    spent = 0,
                    unspent = 2_100,
                    pending = 0,
                ),
            ),
            urls[1] to RestoreMintPhase.Restoring,
            urls[2] to RestoreMintPhase.Failed("Couldn't reach this mint."),
        )
        OnboardingScaffold(
            chassis = OnboardingChassisModel(
                primary = ChassisAction("Continue", onClick = {}, enabled = false),
            ),
        ) {
            Column(Modifier.fillMaxSize()) {
                OnboardingStepHeader(
                    title = "Recover Funds.",
                    subhead = "Recovering funds from your mints…",
                    modifier = Modifier.padding(top = 8.dp, bottom = 12.dp),
                )
                RestoreRecoveredTotal(
                    totalRecovered = 2_100,
                    modifier = Modifier.padding(horizontal = 28.dp, vertical = 8.dp),
                )
                RestoreProgressRows(
                    mintUrls = urls,
                    phases = phases,
                    previews = emptyMap(),
                    onRetry = {},
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

private fun seedChassis(acknowledged: Boolean): OnboardingChassisModel = OnboardingChassisModel(
    primary = ChassisAction(
        label = "I've Saved My Seed Phrase",
        onClick = {},
        enabled = acknowledged,
    ),
)

@Composable
private fun OnboardingFrame(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit,
) {
    CashuTheme(darkTheme = darkTheme) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background,
        ) {
            content()
        }
    }
}
