package com.cashu.me.ui.screenshots

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.android.tools.screenshot.PreviewTest
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.onboarding.ChassisAction
import com.cashu.me.ui.onboarding.ChassisButtonStyle
import com.cashu.me.ui.onboarding.FirstMintSelectionState
import com.cashu.me.ui.onboarding.FirstMintStageContent
import com.cashu.me.ui.onboarding.OnboardingAsciiBackdrop
import com.cashu.me.ui.onboarding.OnboardingBackButton
import com.cashu.me.ui.onboarding.OnboardingChassisModel
import com.cashu.me.ui.onboarding.OnboardingInfoButton
import com.cashu.me.ui.onboarding.OnboardingScaffold
import com.cashu.me.ui.onboarding.OnboardingStepHeader
import com.cashu.me.ui.onboarding.SeedAcknowledgeRow
import com.cashu.me.ui.onboarding.SeedPhraseReveal
import com.cashu.me.ui.onboarding.SeedWarningNotice
import com.cashu.me.ui.onboarding.ShowMnemonicStageContent
import com.cashu.me.ui.onboarding.WelcomeStageContent
import com.cashu.me.ui.onboarding.welcomeChassis
import com.cashu.me.ui.restore.RestoreMintPhase
import com.cashu.me.ui.restore.RestoreMintsStageContent
import com.cashu.me.ui.restore.RestoreMintsSubhead
import com.cashu.me.ui.restore.RestoreMintsTitleOnboarding
import com.cashu.me.ui.restore.RestoreProgressRows
import com.cashu.me.ui.restore.RestoreRecoveredTotal
import com.cashu.me.Core.SeedPhraseEntry
import com.cashu.me.ui.restore.RestoreSeedStageContent
import com.cashu.me.ui.restore.SeedEntryCopy
import com.cashu.me.ui.restore.rememberSeedPhraseEntryState
import com.cashu.me.Models.RestoreMintResult
import com.cashu.me.ui.testing.UiTestTags
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
            ),
        ) {
            WelcomeStageContent(
                startupFailure = null,
                retryingStartup = false,
                errorText = null,
                onRetryStartup = {},
                onInfo = {},
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
            ),
        ) {
            WelcomeStageContent(
                startupFailure = null,
                retryingStartup = false,
                errorText = null,
                onRetryStartup = {},
                onInfo = {},
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
            ),
        ) {
            WelcomeStageContent(
                startupFailure = null,
                retryingStartup = false,
                errorText = null,
                onRetryStartup = {},
                onInfo = {},
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
            accessory = { SeedChassisAccessory(acknowledged = false) },
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
            accessory = { SeedChassisAccessory(acknowledged = true) },
        ) {
            Column(Modifier.fillMaxSize()) {
                OnboardingStepHeader(
                    title = "Your seed phrase.",
                    subhead = "Write these 12 words down in order. This is the only way to recover your wallet.",
                    modifier = Modifier.padding(top = 16.dp),
                )
                // Hand-built because ShowMnemonicStageContent owns `revealed`
                // internally and starts hidden. SeedPhraseReveal draws its own
                // card, so only the surrounding layout can drift here.
                SeedPhraseReveal(
                    words = FixtureWords,
                    revealed = true,
                    onToggle = {},
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 28.dp, vertical = 32.dp),
                )
            }
        }
    }
}

/**
 * Dark-mode coverage for a step that draws the *back* half of the bar band.
 * Both bar-band icons set their content color explicitly, because the
 * onboarding canvas is a `Modifier.background` rather than a `Surface` and so
 * never provides `LocalContentColor` — inheriting it renders black-on-black.
 * This preview is what would catch that regression.
 */
