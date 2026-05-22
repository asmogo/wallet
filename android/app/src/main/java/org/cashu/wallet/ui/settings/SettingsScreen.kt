package org.cashu.wallet.ui.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import org.cashu.wallet.BuildConfig
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.DestructiveTextButton
import org.cashu.wallet.ui.components.NavRow
import org.cashu.wallet.ui.components.SectionHeader

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    walletManager: WalletManager,
    onOpenBackup: () -> Unit,
    onOpenLightning: () -> Unit,
    onOpenP2PK: () -> Unit,
    onOpenNostr: () -> Unit,
    onOpenNWC: () -> Unit,
    onOpenPrivacy: () -> Unit,
    onOpenAppearance: () -> Unit,
    contentPadding: PaddingValues,
) {
    val context = LocalContext.current
    var confirmDelete by remember { mutableStateOf(false) }

    val topBarState = rememberTopAppBarState()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(state = topBarState)

    Scaffold(
        modifier = Modifier
            .padding(contentPadding)
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text("Settings", style = MaterialTheme.typography.headlineMedium) },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.largeTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    scrolledContainerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(bottom = 32.dp),
        ) {
            item("backup-header") { SectionHeader("Backup") }
            item("backup") { NavRow(title = "Backup & Restore", onClick = onOpenBackup) }

            item("payments-header") { SectionHeader("Payments") }
            item("lightning") {
                NavRow(title = "Lightning", subtitle = "Lightning address", onClick = onOpenLightning)
            }
            item("payments-divider") { CanvasDivider(leadingInset = 16) }
            item("p2pk") {
                NavRow(title = "P2PK", subtitle = "Lock ecash to a key", onClick = onOpenP2PK)
            }

            item("integrations-header") { SectionHeader("Integrations") }
            item("nostr") { NavRow(title = "Nostr", onClick = onOpenNostr) }
            item("integrations-divider") { CanvasDivider(leadingInset = 16) }
            item("nwc") {
                NavRow(title = "Nostr Wallet Connect", onClick = onOpenNWC)
            }

            item("privacy-header") { SectionHeader("Privacy & Display") }
            item("privacy") { NavRow(title = "Privacy", onClick = onOpenPrivacy) }
            item("privacy-divider") { CanvasDivider(leadingInset = 16) }
            item("appearance") { NavRow(title = "Appearance", onClick = onOpenAppearance) }

            item("about-header") { SectionHeader("About") }
            item("learn") {
                NavRow(
                    title = "Learn about Cashu",
                    onClick = { context.openExternal("https://cashu.space") },
                )
            }
            item("about-divider") { CanvasDivider(leadingInset = 16) }
            item("specs") {
                NavRow(
                    title = "Protocol Specs (NUTs)",
                    onClick = { context.openExternal("https://github.com/cashubtc/nuts") },
                )
            }

            item("danger-header") { SectionHeader("Danger") }
            item("delete") {
                Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                    DestructiveTextButton(
                        text = "Delete Wallet",
                        onClick = { confirmDelete = true },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            item("footer") {
                Spacer(Modifier.height(24.dp))
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(
                        text = "Cashu Wallet",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                    Text(
                        text = BuildConfig.VERSION_NAME,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete Wallet") },
            text = {
                Text(
                    "Are you sure? This action cannot be undone. Back up your seed phrase first.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    walletManager.launch { walletManager.deleteWallet() }
                }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
            },
        )
    }
}

private fun Context.openExternal(url: String) {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    startActivity(intent)
}
