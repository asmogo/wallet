package com.cashu.me.ui.mints

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.AddCircle
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material.icons.outlined.SignalCellularConnectedNoInternet0Bar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import com.cashu.me.Core.AppLogger
import com.cashu.me.Core.MintDiscoveryManager
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.canonicalDiscoveredMintUrl
import com.cashu.me.Core.shortenMintUrl
import com.cashu.me.Models.MintInfo
import com.cashu.me.ui.components.CashuSearchBar
import com.cashu.me.ui.components.EmptyState
import com.cashu.me.ui.components.MintAvatar
import com.cashu.me.ui.components.MintMethodChips
import com.cashu.me.ui.theme.CashuTheme

private val DiscoveryActionGlyphSize = 28.dp

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun MintDiscoveryContent(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    mintDiscoveryManager: MintDiscoveryManager,
    onMintAdded: () -> Unit = {},
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val discoveryState by mintDiscoveryManager.state.collectAsState()
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current

    var query by remember { mutableStateOf("") }
    val addStates = remember { mutableStateMapOf<String, DiscoveryRowState>() }

    val configuredUrls = remember(walletState.mints) {
        walletState.mints.mapNotNull { canonicalDiscoveredMintUrl(it.url) }.toSet()
    }

    val filtered by remember(discoveryState.discoveredMints, query) {
        derivedStateOf {
            val q = query.trim()
            discoveryState.discoveredMints.filter { mint ->
                val displayName = mint.discoveryDisplayName()
                q.isBlank() ||
                    displayName.contains(q, ignoreCase = true) ||
                    mint.url.contains(q, ignoreCase = true)
            }
        }
    }
    val addedMints by remember(filtered, configuredUrls, addStates) {
        derivedStateOf {
            filtered.filter { mint ->
                mint.url in configuredUrls || addStates[mint.url] == DiscoveryRowState.Added
            }
        }
    }
    val discoverableMints by remember(filtered, configuredUrls, addStates) {
        derivedStateOf {
            filtered.filterNot { mint ->
                mint.url in configuredUrls || addStates[mint.url] == DiscoveryRowState.Added
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

    var refreshing by remember { mutableStateOf(false) }
    val refreshDiscovery = {
        if (!refreshing) {
            refreshing = true
            scope.launch {
                try {
                    mintDiscoveryManager.discoverMints()
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    AppLogger.wallet.error("Mint discovery refresh failed", error)
                } finally {
                    refreshing = false
                }
            }
        }
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

        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = refreshDiscovery,
            modifier = Modifier.fillMaxSize(),
        ) {
        when {
            filtered.isEmpty() && !discoveryState.isDiscovering -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState()),
                    contentAlignment = Alignment.Center,
                ) {
                    when {
                        query.isNotBlank() -> EmptyState(
                            icon = Icons.Outlined.SignalCellularConnectedNoInternet0Bar,
                            title = "No matches",
                            fillHeight = false,
                        )
                        discoveryState.hasCompletedDiscovery -> EmptyState(
                            icon = Icons.Outlined.SearchOff,
                            title = "No mints found",
                            supporting = "Mints announced on Nostr show up here as they arrive. Pull down to refresh or tap Retry.",
                            actionLabel = "Retry",
                            onAction = refreshDiscovery,
                            fillHeight = false,
                        )
                        else -> EmptyState(
                            icon = Icons.Outlined.SignalCellularConnectedNoInternet0Bar,
                            title = "Listening on Nostr…",
                            supporting = "Mints announced on Nostr show up here as they arrive.",
                            fillHeight = false,
                        )
                    }
                }
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = CashuTheme.spacing.section),
                ) {
                    if (discoveryState.isDiscovering) {
                        item(key = "discovering") {
                            DiscoveringRow(modifier = Modifier.animateItem())
                        }
                    }

                    if (addedMints.isNotEmpty()) {
                        item(key = "added-header") {
                            DiscoverySectionHeader("Added", modifier = Modifier.animateItem())
                        }
                        items(addedMints, key = { "mint-${it.url}" }) { mint ->
                            Column(modifier = Modifier.animateItem()) {
                                DiscoveryRow(
                                    mint = mint,
                                    state = DiscoveryRowState.Added,
                                    onAdd = {},
                                )
                            }
                        }
                    }

                    if (discoverableMints.isNotEmpty()) {
                        item(key = "discovered-header") {
                            DiscoverySectionHeader("Discovered", modifier = Modifier.animateItem())
                        }
                        items(discoverableMints, key = { "mint-${it.url}" }) { mint ->
                            Column(modifier = Modifier.animateItem()) {
                                DiscoveryRow(
                                    mint = mint,
                                    state = addStates[mint.url] ?: DiscoveryRowState.Ready,
                                    onAdd = {
                                        if (addStates[mint.url] != DiscoveryRowState.Adding) {
                                            addStates[mint.url] = DiscoveryRowState.Adding
                                            scope.launch {
                                                try {
                                                    walletManager.addMint(mint.url)
                                                    addStates[mint.url] = DiscoveryRowState.Added
                                                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                                    onMintAdded()
                                                } catch (error: CancellationException) {
                                                    addStates.remove(mint.url)
                                                    throw error
                                                } catch (error: Throwable) {
                                                    addStates[mint.url] = DiscoveryRowState.Failed(
                                                        error.userFacingWalletMessage,
                                                    )
                                                    haptics.performHapticFeedback(HapticFeedbackType.Reject)
                                                }
                                            }
                                        }
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }
        }
    }
}

@Composable
private fun DiscoveryRow(
    mint: MintInfo,
    state: DiscoveryRowState,
    onAdd: () -> Unit,
) {
    val displayName = mint.discoveryDisplayName()
    val displayMint = remember(mint, displayName) { mint.copy(name = displayName) }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (state == DiscoveryRowState.Added) 0.7f else 1f)
            .padding(
                horizontal = CashuTheme.spacing.comfortable,
                vertical = CashuTheme.spacing.comfortable,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        MintAvatar(mint = displayMint, size = 40.dp)
        Column(modifier = Modifier.weight(1f)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
            ) {
                Text(
                    text = displayName,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (!mint.supportedMintMethods.isNullOrEmpty() || !mint.supportedMeltMethods.isNullOrEmpty()) {
                    MintMethodChips(mint = mint)
                }
            }
            Text(
                text = shortenMintUrl(mint.url),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
            if (state is DiscoveryRowState.Failed) {
                Text(
                    text = state.message,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
        // Add ↔ Added swaps within one fixed slot so both glyphs stay aligned
        // and render at exactly the same size.
        AnimatedContent(
            targetState = state,
            modifier = Modifier.size(48.dp),
            contentAlignment = Alignment.Center,
            transitionSpec = {
                (
                    fadeIn(spring(stiffness = Spring.StiffnessMedium)) +
                        scaleIn(
                            animationSpec = spring(
                                dampingRatio = 0.7f,
                                stiffness = Spring.StiffnessMediumLow,
                            ),
                            initialScale = 0.9f,
                        )
                    ).togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
            },
            label = "discovery-trailing",
        ) { rowState ->
            val isAdded = rowState == DiscoveryRowState.Added
            if (rowState == DiscoveryRowState.Adding) {
                Box(modifier = Modifier.size(48.dp), contentAlignment = Alignment.Center) {
                    LoadingIndicator(
                        modifier = Modifier
                            .size(DiscoveryActionGlyphSize)
                            .semantics { contentDescription = "Adding $displayName" },
                    )
                }
            } else {
                IconButton(
                    onClick = { if (!isAdded) onAdd() },
                    enabled = !isAdded,
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(
                        imageVector = if (isAdded) Icons.Filled.CheckCircle else Icons.Outlined.AddCircle,
                        contentDescription = when {
                            isAdded -> "Added"
                            rowState is DiscoveryRowState.Failed -> "Retry adding $displayName"
                            else -> "Add $displayName"
                        },
                        tint = if (isAdded) {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        },
                        modifier = Modifier.size(DiscoveryActionGlyphSize),
                    )
                }
            }
        }
    }
}

@Composable
private fun DiscoveringRow(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(
                horizontal = CashuTheme.spacing.comfortable,
                vertical = CashuTheme.spacing.snug,
            )
            .semantics { contentDescription = "Discovering mints" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Box(
            modifier = Modifier.width(40.dp),
            contentAlignment = Alignment.Center,
        ) {
            LoadingIndicator(modifier = Modifier.size(28.dp))
        }
        Text(
            text = "Discovering mints…",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun DiscoverySectionHeader(title: String, modifier: Modifier = Modifier) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.padding(
            start = CashuTheme.spacing.comfortable,
            end = CashuTheme.spacing.comfortable,
            top = CashuTheme.spacing.default,
            bottom = CashuTheme.spacing.micro,
        ),
    )
}

private sealed interface DiscoveryRowState {
    data object Ready : DiscoveryRowState
    data object Adding : DiscoveryRowState
    data object Added : DiscoveryRowState
    data class Failed(val message: String) : DiscoveryRowState
}

private fun MintInfo.discoveryDisplayName(): String {
    val trimmed = name.trim()
    return when {
        trimmed.isNotEmpty() && !trimmed.equals("Unknown Mint", ignoreCase = true) -> trimmed
        else -> shortenMintUrl(url)
    }
}
