package com.cashu.me.ui.receive

import android.content.res.Configuration
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.android.tools.screenshot.PreviewTest
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.theme.CashuTheme

@PreviewTest
@Preview(name = "receive-sats-light", widthDp = 390, heightDp = 780)
@Preview(name = "receive-sats-dark", widthDp = 390, heightDp = 780, uiMode = Configuration.UI_MODE_NIGHT_YES)
@Preview(name = "receive-compact", widthDp = 320, heightDp = 568)
@Preview(name = "receive-large-text", widthDp = 390, heightDp = 780, fontScale = 1.5f)
@Composable
fun receiveSatsTypographyScreenshot() {
    ReceiveTypographyPreview()
}

@PreviewTest
@Preview(name = "receive-fiat-dark", widthDp = 390, heightDp = 780, uiMode = Configuration.UI_MODE_NIGHT_YES)
@Composable
fun receiveFiatTypographyScreenshot() {
    ReceiveTypographyPreview(fiat = true)
}

@Composable
private fun ReceiveTypographyPreview(fiat: Boolean = false) {
    CashuTheme {
        Surface {
            Column(Modifier.fillMaxSize()) {
                SheetHeader(title = "Receive")
                InputFace(
                    amount = if (fiat) "21" else "30497",
                    onAmountChange = {},
                    selectedMethod = PaymentMethodKind.Bolt11,
                    creating = false,
                    mint = MintInfo(url = "https://mint.example", name = "Example mint"),
                    mintBalanceText = "₿74,403",
                    onPickMint = {},
                    isSatUnit = true,
                    unit = "sat",
                    amountSats = 30497,
                    entryPrimary = if (fiat) AmountDisplayPrimary.Fiat else AmountDisplayPrimary.Sats,
                    onFlipEntryPrimary = {},
                    btcPrice = 68859.23,
                    fiatCurrencyCode = "EUR",
                    useBitcoinSymbol = true,
                    formatter = AmountFormatter(),
                    decimals = if (fiat) 2 else 0,
                    amountValid = true,
                    errorText = null,
                    onCreate = {},
                )
            }
        }
    }
}
