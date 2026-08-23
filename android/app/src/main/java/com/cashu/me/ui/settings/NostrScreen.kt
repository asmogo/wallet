package com.cashu.me.ui.settings

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
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
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.SettingsFooterText
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
    var pendingImportNsec by remember { mutableStateOf<String?>(null) }
    var showImportConfirm by remember { mutableStateOf(false) }
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
        AlertDialog(
            onDismissRequest = {
                if (identityMutation != NostrIdentityMutation.ImportKey) {
                    showImport = false
                    importError = null
                }
            },
            title = { Text("Import nsec") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug)) {
                    CashuTextField(
                        value = importInput,
                        onValueChange = { importInput = it; importError = null },
                        label = "nsec1…",
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        isError = importError != null,
                        supportingText = importError,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    pendingImportNsec = importInput.trim()
                    showImport = false
                    showImportConfirm = true
                    importError = null
                }) { Text("Continue") }
            },
            dismissButton = {
                TextButton(
                    enabled = identityMutation != NostrIdentityMutation.ImportKey,
                    onClick = { showImport = false; importError = null },
                ) { Text("Cancel") }
            },
        )
    }

    if (showImportConfirm) {
        AlertDialog(
            onDismissRequest = {
                showImportConfirm = false
                pendingImportNsec = null
            },
            title = { Text("Replace Nostr key?") },
            text = {
                Text(
                    NostrIdentityReplacementWarnings.Import,
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val nsec = pendingImportNsec.orEmpty()
                    showImportConfirm = false
                    performIdentityMutation(
                        mutation = NostrIdentityMutation.ImportKey,
                        operation = { nostrService.importNsec(nsec) },
                        onSuccess = {
                            importInput = ""
                            pendingImportNsec = null
                            importError = null
                        },
                        onFailure = {
                            pendingImportNsec = null
                            importError = it
                            showImport = true
                        },
                    )
                }) { Text("Import") }
            },
            dismissButton = {
                TextButton(onClick = {
                    showImportConfirm = false
                    pendingImportNsec = null
                }) { Text("Cancel") }
            },
        )
    }

    if (showGenerateConfirm) {
        AlertDialog(
            onDismissRequest = { showGenerateConfirm = false },
            title = { Text("Generate new key") },
            text = {
                Text(
                    NostrIdentityReplacementWarnings.Generate,
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                DestructiveTextButton(text = "Generate", onClick = {
                    showGenerateConfirm = false
                    performIdentityMutation(
                        mutation = NostrIdentityMutation.GenerateKey,
                        operation = { nostrService.generateRandomKeypair() },
                    )
                })
            },
            dismissButton = {
                TextButton(onClick = { showGenerateConfirm = false }) { Text("Cancel") }
            },
        )
    }

    if (showResetConfirm) {
        AlertDialog(
            onDismissRequest = { showResetConfirm = false },
            title = { Text("Reset to wallet seed") },
            text = {
                Text(
                    NostrIdentityReplacementWarnings.Reset,
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                DestructiveTextButton(text = "Reset", onClick = {
                    showResetConfirm = false
                    performIdentityMutation(
                        mutation = NostrIdentityMutation.ResetKey,
                        operation = { nostrService.resetToSeedKey() },
                    )
                })
            },
            dismissButton = {
                TextButton(onClick = { showResetConfirm = false }) { Text("Cancel") }
            },
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
