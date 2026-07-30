package com.cashu.me.ui.send

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.displayMintUnitAmount
import com.cashu.me.ui.components.AmountText
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits

internal data class PaymentConfirmationAmountPresentation(
    val primary: String,
    val alternate: String?,
    val talkBackDescription: String,
)

internal fun paymentConfirmationAmountPresentation(
    amount: Long,
    unit: String,
    preferredPrimary: String,
    showFiat: Boolean,
    btcPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
    formatter: AmountFormatter = AmountFormatter(),
): PaymentConfirmationAmountPresentation {
    val display = formatter.displayMintUnitAmount(
        amount = amount,
        unit = unit,
        preferredPrimary = preferredPrimary,
        showFiat = showFiat,
        btcPrice = btcPrice,
        currencyCode = currencyCode,
        useBitcoinSymbol = useBitcoinSymbol,
    )
    val description = buildString {
        append("Payment amount, ")
        append(display.primary)
        display.secondary?.let {
            append(". Alternate value, ")
            append(it)
        }
    }
    return PaymentConfirmationAmountPresentation(
        primary = display.primary,
        alternate = display.secondary,
        talkBackDescription = description,
    )
}

/**
 * Read-only confirmation hero. The persisted primary unit leads while the
 * conversion remains visible as supporting information; the whole pair is one
 * concise TalkBack stop instead of an iOS-style unit-flip control.
 */
@Composable
internal fun PaymentConfirmationAmount(
    amount: Long,
    unit: String,
    preferredPrimary: String,
    showFiat: Boolean,
    btcPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
    formatter: AmountFormatter,
    modifier: Modifier = Modifier,
) {
    val presentation = paymentConfirmationAmountPresentation(
        amount = amount,
        unit = unit,
        preferredPrimary = preferredPrimary,
        showFiat = showFiat,
        btcPrice = btcPrice,
        currencyCode = currencyCode,
        useBitcoinSymbol = useBitcoinSymbol,
        formatter = formatter,
    )
    Column(
        modifier = modifier.clearAndSetSemantics {
            contentDescription = presentation.talkBackDescription
        },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        AmountText(
            text = presentation.primary,
            style = MaterialTheme.typography.displayMedium.withMonoDigits(),
        )
        presentation.alternate?.let { alternate ->
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surfaceVariant,
                contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            ) {
                Text(
                    text = alternate,
                    modifier = Modifier.padding(
                        horizontal = CashuTheme.spacing.default,
                        vertical = CashuTheme.spacing.micro,
                    ),
                    style = MaterialTheme.typography.labelLarge.withMonoDigits(),
                )
            }
        }
    }
}