@PreviewTest
@Preview(
    name = "onboarding-seed-hidden-dark",
    widthDp = 390,
    heightDp = 844,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
fun onboardingSeedHiddenDarkScreenshot() {
    OnboardingFrame(darkTheme = true) {
        OnboardingScaffold(
            chassis = seedChassis(acknowledged = false),
            accessory = { SeedChassisAccessory(acknowledged = false) },
        ) {
            ShowMnemonicStageContent(
                mnemonic = FixtureWords.joinToString(" "),
                onBack = {},
            )
        }
    }
}

/** Mirrors the production chassis accessory: warning above the acknowledge row. */
@Composable
private fun SeedChassisAccessory(acknowledged: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        SeedWarningNotice()
        SeedAcknowledgeRow(acknowledged = acknowledged, onToggle = {})
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
                    title = "Restore wallet.",
                    subhead = "Choose how to restore your wallet.",
                    modifier = Modifier.padding(top = 12.dp),
                )
                Spacer(Modifier.weight(1f))
            }
        }
    }
}

@PreviewTest
@Preview(name = "onboarding-restore-input", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingRestoreInputScreenshot() {
    OnboardingFrame {
        // Six words settled, entering the seventh with "aba" typed — the state
        // that shows the rail part-filled, both ghosts, and the chip row.
        val midEntry = SeedPhraseEntry(
            words = FixtureWords.take(6) + "aba" + List(5) { "" },
            index = 6,
        )
        OnboardingScaffold(
            chassis = OnboardingChassisModel(
                primary = ChassisAction("Continue", onClick = {}, enabled = false),
            ),
        ) {
            Column(Modifier.fillMaxSize()) {
                OnboardingBackButton(onBack = {}, modifier = Modifier.padding(start = 16.dp, top = 8.dp))
                OnboardingStepHeader(
                    title = "Restore wallet.",
                    subhead = SeedEntryCopy.SUBHEAD,
                    modifier = Modifier.padding(top = 12.dp),
                )
                RestoreSeedStageContent(
                    state = rememberSeedPhraseEntryState(midEntry),
                    onOutcome = {},
                    onPaste = {},
                    errorText = null,
                    // A baseline must not request focus: the preview host has no
                    // window, and a settled frame is the point.
                    autoFocus = false,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                )
            }
        }
    }
}

/** The landing state: nothing entered, so the chip row offers paste. */
@PreviewTest
@Preview(name = "onboarding-restore-input-empty", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingRestoreInputEmptyScreenshot() {
    OnboardingFrame {
        OnboardingScaffold(
            chassis = OnboardingChassisModel(
                primary = ChassisAction("Continue", onClick = {}, enabled = false),
            ),
        ) {
            Column(Modifier.fillMaxSize()) {
                OnboardingBackButton(onBack = {}, modifier = Modifier.padding(start = 16.dp, top = 8.dp))
                OnboardingStepHeader(
                    title = "Restore wallet.",
                    subhead = SeedEntryCopy.SUBHEAD,
                    modifier = Modifier.padding(top = 12.dp),
                )
                RestoreSeedStageContent(
                    state = rememberSeedPhraseEntryState(),
                    onOutcome = {},
                    onPaste = {},
                    errorText = null,
                    // A baseline must not request focus: the preview host has no
                    // window, and a settled frame is the point.
                    autoFocus = false,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                )
            }
        }
    }
}

/** The bar band both restore-mints previews draw: Back leading, help trailing. */
@Composable
private fun RestoreMintsBarBand() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 0.dp)
            .padding(top = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OnboardingBackButton(onBack = {})
        OnboardingInfoButton(
            onClick = {},
            contentDescription = "What does Find my mints do?",
            testTag = UiTestTags.OnboardingMintBackupInfo,
        )
    }
}

