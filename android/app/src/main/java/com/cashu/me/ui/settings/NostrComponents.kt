package com.cashu.me.ui.settings

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material.icons.outlined.Sensors
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import com.cashu.me.Core.NostrSignerType
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.SelectionRow
import com.cashu.me.ui.components.SettingsFooterText
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withSlashedZero

/**
 * Resetting only warrants a confirmation when it would discard a relay the
 * defaults don't already contain. An empty list, or one that is a subset of the
 * defaults, loses nothing — prompting there is noise.
 */
internal fun shouldConfirmRelayReset(current: List<String>, defaults: List<String>): Boolean =
    current.any { relay -> defaults.none { it.equals(relay, ignoreCase = true) } }

/**
 * The Nostr key hub: the active key, where it comes from, and the actions that
 * replace it. Stateless so previews and tests can mount it.
 * Mirrors iOS `NostrKeysSettingsSection`.
 */
@Composable
internal fun NostrKeySection(
    npub: String,
    publicKeyHex: String,
    isReady: Boolean,
    signerType: NostrSignerType,
    isMutating: Boolean,
    progressMessage: String?,
    errorMessage: String?,
    onRevealNsec: () -> Unit,
    onSelectSigner: (NostrSignerType) -> Unit,
    onGenerateKey: () -> Unit,
    onImportKey: () -> Unit,
    onResetToSeed: () -> Unit,
) {
    SectionHeader("Nostr key")
    if (isReady) {
        KeyCard(
            title = "Nostr key",
            pubkey = npub,
            status = if (signerType == NostrSignerType.Seed) {
                KeyCardStatus.SeedBacked
            } else {
                KeyCardStatus.Custom
            },
            actions = listOf(
                KeyCardAction("Reveal nsec", Icons.Outlined.Visibility, onRevealNsec),
            ),
            copyOptions = listOf(
                KeyCardCopyOption("Copy npub", npub),
                KeyCardCopyOption("Copy public key (hex)", publicKeyHex),
            ),
            modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
        )
    } else {
        NostrKeyNotReadyCard()
    }
    SettingsFooterText("Your Lightning address and npub.cash come from this key.")

    SectionHeader("Key source")
    Column(modifier = Modifier.selectableGroup()) {
        NostrSignerType.entries.forEach { type ->
            SelectionRow(
                title = type.displayName,
                description = type.description,
                selected = signerType == type,
                enabled = !isMutating,
                onClick = { onSelectSigner(type) },
            )
        }
    }

    Spacer(Modifier.height(CashuTheme.spacing.snug))
    Column(
        modifier = Modifier.animateContentSize(spring(stiffness = Spring.StiffnessMediumLow)),
    ) {
        NavRow(
            title = "Generate new key",
            leadingIcon = Icons.Outlined.AddCircleOutline,
            showChevron = false,
            enabled = !isMutating,
            onClick = onGenerateKey,
        )
        NavRow(
            title = "Import key",
            leadingIcon = Icons.Outlined.FileDownload,
            showChevron = false,
            enabled = !isMutating,
            onClick = onImportKey,
        )
        // iOS only offers the way back when there is a custom key to leave.
        if (signerType == NostrSignerType.PrivateKey) {
            NavRow(
                title = "Reset to wallet seed",
                leadingIcon = Icons.Outlined.RestartAlt,
                showChevron = false,
                enabled = !isMutating,
                onClick = onResetToSeed,
            )
        }
    }

    if (progressMessage != null || errorMessage != null) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.snug,
                ),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            progressMessage?.let { InlineNotice(text = it, severity = NoticeSeverity.Info) }
            errorMessage?.let { InlineNotice(text = it, severity = NoticeSeverity.Error) }
        }
    }
}

/** iOS's placeholder card for a wallet that hasn't derived its key yet. */
@Composable
internal fun NostrKeyNotReadyCard() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = CashuTheme.spacing.comfortable)
            .background(
                MaterialTheme.colorScheme.surfaceContainerHigh,
                MaterialTheme.shapes.medium,
            )
            .padding(CashuTheme.spacing.comfortable),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Box(
            modifier = Modifier
                .size(CashuTheme.spacing.page + CashuTheme.spacing.snug)
                .background(MaterialTheme.colorScheme.surfaceContainerHighest, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Outlined.Key,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(CashuTheme.spacing.loose),
            )
        }
        Text(
            text = "Your Nostr key appears once your wallet finishes setting up.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * The inline "add a relay" field that opens the relay group, replacing the old
 * dialog. Mirrors iOS's glass field with its submit affordance.
 */
@Composable
internal fun NostrRelayInputRow(
    value: String,
    onValueChange: (String) -> Unit,
    onSubmit: () -> Unit,
    isError: Boolean,
    modifier: Modifier = Modifier,
    errorText: String? = null,
) {
    val canSubmit = value.isNotBlank()
    CashuTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        placeholder = "wss://relay.example.com",
        singleLine = true,
        isError = isError,
        supportingText = errorText,
        textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = CashuTheme.fonts.mono).withSlashedZero(),
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None,
            autoCorrectEnabled = false,
            keyboardType = KeyboardType.Uri,
            imeAction = ImeAction.Done,
        ),
        keyboardActions = KeyboardActions(onDone = { if (canSubmit) onSubmit() }),
        trailingIcon = {
            IconButton(onClick = onSubmit, enabled = canSubmit) {
                Icon(
                    imageVector = Icons.Filled.ArrowCircleUp,
                    contentDescription = "Add relay",
                    tint = if (canSubmit) {
                        MaterialTheme.colorScheme.onSurface
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
        },
    )
}

/** One configured relay: the URL, a copy action, and a destructive remove. */
@Composable
internal fun NostrRelayRow(
    relay: String,
    onCopy: () -> Unit,
    onRemove: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                start = CashuTheme.spacing.comfortable,
                end = CashuTheme.spacing.snug,
                top = CashuTheme.spacing.snug,
                bottom = CashuTheme.spacing.snug,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Icon(
            imageVector = Icons.Outlined.Sensors,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(CashuTheme.spacing.section),
        )
        Text(
            text = relay,
            style = MaterialTheme.typography.bodyMedium.copy(fontFamily = CashuTheme.fonts.mono).withSlashedZero(),
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.MiddleEllipsis,
        )
        IconButton(onClick = onCopy) {
            Icon(
                imageVector = Icons.Outlined.ContentCopy,
                contentDescription = "Copy relay URL",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(CashuTheme.spacing.loose),
            )
        }
        IconButton(onClick = onRemove) {
            Icon(
                imageVector = Icons.Outlined.DeleteOutline,
                contentDescription = "Remove relay",
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(CashuTheme.spacing.loose),
            )
        }
    }
}
