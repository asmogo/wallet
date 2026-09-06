package com.cashu.me.ui.settings

import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.ArrowOutward
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import com.cashu.me.BuildConfig
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.WalletManager
import com.cashu.me.ui.components.ActionConfirmationSheet
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.TabTopBar
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.testing.UiTestTags

/**
 * Settings root — section order, rows, and copy mirror iOS SettingsView:
 * Display · Backup & Security · Payments · Integrations · Privacy · About ·
 * Danger, with the version footer.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun SettingsScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    onClose: () -> Unit,
    onOpenBackupRestore: () -> Unit,
    onOpenAppLock: () -> Unit,
    onOpenLightning: () -> Unit,
    onOpenLockedEcash: () -> Unit,
    onOpenNostr: () -> Unit,
    onOpenPrivacy: () -> Unit,
    onOpenLicenses: () -> Unit,
    contentPadding: PaddingValues,
) {
    val context = LocalContext.current
    val settings by settingsManager.state.collectAsState()
    var confirmDelete by remember { mutableStateOf(false) }
    var currencyPickerOpen by remember { mutableStateOf(false) }

    val topBarState = rememberTopAppBarState()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(state = topBarState)

    Scaffold(
        modifier = Modifier
            .testTag(UiTestTags.SettingsScreen)
            .padding(contentPadding)
            // The shell scaffold's padding already carries the status-bar inset;
            // consume it so the nested TopAppBar doesn't apply it a second time.
            .consumeWindowInsets(contentPadding)
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            TabTopBar(
                title = "Settings",
                scrollBehavior = scrollBehavior,
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        ToolbarIcon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .testTag(UiTestTags.SettingsList),
            // Generous bottom inset so the footer clears the navigation bar.
            contentPadding = PaddingValues(bottom = CashuTheme.spacing.section + CashuTheme.spacing.snug),
        ) {
            item("display-header") { SectionHeader("Display") }
            item("currency") {
                NavRow(
                    title = "Currency",
                    leadingIcon = Icons.Outlined.Payments,
                    trailingValue = if (settings.showFiatBalance) settings.bitcoinPriceCurrency else "Off",
                    onClick = { currencyPickerOpen = true },
                )
            }
            item("btc-symbol") {
                ToggleRow(
                    title = "Use ₿ symbol",
                    leadingIcon = Icons.Outlined.CurrencyBitcoin,
                    checked = settings.useBitcoinSymbol,
                    onCheckedChange = settingsManager::setUseBitcoinSymbol,
                    modifier = Modifier.testTag(UiTestTags.BitcoinSymbolToggle),
                )
            }

            item("backup-header") { SectionHeader("Backup & Security") }
            item("backup-restore") {
                NavRow(
                    title = "Backup & Restore",
                    leadingIcon = Icons.Outlined.VpnKey,
                    onClick = onOpenBackupRestore,
                )
            }
            item("app-lock") {
                NavRow(
                    title = "App Lock",
                    leadingIcon = Icons.Outlined.Security,
                    onClick = onOpenAppLock,
                )
            }

            item("payments-header") { SectionHeader("Payments") }
            item("lightning") {
                NavRow(
                    title = "Lightning",
                    leadingIcon = Icons.Outlined.Bolt,
                    onClick = onOpenLightning,
                )
            }
            item("locked-ecash") {
                NavRow(
                    title = "Locked Ecash",
                    leadingIcon = Icons.Outlined.Lock,
                    onClick = onOpenLockedEcash,
                )
            }

            item("integrations-header") { SectionHeader("Integrations") }
            item("nostr") {
                NavRow(
                    title = "Nostr",
                    leadingIcon = Icons.Outlined.AccountCircle,
                    onClick = onOpenNostr,
                )
            }

            item("privacy-header") { SectionHeader("Privacy") }
            item("privacy") {
                NavRow(
                    title = "Privacy",
                    leadingIcon = Icons.Outlined.VisibilityOff,
                    onClick = onOpenPrivacy,
                )
            }

            item("about-header") { SectionHeader("About") }
            item("learn") {
                NavRow(
                    title = "Learn about Cashu",
                    leadingIcon = Icons.Outlined.Public,
                    trailingIcon = Icons.Outlined.ArrowOutward,
                    onClick = { context.openExternal("https://cashu.space") },
                )
            }
            item("specs") {
                NavRow(
                    title = "Protocol Specs (NUTs)",
                    leadingIcon = Icons.Outlined.Description,
                    trailingIcon = Icons.Outlined.ArrowOutward,
                    onClick = { context.openExternal("https://github.com/cashubtc/nuts") },
                )
            }

            item("licenses") {
                NavRow(
                    title = "Licenses",
                    leadingIcon = Icons.Outlined.Description,
                    onClick = onOpenLicenses,
                )
            }

            item("danger-header") { SectionHeader("Danger") }
            item("delete") {
                NavRow(
                    title = "Delete Wallet",
                    leadingIcon = Icons.Outlined.DeleteOutline,
                    onClick = { confirmDelete = true },
                    tint = MaterialTheme.colorScheme.error,
                    showChevron = false,
                )
            }

            item("footer") {
                Spacer(Modifier.height(CashuTheme.spacing.section))
                Text(
                    text = "Cashu Wallet · ${BuildConfig.VERSION_NAME}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }

    if (currencyPickerOpen) {
        CurrencyPickerSheet(
            settingsManager = settingsManager,
            priceService = priceService,
            onDismiss = { currencyPickerOpen = false },
        )
    }

    if (confirmDelete) {
        ActionConfirmationSheet(
            title = "Delete wallet?",
            message = "This deletes the wallet from this device. Make sure you have backed up your seed phrase before continuing. This cannot be undone.",
            actionLabel = "Delete",
            destructive = true,
            onConfirm = {
                confirmDelete = false
                walletManager.launch { walletManager.deleteWallet() }
            },
            onDismiss = { confirmDelete = false },
        )
    }
}

private fun Context.openExternal(url: String) {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    startActivity(intent)
}
