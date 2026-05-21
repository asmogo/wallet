package org.cashu.wallet.Views.Mints

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.shortenMintUrl
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Views.Components.CopyShareRow
import org.cashu.wallet.Views.Components.KeyValueRow
import org.cashu.wallet.Views.Components.SectionHeader

@Composable
fun MintDetailView(
    mint: MintInfo,
    modifier: Modifier = Modifier,
    showTitle: Boolean = true,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (showTitle) {
            Text(mint.name, style = MaterialTheme.typography.headlineSmall)
        }
        mint.description?.let { Text(it, color = MaterialTheme.colorScheme.secondary) }
        KeyValueRow("URL", shortenMintUrl(mint.url))
        CopyShareRow(label = "Mint URL", content = mint.url)
        KeyValueRow("Balance", "${mint.balance} sat")
        KeyValueRow("Units", mint.units.joinToString(", ").ifBlank { "None" })
        SectionHeader("Methods")
        KeyValueRow("Receive", mint.supportedMintMethods.joinToString { it.displayName }.ifBlank { "None" })
        KeyValueRow("Send", mint.supportedMeltMethods.joinToString { it.displayName }.ifBlank { "None" })
        mint.onchainMintConfirmations?.let { KeyValueRow("On-chain confirmations", it.toString()) }
        mint.iconUrl?.let { KeyValueRow("Icon", shortenMintUrl(it)) }
    }
}
