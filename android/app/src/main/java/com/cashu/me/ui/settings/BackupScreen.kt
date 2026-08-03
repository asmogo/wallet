package com.cashu.me.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.WalletManager
import com.cashu.me.ui.components.IconSwap
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.security.rememberWalletAuthenticationLauncher
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withSlashedZero
import kotlinx.coroutines.delay

/**
 * Settings → Backup & Restore → "Backup seed phrase" (iOS `BackupView`): a quiet
 * bottom sheet — a centered "keep it safe" warning over a single card that shows
 * the whole mnemonic as one masked monospace block. Reveal and copy each require
 * device authentication (biometric / credential); hiding is instant. Dismiss by
 * swipe / scrim only, no buttons.
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
    // Mask each word by length (min 3 bullets) so word count/lengths stay hidden.
    val hiddenText = remember(words) {
        words.joinToString(" ") { "•".repeat(maxOf(3, it.length)) }
    }

    val clipboard = LocalClipboardManager.current
    val authenticate = rememberWalletAuthenticationLauncher(appLockManager)

    var revealed by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) { delay(3000); copied = false }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(),
    ) {
        Column(
            modifier = Modifier
                .navigationBarsPadding()
                .padding(horizontal = CashuTheme.spacing.comfortable)
                .padding(bottom = CashuTheme.spacing.section),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
        ) {
            SheetHeader(title = "Backup")

            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
            ) {
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = null,
                    tint = CashuTheme.colors.pending,
                    modifier = Modifier.size(32.dp),
                )
                Text(
                    text = "Keep Your Seed Phrase Safe",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                )
                Text(
                    text = "Anyone with these words can access your funds. Never share them with anyone.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(MaterialTheme.shapes.medium)
                    .background(MaterialTheme.colorScheme.surfaceContainer)
                    .padding(CashuTheme.spacing.comfortable),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                Text(
                    text = "SEED PHRASE",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                ) {
                    Text(
                        text = if (revealed) revealedText else hiddenText,
                        style = MaterialTheme.typography.bodyMedium.copy(fontFamily = CashuTheme.fonts.mono).withSlashedZero(),
                        color = if (revealed) MaterialTheme.colorScheme.onSurface
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 4,
                        modifier = Modifier.weight(1f),
                    )
                    Column(
                        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                    ) {
                        IconButton(
                            onClick = {
                                if (revealed) revealed = false
                                else authenticate("Reveal your seed phrase") { revealed = true }
                            },
                        ) {
                            Icon(
                                imageVector = if (revealed) Icons.Outlined.VisibilityOff
                                else Icons.Outlined.Visibility,
                                contentDescription = if (revealed) "Hide seed phrase" else "Reveal seed phrase",
                            )
                        }
                        IconButton(
                            onClick = {
                                authenticate("Copy your seed phrase") {
                                    clipboard.setText(AnnotatedString(revealedText))
                                    copied = true
                                }
                            },
                        ) {
                            IconSwap(
                                icon = if (copied) Icons.Outlined.Check else Icons.Outlined.ContentCopy,
                                contentDescription = "Copy seed phrase",
                                tint = if (copied) CashuTheme.colors.received
                                else MaterialTheme.colorScheme.onSurface,
                                iconSize = 24.dp,
                            )
                        }
                    }
                }
            }
        }
    }
}
