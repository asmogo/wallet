package com.cashu.me.ui.settings

import android.content.ClipData
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.Bech32
import com.cashu.me.ui.components.LocalConfirmationToastController
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.QrCard
import com.cashu.me.ui.components.SecondaryButton
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.components.shareText
import com.cashu.me.ui.security.rememberWalletAuthenticationLauncher
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.tracked
import com.cashu.me.ui.theme.withSlashedZero

// iOS KeyCard geometry: 34pt glyph circle, rounded-14 card.
private val KeyGlyphSize = 36.dp
private val KeyGlyphIconSize = 18.dp

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

/**
 * Backup status line on a KeyCard (iOS KeyCard.Status). A null text renders no
 * line — a custom key's backup burden is carried by the import confirmation,
 * not a permanent warning badge on the card.
 */
enum class KeyCardStatus(val text: String?) {
    SeedBacked("Backed up by your seed phrase"),
    Custom(null),
    DeviceOnly("On this device only — not in your seed backup"),
    RepairRequired("Repair required before this key can be used"),
}

data class KeyCardAction(
    val title: String,
    val icon: ImageVector,
    val perform: () -> Unit,
)

/**
 * An extra copy target offered on long-press, for values that shouldn't take a
 * row of their own (the Nostr key's hex encoding next to its npub).
 */
data class KeyCardCopyOption(
    val title: String,
    val value: String,
)

