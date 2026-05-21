package org.cashu.wallet.Views.Main

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.MnemonicInput
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.mintUrlCandidates
import org.cashu.wallet.Core.normalizeUserMintUrl
import org.cashu.wallet.Core.shortenMintUrl
import org.cashu.wallet.Models.RestoreMintResult
import org.cashu.wallet.Views.Components.KeyValueRow
import org.cashu.wallet.Views.Components.PrimaryActionButton
import org.cashu.wallet.Views.Components.QuietCard
import org.cashu.wallet.Views.Components.SecondaryActionButton

private enum class OnboardingStep {
    Welcome,
    ShowSeed,
    ConfirmSeed,
    FirstMint,
    Restore,
    RestoreMints,
}

private data class RecommendedMint(
    val name: String,
    val url: String,
)

private val recommendedMints = listOf(
    RecommendedMint(name = "Minibits", url = "https://mint.minibits.cash/Bitcoin"),
    RecommendedMint(name = "Coinos", url = "https://mint.coinos.io"),
    RecommendedMint(name = "Macadamia", url = "https://mint.macadamia.cash"),
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnboardingView(walletManager: WalletManager) {
    val state by walletManager.state.collectAsState()
    val clipboard = LocalClipboardManager.current
    var step by remember { mutableStateOf(OnboardingStep.Welcome) }
    var generatedMnemonic by remember { mutableStateOf<String?>(null) }
    var confirmationPhrase by remember { mutableStateOf("") }
    var restorePhrase by remember { mutableStateOf("") }

    var selectedMintUrls by remember { mutableStateOf<Set<String>>(emptySet()) }
    var customMintUrls by remember { mutableStateOf<List<String>>(emptyList()) }
    var showCustomMintInput by remember { mutableStateOf(false) }
    var customMintInput by remember { mutableStateOf("") }
    var firstMintError by remember { mutableStateOf<String?>(null) }
    var isAddingFirstMints by remember { mutableStateOf(false) }
    var currentAddingMint by remember { mutableStateOf<String?>(null) }

    var restoreMintInput by remember { mutableStateOf("") }
    var mintsToRestore by remember { mutableStateOf<List<String>>(emptyList()) }
    var restoreResults by remember { mutableStateOf<List<RestoreMintResult>>(emptyList()) }
    var restoreMintError by remember { mutableStateOf<String?>(null) }
    var isRestoringMints by remember { mutableStateOf(false) }
    var currentRestoringMint by remember { mutableStateOf<String?>(null) }

    fun addCustomMintFromInput() {
        val normalized = normalizeUserMintUrl(customMintInput)
        when {
            normalized == null -> firstMintError = "That doesn't look like a mint URL."
            recommendedMints.any { it.url == normalized } || normalized in customMintUrls -> {
                firstMintError = "That mint is already in the list."
            }
            else -> {
                customMintUrls = customMintUrls + normalized
                selectedMintUrls = selectedMintUrls + normalized
                customMintInput = ""
                showCustomMintInput = false
                firstMintError = null
            }
        }
    }

    fun addRestoreMint(rawUrl: String, showDuplicateError: Boolean = true, showValidationError: Boolean = true): Boolean {
        val normalized = normalizeUserMintUrl(rawUrl)
        if (normalized == null) {
            if (showValidationError) restoreMintError = "That doesn't look like a mint URL."
            return false
        }
        if (normalized in mintsToRestore || restoreResults.any { it.mintUrl == normalized }) {
            if (showDuplicateError) restoreMintError = "This mint is already in the list."
            return false
        }
        mintsToRestore = mintsToRestore + normalized
        restoreMintError = null
        return true
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.Bottom,
    ) {
        Spacer(Modifier.weight(1f))
        Text("Cashu Wallet", style = MaterialTheme.typography.displayLarge)
        Spacer(Modifier.height(12.dp))
        Text(
            "Private ecash with clear mint boundaries and local secret storage.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.secondary,
        )
        Spacer(Modifier.height(32.dp))
        when (step) {
            OnboardingStep.Welcome -> {
                PrimaryActionButton(
                    text = if (state.isLoading) "Creating..." else "Create Wallet",
                    enabled = !state.isLoading,
                ) {
                    walletManager.launch {
                        generatedMnemonic = walletManager.generateMnemonicForOnboarding()
                        confirmationPhrase = ""
                        step = OnboardingStep.ShowSeed
                    }
                }
                Spacer(Modifier.height(12.dp))
                SecondaryActionButton(
                    text = "I have a seed phrase",
                    enabled = !state.isLoading,
                ) {
                    step = OnboardingStep.Restore
                }
                if (state.canExitOnboarding) {
                    Spacer(Modifier.height(12.dp))
                    SecondaryActionButton(
                        text = "Back to Wallet",
                        enabled = !state.isLoading,
                    ) {
                        walletManager.closeRestoreFlow()
                    }
                }
            }
            OnboardingStep.ShowSeed -> {
                val mnemonic = generatedMnemonic.orEmpty()
                Text(
                    "Write down these words before continuing.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.secondary,
                )
                Spacer(Modifier.height(12.dp))
                SeedPhraseCard(words = MnemonicInput.words(mnemonic))
                Spacer(Modifier.height(12.dp))
                PrimaryActionButton(
                    text = "I've saved these words",
                    enabled = !state.isLoading && mnemonic.isNotBlank(),
                ) {
                    step = OnboardingStep.ConfirmSeed
                }
                Spacer(Modifier.height(12.dp))
                SecondaryActionButton("Back") {
                    generatedMnemonic = null
                    confirmationPhrase = ""
                    step = OnboardingStep.Welcome
                }
            }
            OnboardingStep.ConfirmSeed -> {
                val mnemonic = generatedMnemonic.orEmpty()
                OutlinedTextField(
                    value = confirmationPhrase,
                    onValueChange = { confirmationPhrase = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Confirm seed phrase") },
                    minLines = 3,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                )
                if (confirmationPhrase.isNotBlank() && !MnemonicInput.matches(confirmationPhrase, mnemonic)) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Seed phrase does not match.",
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Spacer(Modifier.height(12.dp))
                PrimaryActionButton(
                    text = if (state.isLoading) "Creating..." else "Create Wallet",
                    enabled = !state.isLoading && MnemonicInput.matches(confirmationPhrase, mnemonic),
                ) {
                    walletManager.launch {
                        walletManager.initializeNewWalletForOnboarding(mnemonic)
                        selectedMintUrls = emptySet()
                        customMintUrls = emptyList()
                        step = OnboardingStep.FirstMint
                    }
                }
                Spacer(Modifier.height(12.dp))
                SecondaryActionButton("Back") {
                    confirmationPhrase = ""
                    step = OnboardingStep.ShowSeed
                }
            }
            OnboardingStep.FirstMint -> {
                FirstMintStep(
                    selectedMintUrls = selectedMintUrls,
                    customMintUrls = customMintUrls,
                    showCustomMintInput = showCustomMintInput,
                    customMintInput = customMintInput,
                    error = firstMintError,
                    isAdding = isAddingFirstMints || state.isLoading,
                    currentAddingMint = currentAddingMint,
                    onToggleMint = { url ->
                        selectedMintUrls = if (url in selectedMintUrls) {
                            selectedMintUrls - url
                        } else {
                            selectedMintUrls + url
                        }
                        firstMintError = null
                    },
                    onShowCustomMintInput = { showCustomMintInput = true },
                    onCustomMintInputChange = { customMintInput = it },
                    onPasteCustomMint = {
                        customMintInput = clipboard.getText()?.text.orEmpty().trim()
                    },
                    onCommitCustomMint = ::addCustomMintFromInput,
                    onContinue = {
                        val ordered = recommendedMints.map { it.url }.filter { it in selectedMintUrls } +
                            customMintUrls.filter { it in selectedMintUrls }
                        walletManager.launch {
                            isAddingFirstMints = true
                            firstMintError = null
                            try {
                                for (url in ordered) {
                                    currentAddingMint = url
                                    walletManager.addMint(url)
                                }
                                walletManager.completeOnboarding()
                            } catch (error: Throwable) {
                                firstMintError = "Couldn't connect to ${shortenMintUrl(currentAddingMint ?: ordered.first())}. ${error.message.orEmpty()}"
                            } finally {
                                currentAddingMint = null
                                isAddingFirstMints = false
                            }
                        }
                    },
                    onSkip = {
                        walletManager.launch { walletManager.completeOnboarding() }
                    },
                )
            }
            OnboardingStep.Restore -> {
                OutlinedTextField(
                    value = restorePhrase,
                    onValueChange = { restorePhrase = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Seed phrase") },
                    minLines = 3,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                )
                if (restorePhrase.isNotBlank() && !MnemonicInput.hasSupportedWordCount(restorePhrase)) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Seed phrase must be ${MnemonicInput.supportedWordCountLabel} words.",
                        color = MaterialTheme.colorScheme.secondary,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Spacer(Modifier.height(12.dp))
                PrimaryActionButton(
                    text = if (state.isLoading) "Opening..." else "Next",
                    enabled = !state.isLoading && MnemonicInput.hasSupportedWordCount(restorePhrase),
                ) {
                    walletManager.launch {
                        walletManager.initializeRestoredWallet(restorePhrase)
                        restoreMintInput = ""
                        mintsToRestore = emptyList()
                        restoreResults = emptyList()
                        restoreMintError = null
                        step = OnboardingStep.RestoreMints
                    }
                }
                Spacer(Modifier.height(12.dp))
                SecondaryActionButton("Back") {
                    restorePhrase = ""
                    step = OnboardingStep.Welcome
                }
            }
            OnboardingStep.RestoreMints -> {
                RestoreMintsStep(
                    mintInput = restoreMintInput,
                    mintsToRestore = mintsToRestore,
                    restoreResults = restoreResults,
                    error = restoreMintError,
                    isRestoring = isRestoringMints || state.isLoading,
                    currentRestoringMint = currentRestoringMint,
                    onMintInputChange = { restoreMintInput = it },
                    onAddMint = {
                        if (addRestoreMint(restoreMintInput)) restoreMintInput = ""
                    },
                    onPasteMints = {
                        val candidates = mintUrlCandidates(clipboard.getText()?.text.orEmpty())
                        var added = 0
                        candidates.forEach { candidate ->
                            if (addRestoreMint(candidate, showDuplicateError = false, showValidationError = false)) added += 1
                        }
                        restoreMintError = when {
                            added > 0 -> null
                            candidates.isEmpty() -> "Nothing in the clipboard looked like a mint URL."
                            else -> "No new mint URLs to add."
                        }
                    },
                    onRemoveMint = { url ->
                        mintsToRestore = mintsToRestore.filterNot { it == url }
                    },
                    onStartRestore = {
                        walletManager.launch {
                            isRestoringMints = true
                            restoreMintError = null
                            try {
                                val urls = mintsToRestore
                                for (url in urls) {
                                    currentRestoringMint = url
                                    runCatching { walletManager.restoreFromMint(url) }
                                        .onSuccess { result ->
                                            restoreResults = restoreResults + result
                                            mintsToRestore = mintsToRestore.filterNot { it == url }
                                        }
                                        .onFailure { error ->
                                            restoreMintError = "Couldn't reach ${shortenMintUrl(url)}. ${error.message.orEmpty()}"
                                        }
                                }
                            } finally {
                                currentRestoringMint = null
                                isRestoringMints = false
                            }
                        }
                    },
                    onContinue = {
                        walletManager.launch { walletManager.completeOnboarding() }
                    },
                    onBack = {
                        mintsToRestore = emptyList()
                        restoreResults = emptyList()
                        restoreMintError = null
                        step = OnboardingStep.Restore
                    },
                )
            }
        }
        state.errorMessage?.let {
            Spacer(Modifier.height(16.dp))
            Text(it, color = MaterialTheme.colorScheme.error)
        }
    }
}

@Composable
private fun FirstMintStep(
    selectedMintUrls: Set<String>,
    customMintUrls: List<String>,
    showCustomMintInput: Boolean,
    customMintInput: String,
    error: String?,
    isAdding: Boolean,
    currentAddingMint: String?,
    onToggleMint: (String) -> Unit,
    onShowCustomMintInput: () -> Unit,
    onCustomMintInputChange: (String) -> Unit,
    onPasteCustomMint: () -> Unit,
    onCommitCustomMint: () -> Unit,
    onContinue: () -> Unit,
    onSkip: () -> Unit,
) {
    Text("Pick your first mint", style = MaterialTheme.typography.headlineSmall)
    Spacer(Modifier.height(8.dp))
    Text(
        "Mints issue your ecash and redeem it for Bitcoin. Add more anytime in Settings.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.secondary,
    )
    Spacer(Modifier.height(12.dp))
    QuietCard {
        val rows = recommendedMints.map { it.name to it.url } + customMintUrls.map { shortenMintUrl(it) to it }
        rows.forEachIndexed { index, row ->
            MintChoiceRow(
                name = row.first,
                url = row.second,
                selected = row.second in selectedMintUrls,
                enabled = !isAdding,
                onToggle = { onToggleMint(row.second) },
            )
            if (index < rows.lastIndex) HorizontalDivider()
        }
    }
    Spacer(Modifier.height(12.dp))
    if (showCustomMintInput) {
        OutlinedTextField(
            value = customMintInput,
            onValueChange = onCustomMintInputChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Custom mint URL") },
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
            singleLine = true,
        )
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            SecondaryActionButton("Paste", enabled = !isAdding, onClick = onPasteCustomMint)
        }
        Spacer(Modifier.height(8.dp))
        PrimaryActionButton("Add custom mint", enabled = customMintInput.isNotBlank() && !isAdding, onClick = onCommitCustomMint)
    } else {
        SecondaryActionButton("Add custom mint URL", enabled = !isAdding, onClick = onShowCustomMintInput)
    }
    currentAddingMint?.let {
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(modifier = Modifier.height(18.dp), strokeWidth = 2.dp)
            Text("Connecting to ${shortenMintUrl(it)}...", color = MaterialTheme.colorScheme.secondary)
        }
    }
    error?.let {
        Spacer(Modifier.height(8.dp))
        Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
    }
    Spacer(Modifier.height(12.dp))
    PrimaryActionButton("Continue", enabled = selectedMintUrls.isNotEmpty() && !isAdding, onClick = onContinue)
    Spacer(Modifier.height(12.dp))
    SecondaryActionButton("Skip for now", enabled = !isAdding, onClick = onSkip)
}

@Composable
private fun RestoreMintsStep(
    mintInput: String,
    mintsToRestore: List<String>,
    restoreResults: List<RestoreMintResult>,
    error: String?,
    isRestoring: Boolean,
    currentRestoringMint: String?,
    onMintInputChange: (String) -> Unit,
    onAddMint: () -> Unit,
    onPasteMints: () -> Unit,
    onRemoveMint: (String) -> Unit,
    onStartRestore: () -> Unit,
    onContinue: () -> Unit,
    onBack: () -> Unit,
) {
    Text("Restore Ecash", style = MaterialTheme.typography.headlineSmall)
    Spacer(Modifier.height(8.dp))
    Text(
        "Add the mints you used before to recover your ecash.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.secondary,
    )
    Spacer(Modifier.height(12.dp))
    OutlinedTextField(
        value = mintInput,
        onValueChange = onMintInputChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text("Mint URL") },
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
        singleLine = true,
    )
    Spacer(Modifier.height(8.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.weight(1f)) {
            PrimaryActionButton("Add", enabled = mintInput.isNotBlank() && !isRestoring, onClick = onAddMint)
        }
        Column(modifier = Modifier.weight(1f)) {
            SecondaryActionButton("Paste", enabled = !isRestoring, onClick = onPasteMints)
        }
    }
    Spacer(Modifier.height(12.dp))
    if (mintsToRestore.isNotEmpty() || restoreResults.isNotEmpty()) {
        QuietCard {
            mintsToRestore.forEachIndexed { index, url ->
                RestoreMintRow(
                    url = url,
                    result = null,
                    isRestoring = currentRestoringMint == url,
                    onRemove = { onRemoveMint(url) },
                )
                if (index < mintsToRestore.lastIndex || restoreResults.isNotEmpty()) HorizontalDivider()
            }
            restoreResults.forEachIndexed { index, result ->
                RestoreMintRow(
                    url = result.mintUrl,
                    result = result,
                    isRestoring = false,
                    onRemove = {},
                )
                if (index < restoreResults.lastIndex) HorizontalDivider()
            }
        }
    } else {
        Text("No mints added yet.", color = MaterialTheme.colorScheme.secondary)
    }
    error?.let {
        Spacer(Modifier.height(8.dp))
        Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
    }
    if (restoreResults.isNotEmpty()) {
        val totalRecovered = restoreResults.sumOf { it.unspent }
        val totalPending = restoreResults.sumOf { it.pending }
        Spacer(Modifier.height(12.dp))
        QuietCard {
            KeyValueRow("Recovered", "$totalRecovered sats")
            KeyValueRow("Pending", "$totalPending sats")
            if (totalRecovered == 0L && totalPending == 0L) {
                Text("No ecash to recover from these mints.", color = MaterialTheme.colorScheme.secondary)
            }
        }
    }
    Spacer(Modifier.height(12.dp))
    if (mintsToRestore.isNotEmpty()) {
        PrimaryActionButton(
            text = if (isRestoring) "Restoring..." else "Restore from ${mintsToRestore.size} mint${if (mintsToRestore.size == 1) "" else "s"}",
            enabled = !isRestoring,
            onClick = onStartRestore,
        )
        Spacer(Modifier.height(12.dp))
    }
    SecondaryActionButton(
        text = if (mintsToRestore.isEmpty() && restoreResults.isEmpty()) "Skip" else "Continue",
        enabled = !isRestoring,
        onClick = onContinue,
    )
    Spacer(Modifier.height(12.dp))
    SecondaryActionButton("Back", enabled = !isRestoring, onClick = onBack)
}

@Composable
private fun MintChoiceRow(
    name: String,
    url: String,
    selected: Boolean,
    enabled: Boolean,
    onToggle: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(url, color = MaterialTheme.colorScheme.secondary, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Checkbox(checked = selected, onCheckedChange = { onToggle() }, enabled = enabled)
    }
}

@Composable
private fun RestoreMintRow(
    url: String,
    result: RestoreMintResult?,
    isRestoring: Boolean,
    onRemove: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isRestoring) {
            CircularProgressIndicator(modifier = Modifier.height(18.dp), strokeWidth = 2.dp)
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(result?.mintName ?: shortenMintUrl(url), style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(url, color = MaterialTheme.colorScheme.secondary, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (result != null) {
            Text("${result.unspent} sats", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium)
        } else if (!isRestoring) {
            TextButton(onClick = onRemove) {
                Text("Remove")
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SeedPhraseCard(words: List<String>) {
    QuietCard {
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            words.forEachIndexed { index, word ->
                Text(
                    text = "${index + 1}. $word",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                )
            }
        }
    }
}
