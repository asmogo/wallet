package com.cashu.me.ui.screenshots

import android.content.res.Configuration
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.android.tools.screenshot.PreviewTest
import com.cashu.me.ui.components.ActionConfirmationContent
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.theme.CashuTheme

@PreviewTest
@Preview(name = "confirmation-light", widthDp = 390, heightDp = 380)
@Preview(name = "confirmation-dark", widthDp = 390, heightDp = 380, uiMode = Configuration.UI_MODE_NIGHT_YES)
@Preview(name = "confirmation-large-text", widthDp = 320, heightDp = 720, fontScale = 2f)
@Composable
fun removeMintConfirmationScreenshot() {
    CashuTheme {
        Surface {
            ActionConfirmationContent(
                title = "Remove mint?",
                message = "Remove Cashu mint from your wallet? Any unspent ecash on this mint will need to be restored from your seed phrase.",
                actionLabel = "Remove",
                destructive = true,
                onConfirm = {},
                onDismiss = {},
            )
        }
    }
}

@PreviewTest
@Preview(name = "lightning-error-light", widthDp = 390, heightDp = 130)
@Preview(name = "lightning-error-dark", widthDp = 390, heightDp = 130, uiMode = Configuration.UI_MODE_NIGHT_YES)
@Composable
fun lightningConnectionErrorScreenshot() {
    CashuTheme {
        Surface {
            Column(Modifier.padding(20.dp)) {
                InlineNotice(
                    text = "Couldn't connect to the Lightning address service. Try again shortly.",
                    severity = NoticeSeverity.Error,
                )
            }
        }
    }
}
