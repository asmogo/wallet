package com.cashu.me.ui.mints

import android.content.res.Configuration
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import com.android.tools.screenshot.PreviewTest
import com.cashu.me.ui.theme.CashuTheme

@PreviewTest
@Preview(name = "connection-light", widthDp = 390)
@Preview(name = "connection-dark", widthDp = 390, uiMode = Configuration.UI_MODE_NIGHT_YES)
@Preview(name = "connection-large-text", widthDp = 320, fontScale = 2f, uiMode = Configuration.UI_MODE_NIGHT_YES)
@Composable
fun mintConnectionStates() {
    CashuTheme {
        Surface {
            Column {
                MintConnectionStatus(MintConnectionState.Offline, showsRecovery = true, onRetry = {})
                MintConnectionStatus(MintConnectionState.Checking, showsRecovery = true, onRetry = {})
                MintConnectionStatus(MintConnectionState.Online, showsRecovery = false, onRetry = {})
            }
        }
    }
}
