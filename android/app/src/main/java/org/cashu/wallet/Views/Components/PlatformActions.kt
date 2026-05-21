package org.cashu.wallet.Views.Components

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

@Composable
fun CopyShareRow(
    label: String,
    content: String,
    modifier: Modifier = Modifier,
    copyContent: String = content,
    shareContent: String = content,
) {
    val context = LocalContext.current
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        OutlinedButton(
            onClick = { context.copyToClipboard(label, copyContent) },
            modifier = Modifier.weight(1f),
        ) {
            Text("Copy")
        }
        OutlinedButton(
            onClick = { context.shareText(label, shareContent) },
            modifier = Modifier.weight(1f),
        ) {
            Text("Share")
        }
    }
}

fun cashuTokenShareContent(token: String): String =
    if (token.startsWith("cashu:", ignoreCase = true)) token else "cashu:$token"

@Composable
fun ClipboardSuggestionChip(
    title: String,
    detail: String,
    onUse: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    QuietCard(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.secondary,
                )
                Text(
                    text = detail,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                )
            }
            OutlinedButton(onClick = onUse) {
                Text("Use")
            }
            OutlinedButton(onClick = onDismiss) {
                Text("Dismiss")
            }
        }
    }
}

@Composable
fun rememberClipboardText(): String? {
    val context = LocalContext.current
    var clipboardText by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        clipboardText = context.readClipboardText()
    }
    return clipboardText
}

fun Context.copyToClipboard(label: String, content: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, content))
    Toast.makeText(this, "$label copied", Toast.LENGTH_SHORT).show()
}

fun Context.readClipboardText(): String? {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val item = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0) ?: return null
    return item.coerceToText(this)?.toString()?.trim()?.takeIf { it.isNotEmpty() }
}

fun Context.shareText(label: String, content: String) {
    val shareIntent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, content)
    }
    startActivity(Intent.createChooser(shareIntent, label).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

fun Context.openUrl(url: String) {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    startActivity(intent)
}
