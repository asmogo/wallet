package com.cashu.me.ui.settings

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.QrCode2
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.NPCService
import com.cashu.me.Core.NPCState
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.WalletState
import com.cashu.me.ui.components.CanvasDivider
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.MintPickerSheet
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.QrCard
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

internal enum class LightningAddressSetupStatus {
    Ready,
    Empty,
    SettingUp,
    NeedsRecovery,
}

internal fun lightningAddressSetupStatus(
    walletState: WalletState,
    npcState: NPCState,
): LightningAddressSetupStatus = when {
    npcState.lightningAddress.isNotBlank() -> LightningAddressSetupStatus.Ready
    !npcState.isEnabled -> LightningAddressSetupStatus.Empty
    !walletState.isRuntimeReady && walletState.startupFailure == null ->
        LightningAddressSetupStatus.SettingUp
    else -> LightningAddressSetupStatus.NeedsRecovery
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LightningScreen(
    walletManager: WalletManager,
    npcService: NPCService,
    onClose: () -> Unit,
) {
    val walletState by walletManager.state.collectAsState()
    val npcState by npcService.state.collectAsState()
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()

    var mintPickerOpen by remember { mutableStateOf(false) }
    var addressQrOpen by remember { mutableStateOf(false) }
    var retryingSetup by remember { mutableStateOf(false) }
    var setupRecoveryError by remember { mutableStateOf<String?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Lightning", style = MaterialTheme.typography.titleMedium) },
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
            modifier = Modifier.fillMaxSize().padding(padding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            SectionHeader("Lightning address")
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .animateContentSize(spring(stiffness = Spring.StiffnessMediumLow)),
            ) {
                if (npcState.lightningAddress.isNotBlank()) {
                    LightningAddressRow(
                        address = npcState.lightningAddress,
                        statusColor = npcStatusColor(npcState),
                        onShowQr = { addressQrOpen = true },
                    )
                    CanvasDivider(leadingInset = 16.dp)
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(
                            horizontal = CashuTheme.spacing.comfortable,
                            vertical = CashuTheme.spacing.snug,
                        ),
                    ) {
                        GhostButton(
                            text = "Copy address",
                            onClick = {
                                clipboard.setText(AnnotatedString(npcState.lightningAddress))
                            },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                } else {
                    LightningAddressSetupFeedback(
                        status = lightningAddressSetupStatus(walletState, npcState),
                        retrying = retryingSetup,
                        recoveryError = setupRecoveryError,
                        onRetry = {
                            scope.launch {
                                retryingSetup = true
                                setupRecoveryError = null
                                try {
                                    walletManager.retryLightningAddressSetup()
                                } catch (cancellation: CancellationException) {
                                    throw cancellation
                                } catch (_: Throwable) {
                                    setupRecoveryError =
                                        "Lightning address setup couldn't finish. Try again or restart the app."
                                } finally {
                                    retryingSetup = false
                                }
                            }
                        },
                    )
                }
            }

            SectionHeader("Settings")
            ToggleRow(
                title = "Enable Nostr-NPC bridge",
                subtitle = "Route Lightning payments through the NPC quote handler",
                checked = npcState.isEnabled,
                onCheckedChange = { npcService.setEnabled(it) },
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Automatic claim",
                subtitle = "Mint paid quotes without confirmation",
                checked = npcState.automaticClaim,
                onCheckedChange = { npcService.setAutomaticClaim(it) },
                enabled = npcState.isEnabled,
            )

            SectionHeader("Default mint")
            val mintLabel = walletState.mints.firstOrNull { it.url == npcState.selectedMintUrl }?.name
                ?: walletState.activeMint?.name
                ?: "No mint"
            InspectorRow(
                label = "Mint",
                value = mintLabel,
                editable = walletState.mints.isNotEmpty(),
                onClick = { if (walletState.mints.isNotEmpty()) mintPickerOpen = true },
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .animateContentSize(spring(stiffness = Spring.StiffnessMediumLow)),
            ) {
                if (npcState.errorMessage != null) {
                    Spacer(Modifier.height(CashuTheme.spacing.snug))
                    InlineNotice(
                        text = npcState.errorMessage!!,
                        modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
                    )
                }
            }

            Spacer(Modifier.height(CashuTheme.spacing.comfortable))
            Column(modifier = Modifier.fillMaxWidth().padding(horizontal = CashuTheme.spacing.comfortable)) {
                PrimaryButton(
                    text = if (npcState.isCheckingPayments) "Checking…" else "Check for paid quotes now",
                    onClick = { npcService.checkAndClaimPayments() },
                    enabled = npcState.isEnabled && !npcState.isCheckingPayments,
                    loading = npcState.isCheckingPayments,
                )
            }
        }
    }

    if (mintPickerOpen) {
        MintPickerSheet(
            mints = walletState.mints,
            activeMintUrl = npcState.selectedMintUrl ?: walletState.activeMint?.url,
            onSelect = { mint ->
                mint?.let { npcService.changeMint(it.url) }
                mintPickerOpen = false
            },
            onDismiss = { mintPickerOpen = false },
            title = "Mint for Lightning",
        )
    }

    if (addressQrOpen) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { addressQrOpen = false },
            sheetState = sheetState,
        ) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.snug,
                ),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
            ) {
                Text(
                    text = "Lightning Address",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                QrCard(
                    content = npcState.lightningAddress,
                    shareSubject = "Lightning address",
                    staticOnly = true,
                )
                Text(
                    text = npcState.lightningAddress,
                    style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(CashuTheme.spacing.snug))
            }
        }
    }
}

@Composable
internal fun LightningAddressSetupFeedback(
    status: LightningAddressSetupStatus,
    retrying: Boolean,
    recoveryError: String?,
    onRetry: () -> Unit,
) {
    val contentModifier = Modifier.padding(
        horizontal = CashuTheme.spacing.comfortable,
        vertical = CashuTheme.spacing.snug,
    )
    when (status) {
        LightningAddressSetupStatus.Ready -> Unit
        LightningAddressSetupStatus.Empty -> Text(
            text = "No Lightning address configured. Enable below to receive at an @ address.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = contentModifier,
        )
        LightningAddressSetupStatus.SettingUp -> Row(
            modifier = contentModifier,
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(CashuTheme.spacing.loose),
                strokeWidth = 2.dp,
            )
            Text(
                text = "Setting up Lightning address…",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        LightningAddressSetupStatus.NeedsRecovery -> Column(
            modifier = contentModifier,
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            InlineNotice(
                text = recoveryError
                    ?: "Wallet not fully initialized. Try setup again to finish your Lightning address.",
            )
            PrimaryButton(
                text = "Try setup again",
                onClick = onRetry,
                loading = retrying,
                enabled = !retrying,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun LightningAddressRow(
    address: String,
    statusColor: Color,
    onShowQr: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onShowQr)
            .padding(
                horizontal = CashuTheme.spacing.comfortable,
                vertical = CashuTheme.spacing.default,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Box(
            modifier = Modifier
                .size(CashuTheme.spacing.snug)
                .clip(CircleShape)
                .background(statusColor),
        )
        Text(
            text = address,
            style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.MiddleEllipsis,
        )
        Icon(
            imageVector = Icons.Outlined.QrCode2,
            contentDescription = "Show QR",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(CashuTheme.spacing.loose),
        )
    }
}

@Composable
private fun npcStatusColor(state: NPCState): Color {
    return when {
        state.errorMessage != null -> MaterialTheme.colorScheme.error
        state.isConnected -> CashuTheme.colors.received
        else -> CashuTheme.colors.pending
    }
}
