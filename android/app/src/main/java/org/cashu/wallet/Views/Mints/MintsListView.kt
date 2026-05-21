package org.cashu.wallet.Views.Mints

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.cashu.wallet.Core.MintDiscoveryManager
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.mintUrlCandidates
import org.cashu.wallet.Core.normalizeUserMintUrl
import org.cashu.wallet.Core.shortenMintUrl
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Resources.CashuGreen
import org.cashu.wallet.Resources.CashuOrange
import org.cashu.wallet.Views.Components.ClipboardSuggestionChip
import org.cashu.wallet.Views.Components.CopyShareRow
import org.cashu.wallet.Views.Components.KeyValueRow
import org.cashu.wallet.Views.Components.PrimaryActionButton
import org.cashu.wallet.Views.Components.QuietCard
import org.cashu.wallet.Views.Components.SectionHeader
import org.cashu.wallet.Views.Components.SecondaryActionButton
import org.cashu.wallet.Views.Components.readClipboardText
import org.cashu.wallet.Views.Components.rememberClipboardText

@Composable
fun MintsListView(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    mintDiscoveryManager: MintDiscoveryManager,
    contentPadding: PaddingValues = PaddingValues(),
    scannedMintUrl: String? = null,
    onScannedMintUrlConsumed: () -> Unit = {},
    onScan: () -> Unit = {},
) {
    val state by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val discoveryState by mintDiscoveryManager.state.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val clipboardText = rememberClipboardText()
    var mintUrl by remember { mutableStateOf("") }
    var discoveryError by remember { mutableStateOf<String?>(null) }
    var inputError by remember { mutableStateOf<String?>(null) }
    var dismissedClipboardSuggestion by remember { mutableStateOf(false) }
    var mintToRemove by remember { mutableStateOf<MintInfo?>(null) }
    var mintToInspect by remember { mutableStateOf<MintInfo?>(null) }
    val clipboardMintUrl = remember(clipboardText) {
        clipboardText?.let { mintUrlCandidates(it).firstOrNull() }
    }
    fun pasteMintUrlFromClipboard() {
        val candidate = context.readClipboardText()
            ?.let { mintUrlCandidates(it).firstOrNull() }
        if (candidate == null) {
            inputError = "No valid mint URL found in clipboard."
        } else {
            mintUrl = candidate
            inputError = null
            dismissedClipboardSuggestion = true
        }
    }
    fun addMint(rawUrl: String = mintUrl, clearInputOnSuccess: Boolean = true) {
        val normalized = normalizeUserMintUrl(rawUrl)
        if (normalized == null) {
            inputError = "Enter a valid HTTPS mint URL."
            return
        }
        inputError = null
        scope.launch {
            runCatching { walletManager.addMint(normalized) }
                .onSuccess {
                    if (clearInputOnSuccess) mintUrl = ""
                }
        }
    }
    LaunchedEffect(scannedMintUrl) {
        val payload = scannedMintUrl?.trim().orEmpty()
        if (payload.isNotEmpty()) {
            mintUrl = normalizeUserMintUrl(payload) ?: payload
            inputError = null
            dismissedClipboardSuggestion = true
            onScannedMintUrlConsumed()
        }
    }
    LaunchedEffect(clipboardMintUrl) {
        dismissedClipboardSuggestion = false
    }
    LaunchedEffect(settings.useWebsockets) {
        if (settings.useWebsockets) discoveryError = null
    }
    mintToRemove?.let { mint ->
        AlertDialog(
            onDismissRequest = { mintToRemove = null },
            title = { Text("Remove Mint") },
            text = {
                Text("Remove ${mint.name}? Any unspent ecash on this mint will need to be restored from your seed phrase.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        mintToRemove = null
                        walletManager.launch { walletManager.removeMint(mint) }
                    },
                ) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { mintToRemove = null }) {
                    Text("Cancel")
                }
            },
        )
    }
    mintToInspect?.let { mint ->
        AlertDialog(
            onDismissRequest = { mintToInspect = null },
            title = { Text(mint.name) },
            text = {
                MintDetailView(
                    mint = mint,
                    modifier = Modifier.fillMaxWidth(),
                    showTitle = false,
                )
            },
            confirmButton = {
                TextButton(onClick = { mintToInspect = null }) {
                    Text("Close")
                }
            },
        )
    }
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding)
            .padding(horizontal = 24.dp),
        contentPadding = PaddingValues(vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text("Mints", style = MaterialTheme.typography.headlineSmall)
        }
        item {
            OutlinedTextField(
                value = mintUrl,
                onValueChange = { mintUrl = it },
                label = { Text("Mint URL") },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (mintUrl.isBlank() && clipboardMintUrl != null && !dismissedClipboardSuggestion) {
            item {
                ClipboardSuggestionChip(
                    title = "Mint URL in clipboard",
                    detail = shortenMintUrl(clipboardMintUrl),
                    onUse = {
                        mintUrl = clipboardMintUrl
                        inputError = null
                        dismissedClipboardSuggestion = true
                    },
                    onDismiss = { dismissedClipboardSuggestion = true },
                )
            }
        }
        inputError?.let { error ->
            item { Text(error, color = MaterialTheme.colorScheme.error) }
        }
        item {
            SecondaryActionButton("Paste URL from clipboard", enabled = !state.isLoading) {
                pasteMintUrlFromClipboard()
            }
        }
        item {
            SecondaryActionButton("Scan mint URL", enabled = !state.isLoading, onClick = onScan)
        }
        item {
            PrimaryActionButton("Add mint", enabled = mintUrl.isNotBlank() && !state.isLoading) {
                addMint()
            }
        }
        item {
            SecondaryActionButton(
                text = if (discoveryState.isDiscovering) "Discovering..." else "Discover mints",
                enabled = !discoveryState.isDiscovering && !state.isLoading,
            ) {
                if (!settings.useWebsockets) {
                    discoveryError = "Enable WebSocket connections in Settings to discover mints."
                } else {
                    discoveryError = null
                    scope.launch { mintDiscoveryManager.discoverMints() }
                }
            }
        }
        discoveryError?.let { error ->
            item { Text(error, color = MaterialTheme.colorScheme.error) }
        }
        if (discoveryState.discoveredMints.isNotEmpty()) {
            item { SectionHeader("Discovered") }
            items(discoveryState.discoveredMints, key = { it.url }) { mint ->
                val alreadyAdded = state.mints.any { it.url == mint.url }
                QuietCard {
                    KeyValueRow("Name", mint.name)
                    KeyValueRow("URL", mint.url)
                    mint.description?.let { KeyValueRow("Description", it) }
                    CopyShareRow(label = "Mint URL", content = mint.url)
                    SecondaryActionButton(
                        text = if (alreadyAdded) "Added" else "Add",
                        enabled = !alreadyAdded && !state.isLoading,
                    ) {
                        addMint(rawUrl = mint.url, clearInputOnSuccess = false)
                    }
                }
            }
        }
        item { SectionHeader("Configured") }
        items(state.mints, key = { it.url }) { mint ->
            val isActive = state.activeMint?.url == mint.url
            QuietCard {
                KeyValueRow("Name", mint.name)
                KeyValueRow("Balance", "${mint.balance} sat")
                KeyValueRow("URL", mint.url)
                if (isActive) {
                    Text("Active", color = CashuGreen, style = MaterialTheme.typography.labelMedium)
                }
                PaymentMethodChips(mint)
                CopyShareRow(label = "Mint URL", content = mint.url)
                SecondaryActionButton("View details") {
                    mintToInspect = mint
                }
                SecondaryActionButton(
                    text = if (isActive) "Active mint" else "Set active",
                    enabled = !isActive && !state.isLoading,
                ) {
                    walletManager.launch { walletManager.setActiveMint(mint) }
                }
                SecondaryActionButton("Remove mint", enabled = !state.isLoading) {
                    mintToRemove = mint
                }
            }
        }
        if (state.mints.isEmpty()) {
            item { Text("No mints added.", color = MaterialTheme.colorScheme.secondary) }
        }
        state.errorMessage?.let { error ->
            item { Text(error, color = MaterialTheme.colorScheme.error) }
        }
    }
}

@Composable
private fun PaymentMethodChips(mint: MintInfo) {
    val featuredMethods = remember(mint.supportedMintMethods, mint.supportedMeltMethods) {
        (mint.supportedMintMethods + mint.supportedMeltMethods)
            .distinct()
            .filter { it == PaymentMethodKind.Bolt12 || it == PaymentMethodKind.Onchain }
            .sortedBy { it.sortOrder }
    }
    if (featuredMethods.isEmpty()) return
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        featuredMethods.forEach { method ->
            val color = when (method) {
                PaymentMethodKind.Onchain -> CashuOrange
                else -> MaterialTheme.colorScheme.primary
            }
            Box(
                modifier = Modifier
                    .background(color.copy(alpha = 0.12f), RoundedCornerShape(percent = 50))
                    .padding(horizontal = 6.dp, vertical = 3.dp),
            ) {
                Text(
                    text = method.displayName,
                    color = color,
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
    }
}