/**
 * The canonical card for a single key, used for both the primary key (on the
 * hub) and a device-only key (on its detail screen) so they read as one family:
 * a key glyph, a name, a backup-status line, the tap-to-copy pubkey, and up to
 * two action buttons. Mirrors iOS KeyCard (liquid glass → M3 surface container).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun KeyCard(
    title: String,
    pubkey: String,
    status: KeyCardStatus,
    actions: List<KeyCardAction>,
    modifier: Modifier = Modifier,
    copyOptions: List<KeyCardCopyOption> = emptyList(),
    copyEnabled: Boolean = true,
) {
    val clipboard = LocalClipboardManager.current
    val confirmationToastController = LocalConfirmationToastController.current
    val haptics = LocalHapticFeedback.current
    var menuOpen by remember { mutableStateOf(false) }
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
                val statusText = status.text
                if (statusText != null) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
                    ) {
                        val statusTint = when (status) {
                            KeyCardStatus.SeedBacked -> MaterialTheme.colorScheme.onSurfaceVariant
                            KeyCardStatus.Custom, KeyCardStatus.DeviceOnly -> CashuTheme.colors.pending
                            KeyCardStatus.RepairRequired -> MaterialTheme.colorScheme.error
                        }
                        Icon(
                            imageVector = when (status) {
                                KeyCardStatus.SeedBacked -> Icons.Filled.Verified
                                KeyCardStatus.Custom,
                                KeyCardStatus.DeviceOnly,
                                KeyCardStatus.RepairRequired,
                                -> Icons.Filled.Warning
                            },
                            contentDescription = null,
                            tint = statusTint,
                            modifier = Modifier.size(CashuTheme.spacing.default),
                        )
                        Text(
                            text = statusText,
                            style = MaterialTheme.typography.bodySmall,
                            color = statusTint,
                        )
                    }
                }
            }
        }

        // Tap-to-copy pubkey with stable affordance + shared toast. When the caller
        // supplies alternate encodings, long-press offers them without spending a row.
        Box {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .then(
                        if (copyOptions.isEmpty()) {
                            Modifier
                                .semantics {
                                    contentDescription = if (copyEnabled) {
                                        "Copy this key"
                                    } else {
                                        "Key unavailable"
                                    }
                                    if (!copyEnabled) disabled()
                                }
                                .clickable(enabled = copyEnabled) {
                                clipboard.setText(AnnotatedString(P2PKKeyDisplay.canonical(pubkey)))
                                confirmationToastController?.show("Copied key")
                            }
                        } else {
                            Modifier
                                .semantics {
                                    contentDescription =
                                        "$title. Long press for more copy options."
                                }
                                .combinedClickable(
                                    enabled = copyEnabled,
                                    onClick = {
                                        clipboard.setText(
                                            AnnotatedString(P2PKKeyDisplay.canonical(pubkey)),
                                        )
                                        confirmationToastController?.show("Copied key")
                                    },
                                    onLongClick = {
                                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                        menuOpen = true
                                    },
                                    onLongClickLabel = "Show copy options",
                                )
                        },
                    ),
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
                Icon(
                    imageVector = Icons.Outlined.ContentCopy,
                    contentDescription = if (copyEnabled) "Copy this key" else "Key unavailable",
                    tint = if (copyEnabled) {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f)
                    },
                    modifier = Modifier.size(CashuTheme.spacing.comfortable),
                )
            }
            DropdownMenu(
                expanded = menuOpen,
                onDismissRequest = { menuOpen = false },
                shape = MaterialTheme.shapes.large,
            ) {
                copyOptions.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option.title) },
                        leadingIcon = {
                            Icon(Icons.Outlined.ContentCopy, contentDescription = null)
                        },
                        onClick = {
                            menuOpen = false
                            clipboard.setText(AnnotatedString(option.value))
                            confirmationToastController?.show("Copied key")
                        },
                    )
                }
            }
        }

        if (actions.isNotEmpty()) {
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
    val confirmationToastController = LocalConfirmationToastController.current

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = CashuTheme.spacing.comfortable)
                    .navigationBarsPadding()
                    .verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                // Canonical sheet chrome, like the sibling reveal sheet —
                // not a bare titleMedium line.
                SheetHeader(title = title)
                Spacer(Modifier.height(CashuTheme.spacing.snug))
                QrCard(
                    content = content,
                    // 248 code + 16 cushion = the 280 card iOS draws, so both
                    // sheets carry the same code-to-sheet proportion.
                    size = 248.dp,
                    staticOnly = true,
                    shareSubject = title,
                    confirmationMessage = "Copied ${title.lowercase()}",
                )
                Spacer(Modifier.height(CashuTheme.spacing.comfortable))
                // One middle-truncated line at full body size and primary ink —
                // the sheet's second focal point, not a footnote. The full
                // value travels via Copy/Share.
                Text(
                    text = content,
                    style = CashuTheme.type.monoDisplay,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                )
                Spacer(Modifier.height(CashuTheme.spacing.section))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
                ) {
                    SecondaryButton(
                        text = "Copy",
                        onClick = {
                            clipboardScope.launch {
                                clipboard.setClipEntry(
                                    ClipEntry(ClipData.newPlainText(title, content)),
                                )
                                confirmationToastController?.show("Copied ${title.lowercase()}")
                            }
                        },
                        modifier = Modifier.weight(1f),
                    )
                    PrimaryButton(
                        text = "Share",
                        onClick = { context.shareText(content, title) },
                        // Inverted ink, matching the confirm sheets' action button
                        // and iOS's white Share pill (PrimaryButton is gray by default).
                        colors = ButtonDefaults.buttonColors(),
                        modifier = Modifier.weight(1f),
                    )
                }
                Spacer(Modifier.height(CashuTheme.spacing.comfortable))
            }
        }
    }
}

/**
 * Reveals a key's nsec, matching the seed-phrase backup sheet beat for beat
 * (iOS `PrivateKeyRevealSheet` parity): sheet title, warning copy, and one CTA
 * that flips from Reveal to Copy once the key is showing, on a sheet dismissed
 * by drag. The key is loaded only after device authentication, independently
 * for reveal and copy.
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
    val confirmationToastController = LocalConfirmationToastController.current
    val authenticate = rememberWalletAuthenticationLauncher(appLockManager)
    var revealedNsec by remember { mutableStateOf<String?>(null) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Box(modifier = Modifier.fillMaxWidth()) {
            PrivateKeyRevealContent(
                title = title,
                warning = warning,
                revealedNsec = revealedNsec,
                onReveal = {
                    authenticate("Reveal this private key") { revealedNsec = loadNsec() }
                },
                onCopy = {
                    authenticate("Copy this private key") {
                        loadNsec()?.let { nsec ->
                            clipboard.setText(AnnotatedString(nsec))
                            confirmationToastController?.show("Copied private key")
                        }
                    }
                },
            )
        }
    }
}

/**
 * The reveal sheet's body, without auth or sheet chrome, so it can be rendered
 * in isolation by tests and previews.
 */
