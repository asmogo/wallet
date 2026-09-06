package com.cashu.me.ui.screenshots

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.android.tools.screenshot.PreviewTest
import com.cashu.me.ui.components.DestructiveTextButton
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SecondaryButton
import com.cashu.me.ui.components.TextButtonContext
import com.cashu.me.ui.theme.CashuTheme

@PreviewTest
@Preview(name = "buttons-light", widthDp = 390)
@Preview(name = "buttons-dark", widthDp = 390, uiMode = Configuration.UI_MODE_NIGHT_YES)
@Preview(name = "buttons-large-text", widthDp = 320, fontScale = 2f, uiMode = Configuration.UI_MODE_NIGHT_YES)
@Composable
fun sharedButtonHierarchy() {
    CashuTheme {
        Surface {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                PrimaryButton(text = "Set as Default", onClick = {})
                SecondaryButton(text = "Other options", onClick = {})
                GhostButton(text = "Back", onClick = {}, context = TextButtonContext.Screen,
                    modifier = Modifier.fillMaxWidth())
                DestructiveTextButton(text = "Remove mint", onClick = {}, context = TextButtonContext.Screen,
                    modifier = Modifier.fillMaxWidth())
                DestructiveTextButton(text = "Remove Key", onClick = {}, context = TextButtonContext.Screen,
                    modifier = Modifier.fillMaxWidth(), enabled = false)
                Text("Compact actions", style = MaterialTheme.typography.bodyMedium)
                Row {
                    GhostButton(text = "Paste", onClick = {}, context = TextButtonContext.Compact)
                    DestructiveTextButton(text = "Remove", onClick = {}, context = TextButtonContext.Compact)
                }
            }
        }
    }
}
