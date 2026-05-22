package org.cashu.wallet.Views.Settings

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.AmountDisplayPrimary
import org.cashu.wallet.Core.NostrService
import org.cashu.wallet.Core.NostrSignerType
import org.cashu.wallet.Core.NPCService
import org.cashu.wallet.Core.Platform.ConnectivityState
import org.cashu.wallet.Core.PriceService
import org.cashu.wallet.Core.PriceState
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.NwcConnection
import org.cashu.wallet.Models.P2PKKeyInfo
import org.cashu.wallet.Views.Components.KeyValueRow
import org.cashu.wallet.Views.Components.QRCodeView
import org.cashu.wallet.Views.Components.QuietCard
import org.cashu.wallet.Views.Components.SectionHeader
import org.cashu.wallet.Views.Components.SecondaryActionButton

@Composable
fun SettingsView(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    nostrService: NostrService,
    priceService: PriceService,
    npcService: NPCService,
    connectivityState: ConnectivityState,
    onRefreshConnectivity: () -> Unit,
    onOpenMints: () -> Unit,
    contentPadding: PaddingValues,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val nostrState by nostrService.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val npcState by npcService.state.collectAsState()
    val selectedAmountPrimary = AmountDisplayPrimary.fromRaw(settings.amountDisplayPrimary)
    val context = LocalContext.current
    var showDeleteDialog by remember { mutableStateOf(false) }
    var showBackupDialog by remember { mutableStateOf(false) }
    var backupSeedPhrase by remember { mutableStateOf<String?>(null) }
    var qrDialogTitle by remember { mutableStateOf<String?>(null) }
    var qrDialogContent by remember { mutableStateOf<String?>(null) }
    var showNsec by remember { mutableStateOf(false) }
    var showGenerateKeyDialog by remember { mutableStateOf(false) }
    var showResetKeyDialog by remember { mutableStateOf(false) }
    var nsecInput by remember { mutableStateOf("") }
    var nostrKeyError by remember { mutableStateOf<String?>(null) }
    var nwcError by remember { mutableStateOf<String?>(null) }
    var p2pkImportText by remember { mutableStateOf("") }
    var p2pkError by remember { mutableStateOf<String?>(null) }
    var relayInput by remember { mutableStateOf("") }
    var relayError by remember { mutableStateOf<String?>(null) }
    var copiedValue by remember { mutableStateOf<String?>(null) }
    var walletActionError by remember { mutableStateOf<String?>(null) }

    fun copyValue(label: String, value: String) {
        if (value.isBlank()) return
        context.copySettingsValue(label, value)
        copiedValue = label
    }

    fun runNostrAction(action: () -> Unit) {
        nostrKeyError = null
        runCatching(action).onFailure { error ->
            nostrKeyError = error.message ?: "Nostr key operation failed."
        }
    }

    fun selectSignerType(type: NostrSignerType) {
        if (nostrState.signerType == type) return
        if (type == NostrSignerType.PrivateKey && !nostrService.hasCustomPrivateKey()) {
            showGenerateKeyDialog = true
            return
        }
        runNostrAction { nostrService.switchSignerType(type) }
    }

    fun importNsec() {
        val trimmed = nsecInput.trim()
        if (trimmed.isEmpty()) {
            nostrKeyError = "Please enter an nsec."
            return
        }
        runNostrAction {
            nostrService.importNsec(trimmed)
            nsecInput = ""
        }
    }

    fun addRelay() {
        relayError = null
        val trimmed = relayInput.trim()
        if (trimmed.isEmpty()) return
        val lower = trimmed.lowercase()
        if (!lower.startsWith("wss://") && !lower.startsWith("ws://")) {
            relayError = "Relay URL must start with ws:// or wss://."
            return
        }
        if (settings.nostrRelays.any { it.equals(trimmed, ignoreCase = true) }) {
            relayError = "Relay already added."
            return
        }
        settingsManager.addRelay(trimmed)
        relayInput = ""
    }

    fun importP2PKNsec() {
        val trimmed = p2pkImportText.trim()
        if (trimmed.isEmpty()) {
            p2pkError = "Please enter an nsec."
            return
        }
        p2pkError = null
        runCatching {
            settingsManager.importP2PKNsec(trimmed)
            p2pkImportText = ""
        }.onFailure { error ->
            p2pkError = error.message ?: "Failed to import P2PK key."
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Settings", style = MaterialTheme.typography.headlineSmall)
        SectionHeader("Backup")
        QuietCard {
            SettingsActionButton(
                text = "Backup seed phrase",
                icon = Icons.Default.ContentCopy,
                onClick = {
                    backupSeedPhrase = walletManager.backupMnemonic()
                    showBackupDialog = true
                },
            )
            SettingsActionButton(
                text = "Restore ecash",
                icon = Icons.Default.Refresh,
                onClick = { walletManager.openRestoreFlow() },
            )
        }
        SectionHeader("Mints")
        SecondaryActionButton("Manage mints", onClick = onOpenMints)
        SectionHeader("Display")
        QuietCard {
            ToggleRow("Use ₿ symbol", settings.useBitcoinSymbol) { settingsManager.setUseBitcoinSymbol(it) }
            ToggleRow("Get exchange rate from Coinbase", settings.showFiatBalance) {
                settingsManager.setShowFiatBalance(it)
                priceService.syncFromSettings(refresh = it)
            }
            if (settings.showFiatBalance) {
                CurrencyDropdown(
                    selected = settings.bitcoinPriceCurrency,
                    onSelect = {
                        settingsManager.setBitcoinPriceCurrency(it)
                        priceService.syncFromSettings(refresh = true)
                    },
                )
                PriceStatusRow(
                    priceState = priceState,
                    onRefresh = { priceService.refresh() },
                )
                Text(
                    text = "Primary amount",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.secondary,
                )
                AmountPrimaryRow(
                    primary = AmountDisplayPrimary.Fiat,
                    selected = selectedAmountPrimary == AmountDisplayPrimary.Fiat,
                    onSelect = { settingsManager.setAmountDisplayPrimary(AmountDisplayPrimary.Fiat.rawValue) },
                )
                AmountPrimaryRow(
                    primary = AmountDisplayPrimary.Sats,
                    selected = selectedAmountPrimary == AmountDisplayPrimary.Sats,
                    onSelect = { settingsManager.setAmountDisplayPrimary(AmountDisplayPrimary.Sats.rawValue) },
                )
            }
        }
        SectionHeader("Privacy")
        QuietCard {
            ToggleRow("Check incoming invoice", settings.checkIncomingInvoices) {
                settingsManager.setCheckIncomingInvoices(it)
            }
            ToggleRow("Check pending invoices on startup", settings.checkPendingOnStartup) {
                settingsManager.setCheckPendingOnStartup(it)
            }
            ToggleRow(
                label = "Check all invoices",
                checked = settings.periodicallyCheckIncomingInvoices,
                enabled = settings.checkIncomingInvoices,
            ) {
                settingsManager.setPeriodicallyCheckIncomingInvoices(it)
            }
            ToggleRow("Check sent ecash", settings.checkSentTokens) { settingsManager.setCheckSentTokens(it) }
            ToggleRow(
                label = "Use WebSockets",
                checked = settings.useWebsockets,
                enabled = settings.checkIncomingInvoices || settings.checkSentTokens,
            ) {
                settingsManager.setUseWebsockets(it)
            }
            ToggleRow("Paste ecash automatically", settings.autoPasteEcashReceive) {
                settingsManager.setAutoPasteEcashReceive(it)
            }
        }
        SectionHeader("Connectivity")
        QuietCard {
            KeyValueRow("Network", connectivityState.displayText)
            connectivityState.isMetered?.let { KeyValueRow("Metered", if (it) "Yes" else "No") }
            SettingsActionButton(
                text = "Refresh network status",
                icon = Icons.Default.Refresh,
                onClick = onRefreshConnectivity,
            )
        }
        SectionHeader("Lightning")
        QuietCard {
            ToggleRow("Enable Lightning Address", npcState.isEnabled) {
                npcService.setEnabled(it)
            }
            if (npcState.isEnabled) {
                if (npcState.isInitialized) {
                    NostrValueRow(
                        label = "Lightning address",
                        value = npcState.lightningAddress,
                        copied = copiedValue == "Lightning address",
                        onCopy = { copyValue("Lightning address", npcState.lightningAddress) },
                    )
                    ToggleRow("Auto-claim payments", npcState.automaticClaim) {
                        npcService.setAutomaticClaim(it)
                    }
                    if (walletState.mints.isNotEmpty()) {
                        MintDropdown(
                            mints = walletState.mints,
                            selectedMintUrl = npcState.selectedMintUrl,
                            onSelect = { npcService.changeMint(it) },
                        )
                    }
                    SettingsActionButton(
                        text = if (npcState.isCheckingPayments) "Checking..." else "Check for payments",
                        icon = Icons.Default.Refresh,
                        enabled = !npcState.isCheckingPayments,
                        onClick = { npcService.checkAndClaimPayments() },
                    )
                    KeyValueRow(
                        "Status",
                        when {
                            npcState.isConnected -> "Connected"
                            npcState.isLoading -> "Connecting"
                            else -> "Not connected"
                        },
                    )
                    npcState.lastCheckEpochMillis?.let {
                        KeyValueRow("Last check", formatRelativeTime(it))
                    }
                    if (npcState.pendingPaidQuotes.isNotEmpty()) {
                        KeyValueRow("Pending paid quotes", npcState.pendingPaidQuotes.size.toString())
                    }
                    npcState.errorMessage?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                    }
                } else {
                    Text(
                        text = "Nostr keys are not initialized.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.secondary,
                    )
                }
            }
        }
        SectionHeader("P2PK")
        QuietCard {
            SettingsActionButton(
                text = "Generate key",
                icon = Icons.Default.AddCircle,
                onClick = {
                    p2pkError = null
                    if (!settingsManager.generateP2PKKey()) {
                        p2pkError = "Failed to generate P2PK key."
                    }
                },
            )
            OutlinedTextField(
                value = p2pkImportText,
                onValueChange = { p2pkImportText = it },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text("Import P2PK nsec") },
                textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                trailingIcon = {
                    IconButton(
                        onClick = ::importP2PKNsec,
                        enabled = p2pkImportText.trim().isNotEmpty(),
                    ) {
                        Icon(Icons.Default.Upload, contentDescription = "Import P2PK nsec")
                    }
                },
            )
            ToggleRow("Quick access to lock", settings.showP2PKButtonInDrawer) {
                settingsManager.setShowP2PKButtonInDrawer(it)
            }
            if (settings.p2pkKeys.isEmpty()) {
                Text(
                    text = "No P2PK keys.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.secondary,
                )
            } else {
                settings.p2pkKeys.forEach { key ->
                    P2PKKeyRow(
                        key = key,
                        copied = copiedValue == key.publicKey,
                        onCopy = { copyValue(key.publicKey, key.publicKey) },
                        onShowQr = {
                            qrDialogTitle = "P2PK Public Key"
                            qrDialogContent = key.publicKey
                        },
                        onRemove = { settingsManager.removeP2PKKey(key.id) },
                    )
                }
            }
            p2pkError?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
        SectionHeader("Nostr")
        QuietCard {
            KeyValueRow("Signer", nostrState.signerType.displayName)
            SignerOptionRow(
                type = NostrSignerType.Seed,
                selected = nostrState.signerType == NostrSignerType.Seed,
                onSelect = { selectSignerType(NostrSignerType.Seed) },
            )
            SignerOptionRow(
                type = NostrSignerType.PrivateKey,
                selected = nostrState.signerType == NostrSignerType.PrivateKey,
                onSelect = { selectSignerType(NostrSignerType.PrivateKey) },
            )

            if (nostrState.isInitialized) {
                NostrValueRow(
                    label = "Public key",
                    value = nostrState.npub,
                    copied = copiedValue == "npub",
                    onCopy = { copyValue("npub", nostrState.npub) },
                )
                NostrSecretRow(
                    label = "Private key",
                    value = nostrState.nsec,
                    revealed = showNsec,
                    copied = copiedValue == "nsec",
                    onToggleReveal = { showNsec = !showNsec },
                    onCopy = { copyValue("nsec", nostrState.nsec) },
                )
            } else {
                Text(
                    text = "Nostr keys are not initialized yet.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.secondary,
                )
            }

            SettingsActionButton(
                text = "Generate custom key",
                icon = Icons.Default.Refresh,
                onClick = { showGenerateKeyDialog = true },
            )
            OutlinedTextField(
                value = nsecInput,
                onValueChange = { nsecInput = it },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text("Import nsec") },
                textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                trailingIcon = {
                    IconButton(
                        onClick = ::importNsec,
                        enabled = nsecInput.trim().isNotEmpty(),
                    ) {
                        Icon(Icons.Default.Upload, contentDescription = "Import nsec")
                    }
                },
            )
            if (nostrState.signerType == NostrSignerType.PrivateKey) {
                SettingsActionButton(
                    text = "Reset to wallet seed",
                    icon = Icons.Default.Refresh,
                    onClick = { showResetKeyDialog = true },
                )
            }
            nostrKeyError?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
        SectionHeader("Nostr relays")
        QuietCard {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = relayInput,
                    onValueChange = { relayInput = it },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    label = { Text("Relay URL") },
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                )
                IconButton(
                    onClick = ::addRelay,
                    enabled = relayInput.trim().isNotEmpty(),
                ) {
                    Icon(Icons.Default.AddCircle, contentDescription = "Add relay")
                }
            }
            settings.nostrRelays.forEach { relay ->
                RelayRow(
                    relay = relay,
                    copied = copiedValue == relay,
                    onCopy = { copyValue(relay, relay) },
                    onRemove = { settingsManager.removeRelay(relay) },
                )
            }
            relayError?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
            SecondaryActionButton("Reset default relays") {
                settingsManager.resetNostrRelaysToDefault()
                relayError = null
            }
        }
        SectionHeader("Nostr Wallet Connect")
        QuietCard {
            ToggleRow("Enable NWC", settings.enableNWC) {
                nwcError = null
                settingsManager.setEnableNWC(it)
            }
            if (settings.enableNWC) {
                Text(
                    text = "Payments use the Bitcoin balance on the active mint.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.secondary,
                )
                SettingsActionButton(
                    text = if (settings.nwcConnections.isEmpty()) "Create connection" else "Ensure connection",
                    icon = Icons.Default.AddCircle,
                    onClick = {
                        nwcError = null
                        runCatching {
                            settingsManager.createNwcConnection(
                                name = "Wallet connection",
                                relay = "",
                                allowanceSats = 1_000,
                            )
                        }.onFailure { error ->
                            nwcError = error.message ?: "Unable to create an NWC connection."
                        }
                    },
                )
                settings.nwcConnections.forEach { connection ->
                    NwcConnectionRow(
                        connection = connection,
                        connectionString = settingsManager.nwcConnectionString(connection),
                        copied = copiedValue == connection.id,
                        onCopy = { copyValue(connection.id, settingsManager.nwcConnectionString(connection)) },
                        onShowQr = {
                            qrDialogTitle = "NWC Connection"
                            qrDialogContent = settingsManager.nwcConnectionString(connection)
                        },
                        onRemove = { settingsManager.removeNwcConnection(connection.id) },
                        onAllowanceChanged = { settingsManager.updateNwcAllowance(connection.id, it) },
                    )
                }
                nwcError?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
            }
        }
        SectionHeader("Advanced")
        QuietCard {
            SettingsActionButton(
                text = "Delete wallet",
                icon = Icons.Default.Delete,
                destructive = true,
                onClick = {
                    walletActionError = null
                    showDeleteDialog = true
                },
            )
            walletActionError?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }

    if (showGenerateKeyDialog) {
        AlertDialog(
            onDismissRequest = { showGenerateKeyDialog = false },
            title = { Text("Generate new key?") },
            text = { Text("This creates a new random Nostr key and changes the Lightning address derived from it.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showGenerateKeyDialog = false
                        runNostrAction { nostrService.generateRandomKeypair() }
                    },
                ) { Text("Generate") }
            },
            dismissButton = {
                TextButton(onClick = { showGenerateKeyDialog = false }) { Text("Cancel") }
            },
        )
    }

    if (showResetKeyDialog) {
        AlertDialog(
            onDismissRequest = { showResetKeyDialog = false },
            title = { Text("Reset to wallet seed?") },
            text = { Text("This deletes the custom Nostr key and switches back to the key derived from the wallet seed.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showResetKeyDialog = false
                        runNostrAction { nostrService.resetToSeedKey() }
                    },
                ) { Text("Reset") }
            },
            dismissButton = {
                TextButton(onClick = { showResetKeyDialog = false }) { Text("Cancel") }
            },
        )
    }

    if (showBackupDialog) {
        AlertDialog(
            onDismissRequest = { showBackupDialog = false },
            title = { Text("Seed phrase") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        text = "Keep this phrase private. Anyone with it can restore this wallet.",
                        color = MaterialTheme.colorScheme.error,
                    )
                    SelectionContainer {
                        Text(
                            text = backupSeedPhrase ?: "No seed phrase is available.",
                            style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = backupSeedPhrase != null,
                    onClick = { backupSeedPhrase?.let { copyValue("Seed phrase", it) } },
                ) { Text("Copy") }
            },
            dismissButton = {
                TextButton(onClick = { showBackupDialog = false }) { Text("Close") }
            },
        )
    }

    if (qrDialogContent != null) {
        AlertDialog(
            onDismissRequest = {
                qrDialogTitle = null
                qrDialogContent = null
            },
            title = { Text(qrDialogTitle ?: "QR Code") },
            text = { QRCodeView(content = qrDialogContent.orEmpty(), showControls = false) },
            confirmButton = {
                TextButton(
                    onClick = {
                        qrDialogTitle = null
                        qrDialogContent = null
                    },
                ) { Text("Close") }
            },
        )
    }

    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text("Delete wallet?") },
            text = { Text("This removes the local wallet, secrets, app state, and wallet database from this Android install.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteDialog = false
                        walletActionError = null
                        walletManager.launch {
                            runCatching { walletManager.deleteWallet() }
                                .onFailure { walletActionError = it.message ?: "Unable to delete wallet." }
                        }
                    },
                ) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun NwcConnectionRow(
    connection: NwcConnection,
    connectionString: String,
    copied: Boolean,
    onCopy: () -> Unit,
    onShowQr: () -> Unit,
    onRemove: () -> Unit,
    onAllowanceChanged: (Long) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("Connection", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.secondary)
                Text(
                    text = connectionString,
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            IconButton(onClick = onCopy) {
                Icon(
                    imageVector = Icons.Default.ContentCopy,
                    contentDescription = if (copied) "NWC connection copied" else "Copy NWC connection",
                    tint = if (copied) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                )
            }
            IconButton(onClick = onShowQr) {
                Icon(
                    imageVector = Icons.Default.QrCode,
                    contentDescription = "Show NWC connection QR",
                )
            }
            IconButton(onClick = onRemove) {
                Icon(
                    imageVector = Icons.Default.Delete,
                    contentDescription = "Remove NWC connection",
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
        OutlinedTextField(
            value = (connection.allowanceSats ?: 0).toString(),
            onValueChange = { value ->
                val amount = value.filter(Char::isDigit).toLongOrNull() ?: 0L
                onAllowanceChanged(amount)
            },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            label = { Text("Allowance left (sat)") },
            textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        )
    }
}

@Composable
private fun P2PKKeyRow(
    key: P2PKKeyInfo,
    copied: Boolean,
    onCopy: () -> Unit,
    onShowQr: () -> Unit,
    onRemove: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = key.publicKey,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (key.used) {
                Text(
                    text = "used ${key.usedCount}x",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.secondary,
                )
            }
        }
        IconButton(onClick = onCopy) {
            Icon(
                imageVector = Icons.Default.ContentCopy,
                contentDescription = if (copied) "P2PK key copied" else "Copy P2PK key",
                tint = if (copied) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
            )
        }
        IconButton(onClick = onShowQr) {
            Icon(
                imageVector = Icons.Default.QrCode,
                contentDescription = "Show P2PK key QR",
            )
        }
        IconButton(onClick = onRemove) {
            Icon(
                imageVector = Icons.Default.Delete,
                contentDescription = "Remove P2PK key",
                tint = MaterialTheme.colorScheme.error,
            )
        }
    }
}

