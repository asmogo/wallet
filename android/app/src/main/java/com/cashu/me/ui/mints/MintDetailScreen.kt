package com.cashu.me.ui.mints

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.AlternateEmail
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Send
import androidx.compose.material.icons.outlined.Straighten
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.shortenMintUrl
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.NutSupport
import com.cashu.me.ui.components.DestructiveTextButton
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.LocalConfirmationToastController
import com.cashu.me.ui.components.MintAvatar
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.SpinnerRing
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.components.neutralActionButtonColors
import com.cashu.me.ui.components.openInBrowser
import com.cashu.me.ui.testing.UiTestTags
import com.cashu.me.ui.theme.CapsuleShape
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withSlashedZero
import kotlinx.coroutines.CancellationException

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MintDetailScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    mintUrl: String,
    onClose: () -> Unit,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val mint = walletState.mints.firstOrNull { it.url == mintUrl }
    val isActive = walletState.activeMint?.url == mintUrl
    var confirmingRemove by remember { mutableStateOf(false) }
    var settingDefault by remember(mintUrl) { mutableStateOf(false) }
    var setDefaultError by remember(mintUrl) { mutableStateOf<String?>(null) }
    var removingMint by remember(mintUrl) { mutableStateOf(false) }
    var removalError by remember(mintUrl) { mutableStateOf<String?>(null) }

    Scaffold(
        modifier = Modifier.testTag(UiTestTags.MintDetailScreen),
        topBar = {
            TopAppBar(
                title = { Text(mint?.name ?: "Mint", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        ToolbarIcon(
                            imageVector = Icons.AutoMirrored.Outlined.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        if (mint == null) {
            EmptyMintFallback(padding = padding, onClose = onClose)
            return@Scaffold
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .testTag(UiTestTags.MintDetailContent),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            HeaderBlock(mint = mint, isActive = isActive)

            // Stats block (unlabeled), matching iOS's identity rows under the
            // header: Balance [+ per-unit balances] then Connection.
            val nonSatUnits = remember(mint.units) {
                mint.units.filter { !it.equals("sat", ignoreCase = true) }.sorted()
            }
            var unitBalances by remember(mint.url) { mutableStateOf<Map<String, Long>>(emptyMap()) }
            LaunchedEffect(mint.url, nonSatUnits) {
                nonSatUnits.forEach { unit ->
                    walletManager.unitBalance(mint.url, unit)?.let { balance ->
                        unitBalances = unitBalances + (unit to balance)
                    }
                }
            }
            // One live fetch drives both Connection (reachability) and the rich
            // metadata (long description, MOTD, capabilities) — mirroring iOS's
            // `cdkInfo`. `info` prefers the fetched record, falling back to the
            // persisted mint until it lands (persisted supplies balance/icon/name).
            // A failed fetch surfaces an inline explanation + Retry, and the rows
            // below keep showing the saved record (stale), never a fake success.
            val infoLoader = remember(mint.url) { MintDetailInfoLoader<MintInfo>() }
            val liveInfo = infoLoader.info
            val connection = infoLoader.connection
            val infoError = infoLoader.errorMessage
            var refreshNonce by remember(mint.url) { mutableStateOf(0) }
            LaunchedEffect(mint.url, refreshNonce) {
                infoLoader.load { walletManager.fetchLiveMintInfo(mint.url) }
            }
            val info = liveInfo ?: mint

            if (infoError != null) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    InlineNotice(
                        text = infoError.orEmpty(),
                        detail = "Showing saved information.",
                        severity = NoticeSeverity.Caution,
                    )
                    GhostButton(
                        text = "Retry",
                        onClick = { refreshNonce += 1 },
                        enabled = connection != MintConnectionState.Checking,
                        modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
                    )
                }
            }

            Column(modifier = Modifier.fillMaxWidth()) {
                InspectorRow(
                    label = "Balance",
                    value = "${mint.balance} sat",
                    // iOS parity: the fiat conversion rides beneath the sat
                    // balance when the user enabled it — sats only, never the
                    // non-sat unit rows below.
                    secondaryValue = mintSatBalanceFiatSecondary(
                        balanceSats = mint.balance,
                        showFiat = settings.showFiatBalance,
                        btcPrice = priceState.btcPrice,
                        currencyCode = settings.bitcoinPriceCurrency,
                    ),
                    leadingIcon = Icons.Outlined.CurrencyBitcoin,
                    valueMonospaced = true,
                )
                nonSatUnits.forEach { unit ->
                    InspectorRow(
                        label = "Balance (${unit.uppercase()})",
                        value = unitBalances[unit]?.let {
                            CurrencyAmount(it, CurrencyRegistry.currencyForMintUnit(unit)).formatted()
                        } ?: "…",
                        leadingIcon = Icons.Outlined.Payments,
                        valueMonospaced = true,
                    )
                }
                InspectorRow(
                    label = "Connection",
                    value = connection.label,
                    leadingIcon = Icons.Outlined.Public,
                    valueColor = when (connection) {
                        MintConnectionState.Offline -> MaterialTheme.colorScheme.error
                        MintConnectionState.NotChecked,
                        MintConnectionState.Checking -> MaterialTheme.colorScheme.onSurfaceVariant
                        MintConnectionState.Online -> null
                    },
                )
            }

            // iOS `loadingRow`: remote metadata is still in flight — hold the
            // sections' place with a quiet spinner line instead of popping them
            // in unannounced.
            if (liveInfo == null && connection == MintConnectionState.Checking) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(
                            horizontal = CashuTheme.spacing.comfortable,
                            vertical = CashuTheme.spacing.loose,
                        ),
                ) {
                    SpinnerRing(
                        size = 18.dp,
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "Loading mint info…",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // About: short description reads primary/white; the long description
            // (iOS `descriptionLong`) reads muted and clamps to three lines with a
            // Read-more toggle — matching iOS's two-tier About.
            val shortDesc = info.description
            val longDesc = info.descriptionLong
            if (!shortDesc.isNullOrBlank() || !longDesc.isNullOrBlank()) {
                SectionHeader("About")
                var aboutExpanded by remember(mint.url) { mutableStateOf(false) }
                var aboutOverflows by remember(mint.url) { mutableStateOf(false) }
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .animateContentSize(spring(stiffness = Spring.StiffnessMediumLow)),
                    verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                ) {
                    if (!shortDesc.isNullOrBlank()) {
                        Text(
                            text = shortDesc,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
                        )
                    }
                    if (!longDesc.isNullOrBlank()) {
                        Text(
                            text = longDesc,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = if (aboutExpanded) Int.MAX_VALUE else ABOUT_COLLAPSED_LINES,
                            overflow = TextOverflow.Ellipsis,
                            onTextLayout = { aboutOverflows = aboutOverflows || it.hasVisualOverflow },
                            modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
                        )
                        if (aboutOverflows) {
                            GhostButton(
                                text = if (aboutExpanded) "Show less" else "Read more",
                                onClick = { aboutExpanded = !aboutExpanded },
                                modifier = Modifier.padding(horizontal = CashuTheme.spacing.default),
                            )
                        }
                    }
                }
            }

            val motd = info.motd
            if (!motd.isNullOrBlank()) {
                SectionHeader("Message from the mint")
                Text(
                    text = motd,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
                )
            }

            // Capabilities + Technical details come only from the live fetch, so
            // gate on it (iOS gates on `cdkInfo.nuts`).
            liveInfo?.let { live ->
                SectionHeader("Capabilities")
                val locks = buildList {
                    if (live.nutSupport.p2pk) add("P2PK")
                    if (live.nutSupport.htlc) add("HTLC")
                }
                if (locks.isNotEmpty()) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(
                                horizontal = CashuTheme.spacing.comfortable,
                                vertical = CashuTheme.spacing.default,
                            ),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Lock,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = "Locked ecash (${locks.joinToString(" · ")})",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
                TechnicalDetails(nut = live.nutSupport)
            }

            // Live NUT-06 is authoritative for the rails; the persisted report
            // fills in until it lands, and the BOLT11 compatibility default only
            // applies to a mint that was never fetched (tri-state — a direction
            // the live mint reported as absent is hidden, matching iOS).
            val receiveMethods = liveInfo?.supportedMintMethods ?: mint.effectiveMintMethods
            val sendMethods = liveInfo?.supportedMeltMethods ?: mint.effectiveMeltMethods
            if (receiveMethods.isNotEmpty() || sendMethods.isNotEmpty()) {
                SectionHeader("Payment methods")
                Column(modifier = Modifier.fillMaxWidth()) {
                    if (receiveMethods.isNotEmpty()) {
                        InspectorRow(
                            label = "Receive",
                            value = receiveMethods.joinToString(" · ") { it.displayName },
                            leadingIcon = Icons.Outlined.ArrowDownward,
                        )
                    }
                    if (sendMethods.isNotEmpty()) {
                        InspectorRow(
                            label = "Send",
                            value = sendMethods.joinToString(" · ") { it.displayName },
                            leadingIcon = Icons.Outlined.ArrowUpward,
                        )
                    }
                }
            }

            // Contact: every channel the live mint reported (blank values are
            // skipped — no dead rows). A row only becomes tappable when its
            // target parses into the mailto:/http(s) allowlist; anything else
            // stays plain text (iOS `contactSection` + `contactURL`).
            val context = LocalContext.current
            val contactRows = liveInfo?.contacts.orEmpty()
                .filter { it.info.isNotBlank() }
                .map { contact -> contact to mintContactLink(contact.method, contact.info) }
            if (contactRows.isNotEmpty()) {
                SectionHeader("Contact")
                Column(modifier = Modifier.fillMaxWidth()) {
                    contactRows.forEachIndexed { index, (contact, link) ->
                        InspectorRow(
                            label = contact.method.replaceFirstChar { it.uppercase() },
                            value = contact.info,
                            leadingIcon = mintContactIcon(contact.method),
                            onClick = link?.let { target -> { context.openInBrowser(target) } },
                            valueColor = if (link != null) MaterialTheme.colorScheme.primary else null,
                        )
                    }
                }
            }

            // Details: software and terms come only from the live NUT-06 record
            // (iOS gates on `cdkInfo`) — absent or unparseable values render no
            // row rather than a placeholder or a dead link.
            val tosUrl = safeExternalHttpUrl(liveInfo?.tosUrl)
            val software = liveInfo?.software
            SectionHeader("Details")
            Column(modifier = Modifier.fillMaxWidth()) {
                if (software != null) {
                    InspectorRow(
                        label = "Software",
                        value = "${software.name} ${software.version}",
                        leadingIcon = Icons.Outlined.Inventory2,
                    )
                }
                InspectorRow(
                    label = "Units",
                    value = mint.units.joinToString(", ").ifBlank { "sat" },
                    leadingIcon = Icons.Outlined.Straighten,
                )
                if (tosUrl != null) {
                    InspectorRow(
                        label = "Terms of Service",
                        value = externalUrlHost(tosUrl) ?: tosUrl,
                        leadingIcon = Icons.Outlined.Description,
                        onClick = { context.openInBrowser(tosUrl) },
                        trailingIcon = Icons.AutoMirrored.Outlined.OpenInNew,
                    )
                }
            }

            // Provenance (iOS `footerNote`): descriptions, contacts, software,
            // and terms above are the mint's own claims, not wallet-verified.
            Text(
                text = "Information reported by the mint.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
            )

            Spacer(Modifier.height(CashuTheme.spacing.comfortable))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = CashuTheme.spacing.comfortable),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                // When it's the default, the button disappears and the header
                // shows a "Default mint" pill instead (iOS parity).
                if (setDefaultError != null) {
                    InlineNotice(text = setDefaultError.orEmpty(), severity = NoticeSeverity.Error)
                }
                if (removalError != null) {
                    InlineNotice(text = removalError.orEmpty(), severity = NoticeSeverity.Error)
                }
                if (!isActive) {
                    // iOS parity: progress disables the action while in flight
                    // and a failure renders inline without flipping the
                    // apparent default (the pill/header only follow walletState).
                    PrimaryButton(
                        text = "Set as Default",
                        loading = settingDefault,
                        onClick = {
                            if (settingDefault) return@PrimaryButton
                            settingDefault = true
                            setDefaultError = null
                            walletManager.launch {
                                runCatching { walletManager.setActiveMint(mint) }
                                    .onFailure { setDefaultError = it.userFacingWalletMessage }
                                settingDefault = false
                            }
                        },
                        colors = neutralActionButtonColors(),
                    )
                }
                DestructiveTextButton(
                    text = "Remove mint",
                    onClick = { confirmingRemove = true },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !removingMint,
                )
            }
            Spacer(Modifier.height(CashuTheme.spacing.section))
        }
    }

    if (confirmingRemove) {
        AlertDialog(
            onDismissRequest = { confirmingRemove = false },
            title = { Text("Remove ${mint?.name ?: "mint"}?") },
            text = {
                Text(
                    "Any unspent ecash on this mint will need to be restored from your seed phrase.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmingRemove = false
                    val target = mint ?: return@TextButton
                    removingMint = true
                    removalError = null
                    walletManager.launch {
                        try {
                            walletManager.removeMint(target)
                            onClose()
                        } catch (cancellation: CancellationException) {
                            throw cancellation
                        } catch (error: Throwable) {
                            removalError = error.userFacingWalletMessage
                        } finally {
                            removingMint = false
                        }
                    }
                }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingRemove = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun HeaderBlock(mint: MintInfo, isActive: Boolean) {
    // Centered hero header, matching iOS `MintDetailView.header`: icon → name →
    // tappable URL-copy chip. No method-icon chips, no balance (balance lives in
    // the Wallet section).
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                horizontal = CashuTheme.spacing.comfortable,
                vertical = CashuTheme.spacing.comfortable,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Box {
            MintAvatar(mint = mint, size = 72.dp)
            if (isActive) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .size(CashuTheme.spacing.comfortable)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.surface),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Check,
                        contentDescription = "Active",
                        tint = CashuTheme.colors.onReceivedContainer,
                        modifier = Modifier.size(CashuTheme.spacing.default),
                    )
                }
            }
        }
        Text(
            text = mint.name,
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        CopyUrlChip(url = mint.url)
        if (isActive) {
            Text(
                text = "Default mint",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier
                    .clip(CapsuleShape)
                    .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                    .padding(
                        horizontal = CashuTheme.spacing.default,
                        vertical = CashuTheme.spacing.tight,
                    ),
            )
        }
    }
}

