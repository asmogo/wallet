package com.cashu.me.ui.mints

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AddCircle
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import com.cashu.me.Core.MintDiscoveryManager
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.shortenMintUrl
import com.cashu.me.Models.MintInfo
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.MintAvatar
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.components.TwoFaceScreen
import com.cashu.me.ui.navigation.ConnectMintBackAction
import com.cashu.me.ui.navigation.connectMintBackAction
import com.cashu.me.ui.testing.UiTestTags
import com.cashu.me.ui.theme.CashuTheme
import androidx.compose.runtime.collectAsState

/**
 * Where the connect-a-mint sheet was opened from. Only the header differs: from
 * Send the sheet is still "Send" and needs an in-body headline explaining why
 * the flow stalled, while the wallet-home CTA already said "Add mint" — repeating
 * it as a headline would stack three levels of title before the list.
 */
enum class ConnectMintContext {
    Send,
    AddMint,
    ;

    internal val pickerTitle: String
        get() = when (this) {
            Send -> "Send"
            AddMint -> "Add mint"
        }

    internal val showsHeadline: Boolean
        get() = this == Send

    internal companion object {
        // The app says "add" everywhere else — CTAs, row a11y labels, the submit
        // button — so the headline says it too rather than introducing "connect"
        // as a second verb for the same act.
        const val HEADLINE = "Add a mint first"
        const val SUBTITLE =
            "Mints issue the ecash you send and receive. Add one to get started."
    }
}

private enum class ConnectMintStep { Picker, AddCustom, Discover }

// Avatar (36) + row gap (12): hairlines start at the text column, not mid-avatar.
private val SuggestedRowAvatarSize = 36.dp
private val SuggestedRowAddGlyphSize = 24.dp
private val SuggestedRowTextGap = 2.dp

/**
 * The single "connect a mint" surface, shared by the wallet-home empty state and
 * the Send flow's no-mints face. Recognition over recall: a curated shortlist to
 * tap, with custom-URL entry and Nostr discovery as in-sheet steps rather than
 * separate destinations.
 *
 * The surface owns its own [SheetHeader] so it can swap the title and reveal a
 * back chevron when a step is pushed — hosts must not draw one above it.
 *
 * Camera overlays sit under dialog windows, so [onScanMintUrl] must dismiss the
 * host sheet before opening the scanner; the result returns via [initialCustomUrl].
 */
@Composable
fun ConnectMintSheetContent(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    mintDiscoveryManager: MintDiscoveryManager,
    context: ConnectMintContext,
    onScanMintUrl: () -> Unit,
    onMintAdded: () -> Unit,
    modifier: Modifier = Modifier,
    allowCleartextLocalTestMints: Boolean = false,
    prefilledMintUrl: String? = null,
    onPrefilledMintUrlConsumed: () -> Unit = {},
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current

    var step by remember { mutableStateOf(ConnectMintStep.Picker) }
    var quickAddError by remember { mutableStateOf<String?>(null) }
    var isQuickAdding by remember { mutableStateOf(false) }

    // A scan lands back here with a URL: reopen straight onto the form the user
    // left, prefilled, instead of dropping them on the picker.
    LaunchedEffect(prefilledMintUrl) {
        if (!prefilledMintUrl.isNullOrBlank()) step = ConnectMintStep.AddCustom
    }

    fun goBack() {
        when (connectMintBackAction(onPickerStep = step == ConnectMintStep.Picker)) {
            ConnectMintBackAction.ReturnToPicker -> step = ConnectMintStep.Picker
            // The host sheet owns dismissal from the picker.
            ConnectMintBackAction.Close -> Unit
        }
    }

    BackHandler(enabled = step != ConnectMintStep.Picker) { goBack() }

    fun quickAdd(url: String) {
        if (isQuickAdding) return
        quickAddError = null
        isQuickAdding = true
        scope.launch {
            runCatching { walletManager.addMint(url) }
                .onSuccess {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onMintAdded()
                }
                .onFailure { quickAddError = it.userFacingWalletMessage }
            isQuickAdding = false
        }
    }

    Column(
        modifier = modifier
            .then(
                // Discovery hosts its own scrolling list and needs bounded height;
                // the picker and the URL form hug their content so the sheet stays
                // thumb-height.
                if (step == ConnectMintStep.Discover) Modifier.fillMaxHeight() else Modifier.fillMaxWidth(),
            )
            .testTag(UiTestTags.ConnectMintSheet),
    ) {
        SheetHeader(
            title = when (step) {
                ConnectMintStep.Picker -> context.pickerTitle
                // The pushed step is titled after the link that opened it.
                ConnectMintStep.AddCustom -> "Add by URL"
                ConnectMintStep.Discover -> "Discover mints"
            },
            navigationIcon = Icons.AutoMirrored.Outlined.ArrowBack.takeIf {
                step != ConnectMintStep.Picker
            },
            navigationContentDescription = "Back",
            onNavigationClick = ::goBack.takeIf { step != ConnectMintStep.Picker },
        )

        TwoFaceScreen(
            targetState = step,
            modifier = if (step == ConnectMintStep.Discover) {
                Modifier.weight(1f).fillMaxWidth()
            } else {
                Modifier.fillMaxWidth()
            },
            forward = { initial, target -> target.ordinal >= initial.ordinal },
            label = "connect-mint-step",
        ) { current ->
            when (current) {
                ConnectMintStep.Picker -> SuggestedMintsFace(
                    context = context,
                    existingUrls = remember(walletState.mints) {
                        walletState.mints.map { it.url }.toSet()
                    },
                    discoveryAvailable = settings.useWebsockets,
                    error = quickAddError,
                    enabled = !isQuickAdding,
                    onAdd = ::quickAdd,
                    onAddCustom = { step = ConnectMintStep.AddCustom },
                    onDiscover = { step = ConnectMintStep.Discover },
                )

                ConnectMintStep.AddCustom -> AddMintFormBody(
                    walletManager = walletManager,
                    initialUrl = prefilledMintUrl.orEmpty(),
                    allowCleartextLocalTestMints = allowCleartextLocalTestMints,
                    onScan = {
                        onPrefilledMintUrlConsumed()
                        onScanMintUrl()
                    },
                    onAdded = onMintAdded,
                    modifier = Modifier
                        .padding(horizontal = CashuTheme.spacing.loose)
                        .navigationBarsPadding()
                        .padding(bottom = CashuTheme.spacing.comfortable),
                )

                ConnectMintStep.Discover -> MintDiscoveryContent(
                    walletManager = walletManager,
                    settingsManager = settingsManager,
                    mintDiscoveryManager = mintDiscoveryManager,
                    onMintAdded = onMintAdded,
                )
            }
        }
    }
}

