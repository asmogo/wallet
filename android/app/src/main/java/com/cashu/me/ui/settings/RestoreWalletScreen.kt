package com.cashu.me.ui.settings

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.cashu.me.Core.MnemonicInput
import com.cashu.me.Core.NostrMintBackupService
import com.cashu.me.Core.WalletManager
import com.cashu.me.Models.MintInfo
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.restore.RestoreMintsStep
import com.cashu.me.ui.restore.RestorePresentation
import com.cashu.me.ui.restore.RestoreProgressStep
import com.cashu.me.ui.restore.RestoreSeedStep
import com.cashu.me.ui.restore.restoreSeedInstallErrorMessage
import kotlinx.coroutines.launch

private sealed interface InAppRestoreStep {
    data object Seed : InAppRestoreStep
    data class Mints(val mnemonic: String) : InAppRestoreStep
    data class Progress(
        val mnemonic: String,
        val mintUrls: List<String>,
        val previews: Map<String, MintInfo>,
    ) : InAppRestoreStep
}

/**
 * In-app restore wizard (iOS `RestoreWalletView`): seed → mints → progress.
 * Navigation back chevron on seed/mints; progress is forward-only.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RestoreWalletScreen(
    walletManager: WalletManager,
    nostrMintBackupService: NostrMintBackupService,
    onClose: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var step: InAppRestoreStep by remember { mutableStateOf(InAppRestoreStep.Seed) }
    var restoring by remember { mutableStateOf(false) }
    var seedError by remember { mutableStateOf<String?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Restore", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    // Forward-only on progress (iOS hides the back chevron).
                    if (step !is InAppRestoreStep.Progress) {
                        IconButton(
                            onClick = {
                                when (step) {
                                    InAppRestoreStep.Seed -> onClose()
                                    is InAppRestoreStep.Mints -> {
                                        seedError = null
                                        step = InAppRestoreStep.Seed
                                    }
                                    is InAppRestoreStep.Progress -> Unit
                                }
                            },
                            enabled = !restoring,
                        ) {
                            ToolbarIcon(
                                Icons.AutoMirrored.Outlined.ArrowBack,
                                contentDescription = if (step is InAppRestoreStep.Seed) {
                                    "Back"
                                } else {
                                    "Back to seed phrase"
                                },
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        AnimatedContent(
            targetState = step,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
            transitionSpec = { fadeIn(tween(280)).togetherWith(fadeOut(tween(280))) },
            label = "restore-wallet-step",
        ) { current ->
            when (current) {
                InAppRestoreStep.Seed -> RestoreSeedStep(
                    presentation = RestorePresentation.InApp,
                    restoring = restoring,
                    errorText = seedError,
                    onClearError = { seedError = null },
                    onBack = null,
                    onValidateChecksum = { walletManager.validateMnemonic(it) },
                    onNext = { mnemonic ->
                        scope.launch {
                            restoring = true
                            seedError = null
                            val normalized = MnemonicInput.normalize(mnemonic)
                            runCatching { walletManager.initializeRestoredWallet(normalized) }
                                .onSuccess { step = InAppRestoreStep.Mints(normalized) }
                                .onFailure { seedError = restoreSeedInstallErrorMessage(it) }
                            restoring = false
                        }
                    },
                )

                is InAppRestoreStep.Mints -> RestoreMintsStep(
                    presentation = RestorePresentation.InApp,
                    walletManager = walletManager,
                    nostrMintBackupService = nostrMintBackupService,
                    onBack = {
                        seedError = null
                        step = InAppRestoreStep.Seed
                    },
                    showBottomBack = false,
                    onRestore = { mintUrls, previews ->
                        step = InAppRestoreStep.Progress(current.mnemonic, mintUrls, previews)
                    },
                )

                is InAppRestoreStep.Progress -> RestoreProgressStep(
                    presentation = RestorePresentation.InApp,
                    walletManager = walletManager,
                    mintUrls = current.mintUrls,
                    stagedPreviews = current.previews,
                    onContinue = {
                        scope.launch {
                            runCatching { walletManager.completeRestore() }
                            onClose()
                        }
                    },
                )
            }
        }
    }
}
