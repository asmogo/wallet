package com.cashu.me.ui.screenshots

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.android.tools.screenshot.PreviewTest
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.theme.CashuTheme

// Inline-error parity audit. Two catalogs:
//
//   inline-notice-matrix   — the shared InlineNotice contract, every severity.
//   inline-error-variants  — the hand-rolled inline errors, as they render
//                            after being routed through the component. Each is
//                            labelled with the source it came from. Sections
//                            marked FIXED render the real post-migration code;
//                            the rest are still reproductions, because the
//                            originals are private composables that cannot be
//                            called from a preview.
//
// See docs/product/inline-error-audit.md.

private const val INSUFFICIENT = "Insufficient balance"
private const val INSUFFICIENT_DETAIL = "You have 21,000 sat in Testnut mint."

@PreviewTest
@Preview(name = "inline-notice-matrix", widthDp = 390, heightDp = 760, showBackground = true)
@Composable
fun inlineNoticeMatrixLightScreenshot() {
    CatalogFrame { NoticeMatrix() }
}

@PreviewTest
@Preview(
    name = "inline-notice-matrix-dark",
    widthDp = 390,
    heightDp = 760,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
fun inlineNoticeMatrixDarkScreenshot() {
    CatalogFrame(darkTheme = true) { NoticeMatrix() }
}

@PreviewTest
@Preview(name = "inline-error-variants", widthDp = 390, heightDp = 640, showBackground = true)
@Composable
fun inlineErrorVariantsLightScreenshot() {
    CatalogFrame { HandRolledVariants() }
}

@PreviewTest
@Preview(
    name = "inline-error-variants-dark",
    widthDp = 390,
    heightDp = 640,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
fun inlineErrorVariantsDarkScreenshot() {
    CatalogFrame(darkTheme = true) { HandRolledVariants() }
}

/** Every severity the in-context channel supports. */
@Composable
private fun NoticeMatrix() {
    CatalogSection("InlineNotice — the in-context channel, M3 role pairs") {
        InlineNotice(text = "Couldn't reach the mint.", severity = NoticeSeverity.Error)
        InlineNotice(
            text = INSUFFICIENT,
            severity = NoticeSeverity.Caution,
            detail = INSUFFICIENT_DETAIL,
        )
        InlineNotice(
            text = "This request asks for a mint you have not added yet.",
            severity = NoticeSeverity.Info,
        )
        InlineNotice(text = "Backed up to your relays.", severity = NoticeSeverity.Success)
    }

    CatalogSection("Field-attached errors now leave via M3 supporting text") {
        CashuTextField(
            value = "notaurl",
            onValueChange = {},
            label = "Mint URL",
            isError = true,
            supportingText = "That doesn't look like a mint URL.",
            modifier = Modifier.fillMaxWidth(),
        )
    }

    CatalogSection("Detail line present vs absent — same state, two call sites") {
        InlineNotice(
            text = INSUFFICIENT,
            severity = NoticeSeverity.Caution,
            detail = INSUFFICIENT_DETAIL,
        )
        InlineNotice(text = INSUFFICIENT, severity = NoticeSeverity.Caution)
    }

    CatalogSection("Bare + centred — the Send amount faces") {
        // No card to sit in and a centred amount above it, so the fill comes off
        // and the glyph + text centre as a group. Everything else keeps the
        // tonal container.
        InlineNotice(
            text = INSUFFICIENT,
            severity = NoticeSeverity.Caution,
            showsContainer = false,
            centered = true,
        )
    }
}

/** Reproductions of the inline errors that never reach InlineNotice. */
@Composable
private fun HandRolledVariants() {
    CatalogSection("V7 — FIXED: one signal, M3 supporting text (SendEcashScreen.kt:954)") {
        // Was: a field tinted error@0.12 with bare bodySmall red text below it,
        // two reds for one error. Now the field owns the whole thing.
        CashuTextField(
            value = "npub1nots0avalidkey",
            onValueChange = {},
            label = "Recipient public key",
            isError = true,
            supportingText = "That's not a valid public key.",
            modifier = Modifier.fillMaxWidth(),
        )
    }

    CatalogSection("V8 — error Text as row subtitle (RestoreWalletFlow.kt:896)") {
        Column {
            Text(
                text = "Testnut",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "Couldn't restore from this mint. Check the URL and retry.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
                maxLines = 2,
            )
        }
    }

    CatalogSection("V9 — icon+text warning row (OnboardingScreen.kt:574, P2PKComponents.kt:195)") {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = CashuTheme.colors.pending,
                modifier = Modifier.size(14.dp),
            )
            Text(
                text = "Never share these words with anyone",
                style = MaterialTheme.typography.labelMedium,
                color = CashuTheme.colors.pending,
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = CashuTheme.colors.pending,
                modifier = Modifier.size(CashuTheme.spacing.default),
            )
            Text(
                text = "This key never left the device.",
                style = MaterialTheme.typography.bodySmall,
                color = CashuTheme.colors.pending,
            )
        }
    }

    CatalogSection("V10 — centered warning hero (BackupScreen.kt:95, P2PKComponents.kt:477)") {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = CashuTheme.colors.pending,
                modifier = Modifier.size(32.dp),
            )
            Text(
                text = "Write these words down",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
            )
            Text(
                text = "Anyone with them can spend your ecash.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }

    CatalogSection("Severity is about cost to the user, not how we found out") {
        // Error is reserved for "the action failed". The recipient-key message
        // above never renders like this — it ships as supportingText on the
        // field. Validation and unmet preconditions are not the Error tier.
        InlineNotice(
            text = "Couldn't reach the mint.",
            severity = NoticeSeverity.Error,
        )
        InlineNotice(
            text = "No valid mint URL found in QR code.",
            severity = NoticeSeverity.Caution,
        )
        InlineNotice(
            text = "NFC is not available on this device.",
            severity = NoticeSeverity.Info,
        )
    }
}

@Composable
private fun CatalogSection(
    label: String,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = CashuTheme.spacing.comfortable),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        content()
    }
}

@Composable
private fun CatalogFrame(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit,
) {
    CashuTheme(darkTheme = darkTheme) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(CashuTheme.spacing.comfortable),
                verticalArrangement = Arrangement.Top,
            ) {
                content()
            }
        }
    }
}
