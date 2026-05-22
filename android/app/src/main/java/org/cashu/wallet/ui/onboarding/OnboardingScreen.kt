package org.cashu.wallet.ui.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.random.Random
import kotlinx.coroutines.launch
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.ui.components.BoldPrimaryButton
import org.cashu.wallet.ui.components.CashuTextField
import org.cashu.wallet.ui.components.GhostButton
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.theme.CashuTheme

private data class RecommendedMint(val name: String, val url: String)

private val RecommendedMints = listOf(
    RecommendedMint("Minibits", "https://mint.minibits.cash/Bitcoin"),
    RecommendedMint("Coinos", "https://mint.coinos.io"),
    RecommendedMint("Macadamia", "https://mint.macadamia.cash"),
)

private sealed interface OnboardingStep {
    data object Welcome : OnboardingStep
    data class ShowMnemonic(val mnemonic: String) : OnboardingStep
    data class VerifyMnemonic(val mnemonic: String) : OnboardingStep
    data class FirstMint(val mnemonic: String) : OnboardingStep
    data object RestoreInput : OnboardingStep
}

@Composable
fun OnboardingScreen(walletManager: WalletManager) {
    val walletState by walletManager.state.collectAsState()
    val scope = rememberCoroutineScope()

    var step: OnboardingStep by remember { mutableStateOf(OnboardingStep.Welcome) }
    var direction by remember { mutableStateOf(1) }
    var infoOpen by remember { mutableStateOf(false) }

    fun goTo(next: OnboardingStep, forward: Boolean = true) {
        direction = if (forward) 1 else -1
        step = next
    }

    AnimatedContent(
        targetState = step,
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .statusBarsPadding()
            .imePadding(),
        transitionSpec = { stepTransition(direction) },
        label = "onboarding-step",
    ) { current ->
        when (current) {
            OnboardingStep.Welcome -> WelcomeFace(
                isLoading = walletState.isLoading,
                onCreate = {
                    scope.launch {
                        val mnemonic = runCatching {
                            walletManager.generateMnemonicForOnboarding()
                        }.getOrNull() ?: return@launch
                        goTo(OnboardingStep.ShowMnemonic(mnemonic))
                    }
                },
                onRestore = { goTo(OnboardingStep.RestoreInput) },
                onInfo = { infoOpen = true },
            )

            is OnboardingStep.ShowMnemonic -> ShowMnemonicFace(
                mnemonic = current.mnemonic,
                onBack = { goTo(OnboardingStep.Welcome, forward = false) },
                onContinue = { goTo(OnboardingStep.VerifyMnemonic(current.mnemonic)) },
            )

            is OnboardingStep.VerifyMnemonic -> VerifyMnemonicFace(
                mnemonic = current.mnemonic,
                onBack = { goTo(OnboardingStep.ShowMnemonic(current.mnemonic), forward = false) },
                onContinue = { goTo(OnboardingStep.FirstMint(current.mnemonic)) },
            )

            is OnboardingStep.FirstMint -> FirstMintFace(
                isLoading = walletState.isLoading,
                onBack = { goTo(OnboardingStep.VerifyMnemonic(current.mnemonic), forward = false) },
                onFinish = { selectedMintUrl ->
                    scope.launch {
                        runCatching {
                            walletManager.initializeNewWalletForOnboarding(current.mnemonic)
                            selectedMintUrl?.let { walletManager.addMint(it) }
                            walletManager.completeOnboarding()
                        }
                    }
                },
            )

            OnboardingStep.RestoreInput -> RestoreInputFace(
                isLoading = walletState.isLoading,
                onBack = { goTo(OnboardingStep.Welcome, forward = false) },
                onRestore = { mnemonic ->
                    scope.launch {
                        runCatching {
                            walletManager.restoreWallet(mnemonic)
                            walletManager.completeOnboarding()
                        }
                    }
                },
                errorMessage = walletState.errorMessage,
            )
        }
    }

    if (infoOpen) {
        EcashInfoDialog(onDismiss = { infoOpen = false })
    }
}