/// Tappable URL chip, matching iOS `copyUrlChip`: the shortened URL keeps a
/// stable Copy glyph while the shared top toast confirms the full URL was copied.
@Composable
private fun CopyUrlChip(url: String) {
    val clipboard = LocalClipboardManager.current
    val confirmationToastController = LocalConfirmationToastController.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
        modifier = Modifier
            .clip(CircleShape)
            .clickable {
                clipboard.setText(AnnotatedString(url))
                confirmationToastController?.show("Copied mint URL")
            }
            .padding(
                horizontal = CashuTheme.spacing.snug,
                vertical = CashuTheme.spacing.tight,
            ),
    ) {
        Text(
            text = shortenMintUrl(url),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.MiddleEllipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        Icon(
            imageVector = Icons.Outlined.ContentCopy,
            contentDescription = "Copy URL",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(COPY_ROW_ICON_SIZE),
        )
    }
}

@Composable
private fun EmptyMintFallback(padding: PaddingValues, onClose: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(CashuTheme.spacing.section),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Mint not found",
            style = MaterialTheme.typography.titleMedium,
        )
        Spacer(Modifier.height(CashuTheme.spacing.comfortable))
        GhostButton(text = "Back to mints", onClick = onClose)
    }
}

/**
 * Expandable NUT-support list, matching iOS's "Technical details" DisclosureGroup:
 * a clickable header with a rotating chevron that reveals the per-NUT rows.
 */
