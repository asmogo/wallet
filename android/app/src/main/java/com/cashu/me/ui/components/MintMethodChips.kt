package com.cashu.me.ui.components

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.ui.theme.CashuTheme

private val MethodIconSize = 20.dp

/**
 * Compact payment-method glyphs for mint rows — icon when known, otherwise a
 * border-only text pill (no fill). Sits on the same line as the mint name.
 */
@Composable
fun MintMethodChips(
    mint: MintInfo,
    modifier: Modifier = Modifier,
) {
    val methods = remember(mint.supportedMintMethods, mint.supportedMeltMethods) {
        (mint.effectiveMintMethods + mint.effectiveMeltMethods).distinct().sortedBy { it.sortOrder }
    }
    MintMethodChips(methods = methods, modifier = modifier)
}

@Composable
fun MintMethodChips(
    methods: List<PaymentMethodKind>,
    modifier: Modifier = Modifier,
) {
    if (methods.isEmpty()) return
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        methods.forEach { method ->
            MethodGlyph(method = method)
        }
    }
}

@Composable
private fun MethodGlyph(method: PaymentMethodKind) {
    val icon = method.rowIcon
    if (icon != null) {
        Icon(
            imageVector = icon,
            contentDescription = method.displayName,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .size(MethodIconSize)
                .border(
                    width = 1.dp,
                    color = MaterialTheme.colorScheme.outlineVariant,
                    shape = CircleShape,
                )
                .padding(3.dp),
        )
    } else {
        Text(
            text = method.displayName,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier
                .border(
                    width = 1.dp,
                    color = MaterialTheme.colorScheme.outlineVariant,
                    shape = RoundedCornerShape(percent = 50),
                )
                .padding(
                    horizontal = CashuTheme.spacing.snug,
                    vertical = CashuTheme.spacing.micro,
                ),
        )
    }
}

private val PaymentMethodKind.rowIcon: ImageVector?
    get() = when (this) {
        PaymentMethodKind.Bolt11 -> Icons.Outlined.Bolt
        PaymentMethodKind.Bolt12 -> Icons.Outlined.Repeat
        PaymentMethodKind.Onchain -> Icons.Outlined.CurrencyBitcoin
    }