@Composable
private fun MintDropdown(
    mints: List<MintInfo>,
    selectedMintUrl: String?,
    onSelect: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedMint = mints.firstOrNull { it.url == selectedMintUrl }
    Box(modifier = Modifier.fillMaxWidth()) {
        OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
            Text("Receiving mint")
            Spacer(Modifier.weight(1f))
            Text(
                text = selectedMint?.name ?: "Select",
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Icon(Icons.Default.ArrowDropDown, contentDescription = null)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            mints.forEach { mint ->
                DropdownMenuItem(
                    text = {
                        Column {
                            Text(mint.name)
                            Text(
                                mint.url,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.secondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    },
                    onClick = {
                        expanded = false
                        onSelect(mint.url)
                    },
                )
            }
        }
    }
}

@Composable
private fun CurrencyDropdown(selected: String, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box(modifier = Modifier.fillMaxWidth()) {
        OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
            Text("Fiat currency")
            Spacer(Modifier.weight(1f))
            Text(selected, fontWeight = FontWeight.Medium)
            Icon(Icons.Default.ArrowDropDown, contentDescription = null)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            SettingsManager.supportedFiatCurrencies.forEach { currency ->
                DropdownMenuItem(
                    text = { Text(currency) },
                    onClick = {
                        expanded = false
                        onSelect(currency)
                    },
                )
            }
        }
    }
}

@Composable
private fun PriceStatusRow(priceState: PriceState, onRefresh: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "BTC Price (${priceState.currencyCode})",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.secondary,
                )
                Text(
                    text = if (priceState.btcPrice > 0) {
                        formatBTCPrice(priceState.btcPrice, priceState.currencyCode)
                    } else {
                        "Loading..."
                    },
                    fontWeight = FontWeight.Medium,
                )
            }
            IconButton(onClick = onRefresh, enabled = !priceState.isFetching && priceState.isEnabled) {
                if (priceState.isFetching) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.Default.Refresh, contentDescription = "Refresh BTC price")
                }
            }
        }
        priceState.lastUpdatedEpochMillis?.let {
            Text(
                text = "Updated ${formatRelativeTime(it)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.secondary,
            )
        }
        priceState.errorMessage?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
    }
}

