package com.cashu.me.ui.restore

import android.app.Activity
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.PhonelinkSetup
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import com.cashu.me.Core.DriveBackupSource
import com.cashu.me.Core.DriveConsentLauncher
import com.cashu.me.Core.DriveDetectResult
import com.cashu.me.Core.GoogleDriveBackupService
import com.cashu.me.Core.WalletManager
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.InlineNoticeHost
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.formatRelativeTimestamp
import com.cashu.me.ui.testing.UiTestTags
import com.cashu.me.ui.theme.CashuTheme

// iOS OnboardingView.iCloudRestore metrics (28/24/24pt), duplicated because the
// flow file keeps its own privates.
private val HeaderPadding = 28.dp
private val CtaPadding = 24.dp
private val BottomPadding = 24.dp
private val PhaseIconSize = 44.dp

private sealed interface DriveRestorePhase {
    data object Detecting : DriveRestorePhase

    /** Detection settled: either a found backup or a terminal message. */
    data class Preview(val result: DriveDetectResult) : DriveRestorePhase
    data class Restoring(val mintCount: Int) : DriveRestorePhase
    data object Success : DriveRestorePhase
}

/**
 * Onboarding "Restore from Google Drive" (iOS OnboardingView .iCloudRestore):
 * detect → preview (found / not found / unavailable) → restore → success.
 * Detection checks Block Store first — after a device migration the backup is
 * already on this phone and no Google sign-in is needed; otherwise the Drive
 * consent sheet appears over onboarding. Restore is all-or-nothing; a failure
 * returns to the preview with the backup preserved, and killing the app
 * mid-restore resumes onboarding at this step (write-barrier marker).
 */
