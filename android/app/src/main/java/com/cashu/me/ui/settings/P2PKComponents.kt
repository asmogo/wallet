package com.cashu.me.ui.settings

import android.content.ClipData
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.Bech32
import com.cashu.me.ui.components.CanvasDivider
import com.cashu.me.ui.components.IconSwap
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.QrCard
import com.cashu.me.ui.components.shareText
import com.cashu.me.ui.security.rememberWalletAuthenticationLauncher
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.asOverline
import com.cashu.me.ui.theme.withSlashedZero
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// iOS KeyCard geometry: 34pt glyph circle, rounded-14 card.
private val KeyGlyphSize = 36.dp
private val KeyGlyphIconSize = 18.dp
private const val CopiedFeedbackMillis = 2_000L
private const val HiddenKeyDots = 24

/**
 * Formatting for P2PK keys so they read the same everywhere (the Locked Ecash
 * hub, the Send lock chip, the receive token detail). P2PK keys are shown and
 * shared as the 33-byte compressed hex ("02…") — the form Cashu wallets expect;
 * we never re-encode them as npub. Mirrors iOS P2PKKeyDisplay.
 */
object P2PKKeyDisplay {
    /** The canonical public key for copy / QR: normalized compressed hex. */
    fun canonical(pubkey: String): String = pubkey.trim().lowercase()

    /** A short, scannable label: middle-truncated hex ("02e56288aa5c…2ef6607a91e0"). */
    fun shortLabel(pubkey: String): String = middleTruncate(canonical(pubkey), lead = 12, tail = 12)

    /** nsec (bech32) for a 32-byte private-key hex — used only when backing up a key. */
    fun nsec(privateKeyHex: String): String? = runCatching {
        val bytes = hexToBytes(privateKeyHex.trim())
        require(bytes.size == 32)
        Bech32.encode("nsec", bytes)
    }.getOrNull()

    fun middleTruncate(value: String, lead: Int, tail: Int): String {
        if (value.length <= lead + tail + 1) return value
        return "${value.take(lead)}…${value.takeLast(tail)}"
    }

    private fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0) { "Invalid hex." }
        return ByteArray(hex.length / 2) { index ->
            hex.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }
}

/** Backup status line on a KeyCard (iOS KeyCard.Status). */
enum class KeyCardStatus(val text: String) {
    SeedBacked("Backed up by your seed phrase"),
    Custom("Custom key — back it up yourself"),
    DeviceOnly("On this device only — not in your seed backup"),
}

data class KeyCardAction(
    val title: String,
    val icon: ImageVector,
    val perform: () -> Unit,
)

/**
 * The canonical card for a single key, used for both the primary key (on the
 * hub) and a device-only key (on its detail screen) so they read as one family:
 * a key glyph, a name, a backup-status line, the tap-to-copy pubkey, and up to
 * two action buttons. Mirrors iOS KeyCard (liquid glass → M3 surface container).
 */
