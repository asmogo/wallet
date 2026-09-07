package com.cashu.me.ui.settings

import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import com.cashu.me.Core.Wallet.ActionErrorMessages

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.Restore
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import kotlinx.coroutines.launch
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.NostrMintBackupService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.WalletManager
import com.cashu.me.ui.components.InlineNoticeHost
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.formatRelativeTimestamp
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme

/**
 * Settings → Backup & Restore (iOS BackupSettingsSection): seed-phrase backup,
 * the restore wizard behind one root row, and the encrypted NUT-27 mint-list
 * backup on Nostr (iOS NostrMintBackupSettingsSection).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupRestoreScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    nostrMintBackupService: NostrMintBackupService,
    appLockManager: AppLockManager,
    onClose: () -> Unit,
    onOpenRestore: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val settings by settingsManager.state.collectAsState()
    val walletState by walletManager.state.collectAsState()
    val backupState by nostrMintBackupService.state.collectAsState()

    var showBackupSheet by remember { mutableStateOf(false) }
    var backupError by remember { mutableStateOf<String?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Backup & Restore", style = MaterialTheme.typography.titleMedium) },
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
            NavRow(
                title = "Backup seed phrase",
                subtitle = "View and copy your 12 recovery words.",
                leadingIcon = Icons.Outlined.VpnKey,
                onClick = { showBackupSheet = true },
            )
            NavRow(
                title = "Restore",
                subtitle = "Restore a wallet and recover funds from mints.",
                leadingIcon = Icons.Outlined.Restore,
                onClick = onOpenRestore,
            )

            SectionHeader("Mint backup")
            ToggleRow(
                title = "Automatic mint backup",
                subtitle = "Publish after every mint change.",
                checked = settings.nostrMintBackupEnabled,
                onCheckedChange = settingsManager::setNostrMintBackupEnabled,
            )
            NavRow(
                title = if (backupState.isBackingUp) "Backing up…" else "Back up now",
                leadingIcon = Icons.Outlined.CloudUpload,
                enabled = !backupState.isBackingUp && walletState.mints.isNotEmpty(),
                showChevron = false,
                trailingIcon = null,
                onClick = {
                    backupError = null
                    scope.launch {
                        runCatching { nostrMintBackupService.backupMints() }
                            .onFailure { backupError = ActionErrorMessages.message(it, ActionErrorMessages.Context.MintBackup) }
                    }
                },
            )
            InlineNoticeHost(
                text = backupError,
                modifier = Modifier.padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.tight,
                ),
                severity = NoticeSeverity.Error,
            )
            Text(
                text = mintBackupFooter(
                    hasMints = walletState.mints.isNotEmpty(),
                    lastBackupEpochMillis = backupState.lastBackupDateEpochMillis,
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.tight,
                ),
            )
        }
    }

    if (showBackupSheet) {
        BackupSeedSheet(
            walletManager = walletManager,
            appLockManager = appLockManager,
            onDismiss = { showBackupSheet = false },
        )
    }
}

/** iOS NostrMintBackupSettingsSection.footerText. */
private fun mintBackupFooter(hasMints: Boolean, lastBackupEpochMillis: Long?): String = when {
    !hasMints ->
        "Add a mint to back up. The list is encrypted to your seed and published to your relays."
    lastBackupEpochMillis != null ->
        "Your mint list is encrypted to your seed and published to your relays. " +
            "Last backup ${formatRelativeTimestamp(lastBackupEpochMillis)}."
    else ->
        "Your mint list is encrypted to your seed and published to your relays, " +
            "so restoring from seed can find your mints."
}
