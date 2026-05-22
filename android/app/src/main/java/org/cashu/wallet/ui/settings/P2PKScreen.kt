package org.cashu.wallet.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Models.P2PKKeyInfo
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.EmptyState
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.SectionHeader
import org.cashu.wallet.ui.components.ToggleRow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun P2PKScreen(
    settingsManager: SettingsManager,
    onClose: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
    val clipboard = LocalClipboardManager.current
    var showImport by remember { mutableStateOf(false) }
    var importError by remember { mutableStateOf<String?>(null) }
    var keyToRemove by remember { mutableStateOf<P2PKKeyInfo?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("P2PK", style = MaterialTheme.typography.titleMedium) },
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
        ) {
            SectionHeader("Your keys")
            if (settings.p2pkKeys.isEmpty()) {
                EmptyState(
                    icon = Icons.Outlined.ContentCopy,
                    title = "No P2PK keys yet",
                    supporting = "Generate a key to lock ecash you receive to it.",
                )
            } else {
                Column(modifier = Modifier.fillMaxWidth()) {
                    settings.p2pkKeys.forEachIndexed { index, key ->
                        P2PKRow(
                            key = key,
                            onCopy = { clipboard.setText(AnnotatedString(key.publicKey)) },
                            onDelete = { keyToRemove = key },
                        )
                        if (index != settings.p2pkKeys.lastIndex) CanvasDivider(leadingInset = 16)
                    }
                }
            }

            SectionHeader("Send flow")
            ToggleRow(
                title = "Quick access to lock",
                subtitle = "Show the P2PK lock button on the Send screen",
                checked = settings.showP2PKButtonInDrawer,
                onCheckedChange = settingsManager::setShowP2PKButtonInDrawer,
            )

            Spacer(Modifier.height(16.dp))
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                PrimaryButton(
                    text = "Generate new key",
                    onClick = {
                        runCatching { settingsManager.generateP2PKKey() }
                    },
                )
                PrimaryButton(
                    text = "Import key…",
                    onClick = { showImport = true },
                )
            }
        }
    }

    if (showImport) {
        var input by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = {
                showImport = false
                importError = null
            },
            title = { Text("Import P2PK key") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = input,
                        onValueChange = { input = it; importError = null },
                        label = { Text("nsec1…") },
                        modifier = Modifier.fillMaxWidth(),
                        shape = MaterialTheme.shapes.medium,
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                        ),
                        singleLine = true,
                    )
                    if (importError != null) {
                        Text(
                            text = importError!!,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    runCatching { settingsManager.importP2PKNsec(input.trim()) }
                        .onSuccess { showImport = false; importError = null }
                        .onFailure { importError = it.message ?: "Could not import key." }
                }) { Text("Import") }
            },
            dismissButton = {
                TextButton(onClick = { showImport = false; importError = null }) {
                    Text("Cancel")
                }
            },
        )
    }

    keyToRemove?.let { key ->
        AlertDialog(
            onDismissRequest = { keyToRemove = null },
            title = { Text("Remove key?") },
            text = {
                Text(
                    "Ecash locked to this key won't be redeemable without it.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    settingsManager.removeP2PKKey(key.id)
                    keyToRemove = null
                }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { keyToRemove = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun P2PKRow(
    key: P2PKKeyInfo,
    onCopy: () -> Unit,
    onDelete: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = Icons.Outlined.VpnKey,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(20.dp),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = key.label.ifBlank { "Untitled key" },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = key.publicKey,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
        }
        IconButton(onClick = onCopy) {
            Icon(
                imageVector = Icons.Outlined.ContentCopy,
                contentDescription = "Copy",
                modifier = Modifier.size(20.dp),
            )
        }
        IconButton(onClick = onDelete) {
            Icon(
                imageVector = Icons.Outlined.Delete,
                contentDescription = "Delete",
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}
