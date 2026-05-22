package org.cashu.wallet.Views.Components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Views.Send.Components.NumberPadAmountInput

@Composable
fun AmountEntryView(
    title: String,
    buttonLabel: String,
    amount: String,
    onAmountChange: (String) -> Unit,
    onSubmit: (Long) -> Unit,
    modifier: Modifier = Modifier,
    unitLabel: String = "sat",
    selectedMint: MintInfo? = null,
    maxAmount: Long? = null,
    showMintSelector: Boolean = true,
    isLoading: Boolean = false,
    onClose: (() -> Unit)? = null,
    onUnitToggle: (() -> Unit)? = null,
    onMintSelectorClick: (() -> Unit)? = null,
) {
    val parsedAmount = amount.toLongOrNull() ?: 0
    val insufficientFunds = maxAmount != null && parsedAmount > maxAmount
    val buttonDisabled = parsedAmount <= 0 || insufficientFunds || isLoading

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            IconButton(onClick = { onClose?.invoke() }, enabled = onClose != null) {
                Icon(Icons.Default.Close, contentDescription = "Close")
            }
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            TextButton(onClick = { onUnitToggle?.invoke() }, enabled = onUnitToggle != null) {
                Text(unitLabel, fontWeight = FontWeight.Bold)
            }
        }

        if (showMintSelector) {
            MintSelectorRow(
                selectedMint = selectedMint,
                maxAmount = maxAmount,
                unitLabel = unitLabel,
                onClick = onMintSelectorClick,
            )
        }

        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = amount.ifBlank { "0" },
                style = MaterialTheme.typography.displayLarge,
                color = if (insufficientFunds) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.onBackground,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(unitLabel, color = MaterialTheme.colorScheme.secondary)
            if (insufficientFunds && parsedAmount > 0) {
                Text("Insufficient balance", color = MaterialTheme.colorScheme.error)
            }
        }

        NumberPadAmountInput(amount = amount, onAmountChange = onAmountChange)

        PrimaryActionButton(
            text = if (isLoading) "Working..." else buttonLabel,
            enabled = !buttonDisabled,
            onClick = { onSubmit(parsedAmount) },
        )
    }
}

@Composable
private fun MintSelectorRow(
    selectedMint: MintInfo?,
    maxAmount: Long?,
    unitLabel: String,
    onClick: (() -> Unit)?,
) {
    val formatter = AmountFormatter()
    QuietCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Default.AccountBalance, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
            Column(modifier = Modifier.weight(1f)) {
                Text(selectedMint?.name ?: "Select mint", fontWeight = FontWeight.Medium)
                if (selectedMint != null && maxAmount != null) {
                    Text(
                        "${formatter.formatSats(maxAmount)} $unitLabel available",
                        color = MaterialTheme.colorScheme.secondary,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            IconButton(onClick = { onClick?.invoke() }, enabled = onClick != null) {
                Icon(Icons.Default.ExpandMore, contentDescription = "Select mint")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MintPickerSheet(
    mints: List<MintInfo>,
    selectedMintUrl: String?,
    onSelectMint: (MintInfo) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 560.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Select Mint", style = MaterialTheme.typography.titleLarge)
            mints.forEach { mint ->
                TextButton(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        onSelectMint(mint)
                        onDismiss()
                    },
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Default.AccountBalance, contentDescription = null)
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.Start) {
                            Text(mint.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("${mint.balance} sat", color = MaterialTheme.colorScheme.secondary)
                        }
                        if (mint.url == selectedMintUrl) {
                            Icon(Icons.Default.CheckCircle, contentDescription = "Selected")
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun TokenDisplayCard(
    token: String,
    amountSats: Long?,
    mintUrl: String?,
    memo: String? = null,
    onCopy: (() -> Unit)? = null,
    onShare: (() -> Unit)? = null,
) {
    QuietCard {
        amountSats?.let { KeyValueRow("Amount", "$it sat") }
        mintUrl?.let { KeyValueRow("Mint", it) }
        memo?.takeIf { it.isNotBlank() }?.let { KeyValueRow("Memo", it) }
        Text(
            token,
            style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
            maxLines = 4,
            overflow = TextOverflow.Ellipsis,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = { onCopy?.invoke() }, enabled = onCopy != null) {
                Icon(Icons.Default.ContentCopy, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("Copy")
            }
            TextButton(onClick = { onShare?.invoke() }, enabled = onShare != null) {
                Icon(Icons.Default.IosShare, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("Share")
            }
        }
    }
}
