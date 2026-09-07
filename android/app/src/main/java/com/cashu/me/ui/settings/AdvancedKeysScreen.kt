package com.cashu.me.ui.settings

import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import com.cashu.me.Core.Wallet.ActionErrorMessages

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.IntSize
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Models.P2PKKeyInfo
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.components.SettingsFooterText
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.rememberReducedMotion

/**
 * Disposable device-only keys: generate, import, and browse. Each key opens its
 * own detail screen. Pushed from the Locked Ecash hub so the main screen stays
 * calm (iOS AdvancedKeysView).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdvancedKeysScreen(
    settingsManager: SettingsManager,
    onOpenKey: (String) -> Unit,
    onClose: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
    var showImport by remember { mutableStateOf(false) }
    var actionError by remember { mutableStateOf<String?>(null) }
    val reduceMotion = rememberReducedMotion()
    val listSizeSpec = MaterialTheme.motionScheme.defaultSpatialSpec<IntSize>()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Advanced Keys", style = MaterialTheme.typography.titleMedium) },
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
            NavRow(
                title = "Generate a key",
                leadingIcon = Icons.Outlined.AddCircleOutline,
                showChevron = false,
                onClick = {
                    actionError = null
                    runCatching { settingsManager.generateP2PKKey() }
                        .onFailure {
                            actionError = ActionErrorMessages.message(it, ActionErrorMessages.Context.KeyGenerate)
                        }
                },
            )
            NavRow(
                title = "Import a key",
                leadingIcon = Icons.Outlined.FileDownload,
                showChevron = false,
                onClick = {
                    actionError = null
                    showImport = true
                },
            )

            actionError?.let { error ->
                InlineNotice(
                    text = error,
                    modifier = Modifier.padding(
                        horizontal = CashuTheme.spacing.comfortable,
                        vertical = CashuTheme.spacing.snug,
                    ),
                    severity = NoticeSeverity.Error,
                )
            }

            if (settings.p2pkKeys.isEmpty()) {
                SettingsFooterText(
                    "Device-only keys are stored on this device, not in your seed backup. " +
                        "If you lose this device, ecash locked to them is gone — keep amounts small.",
                )
            } else {
                Spacer(Modifier.height(CashuTheme.spacing.default))
                SectionHeader("Device keys")
                // Key generation/import/removal animates the list resize (iOS
                // .animation(value: settings.p2pkKeys) parity).
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            if (reduceMotion) {
                                Modifier
                            } else {
                                Modifier.animateContentSize(animationSpec = listSizeSpec)
                            },
                        ),
                ) {
                    settings.p2pkKeys.forEachIndexed { index, key ->
                        DeviceKeyRow(
                            key = key,
                            isUsable = key.id !in settings.p2pkUnavailableKeyIds,
                            onClick = { onOpenKey(key.id) },
                        )
                    }
                }
                SettingsFooterText(
                    "These keys aren't in your seed backup. Back up each one, or keep amounts small.",
                )
            }
            Spacer(Modifier.height(CashuTheme.spacing.section))
        }
    }

    if (showImport) {
        ImportP2PKSheet(
            onImport = { nsec ->
                runCatching { settingsManager.importP2PKNsec(nsec) }
            },
            onDismiss = { showImport = false },
        )
    }
}

@Composable
private fun DeviceKeyRow(key: P2PKKeyInfo, isUsable: Boolean, onClick: () -> Unit) {
    NavRow(
        title = key.label.ifBlank { P2PKKeyDisplay.shortLabel(key.publicKey) },
        subtitle = buildString {
            append(if (isUsable) "Device only" else "Repair required")
            if (isUsable && key.usedCount > 0) {
                append(" · ")
                append(if (key.usedCount == 1) "Used once" else "Used ${key.usedCount} times")
            }
        },
        leadingIcon = Icons.Outlined.Key,
        onClick = onClick,
    )
}

/** Keyboard-resilient nsec form sheet (iOS ImportP2PKSheet). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ImportP2PKSheet(
    onImport: (String) -> Result<Unit>,
    onDismiss: () -> Unit,
) {
    var input by remember { mutableStateOf("") }
    var inputError by remember { mutableStateOf<String?>(null) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberBottomSheetState(
            initialValue = SheetValue.Hidden,
            enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded),
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = CashuTheme.spacing.comfortable)
                .padding(bottom = CashuTheme.spacing.section),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
        ) {
            SheetHeader(title = "Import a key")
            Text(
                "Paste the key's nsec. It will live only on this device, not in your seed backup.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            CashuTextField(
                value = input,
                onValueChange = { input = it; inputError = null },
                label = "nsec1…",
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                isError = inputError != null,
                supportingText = inputError,
            )
            PrimaryButton(
                text = "Import key",
                enabled = input.isNotBlank(),
                onClick = {
                    val trimmed = input.trim()
                    if (!trimmed.startsWith("nsec1", ignoreCase = true)) {
                        inputError = "That doesn't look like an nsec key."
                        return@PrimaryButton
                    }
                    onImport(trimmed)
                        .onSuccess { onDismiss() }
                        .onFailure { inputError = ActionErrorMessages.message(it, ActionErrorMessages.Context.KeyImport) }
                },
            )
        }
    }
}