/**
 * The picker face, split out from [ConnectMintSheetContent] so it can be
 * exercised without standing up the wallet/settings/discovery managers.
 */
@Composable
internal fun SuggestedMintsFace(
    context: ConnectMintContext,
    existingUrls: Set<String>,
    discoveryAvailable: Boolean,
    error: String?,
    enabled: Boolean,
    onAdd: (String) -> Unit,
    onAddCustom: () -> Unit,
    onDiscover: () -> Unit,
) {
    val suggested = remember(existingUrls) {
        RecommendedMints.filterNot { it.url in existingUrls }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            // One gutter for every element on this face — headline, section
            // header, rows and footer links all share the same left edge.
            .padding(horizontal = CashuTheme.spacing.loose)
            .navigationBarsPadding()
            .padding(bottom = CashuTheme.spacing.comfortable),
    ) {
        if (context.showsHeadline) {
            Text(
                text = ConnectMintContext.HEADLINE,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(CashuTheme.spacing.tight))
        }
        Text(
            text = ConnectMintContext.SUBTITLE,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (suggested.isNotEmpty()) {
            Spacer(Modifier.height(CashuTheme.spacing.section))
            SectionHeader(
                // Not "Suggested": the disclaimer two lines up says this wallet
                // isn't affiliated with any mint, and suggesting implies it is.
                text = "Known mints",
                contentPadding = PaddingValues(bottom = CashuTheme.spacing.snug),
            )
            suggested.forEachIndexed { index, mint ->
                SuggestedMintRow(
                    mint = mint,
                    enabled = enabled,
                    onClick = { onAdd(mint.url) },
                )
            }
        }

        if (error != null) {
            Spacer(Modifier.height(CashuTheme.spacing.default))
            InlineNotice(text = error, severity = NoticeSeverity.Error)
        }

        Spacer(Modifier.height(CashuTheme.spacing.loose))
        Column(verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default)) {
            GhostButton(
                // Verb + object, matching "Discover mints" beside it. "Custom" is
                // an implementation label, and "URL" is already said by the step
                // it opens.
                text = "Add by URL",
                onClick = onAddCustom,
                leadingIcon = Icons.Outlined.Add,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag(UiTestTags.ConnectMintAddCustom),
            )
            // Discovery rides Nostr relays over WebSockets. With the setting off it
            // can only show a "turn this on" dead end, so it isn't offered at all.
            if (discoveryAvailable) {
                GhostButton(
                    text = "Discover mints",
                    onClick = onDiscover,
                    leadingIcon = Icons.Outlined.Search,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(UiTestTags.ConnectMintDiscover),
                )
            }
        }
    }
}

@Composable
private fun SuggestedMintRow(
    mint: RecommendedMint,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    // Synthetic record so the shared avatar's Coil + monogram fallback applies —
    // these mints aren't tracked yet, so there's no stored MintInfo to hand it.
    val preview = remember(mint) {
        MintInfo(url = mint.url, name = mint.name, iconUrl = mint.iconUrl)
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = "Add ${mint.name}" }
            .padding(vertical = CashuTheme.spacing.default),
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        MintAvatar(mint = preview, size = SuggestedRowAvatarSize)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(SuggestedRowTextGap),
        ) {
            // Row title and the subtitle above share a size and separate by weight
            // and colour — that is what keeps this face to four type sizes.
            Text(
                text = mint.name,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = shortenMintUrl(mint.url),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Icon(
            imageVector = Icons.Outlined.AddCircle,
            // The whole row is the target; the glyph is an indicator, not a control.
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(SuggestedRowAddGlyphSize),
        )
    }
}