@Composable
fun KeyCard(
    title: String,
    pubkey: String,
    status: KeyCardStatus,
    actions: List<KeyCardAction>,
    modifier: Modifier = Modifier,
) {
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(CopiedFeedbackMillis)
            copied = false
        }
    }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, MaterialTheme.shapes.medium)
            .padding(CashuTheme.spacing.comfortable),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            Box(
                modifier = Modifier
                    .size(KeyGlyphSize)
                    .background(MaterialTheme.colorScheme.surfaceContainerHighest, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Key,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(KeyGlyphIconSize),
                )
            }
            Column {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
                ) {
                    val statusTint = when (status) {
                        KeyCardStatus.SeedBacked -> MaterialTheme.colorScheme.onSurfaceVariant
                        KeyCardStatus.Custom, KeyCardStatus.DeviceOnly -> CashuTheme.colors.pending
                    }
                    Icon(
                        imageVector = when (status) {
                            KeyCardStatus.SeedBacked -> Icons.Filled.Verified
                            KeyCardStatus.Custom, KeyCardStatus.DeviceOnly -> Icons.Filled.Warning
                        },
                        contentDescription = null,
                        tint = statusTint,
                        modifier = Modifier.size(CashuTheme.spacing.default),
                    )
                    Text(
                        text = status.text,
                        style = MaterialTheme.typography.bodySmall,
                        color = statusTint,
                    )
                }
            }
        }

        // Tap-to-copy pubkey with a 2s checkmark beat (iOS parity).
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable {
                    clipboard.setText(AnnotatedString(P2PKKeyDisplay.canonical(pubkey)))
                    copied = true
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            Text(
                text = P2PKKeyDisplay.shortLabel(pubkey),
                style = MaterialTheme.typography.bodyMedium.copy(fontFamily = CashuTheme.fonts.mono).withSlashedZero(),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
            IconSwap(
                icon = if (copied) Icons.Outlined.Check else Icons.Outlined.ContentCopy,
                contentDescription = "Copy this key",
                tint = if (copied) CashuTheme.colors.received
                else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(CashuTheme.spacing.comfortable),
            )
        }

        if (actions.isNotEmpty()) {
            CanvasDivider(leadingInset = 0.dp, trailingInset = 0.dp)
            Row(modifier = Modifier.fillMaxWidth()) {
                actions.forEach { action ->
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .clickable(onClick = action.perform)
                            .padding(vertical = CashuTheme.spacing.snug),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
                    ) {
                        Icon(
                            imageVector = action.icon,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.size(CashuTheme.spacing.loose),
                        )
                        Text(
                            text = action.title,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
            }
        }
    }
}

/** Shared expanded QR sheet with visible copy/share actions (iOS QRCodeDetailSheet parity). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QrDetailSheet(
    title: String,
    content: String,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberBottomSheetState(
        initialValue = SheetValue.Hidden,
        enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded),
    )
    val clipboard = LocalClipboard.current
    val clipboardScope = rememberCoroutineScope()
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }

    LaunchedEffect(copied) {
        if (copied) {
            delay(CopiedFeedbackMillis)
            copied = false
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = CashuTheme.spacing.comfortable)
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(CashuTheme.spacing.loose))
            QrCard(content = content, staticOnly = true, shareSubject = title)
            Spacer(Modifier.height(CashuTheme.spacing.default))
            Text(
                text = content,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = CashuTheme.fonts.mono).withSlashedZero(),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(CashuTheme.spacing.default))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
            ) {
                FilledTonalButton(
                    onClick = {
                        clipboardScope.launch {
                            clipboard.setClipEntry(
                                ClipEntry(ClipData.newPlainText(title, content)),
                            )
                            copied = true
                        }
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Outlined.ContentCopy, contentDescription = null)
                    Spacer(Modifier.size(CashuTheme.spacing.micro))
                    Text(if (copied) "Copied" else "Copy")
                }
                FilledTonalButton(
                    onClick = { context.shareText(content, title) },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.AutoMirrored.Outlined.Send, contentDescription = null)
                    Spacer(Modifier.size(CashuTheme.spacing.micro))
                    Text("Share")
                }
            }
            Spacer(Modifier.height(CashuTheme.spacing.comfortable))
        }
    }
}

/**
 * Reveals a key's nsec, mirroring the seed-phrase backup pattern: the key is
 * loaded only after device authentication, independently for reveal and copy.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrivateKeyRevealSheet(
    title: String,
    loadNsec: () -> String?,
    appLockManager: AppLockManager,
    onDismiss: () -> Unit,
    warning: String = "Anyone with this key can claim ecash locked to it. Never share it.",
) {
    val clipboard = LocalClipboardManager.current
    val authenticate = rememberWalletAuthenticationLauncher(appLockManager)
    var revealedNsec by remember { mutableStateOf<String?>(null) }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(CopiedFeedbackMillis)
            copied = false
        }
    }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = CashuTheme.spacing.comfortable)
                .navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = CashuTheme.colors.pending,
                modifier = Modifier.size(CashuTheme.spacing.page),
            )
            Spacer(Modifier.height(CashuTheme.spacing.default))
            Text(
                text = "Keep this key secret",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(CashuTheme.spacing.snug))
            Text(
                text = warning,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(CashuTheme.spacing.section))

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh, MaterialTheme.shapes.small)
                    .padding(CashuTheme.spacing.default),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                Text(
                    text = "Private key (nsec)",
                    style = MaterialTheme.typography.labelMedium.asOverline(),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                ) {
                    Text(
                        text = revealedNsec ?: "•".repeat(HiddenKeyDots),
                        style = MaterialTheme.typography.bodyMedium.copy(fontFamily = CashuTheme.fonts.mono).withSlashedZero(),
                        color = if (revealedNsec != null) MaterialTheme.colorScheme.onSurface
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 3,
                        modifier = Modifier.weight(1f),
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro)) {
                        IconButton(onClick = {
                            if (revealedNsec != null) {
                                revealedNsec = null
                            } else {
                                authenticate("Reveal this private key") {
                                    revealedNsec = loadNsec()
                                }
                            }
                        }) {
                            IconSwap(
                                icon = if (revealedNsec != null) Icons.Outlined.VisibilityOff
                                else Icons.Outlined.Visibility,
                                contentDescription = if (revealedNsec != null) "Hide key" else "Reveal key",
                            )
                        }
                        IconButton(onClick = {
                            authenticate("Copy this private key") {
                                loadNsec()?.let { nsec ->
                                    clipboard.setText(AnnotatedString(nsec))
                                    copied = true
                                }
                            }
                        }) {
                            IconSwap(
                                icon = if (copied) Icons.Outlined.Check
                                else Icons.Outlined.ContentCopy,
                                contentDescription = "Copy key",
                                tint = if (copied) CashuTheme.colors.received
                                else MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(CashuTheme.spacing.section))
            PrimaryButton(text = "Done", onClick = onDismiss)
            Spacer(Modifier.height(CashuTheme.spacing.comfortable))
        }
    }
}

/**
 * Plain-language explainer for locked ecash — heavy title, secondary prose,
 * single CTA (iOS LockedEcashExplainerSheet).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LockedEcashExplainerSheet(onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = CashuTheme.spacing.page)
                .navigationBarsPadding(),
        ) {
            Text(
                text = "Locked ecash",
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(CashuTheme.spacing.loose))
            ExplainerPoint(
                icon = Icons.Outlined.LockOpen,
                text = "Ecash is bearer cash. Whoever holds a token can spend it — like a banknote.",
            )
            ExplainerPoint(
                icon = Icons.Outlined.Lock,
                text = "Locking ties a token to a key. Even if it's intercepted in transit, only the key's holder can claim it.",
            )
            ExplainerPoint(
                icon = Icons.Filled.Key,
                text = "Your key comes from your seed phrase, so it's backed up automatically. Share your key or QR, and anyone can send you locked ecash.",
            )
            ExplainerPoint(
                icon = Icons.AutoMirrored.Outlined.Send,
                text = "When you send, you can lock ecash to someone else's key so only they can claim it.",
            )
            Spacer(Modifier.height(CashuTheme.spacing.section))
            PrimaryButton(text = "Got it", onClick = onDismiss)
            Spacer(Modifier.height(CashuTheme.spacing.comfortable))
        }
    }
}

@Composable
private fun ExplainerPoint(icon: ImageVector, text: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = CashuTheme.spacing.comfortable),
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.size(CashuTheme.spacing.section),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
    }
}