@Composable
private fun WelcomeFace(
    isLoading: Boolean,
    onCreate: () -> Unit,
    onRestore: () -> Unit,
    onInfo: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = CashuTheme.spacing.section, vertical = CashuTheme.spacing.page + CashuTheme.spacing.micro),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(0.8f))
        Text(
            text = "CASHU",
            style = MaterialTheme.typography.labelSmall.copy(
                letterSpacing = 3.sp,
            ),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(CashuTheme.spacing.default))
        Text(
            text = "Private cash.\nIn your pocket.",
            style = MaterialTheme.typography.displaySmall,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.weight(1f))
        BoldPrimaryButton(
            text = "Create wallet",
            onClick = onCreate,
            loading = isLoading,
        )
        Spacer(Modifier.height(CashuTheme.spacing.snug))
        PrimaryButton(
            text = "I have a seed phrase",
            onClick = onRestore,
        )
        Spacer(Modifier.height(CashuTheme.spacing.snug))
        GhostButton(
            text = "What is ecash?",
            onClick = onInfo,
        )
    }
}

@Composable
private fun ShowMnemonicFace(
    mnemonic: String,
    onBack: () -> Unit,
    onContinue: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val words = remember(mnemonic) {
        mnemonic.trim().split(' ').filter { it.isNotBlank() }
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(CashuTheme.spacing.section)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
    ) {
        Text(
            text = "Your recovery phrase",
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = "Write these 12 words down in order. Anyone with them can spend your wallet.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        SeedGrid(words = words)
        PrimaryButton(
            text = "Copy & continue",
            onClick = {
                clipboard.setText(AnnotatedString(mnemonic))
                onContinue()
            },
        )
        GhostButton(text = "Back", onClick = onBack, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun VerifyMnemonicFace(
    mnemonic: String,
    onBack: () -> Unit,
    onContinue: () -> Unit,
) {
    val words = remember(mnemonic) {
        mnemonic.trim().split(' ').filter { it.isNotBlank() }
    }
    val positions = remember(words) {
        if (words.size < 12) emptyList()
        else generateSequence { Random.nextInt(words.size) }
            .distinct()
            .take(3)
            .toList()
            .sorted()
    }
    val answers = remember { mutableMapOf<Int, String>() }
    var attempts by remember { mutableStateOf(0) }
    val verified = positions.isNotEmpty() && positions.all {
        answers[it]?.trim().equals(words[it], ignoreCase = true)
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(CashuTheme.spacing.section)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Text(
            text = "Verify your phrase",
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = "Type the words at the positions below to confirm you've stored them.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        positions.forEach { position ->
            var value by remember { mutableStateOf("") }
            CashuTextField(
                value = value,
                onValueChange = { v ->
                    value = v
                    answers[position] = v
                    attempts++ // trigger recomposition for verified check
                },
                label = "Word ${position + 1}",
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
            )
        }
        if (verified) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Check,
                    contentDescription = null,
                    tint = CashuTheme.colors.received,
                    modifier = Modifier.size(VERIFY_CHECK_ICON_SIZE),
                )
                Text(
                    text = "Looks right.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = CashuTheme.colors.received,
                )
            }
        }
        Spacer(Modifier.height(CashuTheme.spacing.snug))
        PrimaryButton(
            text = "Verified, continue",
            onClick = onContinue,
            enabled = verified,
        )
        GhostButton(text = "Back", onClick = onBack, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun FirstMintFace(
    isLoading: Boolean,
    onBack: () -> Unit,
    onFinish: (selectedMintUrl: String?) -> Unit,
) {
    var selectedUrl by remember { mutableStateOf<String?>(RecommendedMints.first().url) }
    var customUrl by remember { mutableStateOf("") }
    var useCustom by remember { mutableStateOf(false) }
    val effectiveUrl = if (useCustom) customUrl.trim().takeIf { it.isNotBlank() } else selectedUrl
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(CashuTheme.spacing.section)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Text(
            text = "Add your first mint",
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = "A mint custodies your ecash. You can change or add more later.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        RecommendedMints.forEach { rec ->
            MintOptionRow(
                title = rec.name,
                subtitle = rec.url.removePrefix("https://"),
                selected = !useCustom && selectedUrl == rec.url,
                onSelect = {
                    useCustom = false
                    selectedUrl = rec.url
                },
            )
        }
        MintOptionRow(
            title = "Custom mint URL",
            subtitle = "Paste any HTTPS mint URL",
            selected = useCustom,
            onSelect = { useCustom = true },
        )
        if (useCustom) {
            CashuTextField(
                value = customUrl,
                onValueChange = { customUrl = it },
                label = "https://…",
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
            )
        }
        Spacer(Modifier.height(CashuTheme.spacing.snug))
        PrimaryButton(
            text = if (isLoading) "Setting up…" else "Continue",
            onClick = { onFinish(effectiveUrl) },
            enabled = effectiveUrl != null && !isLoading,
            loading = isLoading,
        )
        GhostButton(
            text = "Skip for now",
            onClick = { onFinish(null) },
            enabled = !isLoading,
            modifier = Modifier.fillMaxWidth(),
        )
        GhostButton(text = "Back", onClick = onBack, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun RestoreInputFace(
    isLoading: Boolean,
    onBack: () -> Unit,
    onRestore: (String) -> Unit,
    errorMessage: String?,
) {
    var input by remember { mutableStateOf("") }
    val wordCount = remember(input) {
        input.trim().split(Regex("\\s+")).count { it.isNotBlank() }
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(CashuTheme.spacing.section)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Text(
            text = "Restore from seed",
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = "Paste or type your 12-word recovery phrase.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        CashuTextField(
            value = input,
            onValueChange = { input = it },
            label = "Recovery phrase",
            placeholder = "word1 word2 word3 …",
            minLines = 4,
            modifier = Modifier
                .fillMaxWidth()
                .height(SEED_INPUT_HEIGHT),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
        )
        Text(
            text = "$wordCount / 12 words",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (errorMessage != null) {
            Text(
                text = errorMessage,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        Spacer(Modifier.height(CashuTheme.spacing.snug))
        PrimaryButton(
            text = if (isLoading) "Restoring…" else "Restore wallet",
            onClick = { onRestore(input) },
            enabled = wordCount == 12 && !isLoading,
            loading = isLoading,
        )
        GhostButton(text = "Back", onClick = onBack, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun SeedGrid(words: List<String>) {
    val mono = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(CashuTheme.spacing.comfortable),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        words.chunked(2).forEachIndexed { rowIndex, pair ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
            ) {
                pair.forEachIndexed { columnIndex, word ->
                    val index = rowIndex * 2 + columnIndex + 1
                    Row(
                        modifier = Modifier.weight(1f),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                    ) {
                        Text(
                            text = "%2d".format(index),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(text = word, style = mono)
                    }
                }
            }
        }
    }
}

@Composable
private fun MintOptionRow(
    title: String,
    subtitle: String,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .clickable(onClick = onSelect)
            .padding(CashuTheme.spacing.comfortable),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Box(
            modifier = Modifier
                .size(CashuTheme.spacing.loose)
                .clip(CircleShape)
                .background(
                    if (selected) CashuTheme.colors.received
                    else MaterialTheme.colorScheme.surfaceContainerHighest,
                ),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) {
                Icon(
                    imageVector = Icons.Outlined.Check,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.surface,
                    modifier = Modifier.size(RADIO_CHECK_ICON_SIZE),
                )
            }
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun EcashInfoDialog(onDismiss: () -> Unit) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("What is ecash?") },
        text = {
            Text(
                "Ecash is bearer money: you hold the value as tokens on your device, not as an account at a service. A mint issues and redeems tokens; you can send them to anyone with a copy/paste, QR code, or Lightning.",
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) { Text("Got it") }
        },
    )
}

// Component-local sizes that sit below the spacing scale on purpose.
private val VERIFY_CHECK_ICON_SIZE = 18.dp
private val SEED_INPUT_HEIGHT = 160.dp
private val RADIO_CHECK_ICON_SIZE = 14.dp

private fun <S> AnimatedContentTransitionScope<S>.stepTransition(direction: Int):
    androidx.compose.animation.ContentTransform {
    val offset = if (direction >= 0) 80 else -80
    return (
        androidx.compose.animation.slideInHorizontally(tween(280)) { offset } +
            fadeIn(tween(220))
    ).togetherWith(
        androidx.compose.animation.slideOutHorizontally(tween(260)) { -offset / 2 } +
            fadeOut(tween(180))
    )
}
