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
import org.cashu.wallet.Models.NwcConnection
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.EmptyState
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.SectionHeader

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NWCScreen(
    settingsManager: SettingsManager,
    onClose: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
    val clipboard = LocalClipboardManager.current
    var showCreate by remember { mutableStateOf(false) }
    var createError by remember { mutableStateOf<String?>(null) }
    var connectionToRemove by remember { mutableStateOf<NwcConnection?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Nostr Wallet Connect", style = MaterialTheme.typography.titleMedium) },
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
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            SectionHeader("Connections")
            if (settings.nwcConnections.isEmpty()) {
                EmptyState(
                    icon = Icons.Outlined.ContentCopy,
                    title = "No NWC connections",
                    supporting = "Generate a connection string to authorize a remote wallet client.",
                )
            } else {
                Column(modifier = Modifier.fillMaxWidth()) {
                    settings.nwcConnections.forEachIndexed { index, conn ->
                        ConnectionRow(
                            connection = conn,
                            onCopy = {
                                val str = settingsManager.nwcConnectionString(conn)
                                clipboard.setText(AnnotatedString(str))
                            },
                            onRemove = { connectionToRemove = conn },
                        )
                        if (index != settings.nwcConnections.lastIndex) CanvasDivider(leadingInset = 16)
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
            Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                PrimaryButton(
                    text = "New connection…",
                    onClick = { showCreate = true },
                )
            }
        }
    }

    if (showCreate) {
        var name by remember { mutableStateOf("") }
        var relay by remember { mutableStateOf("wss://relay.damus.io") }
        var allowance by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showCreate = false; createError = null },
            title = { Text("New NWC connection") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it; createError = null },
                        label = { Text("Nickname") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        shape = MaterialTheme.shapes.medium,
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                        ),
                    )
                    OutlinedTextField(
                        value = relay,
                        onValueChange = { relay = it },
                        label = { Text("Relay (wss://)") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        shape = MaterialTheme.shapes.medium,
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                        ),
                    )
                    OutlinedTextField(
                        value = allowance,
                        onValueChange = { allowance = it.filter { ch -> ch.isDigit() } },
                        label = { Text("Allowance (sats, optional)") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        shape = MaterialTheme.shapes.medium,
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                        ),
                    )
                    if (createError != null) {
                        Text(
                            text = createError!!,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    runCatching {
                        settingsManager.createNwcConnection(
                            name = name.ifBlank { "Connection" },
                            relay = relay,
                            allowanceSats = allowance.toLongOrNull(),
                        )
                    }
                        .onSuccess { showCreate = false; createError = null }
                        .onFailure { createError = it.message ?: "Could not create." }
                }) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { showCreate = false; createError = null }) { Text("Cancel") }
            },
        )
    }

    connectionToRemove?.let { conn ->
        AlertDialog(
            onDismissRequest = { connectionToRemove = null },
            title = { Text("Revoke ${conn.name}?") },
            text = {
                Text(
                    "The remote wallet client using this connection won't be able to send commands until you create a new one.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    settingsManager.removeNwcConnection(conn.id)
                    connectionToRemove = null
                }) {
                    Text("Revoke", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { connectionToRemove = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun ConnectionRow(
    connection: NwcConnection,
    onCopy: () -> Unit,
    onRemove: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = connection.name.ifBlank { "Connection" },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = connection.walletPublicKey,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
            connection.allowanceSats?.let {
                Text(
                    text = "Allowance: $it sat",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        IconButton(onClick = onCopy) {
            Icon(
                imageVector = Icons.Outlined.ContentCopy,
                contentDescription = "Copy connection string",
                modifier = Modifier.size(20.dp),
            )
        }
        IconButton(onClick = onRemove) {
            Icon(
                imageVector = Icons.Outlined.Delete,
                contentDescription = "Revoke",
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}
