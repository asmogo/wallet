package com.cashu.me.ui.settings

import android.content.ClipData
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.QrCode2
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import kotlinx.coroutines.launch
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.NwcManager
import com.cashu.me.Core.NwcState
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.WalletManager
import com.cashu.me.ui.components.CanvasDivider
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.MintPickerSheet
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.SettingsFooterText
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme

/** Settings and pairing surface for CDK's NIP-47 wallet service. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NwcSettingsScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    nwcManager: NwcManager,
    onClose: () -> Unit,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val nwcState by nwcManager.state.collectAsState()
    val clipboard = LocalClipboard.current
    val clipboardScope = rememberCoroutineScope()
    val amountFormatter = remember { AmountFormatter() }

    var mintPickerOpen by remember { mutableStateOf(false) }
    var budgetSheetOpen by remember { mutableStateOf(false) }
    var connectionQrOpen by remember { mutableStateOf(false) }
    var resetConfirmationOpen by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Wallet Connect", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        ToolbarIcon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            Text(
                text = "Connect a Nostr app to this wallet. Paired apps can check your balance, " +
                    "create invoices, and pay Lightning invoices with your ecash.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.default,
                ),
            )

            ToggleRow(
                title = "Enable Wallet Connect",
                subtitle = nwcStatusText(nwcState),
                checked = nwcState.isEnabled,
                onCheckedChange = { enabled ->
                    walletManager.launch {
                        nwcManager.setEnabled(
                            value = enabled,
                            defaultMintUrl = walletState.activeMint?.url ?: walletState.mints.firstOrNull()?.url,
                        )
                    }
                },
                enabled = !nwcState.isBusy && (walletState.mints.isNotEmpty() || nwcState.isEnabled),
            )

            when {
                walletState.mints.isEmpty() -> SettingsFooterText("Add a mint first to use Wallet Connect.")
                nwcState.errorMessage != null -> InlineNotice(
                    text = nwcState.errorMessage!!,
                    modifier = Modifier.padding(
                        horizontal = CashuTheme.spacing.comfortable,
                        vertical = CashuTheme.spacing.snug,
                    ),
                )
                !nwcState.isEnabled -> SettingsFooterText(
                    "Enabling creates a private connection code you can scan or paste into a Nostr app.",
                )
            }

            val connectionUri = nwcState.connectionUri
            if (nwcState.isEnabled && connectionUri != null) {
                SectionHeader("Connection")
                NwcConnectionRow(
                    uri = connectionUri,
                    isRunning = nwcState.isRunning,
                    onShowQr = { connectionQrOpen = true },
                    onCopy = {
                        clipboardScope.launch {
                            clipboard.setClipEntry(
                                ClipEntry(ClipData.newPlainText("Wallet Connect", connectionUri)),
                            )
                        }
                    },
                )
                SettingsFooterText(
                    "Keep this code private. Anyone with it can spend within your payment limit.",
                )

                SectionHeader("Spending")
                val selectedMintName = walletState.mints
                    .firstOrNull { it.url == nwcState.selectedMintUrl }
                    ?.name
                    ?: nwcState.selectedMintUrl
                    ?: "Select a mint"
                NavRow(
                    title = "Mint",
                    subtitle = selectedMintName,
                    enabled = walletState.mints.isNotEmpty(),
                    onClick = { mintPickerOpen = walletState.mints.isNotEmpty() },
                )
                CanvasDivider(leadingInset = CashuTheme.spacing.comfortable)
                NavRow(
                    title = "Payment limit",
                    subtitle = nwcState.budgetSats?.let {
                        "${amountFormatter.formatWalletSats(it, settings.useBitcoinSymbol)} per payment"
                    } ?: "No limit",
                    onClick = { budgetSheetOpen = true },
                )
                SettingsFooterText("Payments are sent as ecash from this mint over your Nostr relays.")

                Spacer(Modifier.height(CashuTheme.spacing.default))
                NavRow(
                    title = "Reset connection",
                    leadingIcon = Icons.Outlined.RestartAlt,
                    onClick = { resetConfirmationOpen = true },
                    enabled = !nwcState.isBusy,
                    tint = MaterialTheme.colorScheme.error,
                    showChevron = false,
                )
            }

            Spacer(Modifier.height(CashuTheme.spacing.section))
        }
    }

    if (mintPickerOpen) {
        MintPickerSheet(
            mints = walletState.mints,
            activeMintUrl = nwcState.selectedMintUrl,
            onSelect = { mint ->
                mintPickerOpen = false
                mint?.let { selected ->
                    walletManager.launch { nwcManager.setSelectedMintUrl(selected.url) }
                }
            },
            onDismiss = { mintPickerOpen = false },
            title = "Mint for Wallet Connect",
        )
    }

    if (budgetSheetOpen) {
        NwcBudgetSheet(
            currentBudget = nwcState.budgetSats,
            onSave = { budget ->
                budgetSheetOpen = false
                walletManager.launch { nwcManager.setBudgetSats(budget) }
            },
            onDismiss = { budgetSheetOpen = false },
        )
    }

    if (connectionQrOpen) {
        QrDetailSheet(
            title = "Wallet Connect",
            content = nwcState.connectionUri.orEmpty(),
            onDismiss = { connectionQrOpen = false },
        )
    }

    if (resetConfirmationOpen) {
        AlertDialog(
            onDismissRequest = { resetConfirmationOpen = false },
            title = { Text("Reset connection") },
            text = {
                Text(
                    "This creates a new connection code. Apps paired with the current code will stop working until you share the new code with them.",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    resetConfirmationOpen = false
                    walletManager.launch { nwcManager.regenerateConnection() }
                }) {
                    Text("Reset", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { resetConfirmationOpen = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun NwcConnectionRow(
    uri: String,
    isRunning: Boolean,
    onShowQr: () -> Unit,
    onCopy: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onShowQr)
            .semantics {
                contentDescription = if (isRunning) {
                    "Wallet Connect code. Connected."
                } else {
                    "Wallet Connect code. Connecting."
                }
            }
            .padding(
                horizontal = CashuTheme.spacing.comfortable,
                vertical = CashuTheme.spacing.default,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Box(
            modifier = Modifier
                .size(CashuTheme.spacing.snug)
                .clip(CircleShape)
                .background(if (isRunning) CashuTheme.colors.received else CashuTheme.colors.pending),
        )
        Text(
            text = uri,
            style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.MiddleEllipsis,
        )
        IconButton(onClick = onCopy) {
            Icon(Icons.Outlined.ContentCopy, contentDescription = "Copy connection code")
        }
        Icon(
            imageVector = Icons.Outlined.QrCode2,
            contentDescription = "Show QR code",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(CashuTheme.spacing.loose),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NwcBudgetSheet(
    currentBudget: Long?,
    onSave: (Long?) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember(currentBudget) { mutableStateOf(currentBudget?.toString().orEmpty()) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = CashuTheme.spacing.comfortable)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            Text("Payment limit", style = MaterialTheme.typography.titleMedium)
            Text(
                "Caps how much a single payment can spend. Leave empty for no limit.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            CashuTextField(
                value = text,
                onValueChange = { value ->
                    text = value.filter(Char::isDigit).take(12)
                },
                modifier = Modifier.fillMaxWidth(),
                label = "Sats per payment",
                placeholder = "No limit",
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
            )
            PrimaryButton(
                text = "Save",
                onClick = {
                    onSave(text.toLongOrNull()?.takeIf { it > 0 })
                },
            )
            Spacer(Modifier.height(CashuTheme.spacing.comfortable))
        }
    }
}

private fun nwcStatusText(state: NwcState): String = when {
    state.isBusy -> "Working…"
    state.isRunning -> "Connected"
    state.isEnabled -> "Starting…"
    else -> "Off"
}
