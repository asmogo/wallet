package org.cashu.wallet.ui.mints

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.shortenMintUrl
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.ui.components.AmountText
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.DestructiveTextButton
import org.cashu.wallet.ui.components.GhostButton
import org.cashu.wallet.ui.components.InspectorRow
import org.cashu.wallet.ui.components.MintAvatar
import org.cashu.wallet.ui.components.MintMethodChips
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.SectionHeader
import org.cashu.wallet.ui.theme.CashuTheme
import org.cashu.wallet.ui.theme.withMonoDigits

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MintDetailScreen(
    walletManager: WalletManager,
    mintUrl: String,
    onClose: () -> Unit,
) {
    val walletState by walletManager.state.collectAsState()
    val mint = walletState.mints.firstOrNull { it.url == mintUrl }
    val isActive = walletState.activeMint?.url == mintUrl
    val clipboard = LocalClipboardManager.current
    var confirmingRemove by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(mint?.name ?: "Mint", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Outlined.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        if (mint == null) {
            EmptyMintFallback(padding = padding, onClose = onClose)
            return@Scaffold
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            HeaderBlock(mint = mint, isActive = isActive)

            if (!mint.description.isNullOrBlank()) {
                SectionHeader("About")
                Text(
                    text = mint.description,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }

            SectionHeader("Identity")
            Column(modifier = Modifier.fillMaxWidth()) {
                InspectorRow(
                    label = "URL",
                    value = shortenMintUrl(mint.url),
                    valueMonospaced = true,
                )
                CanvasDivider(leadingInset = 16)
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { clipboard.setText(AnnotatedString(mint.url)) }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.ContentCopy,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp),
                    )
                    Text(
                        text = "Copy full URL",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }

            SectionHeader("Payment methods")
            Column(modifier = Modifier.fillMaxWidth()) {
                InspectorRow(
                    label = "Receive",
                    value = mint.supportedMintMethods.joinToString { it.displayName }.ifBlank { "None" },
                )
                CanvasDivider(leadingInset = 16)
                InspectorRow(
                    label = "Send",
                    value = mint.supportedMeltMethods.joinToString { it.displayName }.ifBlank { "None" },
                )
                mint.onchainMintConfirmations?.let {
                    CanvasDivider(leadingInset = 16)
                    InspectorRow(
                        label = "On-chain confirmations",
                        value = it.toString(),
                        valueMonospaced = true,
                    )
                }
            }

            SectionHeader("Wallet")
            InspectorRow(
                label = "Balance on this mint",
                value = "${mint.balance} sat",
                valueMonospaced = true,
            )
            CanvasDivider(leadingInset = 16)
            InspectorRow(
                label = "Units",
                value = mint.units.joinToString(", ").ifBlank { "sat" },
            )

            Spacer(Modifier.height(16.dp))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                PrimaryButton(
                    text = if (isActive) "Active mint" else "Set as active mint",
                    onClick = {
                        if (!isActive) walletManager.launch { walletManager.setActiveMint(mint) }
                    },
                    enabled = !isActive,
                )
                DestructiveTextButton(
                    text = "Remove mint",
                    onClick = { confirmingRemove = true },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (confirmingRemove) {
        AlertDialog(
            onDismissRequest = { confirmingRemove = false },
            title = { Text("Remove ${mint?.name ?: "mint"}?") },
            text = {
                Text(
                    "Any unspent ecash on this mint will need to be restored from your seed phrase.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmingRemove = false
                    mint?.let { walletManager.launch { walletManager.removeMint(it) } }
                    onClose()
                }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingRemove = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun HeaderBlock(mint: MintInfo, isActive: Boolean) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Box {
                MintAvatar(mint = mint, size = 72)
                if (isActive) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(16.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.surface),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Check,
                            contentDescription = "Active",
                            tint = CashuTheme.colors.received,
                            modifier = Modifier.size(12.dp),
                        )
                    }
                }
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = mint.name,
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = shortenMintUrl(mint.url),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                )
                AmountText(
                    text = "${mint.balance} sat",
                    style = MaterialTheme.typography.bodyMedium.withMonoDigits(),
                )
            }
        }
        MintMethodChips(mint = mint)
    }
}

@Composable
private fun EmptyMintFallback(padding: PaddingValues, onClose: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Mint not found",
            style = MaterialTheme.typography.titleMedium,
        )
        Spacer(Modifier.height(16.dp))
        GhostButton(text = "Back to mints", onClick = onClose)
    }
}