@Composable
private fun AmountPrimaryRow(
    primary: AmountDisplayPrimary,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onSelect)
        Text(primary.label, modifier = Modifier.padding(start = 8.dp), fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun SignerOptionRow(type: NostrSignerType, selected: Boolean, onSelect: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onSelect)
        Column(modifier = Modifier.padding(start = 8.dp)) {
            Text(type.displayName, fontWeight = FontWeight.Medium)
            Text(
                text = when (type) {
                    NostrSignerType.Seed -> "Use the wallet seed-derived Nostr key"
                    NostrSignerType.PrivateKey -> "Use a custom Nostr private key"
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.secondary,
            )
        }
    }
}

@Composable
private fun NostrValueRow(label: String, value: String, copied: Boolean, onCopy: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.secondary)
            Text(
                text = value,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(onClick = onCopy) {
            Icon(
                imageVector = Icons.Default.ContentCopy,
                contentDescription = if (copied) "$label copied" else "Copy $label",
                tint = if (copied) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun NostrSecretRow(
    label: String,
    value: String,
    revealed: Boolean,
    copied: Boolean,
    onToggleReveal: () -> Unit,
    onCopy: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.secondary)
            Text(
                text = if (revealed) value else "*".repeat(20),
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                color = if (revealed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.secondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(onClick = onToggleReveal) {
            Icon(
                imageVector = if (revealed) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                contentDescription = if (revealed) "Hide $label" else "Show $label",
            )
        }
        IconButton(onClick = onCopy) {
            Icon(
                imageVector = Icons.Default.ContentCopy,
                contentDescription = if (copied) "$label copied" else "Copy $label",
                tint = if (copied) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun RelayRow(relay: String, copied: Boolean, onCopy: () -> Unit, onRemove: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = relay,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        IconButton(onClick = onCopy) {
            Icon(
                imageVector = Icons.Default.ContentCopy,
                contentDescription = if (copied) "Relay copied" else "Copy relay",
                tint = if (copied) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
            )
        }
        IconButton(onClick = onRemove) {
            Icon(
                imageVector = Icons.Default.Delete,
                contentDescription = "Remove relay",
                tint = MaterialTheme.colorScheme.error,
            )
        }
    }
}

@Composable
private fun SettingsActionButton(
    text: String,
    icon: ImageVector,
    enabled: Boolean = true,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    OutlinedButton(onClick = onClick, enabled = enabled, modifier = Modifier.fillMaxWidth()) {
        val contentColor = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
        Icon(icon, contentDescription = null, tint = contentColor)
        Spacer(Modifier.width(8.dp))
        Text(text, color = contentColor)
    }
}

@Composable
private fun ToggleRow(
    label: String,
    checked: Boolean,
    enabled: Boolean = true,
    onCheckedChange: (Boolean) -> Unit,
) {
    androidx.compose.foundation.layout.Row(
        horizontalArrangement = Arrangement.SpaceBetween,
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            modifier = Modifier.weight(1f),
            color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.secondary,
        )
        Switch(checked = checked, enabled = enabled, onCheckedChange = onCheckedChange)
    }
}

private fun Context.copySettingsValue(label: String, value: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, value))
    Toast.makeText(this, "$label copied", Toast.LENGTH_SHORT).show()
}

private fun formatBTCPrice(price: Double, currencyCode: String): String {
    val formatter = NumberFormat.getCurrencyInstance(Locale.getDefault())
    runCatching { formatter.currency = Currency.getInstance(currencyCode) }
    formatter.maximumFractionDigits = 0
    return formatter.format(price)
}

private fun formatRelativeTime(epochMillis: Long): String {
    val elapsedSeconds = ((System.currentTimeMillis() - epochMillis) / 1000).coerceAtLeast(0)
    return when {
        elapsedSeconds < 60 -> "just now"
        elapsedSeconds < 3_600 -> "${elapsedSeconds / 60}m ago"
        elapsedSeconds < 86_400 -> "${elapsedSeconds / 3_600}h ago"
        else -> "${elapsedSeconds / 86_400}d ago"
    }
}
