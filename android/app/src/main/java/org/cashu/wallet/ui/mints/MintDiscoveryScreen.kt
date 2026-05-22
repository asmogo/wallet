package org.cashu.wallet.ui.mints

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.SignalCellularConnectedNoInternet0Bar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.cashu.wallet.Core.MintDiscoveryManager
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.shortenMintUrl
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.CashuSearchBar
import org.cashu.wallet.ui.components.EmptyState
import org.cashu.wallet.ui.components.MintAvatar
import org.cashu.wallet.ui.components.MintMethodChips
import org.cashu.wallet.ui.theme.CashuTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MintDiscoveryContent(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    mintDiscoveryManager: MintDiscoveryManager,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val discoveryState by mintDiscoveryManager.state.collectAsState()
    val scope = rememberCoroutineScope()

    var query by remember { mutableStateOf("") }

    val configuredUrls = remember(walletState.mints) { walletState.mints.map { it.url }.toSet() }

    val filtered by remember(discoveryState.discoveredMints, query, configuredUrls) {
        derivedStateOf {
            val q = query.trim()
            discoveryState.discoveredMints.filter { mint ->
                q.isBlank() ||
                    mint.name.contains(q, ignoreCase = true) ||
                    mint.url.contains(q, ignoreCase = true)
            }
        }
    }

    LaunchedEffect(settings.useWebsockets) {
        if (settings.useWebsockets &&
            discoveryState.discoveredMints.isEmpty() &&
            !discoveryState.isDiscovering
        ) {
            scope.launch {
                runCatching { mintDiscoveryManager.discoverMints() }
            }
        }
    }
    DisposableEffect(Unit) {
        onDispose { mintDiscoveryManager.clearDiscoveredMints() }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        CashuSearchBar(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.snug,
                ),
            placeholder = "Search mints",
        )

        if (!settings.useWebsockets) {
            EmptyState(
                icon = Icons.Outlined.SignalCellularConnectedNoInternet0Bar,
                title = "Discovery disabled",
                supporting = "Discovery uses Nostr relays over WebSockets. Enable it in Settings → Privacy.",
            )
            return@Column
        }

        when {
            discoveryState.isDiscovering && discoveryState.discoveredMints.isEmpty() -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            filtered.isEmpty() -> {
                EmptyState(
                    icon = Icons.Outlined.SignalCellularConnectedNoInternet0Bar,
                    title = if (query.isBlank()) "Listening on Nostr…" else "No matches",
                    supporting = if (query.isBlank())
                        "Mints announced on Nostr show up here as they arrive."
                    else null,
                )
            }
            else -> {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(filtered, key = { it.url }) { mint ->
                        val isConfigured = mint.url in configuredUrls
                        DiscoveryRow(
                            mint = mint,
                            isConfigured = isConfigured,
                            isBusy = walletState.isLoading,
                            onAdd = {
                                scope.launch { runCatching { walletManager.addMint(mint.url) } }
                            },
                        )
                        if (mint != filtered.last()) CanvasDivider(leadingInset = 64)
                    }
                }
            }
        }
    }
}

@Composable
private fun DiscoveryRow(
    mint: MintInfo,
    isConfigured: Boolean,
    isBusy: Boolean,
    onAdd: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                horizontal = CashuTheme.spacing.comfortable,
                vertical = CashuTheme.spacing.default,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        MintAvatar(mint = mint)
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = mint.name,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = shortenMintUrl(mint.url),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
            if (mint.supportedMintMethods.isNotEmpty() || mint.supportedMeltMethods.isNotEmpty()) {
                MintMethodChips(mint = mint)
            }
        }
        if (isConfigured) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Check,
                    contentDescription = null,
                    tint = CashuTheme.colors.received,
                    modifier = Modifier.size(CashuTheme.spacing.loose),
                )
                Text(
                    text = "Added",
                    style = MaterialTheme.typography.labelLarge,
                    color = CashuTheme.colors.received,
                )
            }
        } else {
            FilledTonalButton(
                onClick = onAdd,
                enabled = !isBusy,
                shape = MaterialTheme.shapes.extraLarge,
            ) {
                Text("Add")
            }
        }
    }
}