@Composable
internal fun PrivateKeyRevealContent(
    title: String,
    warning: String,
    revealedNsec: String?,
    onReveal: () -> Unit,
    onCopy: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = CashuTheme.spacing.comfortable)
            .padding(bottom = CashuTheme.spacing.section)
            .animateContentSize(
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioNoBouncy,
                    stiffness = Spring.StiffnessMediumLow,
                ),
            ),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
    ) {
        // Names which key is on screen — the app holds a Nostr key, a primary
        // P2PK key, and any number of device keys.
        SheetHeader(title = title)

        Text(
            text = warning,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        if (revealedNsec != null) {
            // Same container treatment the revealed seed words use.
            Text(
                text = revealedNsec,
                style = MaterialTheme.typography.bodyMedium
                    .copy(fontFamily = CashuTheme.fonts.mono)
                    .withSlashedZero(),
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surfaceContainer, MaterialTheme.shapes.medium)
                    .padding(CashuTheme.spacing.default),
            )
        }

        // Reveal is the sheet's one primary action; once the key is showing,
        // Copy is a quieter follow-up and drops to the secondary style.
        if (revealedNsec != null) {
            SecondaryButton(
                text = "Copy Private Key",
                onClick = onCopy,
                modifier = Modifier.fillMaxWidth(),
            )
        } else {
            PrimaryButton(
                text = "Reveal Private Key",
                onClick = onReveal,
                colors = ButtonDefaults.buttonColors(),
                modifier = Modifier.fillMaxWidth(),
            )
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
                // iOS's `.title.weight(.heavy)` with tightened tracking — the
                // bare headlineMedium renders regular-weight and reads off-brand
                // next to every other bold surface title.
                style = MaterialTheme.typography.headlineMedium
                    .copy(fontWeight = FontWeight.Bold)
                    .tracked(-0.01f),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(CashuTheme.spacing.loose))
            ExplainerPoint(
                icon = LockOpenClear,
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
            // Dismissal-only CTA — secondary on both platforms.
            SecondaryButton(text = "Got it", onClick = onDismiss)
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
            // iOS `.callout` (16pt) — bodyMedium's 14sp made the prose read a
            // size class smaller than the iOS sheet.
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
    }
}

/**
 * An unlocked padlock whose shackle is swung open with a visible gap (SF
 * `lock.open` parity). Material's `Outlined.LockOpen` keeps the shackle arched
 * over the body, so at 24dp it reads as locked — defeating the one bullet whose
 * whole point is "unlocked".
 */
private val LockOpenClear: ImageVector by lazy {
    ImageVector.Builder(
        name = "LockOpenClear",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        // Body
        path(
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        ) {
            moveTo(6f, 10f)
            horizontalLineTo(12f)
            arcTo(2f, 2f, 0f, false, true, 14f, 12f)
            verticalLineTo(19f)
            arcTo(2f, 2f, 0f, false, true, 12f, 21f)
            horizontalLineTo(6f)
            arcTo(2f, 2f, 0f, false, true, 4f, 19f)
            verticalLineTo(12f)
            arcTo(2f, 2f, 0f, false, true, 6f, 10f)
            close()
        }
        // Keyhole
        path(fill = SolidColor(Color.Black)) {
            moveTo(9f, 14f)
            arcToRelative(1.5f, 1.5f, 0f, true, true, 0f, 3f)
            arcToRelative(1.5f, 1.5f, 0f, true, true, 0f, -3f)
            close()
        }
        // Shackle, attached on the left and hanging open past the body's edge
        path(
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        ) {
            moveTo(9f, 10f)
            verticalLineTo(6.5f)
            arcTo(3.5f, 3.5f, 0f, false, true, 16f, 6.5f)
            verticalLineTo(8f)
        }
    }.build()
}
