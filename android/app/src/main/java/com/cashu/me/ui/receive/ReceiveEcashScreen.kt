package com.cashu.me.ui.receive

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import com.cashu.me.Core.CashuRequestStore
import com.cashu.me.Core.CashuRequestNostrReadiness
import com.cashu.me.Core.NostrService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.TokenParser
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.createNostrCashuRequest
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.CircularMethodButton
import com.cashu.me.ui.components.FlowSheetTitle
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.MethodRowSpacing
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.PaymentStatusPhase
import com.cashu.me.ui.components.PaymentStatusScreen
import com.cashu.me.ui.send.SendDestinationResolution
import com.cashu.me.ui.send.resolveSendDestination
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.rememberReducedMotion
import com.cashu.me.ui.testing.UiTestTags

private const val TYPE_DEBOUNCE_MS = 400L

internal fun automaticReceiveClipboardToken(
    enabled: Boolean,
    currentInput: String,
    prefilledPayload: String?,
    clipboardText: () -> String?,
): String? {
    if (!enabled || currentInput.isNotBlank() || !prefilledPayload.isNullOrBlank()) return null
    return clipboardText()?.let(TokenParser::extractToken)
}

/**
 * The Receive surface — the mirror of [com.cashu.me.ui.send.UnifiedSendScreen]'s
 * input face so Send and Receive read as one system: a paste field ("Paste a
 * Cashu token") over a Scan · Ecash · Bitcoin ways-to-receive row.
 *
 * A pasted / scanned bearer *token* opens the full-screen claim page (Send
 * parity); anything else payable (invoice, address, Cashu Request) is really a
 * Send and is handed back to the Send flow. Ecash mints a fresh Cashu Request
 * and opens its QR (no intermediate form — past requests live in History);
 * Bitcoin opens the mint's Lightning / on-chain receive dialog.
 *
 * Home's Receive button lands here directly — there is no receive chooser.
 */
