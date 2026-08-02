package com.cashu.me.ui.settings

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.NostrService
import com.cashu.me.Core.NostrSignerSelectionAction
import com.cashu.me.Core.NostrSignerType
import com.cashu.me.Core.NwcManager
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.nostrSignerSelectionAction
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.DestructiveTextButton
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.IconSwap
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.security.rememberWalletAuthenticationLauncher
import com.cashu.me.ui.theme.CashuTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val NsecCopiedFeedbackMillis = 2_000L
internal const val NostrPrivateKeyWarningText =
    "Your nsec controls your Nostr identity and Lightning address. Never share it."

@Composable
internal fun NostrPrivateKeyWarning(modifier: Modifier = Modifier) {
    InlineNotice(
        text = NostrPrivateKeyWarningText,
        modifier = modifier,
        severity = NoticeSeverity.Warning,
    )
}

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
    val authenticate = rememberWalletAuthenticationLauncher(appLockManager)
    val scope = rememberCoroutineScope()
    // Keep the authenticated value tied to this key. Replacing/importing/resetting
    // the Nostr key creates fresh hidden state, even if the previous key was visible.
    var revealedNsec by remember(nostrState.nsec) { mutableStateOf<String?>(null) }
    var nsecCopied by remember { mutableStateOf(false) }
    LaunchedEffect(nsecCopied) {
        if (nsecCopied) {
            delay(NsecCopiedFeedbackMillis)
            nsecCopied = false
        }
    }
    var showImport by remember { mutableStateOf(false) }
    var importInput by remember { mutableStateOf("") }
    var pendingImportNsec by remember { mutableStateOf<String?>(null) }
    var showImportConfirm by remember { mutableStateOf(false) }
    var importError by remember { mutableStateOf<String?>(null) }
    var addRelayOpen by remember { mutableStateOf(false) }
    var addRelayError by remember { mutableStateOf<String?>(null) }
    var showMissingCustomKeyChoice by remember { mutableStateOf(false) }
    var showGenerateConfirm by remember { mutableStateOf(false) }
    var showResetConfirm by remember { mutableStateOf(false) }
    var identityMutation by remember { mutableStateOf<NostrIdentityMutation?>(null) }
    var identityMutationError by remember { mutableStateOf<String?>(null) }

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
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            SectionHeader("Signer")
            Column(modifier = Modifier.fillMaxWidth().padding(horizontal = CashuTheme.spacing.comfortable)) {
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    NostrSignerType.entries.forEachIndexed { index, kind ->
                        SegmentedButton(
                            shape = SegmentedButtonDefaults.itemShape(
                                index = index,
                                count = NostrSignerType.entries.size,
                            ),
                            selected = kind == nostrState.signerType,
                            enabled = identityMutation == null,
                            onClick = {
                                when (
                                    nostrSignerSelectionAction(
                                        current = nostrState.signerType,
                                        requested = kind,
                                        hasCustomKey = nostrService.hasCustomPrivateKey(),
                                    )
                                ) {
                                    NostrSignerSelectionAction.NoChange -> Unit
                                    NostrSignerSelectionAction.ChooseCustomKey -> {
                                        showMissingCustomKeyChoice = true
                                    }
                                    NostrSignerSelectionAction.Switch -> {
                                        if (kind == NostrSignerType.Seed) {
                                            showResetConfirm = true
                                        } else {
                                            pendingSignerType = kind
                                        }
                                    }
                                }
                            },
                        ) { Text(kind.displayName) }
                    }
                }
                Spacer(Modifier.height(CashuTheme.spacing.snug))
                Text(
                    text = when (nostrState.signerType) {
                        NostrSignerType.Seed -> "Keys are derived from your wallet seed."
                        NostrSignerType.PrivateKey -> "Custom key stored in secure storage."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            SectionHeader("Public identity")
            InspectorRow(
                label = "npub",
                value = nostrState.npub.ifBlank { "—" },
                valueMonospaced = true,
                onClick = { clipboard.setText(AnnotatedString(nostrState.npub)) },
                editable = nostrState.npub.isNotBlank(),
            )
            InspectorRow(
                label = "hex",
                value = nostrState.publicKeyHex.ifBlank { "—" },
                valueMonospaced = true,
                onClick = { clipboard.setText(AnnotatedString(nostrState.publicKeyHex)) },
                editable = nostrState.publicKeyHex.isNotBlank(),
            )

            SectionHeader("Private key")
            NostrPrivateKeyWarning(
                modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(
                        horizontal = CashuTheme.spacing.comfortable,
                        vertical = CashuTheme.spacing.snug,
                    ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                Text(
                    text = revealedNsec?.ifBlank { "—" } ?: "•".repeat(12),
                    style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                )
                IconButton(
                    onClick = {
                        if (revealedNsec != null) {
                            revealedNsec = null
                        } else {
                            authenticate("Reveal your Nostr private key") {
                                revealedNsec = nostrState.nsec
                            }
                        }
                    },
                ) {
                    Icon(
                        imageVector = if (revealedNsec != null) Icons.Outlined.VisibilityOff
                        else Icons.Outlined.Visibility,
                        contentDescription = if (revealedNsec != null) "Hide" else "Reveal",
                    )
                }
                IconButton(
                    onClick = {
                        authenticate("Copy your Nostr private key") {
                            clipboard.setText(AnnotatedString(nostrState.nsec))
                            nsecCopied = true
                        }
                    },
                    enabled = nostrState.nsec.isNotBlank(),
                ) {
                    IconSwap(
                        icon = if (nsecCopied) Icons.Outlined.Check else Icons.Outlined.ContentCopy,
                        contentDescription = "Copy nsec",
                        tint = if (nsecCopied) CashuTheme.colors.received else MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.size(CashuTheme.spacing.comfortable),
                    )
                }
            }
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = CashuTheme.spacing.comfortable),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                PrimaryButton(
                    text = "Generate new key",
                    onClick = { showGenerateConfirm = true },
                    enabled = identityMutation == null,
                    loading = identityMutation == NostrIdentityMutation.GenerateKey,
                )
                GhostButton(
                    text = "Import nsec…",
                    onClick = { showImport = true },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = identityMutation == null,
                )
                GhostButton(
                    text = "Reset to wallet seed",
                    onClick = { showResetConfirm = true },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = nostrState.signerType != NostrSignerType.Seed && identityMutation == null,
                )
                identityMutation?.let {
                    InlineNotice(
                        text = it.progressMessage,
                        severity = NoticeSeverity.Info,
                    )
                }
                identityMutationError?.let { InlineNotice(text = it) }
            }

            SectionHeader("Relays")
            if (settings.nostrRelays.isEmpty()) {
                Text(
                    text = "Using defaults (relay.damus.io, nos.lol, primal.net, 8333.space).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(
                        horizontal = CashuTheme.spacing.comfortable,
                        vertical = CashuTheme.spacing.snug,
                    ),
                )
            } else {
                // Relay add/remove animates the list resize (iOS
                // .animation(value: settings.nostrRelays) parity).
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .animateContentSize(spring(stiffness = Spring.StiffnessMediumLow)),
                ) {
                    settings.nostrRelays.forEachIndexed { index, relay ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(
                                    horizontal = CashuTheme.spacing.comfortable,
                                    vertical = CashuTheme.spacing.default,
                                ),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = relay,
                                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.weight(1f),
                                maxLines = 1,
                                overflow = TextOverflow.MiddleEllipsis,
                            )
                            IconButton(onClick = { settingsManager.removeRelay(relay) }) {
                                Icon(
                                    imageVector = Icons.Outlined.Close,
                                    contentDescription = "Remove relay",
                                    modifier = Modifier.size(CashuTheme.spacing.loose),
                                )
                            }
                        }
                    }
                }
            }
            FooterText(
                "Relays sync your Nostr data for compatible features like npub.cash and backups.",
            )
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = CashuTheme.spacing.comfortable),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                PrimaryButton(
                    text = "Add relay…",
                    onClick = { addRelayOpen = true },
                )
                GhostButton(
                    text = "Reset to defaults",
                    onClick = { settingsManager.resetNostrRelaysToDefault() },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            SectionHeader("Apps")
            NavRow(
                title = "Wallet Connect",
                subtitle = "Let a Nostr app use this wallet",
                leadingIcon = Icons.Outlined.Bolt,
                trailingValue = if (nwcState.isEnabled) "On" else "Off",
                onClick = onOpenWalletConnect,
            )
            Spacer(Modifier.height(CashuTheme.spacing.section))
        }
    }

    if (showMissingCustomKeyChoice) {
        AlertDialog(
            onDismissRequest = { showMissingCustomKeyChoice = false },
            title = { Text("Choose a custom key") },
            text = {
                Text(
                    "Generate a new Nostr identity or import an existing nsec before switching to Custom Key.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showMissingCustomKeyChoice = false
                    showGenerateConfirm = true
                }) { Text("Generate") }
            },
            dismissButton = {
                Row {
                    TextButton(onClick = { showMissingCustomKeyChoice = false }) {
                        Text("Cancel")
                    }
                    TextButton(onClick = {
                        showMissingCustomKeyChoice = false
                        showImport = true
                    }) { Text("Import") }
                }
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
                    )
                    if (importError != null) {
                        InlineNotice(text = importError!!)
                    }
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
                TextButton(onClick = {
                    showResetConfirm = false
                    performIdentityMutation(
                        mutation = NostrIdentityMutation.ResetKey,
                        operation = { nostrService.resetToSeedKey() },
                    )
                }) {
                    Text("Reset", color = MaterialTheme.colorScheme.error)
                }
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
                TextButton(onClick = {
                    pendingSignerType = null
                    performIdentityMutation(
                        mutation = NostrIdentityMutation.SwitchSigner,
                        operation = { nostrService.switchSignerType(signerType) },
                    )
                }) { Text("Switch") }
            },
            dismissButton = {
                TextButton(onClick = { pendingSignerType = null }) { Text("Cancel") }
            },
        )
    }

    if (addRelayOpen) {
        var input by remember { mutableStateOf("wss://") }
        AlertDialog(
            onDismissRequest = { addRelayOpen = false; addRelayError = null },
            title = { Text("Add relay") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug)) {
                    CashuTextField(
                        value = input,
                        onValueChange = { input = it; addRelayError = null },
                        label = "wss:// URL",
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                    if (addRelayError != null) {
                        InlineNotice(text = addRelayError!!)
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    runCatching { settingsManager.addRelay(input.trim()) }
                        .onSuccess { addRelayOpen = false; addRelayError = null }
                        .onFailure { addRelayError = it.message ?: "Invalid relay URL." }
                }) { Text("Add") }
            },
            dismissButton = {
                TextButton(onClick = { addRelayOpen = false; addRelayError = null }) { Text("Cancel") }
            },
        )
    }
}