@Composable
private fun TechnicalDetails(nut: NutSupport) {
    var expanded by remember { mutableStateOf(false) }
    val chevronRotation by animateFloatAsState(
        targetValue = if (expanded) 180f else 0f,
        label = "techChevron",
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .animateContentSize(spring(stiffness = Spring.StiffnessMediumLow)),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.default,
                ),
        ) {
            Text(
                text = "Technical details",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.weight(1f))
            Icon(
                imageVector = Icons.Outlined.KeyboardArrowDown,
                contentDescription = if (expanded) "Collapse" else "Expand",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .size(20.dp)
                    .graphicsLayer { rotationZ = chevronRotation },
            )
        }
        if (expanded) {
            Column(modifier = Modifier.padding(bottom = CashuTheme.spacing.snug)) {
                NutRow("NUT-04", "Mint", true)
                NutRow("NUT-05", "Melt", true)
                NutRow("NUT-07", "Token state check", nut.tokenStateCheck)
                NutRow("NUT-08", "Lightning fee return", nut.lightningFeeReturn)
                NutRow("NUT-09", "Restore from seed", nut.restoreFromSeed)
                NutRow("NUT-10", "Spending conditions", nut.spendingConditions)
                NutRow("NUT-11", "P2PK locking", nut.p2pk)
                NutRow("NUT-12", "DLEQ proofs", nut.dleq)
                NutRow("NUT-14", "HTLCs", nut.htlc)
                NutRow("NUT-20", "WebSocket updates", nut.webSocket)
            }
        }
    }
}