// Enough mints to overflow the viewport. Two didn't, so this baseline used to
// pin nothing about the bottom edge — which is exactly where the list was
// reported cutting off dead against the CTA.
@PreviewTest
@Preview(name = "onboarding-restore-mints", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingRestoreMintsScreenshot() {
    OnboardingFrame {
        val staged = List(11) { "https://mint${it + 1}.example.com" }
        OnboardingScaffold(
            chassis = OnboardingChassisModel(
                primary = ChassisAction("Restore from 11 mints", onClick = {}),
            ),
        ) {
            Column(Modifier.fillMaxSize()) {
                RestoreMintsBarBand()
                OnboardingStepHeader(
                    title = RestoreMintsTitleOnboarding,
                    subhead = RestoreMintsSubhead,
                    modifier = Modifier.padding(top = 12.dp),
                )
                RestoreMintsStageContent(
                    input = "",
                    staged = staged,
                    previews = emptyMap(),
                    notice = "Added 11 mints from your backup.",
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

// The lookup in flight: the chip's glyph becomes the house spinner in a
// fixed-size slot, and the capsule keeps full contrast rather than dimming to
// a disabled 0.38 — a spinner in a greyed pill reads as broken, not busy.
@PreviewTest
@Preview(
    name = "onboarding-restore-mints-searching",
    widthDp = 390,
    heightDp = 844,
    showBackground = true,
)
@Composable
fun onboardingRestoreMintsSearchingScreenshot() {
    OnboardingFrame {
        OnboardingScaffold(
            chassis = OnboardingChassisModel(
                primary = ChassisAction("Restore", onClick = {}, enabled = false),
            ),
        ) {
            Column(Modifier.fillMaxSize()) {
                RestoreMintsBarBand()
                OnboardingStepHeader(
                    title = RestoreMintsTitleOnboarding,
                    subhead = RestoreMintsSubhead,
                    modifier = Modifier.padding(top = 12.dp),
                )
                RestoreMintsStageContent(
                    input = "",
                    staged = emptyList(),
                    previews = emptyMap(),
                    notice = null,
                    noticeSeverity = NoticeSeverity.Info,
                    searching = true,
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

// The state everyone now arrives in, since the backup lookup no longer runs
// itself: empty list, disabled primary, and the empty-state line carrying the
// whole way forward.
@PreviewTest
@Preview(
    name = "onboarding-restore-mints-landing",
    widthDp = 390,
    heightDp = 844,
    showBackground = true,
)
@Composable
fun onboardingRestoreMintsLandingScreenshot() {
    OnboardingFrame {
        OnboardingScaffold(
            chassis = OnboardingChassisModel(
                primary = ChassisAction("Restore", onClick = {}, enabled = false),
            ),
        ) {
            Column(Modifier.fillMaxSize()) {
                RestoreMintsBarBand()
                OnboardingStepHeader(
                    title = RestoreMintsTitleOnboarding,
                    subhead = RestoreMintsSubhead,
                    modifier = Modifier.padding(top = 12.dp),
                )
                RestoreMintsStageContent(
                    input = "",
                    staged = emptyList(),
                    previews = emptyMap(),
                    notice = null,
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
                    backupSearchCompleted = false,
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
                    title = "Restoring wallet.",
                    subhead = "Checking your mints…",
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

// ---------------------------------------------------------------------------
// ASCII terrain band (AsciiField.kt). The production field mounts at the
// OnboardingScreen root, so the plain scaffold goldens above never see it —
// these compositions mount the backdrop explicitly, mirroring the root's
// wiring, frozen at a fixed staticTime so every run renders identical
// terrain. The synthetic chassis height stands in for the root's measured
// one (the screenshot renderer can't be trusted to settle an onSizeChanged
// round-trip before capture).
// ---------------------------------------------------------------------------

/** ~the two-capsule welcome/restore chassis. */
private val FixtureChassisHeight = 176.dp

@Composable
private fun AsciiFieldFrame(
    darkTheme: Boolean = false,
    staticTime: Float = 2.5f,
    expanded: Boolean,
    chassis: OnboardingChassisModel,
    stage: @Composable () -> Unit,
) {
    OnboardingFrame(darkTheme = darkTheme) {
        Box(Modifier.fillMaxSize()) {
            OnboardingAsciiBackdrop(
                visible = true,
                expanded = expanded,
                conceptSheetOpen = false,
                chassisHeightPx = with(LocalDensity.current) { FixtureChassisHeight.roundToPx() },
                staticTime = staticTime,
                modifier = Modifier.matchParentSize(),
            )
            OnboardingScaffold(chassis = chassis, modifier = Modifier.fillMaxSize()) {
                stage()
            }
        }
    }
}

@Composable
private fun AsciiWelcomeFrame(darkTheme: Boolean = false, staticTime: Float = 2.5f) {
    AsciiFieldFrame(
        darkTheme = darkTheme,
        staticTime = staticTime,
        // Welcome runs the field tall (mask extent 1).
        expanded = true,
        chassis = welcomeChassis(
            creating = false,
            retryingStartup = false,
            onCreate = {},
            onRestore = {},
        ),
    ) {
        WelcomeStageContent(
            startupFailure = null,
            retryingStartup = false,
            errorText = null,
            onRetryStartup = {},
            onInfo = {},
        )
    }
}

@Composable
private fun AsciiRestoreMethodFrame(darkTheme: Boolean = false) {
    AsciiFieldFrame(
        darkTheme = darkTheme,
        // Restore Wallet shows the classic band (mask extent 0).
        expanded = false,
        chassis = OnboardingChassisModel(
            primary = ChassisAction("Use Seed Phrase", onClick = {}, style = ChassisButtonStyle.Secondary),
        ),
    ) {
        Column(Modifier.fillMaxSize()) {
            OnboardingBackButton(onBack = {}, modifier = Modifier.padding(start = 16.dp, top = 8.dp))
            OnboardingStepHeader(
                title = "Restore wallet.",
                subhead = "Choose how to restore your wallet.",
                modifier = Modifier.padding(top = 12.dp),
            )
            Spacer(Modifier.weight(1f))
        }
    }
}

@PreviewTest
@Preview(name = "onboarding-ascii-welcome-light", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingAsciiWelcomeLightScreenshot() {
    AsciiWelcomeFrame()
}

@PreviewTest
@Preview(
    name = "onboarding-ascii-welcome-dark",
    widthDp = 390,
    heightDp = 844,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
fun onboardingAsciiWelcomeDarkScreenshot() {
    AsciiWelcomeFrame(darkTheme = true)
}

@PreviewTest
@Preview(name = "onboarding-ascii-restore-light", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingAsciiRestoreLightScreenshot() {
    AsciiRestoreMethodFrame()
}

@PreviewTest
@Preview(
    name = "onboarding-ascii-restore-dark",
    widthDp = 390,
    heightDp = 844,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
fun onboardingAsciiRestoreDarkScreenshot() {
    AsciiRestoreMethodFrame(darkTheme = true)
}

// The §11 strip frames: the same welcome composition at t = 0 / 2.5 / 5.0s.
// Together they prove the terrain evolves — and, against the iOS strip at the
// same times, that both platforms evolve identically — with no video to
// eyeball.

@PreviewTest
@Preview(name = "onboarding-ascii-strip-t0", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingAsciiStripT0Screenshot() {
    AsciiWelcomeFrame(staticTime = 0f)
}

@PreviewTest
@Preview(name = "onboarding-ascii-strip-t2-5", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingAsciiStripT25Screenshot() {
    AsciiWelcomeFrame(staticTime = 2.5f)
}

@PreviewTest
@Preview(name = "onboarding-ascii-strip-t5", widthDp = 390, heightDp = 844, showBackground = true)
@Composable
fun onboardingAsciiStripT5Screenshot() {
    AsciiWelcomeFrame(staticTime = 5f)
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
        // Deliberately `Modifier.background`, NOT `Surface` — production paints
        // the onboarding canvas exactly this way (OnboardingScreen's root
        // modifier). A `Surface` here would provide `LocalContentColor` that
        // production does not, so anything inheriting the ambient content color
        // would render correctly in these previews while being invisible in the
        // real app's dark mode. That drift hid a black-on-black bar-band icon.
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background),
        ) {
            content()
        }
    }
}
