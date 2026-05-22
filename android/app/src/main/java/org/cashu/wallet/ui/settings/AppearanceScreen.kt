package org.cashu.wallet.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.PriceService
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.SectionHeader
import org.cashu.wallet.ui.components.ToggleRow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppearanceScreen(
    settingsManager: SettingsManager,
    priceService: PriceService,
    onClose: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Appearance", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
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
        ) {
            SectionHeader("Theme")
            Column(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = "Follows system theme",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "Switch Light/Dark in Android system settings.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            SectionHeader("Display")
            ToggleRow(
                title = "Show fiat balance",
                subtitle = "Display USD/EUR equivalent next to sats",
                checked = settings.showFiatBalance,
                onCheckedChange = {
                    settingsManager.setShowFiatBalance(it)
                    priceService.syncFromSettings(refresh = it)
                },
            )
            CanvasDivider(leadingInset = 16)
            ToggleRow(
                title = "Use ₿ symbol",
                subtitle = "Prefix balances with ₿ instead of \"sat\"",
                checked = settings.useBitcoinSymbol,
                onCheckedChange = { settingsManager.setUseBitcoinSymbol(it) },
            )
        }
    }
}