@Composable
private fun NutRow(code: String, label: String, supported: Boolean) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                horizontal = CashuTheme.spacing.comfortable,
                vertical = CashuTheme.spacing.tight,
            ),
    ) {
        Text(
            text = code,
            style = MaterialTheme.typography.labelSmall.copy(fontFamily = CashuTheme.fonts.mono).withSlashedZero(),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(56.dp),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = if (supported) MaterialTheme.colorScheme.onSurface
            else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.weight(1f))
        Icon(
            imageVector = if (supported) Icons.Outlined.Check else Icons.Outlined.Remove,
            contentDescription = if (supported) "Supported" else "Not supported",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp),
        )
    }
}

/// Per-channel contact glyph (iOS `contactIcon`).
private fun mintContactIcon(method: String): ImageVector = when (method.trim().lowercase()) {
    "email" -> Icons.Outlined.MailOutline
    "twitter", "x" -> Icons.Outlined.AlternateEmail
    "nostr" -> Icons.Outlined.Key
    "website", "url", "web" -> Icons.Outlined.Public
    "telegram" -> Icons.Outlined.Send
    else -> Icons.Outlined.Person
}

/**
 * Fiat caption beneath a sat balance (iOS `showFiat`): only when the user's
 * fiat-balance preference is on and a usable BTC price is loaded. Sub-cent
 * conversions stay hidden (`AmountFormatter.formatFiat` returns null), and
 * non-sat unit balances never reach here — they render native-only.
 */
internal fun mintSatBalanceFiatSecondary(
    balanceSats: Long,
    showFiat: Boolean,
    btcPrice: Double,
    currencyCode: String,
    formatter: AmountFormatter = AmountFormatter(),
): String? {
    if (!showFiat || btcPrice <= 0) return null
    return formatter.formatFiat(balanceSats, btcPrice, currencyCode)
}

// Inline copy-row glyph (smaller than the body 20dp).
private val COPY_ROW_ICON_SIZE = 18.dp

// iOS parity: collapsed "About" clamp.
private const val ABOUT_COLLAPSED_LINES = 3