@Composable
fun DriveRestoreStep(
    walletManager: WalletManager,
    googleDriveBackupService: GoogleDriveBackupService,
    onBack: () -> Unit,
    onDone: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val walletState by walletManager.state.collectAsState()

    var phase: DriveRestorePhase by remember { mutableStateOf(DriveRestorePhase.Detecting) }
    var detectAttempt by remember { mutableIntStateOf(0) }
    var restoreError by remember { mutableStateOf<String?>(null) }

    // Bridges the Authorization consent PendingIntent into the suspended
    // service calls (same shape as DriveBackupScreen).
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

    LaunchedEffect(detectAttempt) {
        if (phase is DriveRestorePhase.Restoring || phase is DriveRestorePhase.Success) {
            return@LaunchedEffect
        }
        phase = DriveRestorePhase.Detecting
        phase = DriveRestorePhase.Preview(googleDriveBackupService.detectBackup(launchResolution))
    }

    fun restore(found: DriveDetectResult.Found) {
        scope.launch {
            restoreError = null
            phase = DriveRestorePhase.Restoring(found.payload.mintUrls.size)
            try {
                walletManager.restoreFromDriveBackup(found.payload, launchResolution)
                phase = DriveRestorePhase.Success
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                restoreError = error.message ?: "Couldn't restore the wallet."
                phase = DriveRestorePhase.Preview(found)
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .testTag(UiTestTags.OnboardingDriveRestore),
    ) {
        Spacer(Modifier.weight(1f))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = HeaderPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            when (val current = phase) {
                DriveRestorePhase.Detecting -> {
                    PhaseHeading(
                        icon = Icons.Outlined.Cloud,
                        title = "Checking\nGoogle Drive…",
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                        BodyText("Checking Google Drive…")
                    }
                }

                is DriveRestorePhase.Preview -> when (val result = current.result) {
                    is DriveDetectResult.Found -> {
                        PhaseHeading(
                            icon = if (result.source == DriveBackupSource.BlockStore) {
                                Icons.Outlined.PhonelinkSetup
                            } else {
                                Icons.Outlined.CloudDownload
                            },
                            title = if (result.source == DriveBackupSource.BlockStore) {
                                "Wallet found\non this device."
                            } else {
                                "Wallet found\nin Google Drive."
                            },
                            tint = true,
                        )
                        BodyText("Backed up ${formatRelativeTimestamp(result.payload.updatedAt)}")
                        BodyText(
                            if (result.payload.mintUrls.isEmpty()) {
                                "Seed backup — add mints after"
                            } else {
                                "${result.payload.mintUrls.size} mint" +
                                    if (result.payload.mintUrls.size == 1) "" else "s"
                            },
                        )
                    }

                    DriveDetectResult.NotFound -> {
                        PhaseHeading(icon = Icons.Outlined.CloudOff, title = "No backup\nfound.")
                        BodyText(
                            "No backup found. Make sure you signed in with the Google " +
                                "account that holds your backup.",
                        )
                    }

                    DriveDetectResult.ConsentDeclined -> {
                        PhaseHeading(icon = Icons.Outlined.CloudOff, title = "No backup\nfound.")
                        BodyText("Google Drive access was declined. Grant access to look for your backup.")
                    }

                    DriveDetectResult.Unavailable -> {
                        PhaseHeading(icon = Icons.Outlined.CloudOff, title = "Google Drive\nunavailable.")
                        BodyText(
                            "Google Play services isn't available on this device. " +
                                "Restore with your seed phrase instead.",
                        )
                    }
                }

                is DriveRestorePhase.Restoring -> {
                    PhaseHeading(icon = Icons.Outlined.CloudDownload, title = "Restoring\nWallet")
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                        BodyText(
                            if (current.mintCount == 0) {
                                "Restoring your wallet…"
                            } else {
                                "Recovering your funds from ${current.mintCount} mint" +
                                    (if (current.mintCount == 1) "" else "s") + "…"
                            },
                        )
                    }
                }

                DriveRestorePhase.Success -> {
                    PhaseHeading(
                        icon = Icons.Filled.CheckCircle,
                        title = "Wallet\nRestored",
                        tint = true,
                    )
                    Text(
                        text = "${walletState.balance} sats",
                        style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold),
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    BodyText(
                        if (walletState.mints.isEmpty()) {
                            "Your funds are ready."
                        } else {
                            "across ${walletState.mints.size} mint" +
                                if (walletState.mints.size == 1) "" else "s"
                        },
                    )
                }
            }
        }
        Spacer(Modifier.weight(1f))

        InlineNoticeHost(
            text = restoreError,
            modifier = Modifier.padding(
                horizontal = CtaPadding,
                vertical = CashuTheme.spacing.tight,
            ),
        )

        Column(
            modifier = Modifier
                .padding(horizontal = CtaPadding)
                .padding(bottom = BottomPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            when (val current = phase) {
                DriveRestorePhase.Success -> PrimaryButton(
                    text = "Open Wallet",
                    onClick = onDone,
                    modifier = Modifier.testTag(UiTestTags.DriveRestoreCta),
                )

                is DriveRestorePhase.Restoring -> PrimaryButton(
                    text = "Restore Wallet",
                    onClick = {},
                    enabled = false,
                    loading = true,
                    modifier = Modifier.testTag(UiTestTags.DriveRestoreCta),
                )

                else -> {
                    val found = (current as? DriveRestorePhase.Preview)?.result as? DriveDetectResult.Found
                    PrimaryButton(
                        text = "Restore Wallet",
                        onClick = { found?.let(::restore) },
                        enabled = found != null,
                        modifier = Modifier.testTag(UiTestTags.DriveRestoreCta),
                    )
                    val retryable = (current as? DriveRestorePhase.Preview)?.result.let {
                        it == DriveDetectResult.NotFound || it == DriveDetectResult.ConsentDeclined
                    }
                    if (retryable) {
                        GhostButton(text = "Try Again", onClick = { detectAttempt++ })
                    }
                    GhostButton(text = "Back", onClick = onBack)
                }
            }
        }
    }
}

@Composable
private fun PhaseHeading(icon: ImageVector, title: String, tint: Boolean = false) {
    Icon(
        imageVector = icon,
        contentDescription = null,
        tint = if (tint) CashuTheme.colors.received else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.size(PhaseIconSize),
    )
    Text(
        text = title,
        style = restoreOnboardingTitleStyle(),
        color = MaterialTheme.colorScheme.onSurface,
    )
}

@Composable
private fun BodyText(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
