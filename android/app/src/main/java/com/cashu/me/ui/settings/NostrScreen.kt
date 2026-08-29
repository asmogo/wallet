package com.cashu.me.ui.settings

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.NostrService
import com.cashu.me.Core.NostrSignerSelectionAction
import com.cashu.me.Core.NostrSignerType
import com.cashu.me.Core.NwcManager
import com.cashu.me.Core.RelayAddResult
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.nostrSignerSelectionAction
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.DestructiveTextButton
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.LocalConfirmationToastController
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SecondaryButton
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.SettingsFooterText
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme

/** Shown inside the reveal sheet, at the moment the key is about to be exposed. */
internal const val NostrPrivateKeyWarningText =
    "Your nsec controls your Nostr identity and Lightning address. Never share it."

internal enum class NostrIdentityMutation(
    val progressMessage: String,
    private val failureAction: String,
) {
    SwitchSigner("Updating Nostr key source…", "switch the Nostr key source"),
    ImportKey("Importing Nostr key…", "import the Nostr key"),
    GenerateKey("Generating a new Nostr key…", "generate a new Nostr key"),
    ResetKey("Resetting to the wallet seed…", "reset the Nostr key"),
    ;

    fun failureMessage(error: Throwable): String {
        val detail = error.message?.trim()?.takeIf(String::isNotEmpty) ?: "Please try again."
        return "Couldn’t $failureAction. Your current identity was not changed. $detail"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NostrScreen(
    nostrService: NostrService,
    settingsManager: SettingsManager,
    nwcManager: NwcManager,
    appLockManager: AppLockManager,
    onOpenWalletConnect: () -> Unit,
    onClose: () -> Unit,
) {
    val nostrState by nostrService.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val nwcState by nwcManager.state.collectAsState()
    val clipboard = LocalClipboardManager.current
    val confirmationToastController = LocalConfirmationToastController.current
    val scope = rememberCoroutineScope()
    var showNsecReveal by remember { mutableStateOf(false) }
    var showImport by remember { mutableStateOf(false) }
    var importInput by remember { mutableStateOf("") }
    var importError by remember { mutableStateOf<String?>(null) }
    var relayInput by remember { mutableStateOf("") }
    var addRelayError by remember { mutableStateOf<String?>(null) }
    var showRelayResetConfirm by remember { mutableStateOf(false) }
    var showMissingCustomKeyChoice by remember { mutableStateOf(false) }
    var showGenerateConfirm by remember { mutableStateOf(false) }
    var showResetConfirm by remember { mutableStateOf(false) }
    var identityMutation by remember { mutableStateOf<NostrIdentityMutation?>(null) }
    var identityMutationError by remember { mutableStateOf<String?>(null) }

    fun submitRelay() {
        when (val result = settingsManager.addRelay(relayInput)) {
            null -> Unit
            is RelayAddResult.Added -> {
                relayInput = ""
                addRelayError = null
            }
            is RelayAddResult.Rejected -> addRelayError = result.message
        }
    }

    fun performIdentityMutation(
        mutation: NostrIdentityMutation,
        operation: () -> Unit,
        onSuccess: () -> Unit = {},
        onFailure: (String) -> Unit = { identityMutationError = it },
    ) {
        if (identityMutation != null) return
        identityMutation = mutation
        identityMutationError = null
        scope.launch {
            try {
                withContext(Dispatchers.Default) { operation() }
                onSuccess()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                onFailure(mutation.failureMessage(error))
            } finally {
                identityMutation = null
            }
        }
    }
    var pendingSignerType by remember { mutableStateOf<NostrSignerType?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Nostr", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        ToolbarIcon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            Text(
                text = "Nostr powers your Lightning address, npub.cash requests, " +
                    "encrypted backups, and Wallet Connect.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.snug,
                ),
            )
            Spacer(Modifier.height(CashuTheme.spacing.default))

            NostrKeySection(
                npub = nostrState.npub,
                publicKeyHex = nostrState.publicKeyHex,
                isReady = nostrState.isInitialized && nostrState.npub.isNotBlank(),
                signerType = nostrState.signerType,
                isMutating = identityMutation != null,
                progressMessage = identityMutation?.progressMessage,
                errorMessage = identityMutationError,
                onRevealNsec = { showNsecReveal = true },
                onSelectSigner = { kind ->
                    when (
                        nostrSignerSelectionAction(
                            current = nostrState.signerType,
                            requested = kind,
                            hasCustomKey = nostrService.hasCustomPrivateKey(),
                        )
                    ) {
                        NostrSignerSelectionAction.NoChange -> Unit
                        NostrSignerSelectionAction.ChooseCustomKey ->
                            showMissingCustomKeyChoice = true
                        NostrSignerSelectionAction.Switch ->
                            if (kind == NostrSignerType.Seed) {
                                showResetConfirm = true
                            } else {
                                pendingSignerType = kind
                            }
                    }
                },
                onGenerateKey = { showGenerateConfirm = true },
                onImportKey = { showImport = true },
                onResetToSeed = { showResetConfirm = true },
            )

            SectionHeader("Relays")
            NostrRelayInputRow(
                value = relayInput,
                onValueChange = { relayInput = it; addRelayError = null },
                onSubmit = { submitRelay() },
                isError = addRelayError != null,
                errorText = addRelayError,
                modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
            )
            Spacer(Modifier.height(CashuTheme.spacing.snug))
            // Relay add/remove animates the list resize (iOS
            // .animation(value: settings.nostrRelays) parity).
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .animateContentSize(spring(stiffness = Spring.StiffnessMediumLow)),
            ) {
                if (settings.nostrRelays.isEmpty()) {
                    InlineNotice(
                        text = "No relays configured. Your Lightning address, encrypted " +
                            "backups, and payment requests stay off until you add one.",
                        severity = NoticeSeverity.Caution,
                        modifier = Modifier.padding(
                            horizontal = CashuTheme.spacing.comfortable,
                            vertical = CashuTheme.spacing.snug,
                        ),
                    )
                } else {
                    settings.nostrRelays.forEach { relay ->
                        NostrRelayRow(
                            relay = relay,
                            onCopy = {
                                clipboard.setText(AnnotatedString(relay))
                                confirmationToastController?.show("Copied relay URL")
                            },
                            onRemove = { settingsManager.removeRelay(relay) },
                        )
                    }
                }
            }
            SettingsFooterText(
                "Relays sync your Nostr data for compatible features like npub.cash and backups.",
            )
            NavRow(
                title = "Reset to default relays",
                leadingIcon = Icons.Outlined.RestartAlt,
                showChevron = false,
                onClick = {
                    addRelayError = null
                    if (shouldConfirmRelayReset(
                            settings.nostrRelays,
                            SettingsManager.defaultNostrRelays,
                        )
                    ) {
                        showRelayResetConfirm = true
                    } else {
                        settingsManager.resetNostrRelaysToDefault()
                    }
                },
            )

            SectionHeader("Apps")
            NavRow(
                title = "Wallet Connect",
                leadingIcon = Icons.Outlined.Bolt,
                trailingValue = if (nwcState.isEnabled) "On" else "Off",
                onClick = onOpenWalletConnect,
            )
            SettingsFooterText(
                "Let a Nostr app create invoices and pay Lightning invoices from this wallet.",
            )
            Spacer(Modifier.height(CashuTheme.spacing.section))
        }
    }

    if (showMissingCustomKeyChoice) {
        // Three actions don't fit M3's two button slots, so the two choices live
        // in the body as rows and Cancel keeps the one button.
        AlertDialog(
            onDismissRequest = { showMissingCustomKeyChoice = false },
            title = { Text("Choose a custom key") },
            text = {
                Column {
                    Text(
                        "Switching to Custom Key needs a key to switch to.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Spacer(Modifier.height(CashuTheme.spacing.snug))
                    NavRow(
                        title = "Generate a new key",
                        leadingIcon = Icons.Outlined.AddCircleOutline,
                        showChevron = false,
                        onClick = {
                            showMissingCustomKeyChoice = false
                            showGenerateConfirm = true
                        },
                    )
                    NavRow(
                        title = "Import an existing nsec",
                        leadingIcon = Icons.Outlined.FileDownload,
                        showChevron = false,
                        onClick = {
                            showMissingCustomKeyChoice = false
                            showImport = true
                        },
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { showMissingCustomKeyChoice = false }) { Text("Cancel") }
            },
        )
    }

    if (showImport) {
        NsecImportSheet(
            input = importInput,
            onInputChange = { importInput = it },
            error = importError,
            onErrorChange = { importError = it },
            importing = identityMutation == NostrIdentityMutation.ImportKey,
            onConfirmImport = { nsec, onSuccess, onFailure ->
                performIdentityMutation(
                    mutation = NostrIdentityMutation.ImportKey,
                    operation = { nostrService.importNsec(nsec) },
                    onSuccess = {
                        importInput = ""
                        onSuccess()
                    },
                    onFailure = onFailure,
                )
            },
            onDismiss = {
                showImport = false
                importError = null
            },
        )
    }

    if (showGenerateConfirm) {
        KeyActionConfirmSheet(
            title = "Generate new key?",
            message = NostrIdentityReplacementWarnings.Generate,
            actionLabel = "Generate",
            onConfirm = {
                showGenerateConfirm = false
                performIdentityMutation(
                    mutation = NostrIdentityMutation.GenerateKey,
                    operation = { nostrService.generateRandomKeypair() },
                )
            },
            onDismiss = { showGenerateConfirm = false },
        )
    }

    if (showResetConfirm) {
        KeyActionConfirmSheet(
            title = "Reset to wallet seed?",
            message = NostrIdentityReplacementWarnings.Reset,
            actionLabel = "Reset",
            onConfirm = {
                showResetConfirm = false
                performIdentityMutation(
                    mutation = NostrIdentityMutation.ResetKey,
                    operation = { nostrService.resetToSeedKey() },
                )
            },
            onDismiss = { showResetConfirm = false },
        )
    }

    pendingSignerType?.let { signerType ->
        AlertDialog(
            onDismissRequest = { pendingSignerType = null },
            title = { Text("Switch Nostr key?") },
            text = {
                Text(
                    NostrIdentityReplacementWarnings.switchTo(signerType.displayName),
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                DestructiveTextButton(text = "Switch", onClick = {
                    pendingSignerType = null
                    performIdentityMutation(
                        mutation = NostrIdentityMutation.SwitchSigner,
                        operation = { nostrService.switchSignerType(signerType) },
                    )
                })
            },
            dismissButton = {
                TextButton(onClick = { pendingSignerType = null }) { Text("Cancel") }
            },
        )
    }

    if (showRelayResetConfirm) {
        AlertDialog(
            onDismissRequest = { showRelayResetConfirm = false },
            title = { Text("Reset to default relays") },
            text = {
                Text(
                    "This replaces your relay list with " +
                        SettingsManager.defaultNostrRelays.joinToString(", ") + ".",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                DestructiveTextButton(text = "Reset", onClick = {
                    showRelayResetConfirm = false
                    settingsManager.resetNostrRelaysToDefault()
                })
            },
            dismissButton = {
                TextButton(onClick = { showRelayResetConfirm = false }) { Text("Cancel") }
            },
        )
    }

    if (showNsecReveal) {
        PrivateKeyRevealSheet(
            title = "Nostr private key",
            // Read through the service so a generate/import while the sheet is
            // open cannot hand back the key it replaced.
            loadNsec = { nostrService.state.value.nsec.takeIf(String::isNotBlank) },
            appLockManager = appLockManager,
            warning = NostrPrivateKeyWarningText,
            onDismiss = { showNsecReveal = false },
        )
    }
}

private enum class NsecImportStep { Entry, Confirm, Success }

private val ImportSuccessGlyphSize = 64.dp

/**
 * Imports a custom nsec on the house sheet recipe (iOS `ImportNsecSheet`
 * parity): one sheet, three faces — entry, the replace-key confirmation, and
 * success — cross-fading while the sheet resizes between them, instead of
 * stacking AlertDialogs on top of each other.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NsecImportSheet(
    input: String,
    onInputChange: (String) -> Unit,
    error: String?,
    onErrorChange: (String?) -> Unit,
    importing: Boolean,
    onConfirmImport: (nsec: String, onSuccess: () -> Unit, onFailure: (String) -> Unit) -> Unit,
    onDismiss: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    var step by remember { mutableStateOf(NsecImportStep.Entry) }

    fun review() {
        val trimmed = input.trim()
        if (!trimmed.lowercase().startsWith("nsec1")) {
            onErrorChange("Invalid format. nsec must start with 'nsec1'")
            return
        }
        if (trimmed.length < 59) {
            onErrorChange(
                "That doesn't look like a complete nsec. Check you copied the whole key and try again.",
            )
            return
        }
        onErrorChange(null)
        // Hide concurrently with the face swap — the confirm face has no field.
        keyboard?.hide()
        step = NsecImportStep.Confirm
    }

    ModalBottomSheet(
        onDismissRequest = { if (!importing) onDismiss() },
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .navigationBarsPadding()
                    .padding(horizontal = CashuTheme.spacing.comfortable)
                    .padding(bottom = CashuTheme.spacing.section),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
            ) {
                SheetHeader(
                    title = when (step) {
                        NsecImportStep.Entry -> "Import Key"
                        NsecImportStep.Confirm -> "Replace Nostr key?"
                        NsecImportStep.Success -> "Key Imported"
                    },
                )
                AnimatedContent(
                    targetState = step,
                    transitionSpec = {
                        fadeIn(spring(stiffness = Spring.StiffnessMedium)) togetherWith
                            fadeOut(spring(stiffness = Spring.StiffnessMedium))
                    },
                    label = "nsec-import-step",
                ) { current ->
                    when (current) {
                        NsecImportStep.Entry -> Column(
                            modifier = Modifier.animateContentSize(
                                animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
                            ),
                            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
                        ) {
                            Text(
                                text = "Enter your nsec (Nostr private key) to use it for " +
                                    "your Lightning address.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            CashuTextField(
                                value = input,
                                onValueChange = {
                                    onInputChange(it)
                                    onErrorChange(null)
                                },
                                label = "Nostr private key",
                                placeholder = "nsec1…",
                                singleLine = true,
                                isError = error != null,
                                supportingText = error,
                                keyboardOptions = KeyboardOptions(
                                    capitalization = KeyboardCapitalization.None,
                                ),
                                trailingIcon = if (input.isNotBlank()) {
                                    {
                                        IconButton(onClick = {
                                            onInputChange("")
                                            onErrorChange(null)
                                        }) {
                                            Icon(Icons.Outlined.Cancel, contentDescription = "Clear")
                                        }
                                    }
                                } else {
                                    null
                                },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                            ) {
                                SecondaryButton(
                                    text = "Paste",
                                    onClick = {
                                        val text = clipboard.getText()?.text?.trim().orEmpty()
                                        if (text.isEmpty()) {
                                            onErrorChange("Clipboard is empty.")
                                        } else {
                                            onInputChange(text)
                                            onErrorChange(null)
                                        }
                                    },
                                    modifier = Modifier.weight(1f),
                                )
                                PrimaryButton(
                                    text = "Review Import",
                                    onClick = ::review,
                                    enabled = input.isNotBlank(),
                                    colors = ButtonDefaults.buttonColors(),
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                        NsecImportStep.Confirm -> Column(
                            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
                        ) {
                            Text(
                                text = NostrIdentityReplacementWarnings.Import,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                            ) {
                                SecondaryButton(
                                    text = "Cancel",
                                    onClick = { step = NsecImportStep.Entry },
                                    enabled = !importing,
                                    modifier = Modifier.weight(1f),
                                )
                                PrimaryButton(
                                    text = "Import",
                                    onClick = {
                                        onConfirmImport(
                                            input.trim(),
                                            { step = NsecImportStep.Success },
                                            { message ->
                                                onErrorChange(message)
                                                step = NsecImportStep.Entry
                                            },
                                        )
                                    },
                                    loading = importing,
                                    colors = ButtonDefaults.buttonColors(),
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                        NsecImportStep.Success -> Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
                        ) {
                            Icon(
                                imageVector = Icons.Filled.CheckCircle,
                                contentDescription = "Success",
                                tint = CashuTheme.colors.received,
                                modifier = Modifier.size(ImportSuccessGlyphSize),
                            )
                            Text(
                                text = "Your Nostr key was replaced with the imported key. " +
                                    "Your Lightning address and npub.cash now come from this key.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                            )
                            SecondaryButton(
                                text = "Done",
                                onClick = onDismiss,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * Single-face confirmation sheet for a Nostr key mutation, on the same recipe
 * as the import sheet's confirm face (iOS `KeyActionConfirmSheet` parity):
 * SheetHeader title, centered warning copy, and a Cancel/action row, instead
 * of an AlertDialog stacked over the screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KeyActionConfirmSheet(
    title: String,
    message: String,
    actionLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Box(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .navigationBarsPadding()
                    .padding(horizontal = CashuTheme.spacing.comfortable)
                    .padding(bottom = CashuTheme.spacing.section),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
            ) {
                SheetHeader(title = title)

                Text(
                    text = message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                ) {
                    SecondaryButton(
                        text = "Cancel",
                        onClick = onDismiss,
                        modifier = Modifier.weight(1f),
                    )
                    PrimaryButton(
                        text = actionLabel,
                        onClick = onConfirm,
                        colors = ButtonDefaults.buttonColors(),
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}
