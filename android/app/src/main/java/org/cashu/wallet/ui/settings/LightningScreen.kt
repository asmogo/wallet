package org.cashu.wallet.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.NPCService
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.GhostButton
import org.cashu.wallet.ui.components.InspectorRow
import org.cashu.wallet.ui.components.MintPickerSheet
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.SectionHeader
import org.cashu.wallet.ui.components.ToggleRow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LightningScreen(
    walletManager: WalletManager,
    npcService: NPCService,
    onClose: () -> Unit,
) {
    val walletState by walletManager.state.collectAsState()
    val npcState by npcService.state.collectAsState()
    val clipboard = LocalClipboardManager.current

    var mintPickerOpen by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Lightning", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SectionHeader("Lightning address")
            if (npcState.lightningAddress.isNotBlank()) {
                InspectorRow(
                    label = "Address",
                    value = npcState.lightningAddress,
                    valueMonospaced = true,
                )
                CanvasDivider(leadingInset = 16)
                Column(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    GhostButton(
                        text = "Copy address",
                        onClick = {
                            clipboard.setText(AnnotatedString(npcState.lightningAddress))
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            } else {
                Text(
                    text = "No Lightning address configured. Enable below to receive at an @ address.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
            }

            SectionHeader("Settings")
            ToggleRow(
                title = "Enable Nostr-NPC bridge",
                subtitle = "Route Lightning payments through the NPC quote handler",
                checked = npcState.isEnabled,
                onCheckedChange = { npcService.setEnabled(it) },
            )
            CanvasDivider(leadingInset = 16)
            ToggleRow(
                title = "Automatic claim",
                subtitle = "Mint paid quotes without confirmation",
                checked = npcState.automaticClaim,
                onCheckedChange = { npcService.setAutomaticClaim(it) },
                enabled = npcState.isEnabled,
            )

            SectionHeader("Active mint")
            val mintLabel = walletState.mints.firstOrNull { it.url == npcState.selectedMintUrl }?.name
                ?: walletState.activeMint?.name
                ?: "No mint"
            InspectorRow(
                label = "Mint",
                value = mintLabel,
                editable = walletState.mints.isNotEmpty(),
                onClick = { if (walletState.mints.isNotEmpty()) mintPickerOpen = true },
            )

            if (npcState.errorMessage != null) {
                Spacer(Modifier.height(8.dp))
                Text(
                    text = npcState.errorMessage!!,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }

            Spacer(Modifier.height(16.dp))
            Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                PrimaryButton(
                    text = if (npcState.isCheckingPayments) "Checking…" else "Check for paid quotes now",
                    onClick = { npcService.checkAndClaimPayments() },
                    enabled = npcState.isEnabled && !npcState.isCheckingPayments,
                    loading = npcState.isCheckingPayments,
                )
            }
        }
    }

    if (mintPickerOpen) {
        MintPickerSheet(
            mints = walletState.mints,
            activeMintUrl = npcState.selectedMintUrl ?: walletState.activeMint?.url,
            onSelect = { mint ->
                npcService.changeMint(mint.url)
                mintPickerOpen = false
            },
            onDismiss = { mintPickerOpen = false },
            title = "Mint for Lightning",
        )
    }
}
