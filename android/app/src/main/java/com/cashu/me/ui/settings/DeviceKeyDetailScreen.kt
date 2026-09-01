package com.cashu.me.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.QrCode
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.SettingsManager
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.DestructiveTextButton
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.SettingsFooterText
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme

/**
 * One device-only key, with everything you can do to it laid out as plain rows —
 * copy, show QR, back up, rename, remove (iOS DeviceKeyDetailView). Resolves the
 * key live from settings so a rename updates in place; pops if it's removed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceKeyDetailScreen(
    settingsManager: SettingsManager,
    appLockManager: AppLockManager,
    keyId: String,
    onClose: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
    val key = settings.p2pkKeys.firstOrNull { it.id == keyId }

    var nameText by remember { mutableStateOf(key?.label.orEmpty()) }
    var activeQr by remember { mutableStateOf<String?>(null) }
    var showPrivateKeyBackup by remember { mutableStateOf(false) }
    var showRemoveConfirm by remember { mutableStateOf(false) }
    var showRepair by remember { mutableStateOf(false) }
    var actionError by remember { mutableStateOf<String?>(null) }

    // Pop when the key is removed underneath us (iOS onChange dismiss).
    LaunchedEffect(key == null) {
        if (key == null) onClose()
    }
    if (key == null) return

    val displayName = key.label.ifBlank { "Device key" }
    val isUsable = key.id !in settings.p2pkUnavailableKeyIds

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(displayName, style = MaterialTheme.typography.titleMedium) },
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
            Spacer(Modifier.height(CashuTheme.spacing.snug))
            KeyCard(
                title = displayName,
                pubkey = key.publicKey,
                status = if (isUsable) KeyCardStatus.DeviceOnly else KeyCardStatus.RepairRequired,
                actions = if (isUsable) {
                    listOf(
                        KeyCardAction("Show QR", Icons.Outlined.QrCode) {
                            activeQr = P2PKKeyDisplay.canonical(key.publicKey)
                        },
                        KeyCardAction("Back up key", Icons.Outlined.Key) {
                            showPrivateKeyBackup = true
                        },
                    )
                } else {
                    listOf(
                        KeyCardAction("Repair key", Icons.Outlined.FileDownload) {
                            actionError = null
                            showRepair = true
                        },
                    )
                },
                copyEnabled = isUsable,
                modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
            )

            if (!isUsable) {
                InlineNotice(
                    text = "This key's encrypted private key is unavailable. Import its nsec to " +
                        "repair it before sharing the public key or receiving locked ecash.",
                    modifier = Modifier.padding(
                        horizontal = CashuTheme.spacing.comfortable,
                        vertical = CashuTheme.spacing.snug,
                    ),
                    severity = NoticeSeverity.Error,
                )
            }

            actionError?.let { error ->
                InlineNotice(
                    text = error,
                    modifier = Modifier.padding(
                        horizontal = CashuTheme.spacing.comfortable,
                        vertical = CashuTheme.spacing.snug,
                    ),
                    severity = NoticeSeverity.Error,
                )
            }

            Spacer(Modifier.height(CashuTheme.spacing.default))
            SectionHeader("Name")
            CashuTextField(
                value = nameText,
                onValueChange = {
                    nameText = it
                    runCatching { settingsManager.setP2PKKeyNickname(key.id, it) }
                        .onFailure { error ->
                            actionError = error.message ?: "Could not rename the key."
                        }
                },
                label = "Add a name",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = CashuTheme.spacing.comfortable),
                singleLine = true,
            )

            Spacer(Modifier.height(CashuTheme.spacing.section))
            DestructiveTextButton(
                text = "Remove Key",
                onClick = { showRemoveConfirm = true },
                modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
            )
            SettingsFooterText(
                "Ecash locked to this key can only be claimed with it. Removing it can't be " +
                    "undone — back it up first if you might still receive to it.",
            )
            Spacer(Modifier.height(CashuTheme.spacing.section))
        }
    }

    activeQr?.let { content ->
        QrDetailSheet(title = "Key", content = content, onDismiss = { activeQr = null })
    }
    if (showPrivateKeyBackup) {
        PrivateKeyRevealSheet(
            title = "Back up key",
            loadNsec = {
                settingsManager.p2pkPrivateKeyHex(key.id)
                    ?.let(P2PKKeyDisplay::nsec)
            },
            appLockManager = appLockManager,
            onDismiss = { showPrivateKeyBackup = false },
        )
    }
    if (showRepair) {
        ImportP2PKSheet(
            onImport = { nsec -> runCatching { settingsManager.importP2PKNsec(nsec) } },
            onDismiss = { showRepair = false },
        )
    }
    if (showRemoveConfirm) {
        AlertDialog(
            onDismissRequest = { showRemoveConfirm = false },
            title = { Text("Remove this key?") },
            text = {
                Text(
                    "Ecash locked to this key can only be claimed with it. This can't be undone.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showRemoveConfirm = false
                    actionError = null
                    runCatching { settingsManager.removeP2PKKey(key.id) }
                        .onFailure { error ->
                            actionError = error.message ?: "Could not remove the key."
                        }
                }) {
                    Text("Remove Key", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showRemoveConfirm = false }) { Text("Cancel") }
            },
        )
    }
}
