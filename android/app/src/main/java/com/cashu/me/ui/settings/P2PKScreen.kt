package com.cashu.me.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.QrCode
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.LockedReceiveRequest
import com.cashu.me.Core.NostrService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme

/** A QR payload the hub is currently presenting. */
private data class QrPayload(val title: String, val content: String)

/**
 * The "Locked Ecash" settings hub (iOS P2PKSettingsSection): explains P2PK in
 * plain language and surfaces the recoverable seed-derived primary key.
 * Disposable device-only keys live on the pushed Advanced Keys screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun P2PKScreen(
    settingsManager: SettingsManager,
    nostrService: NostrService,
    appLockManager: AppLockManager,
    onOpenAdvancedKeys: () -> Unit,
    onClose: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
    // Recompute when the Nostr identity settles (seed key becomes available).
    val nostrState by nostrService.state.collectAsState()
    val primaryKey = remember(nostrState) { settingsManager.primaryP2PKKeyInfo() }

    var showExplainer by remember { mutableStateOf(false) }
    var activeQr by remember { mutableStateOf<QrPayload?>(null) }
    var showPrivateKeyBackup by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Locked Ecash", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        ToolbarIcon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { showExplainer = true }) {
                        ToolbarIcon(Icons.Outlined.Info, contentDescription = "How locking works")
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
            Text(
                text = "Lock ecash to a key so only its holder can claim it — even if the token is intercepted in transit.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.snug,
                ),
            )
            Spacer(Modifier.height(CashuTheme.spacing.default))

            SectionHeader("Your key")
            if (primaryKey != null) {
                KeyCard(
                    title = "Your key",
                    pubkey = primaryKey.publicKey,
                    status = KeyCardStatus.SeedBacked,
                    actions = listOf(
                        KeyCardAction("Show QR", Icons.Outlined.QrCode) {
                            val locked = LockedReceiveRequest.build(nostrService, settingsManager)
                            activeQr = if (locked != null) {
                                QrPayload("Receive Locked Ecash", locked)
                            } else {
                                // No Nostr transport available — fall back to the raw key.
                                QrPayload("Your Key", P2PKKeyDisplay.canonical(primaryKey.publicKey))
                            }
                        },
                        KeyCardAction("Reveal key", Icons.Outlined.Visibility) {
                            showPrivateKeyBackup = true
                        },
                    ),
                    modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
                )
            } else {
                Text(
                    text = "Your key appears once your wallet finishes setting up.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
                )
            }
            FooterText(
                "Show your QR or share this key, and anyone can send you locked ecash. " +
                    "The key comes from your seed phrase, so only you can claim it.",
            )

            SectionHeader("When sending")
            ToggleRow(
                title = "Quick lock to my key",
                subtitle = "Show a \u201CLock to my key\u201D shortcut when sending ecash.",
                checked = settings.showP2PKButtonInDrawer,
                onCheckedChange = settingsManager::setShowP2PKButtonInDrawer,
            )

            Spacer(Modifier.height(CashuTheme.spacing.default))
            NavRow(
                title = "Advanced keys",
                subtitle = advancedKeysSubtitle(settings.p2pkKeys.size),
                leadingIcon = Icons.Outlined.MoreHoriz,
                onClick = onOpenAdvancedKeys,
            )
            Spacer(Modifier.height(CashuTheme.spacing.section))
        }
    }

    if (showExplainer) {
        LockedEcashExplainerSheet(onDismiss = { showExplainer = false })
    }
    activeQr?.let { payload ->
        QrDetailSheet(
            title = payload.title,
            content = payload.content,
            onDismiss = { activeQr = null },
        )
    }
    if (showPrivateKeyBackup && primaryKey != null) {
        PrivateKeyRevealSheet(
            title = "Your Key",
            loadNsec = { P2PKKeyDisplay.nsec(primaryKey.privateKeyHex) },
            appLockManager = appLockManager,
            onDismiss = { showPrivateKeyBackup = false },
        )
    }
}

internal fun advancedKeysSubtitle(count: Int): String = when (count) {
    0 -> "Add a key that lives only on this device"
    1 -> "1 device key"
    else -> "$count device keys"
}

/** iOS SettingsSectionFooter: quiet explanatory prose under a section. */
@Composable
internal fun FooterText(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                horizontal = CashuTheme.spacing.comfortable,
                vertical = CashuTheme.spacing.default,
            ),
    )
}
