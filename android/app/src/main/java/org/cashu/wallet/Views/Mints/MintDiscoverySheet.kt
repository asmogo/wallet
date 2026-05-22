package org.cashu.wallet.Views.Mints

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateSetOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.cashu.wallet.Core.MintDiscoveryManager
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Views.Components.CanvasDivider
import org.cashu.wallet.Views.Components.CopyShareRow
import org.cashu.wallet.Views.Components.QuietCard
import org.cashu.wallet.Views.Components.SecondaryActionButton

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MintDiscoverySheet(
    mintDiscoveryManager: MintDiscoveryManager,
    configuredMints: List<MintInfo>,
    useWebsockets: Boolean,
    isWalletLoading: Boolean,
    onAddMint: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val discoveryState by mintDiscoveryManager.state.collectAsState()
    val scope = rememberCoroutineScope()
    var searchText by remember { mutableStateOf("") }
    val addedThisSession = remember { mutableStateSetOf<String>() }

    LaunchedEffect(useWebsockets) {
        if (useWebsockets && discoveryState.discoveredMints.isEmpty()) {
            mintDiscoveryManager.discoverMints()
        }
    }
    DisposableEffect(Unit) {
        onDispose { mintDiscoveryManager.clearDiscoveredMints() }
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 680.dp)
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Discover Mints", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                TextButton(onClick = onDismiss) { Text("Done") }
            }

            if (!useWebsockets) {
                QuietCard {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Warning, contentDescription = null)
                        Column {
                            Text("WebSockets Required", fontWeight = FontWeight.SemiBold)
                            Text(
                                "Enable WebSocket connections in Settings to discover mints over Nostr.",
                                color = MaterialTheme.colorScheme.secondary,
                            )
                        }
                    }
                }
                return@Column
            }

            OutlinedTextField(
                value = searchText,
                onValueChange = { searchText = it },
                modifier = Modifier.fillMaxWidth(),
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                label = { Text("Search mints") },
                singleLine = true,
            )

            SecondaryActionButton(
                text = if (discoveryState.isDiscovering) "Discovering..." else "Refresh discovery",
                enabled = !discoveryState.isDiscovering,
            ) {
                scope.launch { mintDiscoveryManager.discoverMints() }
            }

            val filtered = remember(searchText, discoveryState.discoveredMints) {
                val query = searchText.trim()
                if (query.isEmpty()) {
                    discoveryState.discoveredMints
                } else {
                    discoveryState.discoveredMints.filter { mint ->
                        mint.name.contains(query, ignoreCase = true) ||
                            mint.url.contains(query, ignoreCase = true)
                    }
                }
            }
            val configuredUrls = configuredMints.map { it.url }.toSet()
            val addedMints = filtered.filter { it.url in configuredUrls || it.url in addedThisSession }
            val discoverableMints = filtered.filterNot { it.url in configuredUrls || it.url in addedThisSession }

            LazyColumn(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (discoveryState.isDiscovering) {
                    item {
                        QuietCard {
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                CircularProgressIndicator()
                                Text("Discovering mints...", color = MaterialTheme.colorScheme.secondary)
                            }
                        }
                    }
                }

                if (addedMints.isNotEmpty()) {
                    item { SectionTitle("Added") }
                    items(addedMints, key = { "added-${it.url}" }) { mint ->
                        AddedMintRow(mint = mint, highlighted = mint.url in addedThisSession)
                    }
                }

                if (discoverableMints.isNotEmpty()) {
                    item { SectionTitle("Discovered") }
                    items(discoverableMints, key = { "discovered-${it.url}" }) { mint ->
                        DiscoverableMintRow(
                            mint = mint,
                            enabled = !isWalletLoading,
                            onAdd = {
                                addedThisSession += mint.url
                                onAddMint(mint.url)
                            },
                        )
                    }
                } else if (!discoveryState.isDiscovering && addedMints.isEmpty()) {
                    item {
                        QuietCard {
                            Text(
                                if (searchText.isBlank()) "No mints found." else "No results for \"$searchText\".",
                                color = MaterialTheme.colorScheme.secondary,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.secondary,
        modifier = Modifier.padding(top = 6.dp),
    )
}

@Composable
private fun AddedMintRow(mint: MintInfo, highlighted: Boolean) {
    QuietCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(mint.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(mint.url, color = MaterialTheme.colorScheme.secondary, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
            }
            AnimatedVisibility(visible = highlighted) {
                Text("Added", color = MaterialTheme.colorScheme.primary)
            }
            Icon(Icons.Default.CheckCircle, contentDescription = "Added")
        }
        CanvasDivider()
        CopyShareRow(label = "Mint URL", content = mint.url)
    }
}

@Composable
private fun DiscoverableMintRow(
    mint: MintInfo,
    enabled: Boolean,
    onAdd: () -> Unit,
) {
    QuietCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(mint.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(mint.url, color = MaterialTheme.colorScheme.secondary, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
            }
            IconButton(onClick = onAdd, enabled = enabled) {
                Icon(Icons.Default.AddCircle, contentDescription = "Add ${mint.name}")
            }
        }
        mint.description?.let {
            Text(it, color = MaterialTheme.colorScheme.secondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        CopyShareRow(label = "Mint URL", content = mint.url)
    }
}