@Composable
fun ReceiveEcashScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    nostrService: NostrService,
    cashuRequestStore: CashuRequestStore,
    onOpenRequest: (String) -> Unit,
    onClose: () -> Unit,
    onScan: () -> Unit,
    onOpenReceiveToken: (String) -> Unit,
    onSendPayable: (String) -> Unit,
    onReceiveBitcoin: () -> Unit,
    prefilledPayload: String? = null,
    onPrefilledConsumed: () -> Unit = {},
    allowAutomaticClipboardRead: Boolean = true,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val clipboard = LocalClipboardManager.current

    var input by remember { mutableStateOf("") }
    var inputHint by remember { mutableStateOf<String?>(null) }
    var requestFailure by remember { mutableStateOf<String?>(null) }
    // Once we've routed away (token → claim, payable → Send) the debounce must
    // not re-fire; reset whenever the field is edited or cleared.
    var routed by remember { mutableStateOf(false) }

    // iOS "New Request": publish a fresh any-amount NUT-18 request over the
    // wallet's Nostr identity and open its inspector — no intermediate form.
    // Keep it mint-agnostic even when an active mint exists; the request detail
    // screen lets the user opt into a specific mint later.
    fun createNewRequest() {
        val readiness = CashuRequestNostrReadiness.current(nostrService, settingsManager)
        val configuration = readiness.requestConfigurationOrNull()
        if (configuration == null) {
            inputHint = (readiness as? CashuRequestNostrReadiness.Blocked)?.recoveryMessage
            return
        }
        inputHint = null
        runCatching {
            val id = com.cashu.me.Models.CashuRequest.newId()
            cashuRequestStore.createNostrCashuRequest(
                id = id,
                amount = null,
                unit = "sat",
                nostrPubkeyHex = configuration.publicKeyHex,
                relays = configuration.relays,
            )
        }.onSuccess { request ->
            requestFailure = null
            onOpenRequest(request.id)
        }.onFailure {
            requestFailure = it.userFacingWalletMessage
        }
    }

    // A token redeems on the full-screen claim page (Send parity); anything else
    // payable is a Send, handed back to the Send flow. Inverts Send's advance().
    fun routeInput(raw: String) {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || routed) return
        inputHint = null
        when (val res = resolveSendDestination(trimmed, walletState.mints)) {
            is SendDestinationResolution.EcashToken -> {
                routed = true
                onOpenReceiveToken(res.token)
            }
            is SendDestinationResolution.Melt,
            is SendDestinationResolution.CashuRequest -> {
                routed = true
                onSendPayable(trimmed)
            }
            is SendDestinationResolution.Hint -> inputHint = res.message
            SendDestinationResolution.Unrecognized ->
                inputHint = "That doesn't look like a Cashu token. Paste an ecash token to receive."
        }
    }

    LaunchedEffect(Unit) {
        automaticReceiveClipboardToken(
            enabled = allowAutomaticClipboardRead && settings.autoPasteEcashReceive,
            currentInput = input,
            prefilledPayload = prefilledPayload,
            clipboardText = { clipboard.getText()?.text },
        )?.let { input = it }
    }

    // Typing settles for a beat before routing; paste/scan advance immediately.
    LaunchedEffect(input) {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) {
            inputHint = null
            return@LaunchedEffect
        }
        delay(TYPE_DEBOUNCE_MS)
        routeInput(input)
    }

    LaunchedEffect(prefilledPayload) {
        val pre = prefilledPayload?.takeIf { it.isNotBlank() } ?: return@LaunchedEffect
        input = pre
        routeInput(pre)
        onPrefilledConsumed()
    }

    val failure = requestFailure
    if (failure != null) {
        Column(
            modifier = Modifier
                .fillMaxHeight()
                .fillMaxWidth()
                .testTag(UiTestTags.ReceiveSheet),
        ) {
            FlowSheetTitle(title = "Receive")
            PaymentStatusScreen(
                phase = PaymentStatusPhase.Failure,
                title = "Couldn't Create Request",
                detail = failure,
                modifier = Modifier.weight(1f),
                doneLabel = "Try Again",
                onDone = { requestFailure = null },
            )
        }
        return
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(UiTestTags.ReceiveSheet),
    ) {
        FlowSheetTitle(title = "Receive")
        // Wrap-content — the sheet settles just below Scan · Ecash · Bitcoin
        // (thumb-reachable), matching iOS's content-fit detent and the Send face.
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = CashuTheme.spacing.comfortable)
                .padding(bottom = 52.dp)
                .navigationBarsPadding()
                .imePadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CashuTextField(
                value = input,
                onValueChange = {
                    input = it
                    inputHint = null
                    routed = false
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = CashuTheme.spacing.default),
                placeholder = "Paste a Cashu token",
                singleLine = false,
                maxLines = 4,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                // Paste ↔ Clear cross-fade, identical to the Send input face.
                trailingIcon = if (input.isNotBlank() || clipboard.hasText()) {
                    {
                        AnimatedContent(
                            targetState = input.isNotBlank(),
                            transitionSpec = {
                                fadeIn(spring(stiffness = Spring.StiffnessMedium))
                                    .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
                            },
                            label = "input-trailing",
                        ) { hasInput ->
                            if (hasInput) {
                                IconButton(onClick = {
                                    input = ""
                                    inputHint = null
                                    routed = false
                                }) {
                                    Icon(Icons.Outlined.Cancel, contentDescription = "Clear")
                                }
                            } else {
                                GhostButton(text = "Paste", onClick = {
                                    val clip = clipboard.getText()?.text?.trim().orEmpty()
                                    if (clip.isNotEmpty()) {
                                        input = clip
                                        routeInput(clip)
                                    }
                                })
                            }
                        }
                    }
                } else null,
            )
            val reduceMotion = rememberReducedMotion()
            AnimatedContent(
                targetState = inputHint,
                transitionSpec = {
                    if (reduceMotion) {
                        fadeIn(spring(stiffness = Spring.StiffnessMedium)) togetherWith
                            fadeOut(spring(stiffness = Spring.StiffnessMedium))
                    } else {
                        (fadeIn(spring(stiffness = Spring.StiffnessMedium)) +
                            expandVertically(
                                animationSpec = spring(stiffness = Spring.StiffnessMedium),
                                expandFrom = Alignment.Top,
                            )) togetherWith
                            (fadeOut(spring(stiffness = Spring.StiffnessMedium)) +
                                shrinkVertically(
                                    animationSpec = spring(stiffness = Spring.StiffnessMedium),
                                    shrinkTowards = Alignment.Top,
                                ))
                    }
                },
                label = "receive-input-hint",
            ) { hint ->
                if (hint != null) {
                    Column {
                        Spacer(Modifier.height(CashuTheme.spacing.default))
                        InlineNotice(text = hint, severity = NoticeSeverity.Caution)
                    }
                }
            }
            Spacer(Modifier.height(CashuTheme.spacing.page + CashuTheme.spacing.micro))
            // Ways to receive: Scan · Ecash · Bitcoin, round 72dp buttons.
            Row(
                horizontalArrangement = Arrangement.spacedBy(MethodRowSpacing),
                verticalAlignment = Alignment.Top,
            ) {
                CircularMethodButton(
                    icon = Icons.Outlined.QrCodeScanner,
                    label = "Scan",
                    onClick = onScan,
                )
                CircularMethodButton(
                    icon = Icons.Outlined.Payments,
                    label = "Ecash",
                    onClick = ::createNewRequest,
                )
                CircularMethodButton(
                    icon = Icons.Outlined.CurrencyBitcoin,
                    label = "Bitcoin",
                    onClick = onReceiveBitcoin,
                    enabled = walletState.activeMint != null,
                )
            }
            if (walletState.activeMint == null) {
                Spacer(Modifier.height(CashuTheme.spacing.comfortable))
                InlineNotice(
                    text = "Add a mint to receive bitcoin. Ecash requests and token scans still work without one.",
                    severity = NoticeSeverity.Info,
                )
            }
        }
    }
}
