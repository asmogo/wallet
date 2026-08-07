package com.cashu.me.ui.mints

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import kotlinx.coroutines.launch
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.mintUrlCandidates
import com.cashu.me.Core.normalizeUserMintUrl
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.FlowSheetTitle
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.testing.UiTestTags

/**
 * URL entry for connecting a mint, without any sheet chrome of its own — the
 * host supplies the title, padding and dismissal. Used standalone by
 * [AddMintSheet] (Mints tab) and as the pushed step of
 * [ConnectMintSheetContent].
 *
 * Camera overlays sit under dialog windows, so [onScan] must dismiss the host
 * sheet before opening the scanner; a successful scan comes back through
 * [initialUrl].
 */
@Composable
fun AddMintFormBody(
    walletManager: WalletManager,
    onScan: () -> Unit,
    onAdded: () -> Unit,
    modifier: Modifier = Modifier,
    initialUrl: String = "",
    allowCleartextLocalTestMints: Boolean = false,
) {
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current

    var url by remember(initialUrl) { mutableStateOf(initialUrl) }
    var error by remember { mutableStateOf<String?>(null) }
    var isAdding by remember { mutableStateOf(false) }

    fun pasteFromClipboard() {
        val clipboardText = clipboard.getText()?.text
        val candidate = clipboardText?.let { mintUrlCandidates(it).firstOrNull() }
        when {
            // Empty and "held something, but not a mint URL" are different
            // mistakes with different fixes — iOS already split them.
            clipboardText.isNullOrBlank() -> error = "Clipboard is empty."
            candidate == null ->
                error = "No mint URL in your clipboard. Copy the mint's address, then paste."
            else -> {
                url = candidate
                error = null
            }
        }
    }

    fun addMint() {
        val normalized = normalizeUserMintUrl(
            url,
            allowCleartextLocalTestMints = allowCleartextLocalTestMints,
        )
        if (normalized == null) {
            // Names the requirement, which no earlier copy does — the field's
            // placeholder is the only other place https:// appears.
            error = "That doesn't look like a mint address. Mint URLs start with https://."
            return
        }
        error = null
        isAdding = true
        scope.launch {
            runCatching { walletManager.addMint(normalized) }
                .onSuccess {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    url = ""
                    onAdded()
                }
                .onFailure { error = it.userFacingWalletMessage }
            isAdding = false
        }
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        CashuTextField(
            value = url,
            onValueChange = {
                url = it
                error = null
            },
            label = "Mint URL",
            placeholder = "https://…",
            singleLine = true,
            isError = error != null,
            supportingText = error,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(UiTestTags.AddMintUrl),
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
            ),
            trailingIcon = {
                IconButton(onClick = onScan) {
                    Icon(
                        imageVector = Icons.Outlined.QrCodeScanner,
                        contentDescription = "Scan",
                    )
                }
            },
        )

        Text(
            // The label and placeholder already say "enter a mint URL"; the only
            // load-bearing sentence here is the trust one.
            text = "Mints are run by third parties; this wallet isn't affiliated " +
                "with any of them. Only add a mint you trust.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(CashuTheme.spacing.tight))

        PrimaryButton(
            text = "Add mint",
            onClick = ::addMint,
            enabled = url.isNotBlank() && !isAdding,
            loading = isAdding,
            modifier = Modifier.testTag(UiTestTags.AddMintSubmit),
        )
        GhostButton(
            text = "Paste from clipboard",
            onClick = ::pasteFromClipboard,
            enabled = !isAdding,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/**
 * Bottom sheet for pasting/typing a mint URL — mirrors iOS `AddMintSheet`.
 * The Mints tab entry point; the wallet-home and Send entry points go through
 * [ConnectMintSheetContent] instead.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddMintSheet(
    walletManager: WalletManager,
    initialUrl: String = "",
    allowCleartextLocalTestMints: Boolean = false,
    onScan: () -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .testTag(UiTestTags.AddMintSheet)
                .padding(horizontal = CashuTheme.spacing.comfortable)
                .navigationBarsPadding()
                .padding(bottom = CashuTheme.spacing.comfortable),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            // Reached from the Mints tab, not through the "Add by URL" link, so
            // this one keeps the plain name.
            FlowSheetTitle(title = "Add mint")

            AddMintFormBody(
                walletManager = walletManager,
                initialUrl = initialUrl,
                allowCleartextLocalTestMints = allowCleartextLocalTestMints,
                onScan = onScan,
                onAdded = onDismiss,
            )
        }
    }
}
