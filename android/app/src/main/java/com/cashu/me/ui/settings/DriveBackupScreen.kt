package com.cashu.me.ui.settings

import android.app.Activity
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.PhonelinkSetup
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.DriveAvailability
import com.cashu.me.Core.DriveBackupOutcome
import com.cashu.me.Core.DriveConsentLauncher
import com.cashu.me.Core.GoogleDriveBackupService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.ui.components.InlineNoticeHost
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.components.formatRelativeTimestamp
import com.cashu.me.ui.security.rememberWalletAuthenticationLauncher
import com.cashu.me.ui.testing.UiTestTags
import com.cashu.me.ui.theme.CashuTheme

/**
 * Settings → Backup & Restore → Google Drive Backup (iOS
 * ICloudBackupSettingsView). One toggle drives both storage legs: the Drive
 * appDataFolder file and the Block Store device-transfer copy. Copy is honest
 * about the trust model — Drive is encrypted at rest by Google, NOT
 * end-to-end; only the Block Store leg is E2E (and only with a screen lock).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DriveBackupScreen(
    googleDriveBackupService: GoogleDriveBackupService,
    settingsManager: SettingsManager,
    appLockManager: AppLockManager,
    onClose: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val settings by settingsManager.state.collectAsState()
    val backupState by googleDriveBackupService.state.collectAsState()
    val authenticate = rememberWalletAuthenticationLauncher(appLockManager)

    var confirmEnable by remember { mutableStateOf(false) }
    var confirmDisable by remember { mutableStateOf(false) }
    var backupError by remember { mutableStateOf<String?>(null) }
    var justBackedUp by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { googleDriveBackupService.refreshAvailability() }

    LaunchedEffect(justBackedUp) {
        if (justBackedUp) {
            delay(3_000)
            justBackedUp = false
        }
    }

    // Bridges the Authorization consent PendingIntent into the suspended
    // service call: launch the sheet, resume with the result intent.
    val pendingConsent = remember { mutableStateOf<CompletableDeferred<Intent?>?>(null) }
    val consentLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult(),
    ) { result ->
        pendingConsent.value?.complete(
            if (result.resultCode == Activity.RESULT_OK) result.data else null,
        )
        pendingConsent.value = null
    }
    val launchResolution: DriveConsentLauncher = { consent ->
        val deferred = CompletableDeferred<Intent?>()
        pendingConsent.value = deferred
        consentLauncher.launch(
            IntentSenderRequest.Builder(consent.pendingIntent().intentSender).build(),
        )
        deferred.await()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Google Drive Backup", style = MaterialTheme.typography.titleMedium) },
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
                .verticalScroll(rememberScrollState())
                .testTag(UiTestTags.DriveBackupScreen),
        ) {
            SectionHeader("What's backed up")
            NavRow(
                title = "Seed phrase",
                subtitle = "Google Drive · Encrypted at rest by Google",
                leadingIcon = Icons.Outlined.VpnKey,
                onClick = {},
                enabled = false,
                showChevron = false,
            )
            NavRow(
                title = "Mint list",
                subtitle = "Google Drive · Encrypted at rest by Google",
                leadingIcon = Icons.Outlined.AccountBalance,
                onClick = {},
                enabled = false,
                showChevron = false,
            )
            NavRow(
                title = "Device transfer copy",
                subtitle = "Block Store · End-to-end encrypted when your device has a screen lock",
                leadingIcon = Icons.Outlined.PhonelinkSetup,
                onClick = {},
                enabled = false,
                showChevron = false,
            )

            SectionHeader("Backup")
            if (backupState.availability == DriveAvailability.NoPlayServices) {
                Text(
                    text = "Google Play services isn't available on this device, " +
                        "so Google Drive backup can't be used.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(
                        horizontal = CashuTheme.spacing.comfortable,
                        vertical = CashuTheme.spacing.tight,
                    ),
                )
            } else {
                ToggleRow(
                    title = "Back up to Google Drive",
                    checked = settings.driveBackupEnabled,
                    onCheckedChange = { checked ->
                        if (checked) confirmEnable = true else confirmDisable = true
                    },
                    modifier = Modifier.testTag(UiTestTags.DriveBackupToggle),
                )
            }

            if (settings.driveBackupEnabled) {
                backupState.lastBackupEpochMillis?.let { lastBackup ->
                    NavRow(
                        title = "Last backed up",
                        trailingValue = formatRelativeTimestamp(lastBackup),
                        onClick = {},
                        enabled = false,
                        showChevron = false,
                    )
                }
                NavRow(
                    title = when {
                        backupState.isBackingUp -> "Backing up…"
                        justBackedUp -> "Backed up"
                        else -> "Back Up Now"
                    },
                    leadingIcon = if (justBackedUp) Icons.Outlined.Check else Icons.Outlined.CloudUpload,
                    tint = if (justBackedUp) CashuTheme.colors.received else null,
                    enabled = !backupState.isBackingUp,
                    showChevron = false,
                    trailingIcon = null,
                    onClick = {
                        backupError = null
                        scope.launch {
                            val outcome = googleDriveBackupService.performBackup(
                                allowResolution = true,
                                launchResolution = launchResolution,
                            )
                            if (outcome is DriveBackupOutcome.Success) {
                                justBackedUp = true
                            } else {
                                backupError = backupOutcomeMessage(outcome)
                            }
                        }
                    },
                )
            }

            InlineNoticeHost(
                text = backupError ?: standingNotice(backupState.lastOutcome, settings.driveBackupEnabled),
                modifier = Modifier.padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.tight,
                ),
            )

            Text(
                text = driveBackupFooter(backupState.accountEmail),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.tight,
                ),
            )
        }
    }

    if (confirmEnable) {
        AlertDialog(
            onDismissRequest = { confirmEnable = false },
            title = { Text("Enable Google Drive Backup?") },
            text = {
                Text(
                    "Your seed phrase and mint list will be stored in your Google Drive's " +
                        "app storage. Google encrypts this data at rest, but it is not " +
                        "end-to-end encrypted — anyone who can read the backup can spend " +
                        "your funds. You may be asked to pick a Google account and grant access.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmEnable = false
                    authenticate("Back up your seed phrase to Google Drive") {
                        scope.launch {
                            backupError = null
                            val outcome = googleDriveBackupService.setEnabled(true, launchResolution)
                            backupError = outcome?.let(::backupOutcomeMessage)
                        }
                    }
                }) {
                    Text("Enable")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmEnable = false }) { Text("Cancel") }
            },
        )
    }

    if (confirmDisable) {
        AlertDialog(
            onDismissRequest = { confirmDisable = false },
            title = { Text("Disable Google Drive Backup?") },
            text = {
                Text(
                    "Your backup will be removed from Google Drive and Block Store. " +
                        "Your local wallet is not affected.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmDisable = false
                    backupError = null
                    scope.launch { googleDriveBackupService.setEnabled(false) }
                }) {
                    Text("Disable", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDisable = false }) { Text("Cancel") }
            },
        )
    }
}

/** iOS `backupErrorMessage(for:)`, extended with Android's consent cases. Null for success. */
private fun backupOutcomeMessage(outcome: DriveBackupOutcome): String? = when (outcome) {
    is DriveBackupOutcome.Success -> null
    DriveBackupOutcome.Deferred -> "Drive backup is paused until wallet recovery finishes."
    DriveBackupOutcome.Unavailable -> "Google Play services is unavailable on this device."
    DriveBackupOutcome.NoSeed -> "There's no wallet seed to back up."
    DriveBackupOutcome.NeedsConsent -> "Backup needs access to Google Drive. Tap Back Up Now to grant it."
    DriveBackupOutcome.ConsentDeclined -> "Google Drive access was declined."
    is DriveBackupOutcome.Failed -> outcome.message
}

/** A background trigger that couldn't show the consent sheet leaves a standing hint. */
private fun standingNotice(lastOutcome: DriveBackupOutcome?, enabled: Boolean): String? =
    if (enabled && lastOutcome == DriveBackupOutcome.NeedsConsent) {
        backupOutcomeMessage(DriveBackupOutcome.NeedsConsent)
    } else {
        null
    }

private fun driveBackupFooter(accountEmail: String?): String {
    val base = "Your seed phrase and mint URLs are stored in your Google Drive's hidden " +
        "app storage, visible only to this app. Google encrypts this data at rest but " +
        "can technically read it — it is not end-to-end encrypted. A second copy is " +
        "saved to Android Block Store so a new phone can restore it during device " +
        "setup; that copy is end-to-end encrypted when your device has a screen lock."
    return accountEmail?.let { "$base\n\nConnected as $it." } ?: base
}
