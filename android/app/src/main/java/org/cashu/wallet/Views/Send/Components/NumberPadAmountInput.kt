package org.cashu.wallet.Views.Send.Components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.WalletHaptic
import org.cashu.wallet.Core.rememberWalletHaptics

@Composable
fun NumberPadAmountInput(
    amount: String,
    onAmountChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptics = rememberWalletHaptics()
    val rows = listOf(
        listOf("1", "2", "3"),
        listOf("4", "5", "6"),
        listOf("7", "8", "9"),
        listOf("", "0", "delete"),
    )

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        rows.forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                row.forEach { key ->
                    when (key) {
                        "" -> Box(modifier = Modifier.weight(1f).height(56.dp))
                        "delete" -> NumberPadKey(
                            modifier = Modifier.weight(1f),
                            contentDescription = "Delete",
                            onClick = {
                                if (amount.isNotEmpty()) {
                                    haptics.perform(WalletHaptic.Selection)
                                    onAmountChange(amount.dropLast(1))
                                }
                            },
                            onLongClick = {
                                if (amount.isNotEmpty()) {
                                    haptics.perform(WalletHaptic.LightImpact)
                                    onAmountChange("")
                                }
                            },
                        ) {
                            Icon(Icons.AutoMirrored.Filled.Backspace, contentDescription = null)
                        }
                        else -> NumberPadKey(
                            modifier = Modifier.weight(1f),
                            contentDescription = key,
                            onClick = {
                                haptics.perform(WalletHaptic.Selection)
                                onAmountChange(if (amount == "0") key else amount + key)
                            },
                        ) {
                            Text(
                                text = key,
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Normal,
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun NumberPadKey(
    contentDescription: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    Surface(
        modifier = modifier
            .height(56.dp)
            .combinedClickable(
                onClickLabel = contentDescription,
                onLongClickLabel = onLongClick?.let { "Clear" },
                onLongClick = onLongClick,
                onClick = onClick,
            ),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            content()
        }
    }
}
