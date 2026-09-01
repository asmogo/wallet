package com.cashu.me.ui.settings

import android.content.ClipData
import androidx.compose.foundation.background
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.WalletManager
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.components.LocalConfirmationToastController
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.security.rememberWalletAuthenticationLauncher
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.rememberReducedMotion
import kotlinx.coroutines.launch

/**
 * Settings → Backup & Restore → "Backup seed phrase" (iOS `BackupView`): a quiet
 * bottom sheet. It reveals an ordered recovery-word grid after authentication,
 * and grows with the content instead of replacing the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupSeedSheet(
    walletManager: WalletManager,
    appLockManager: AppLockManager,
    onDismiss: () -> Unit,
) {
    val mnemonic = remember { walletManager.backupMnemonic().orEmpty() }
    val words = remember(mnemonic) { mnemonic.trim().split(' ').filter { it.isNotBlank() } }
    val revealedText = remember(words) { words.joinToString(" ") }

    val clipboard = LocalClipboard.current
    val clipboardScope = rememberCoroutineScope()
    val confirmationToastController = LocalConfirmationToastController.current
    val authenticate = rememberWalletAuthenticationLauncher(appLockManager)
    val reduceMotion = rememberReducedMotion()
    val revealEnterSpec = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val revealExitSpec = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    val contentSizeSpec = MaterialTheme.motionScheme.defaultSpatialSpec<IntSize>()

    var revealed by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberBottomSheetState(
            initialValue = SheetValue.Hidden,
            enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded),
        ),
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .navigationBarsPadding()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = CashuTheme.spacing.comfortable)
                    .padding(bottom = CashuTheme.spacing.section)
                    .then(
                        if (reduceMotion) {
                            Modifier
                        } else {
                            Modifier.animateContentSize(animationSpec = contentSizeSpec)
                        },
                    ),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
            ) {
                SheetHeader(title = "Backup Wallet")

                Text(
                    text = if (revealed) {
                        "Write down these words in order and store them somewhere safe. Do not share them with anyone."
                    } else {
                        "Your recovery phrase is the only way to restore your wallet. Keep it private and stored somewhere safe. Never share it with anyone."
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )

                AnimatedVisibility(
                    visible = revealed,
                    enter = fadeIn(revealEnterSpec),
                    exit = fadeOut(revealExitSpec),
                ) {
                    LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = 96.dp),
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 260.dp),
                    ) {
                        itemsIndexed(words, key = { index, _ -> index }) { index, word ->
                            Text(
                                text = "${index + 1}. $word",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(
                                        color = MaterialTheme.colorScheme.surfaceContainer,
                                        shape = MaterialTheme.shapes.medium,
                                    )
                                    .padding(CashuTheme.spacing.default),
                            )
                        }
                    }
                }

                PrimaryButton(
                    text = if (revealed) "Copy Recovery Phrase" else "Reveal Recovery Phrase",
                    onClick = {
                        if (revealed) {
                            authenticate("Copy your seed phrase") {
                                clipboardScope.launch {
                                    clipboard.setClipEntry(
                                        ClipEntry(ClipData.newPlainText("Recovery phrase", revealedText)),
                                    )
                                    confirmationToastController?.show("Copied recovery phrase")
                                }
                            }
                        } else {
                            authenticate("Reveal your seed phrase") { revealed = true }
                        }
                    },
                )
            }
        }
    }
}
