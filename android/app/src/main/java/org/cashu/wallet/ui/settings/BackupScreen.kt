package org.cashu.wallet.ui.settings

import androidx.compose.foundation.background
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import kotlin.random.Random
import kotlinx.coroutines.delay
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.ui.components.CashuTextField
import org.cashu.wallet.ui.components.GhostButton
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.SectionHeader
import org.cashu.wallet.ui.theme.CashuTheme as CashuThemeTokens

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupScreen(
    walletManager: WalletManager,
    onClose: () -> Unit,
) {
    val mnemonic = remember { walletManager.backupMnemonic().orEmpty() }
    val words = remember(mnemonic) {
        mnemonic.trim().split(' ').filter { it.isNotBlank() }
    }
    val clipboard = LocalClipboardManager.current

    var revealed by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    var verifying by remember { mutableStateOf(false) }

    LaunchedEffect(copied) {
        if (copied) { delay(2000); copied = false }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Backup", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
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
                .verticalScroll(rememberScrollState())
                .padding(horizontal = CashuThemeTokens.spacing.comfortable),
            verticalArrangement = Arrangement.spacedBy(CashuThemeTokens.spacing.comfortable),
        ) {
            Spacer(Modifier.height(CashuThemeTokens.spacing.snug))
            WarningBanner(
                "Anyone with these words can spend your wallet. Store them offline."
            )
            if (revealed) {
                SectionHeader("Recovery phrase")
                SeedGrid(words = words)
                Row(
                    horizontalArrangement = Arrangement.spacedBy(CashuThemeTokens.spacing.snug),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    PrimaryButton(
                        text = if (copied) "Copied" else "Copy phrase",
                        onClick = {
                            clipboard.setText(AnnotatedString(mnemonic))
                            copied = true
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
                GhostButton(
                    text = if (verifying) "Hide verify quiz" else "Verify phrase",
                    onClick = { verifying = !verifying },
                    modifier = Modifier.fillMaxWidth(),
                )
                if (verifying) {
                    VerifyQuiz(words = words)
                }
            } else {
                PrimaryButton(
                    text = "Reveal phrase",
                    onClick = { revealed = true },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Spacer(Modifier.height(CashuThemeTokens.spacing.section))
        }
    }
}

@Composable
private fun WarningBanner(text: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .background(CashuThemeTokens.colors.pendingContainer)
            .padding(CashuThemeTokens.spacing.comfortable),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuThemeTokens.spacing.snug),
    ) {
        Icon(
            imageVector = Icons.Outlined.Warning,
            contentDescription = null,
            tint = CashuThemeTokens.colors.pending,
            modifier = Modifier.size(CashuThemeTokens.spacing.loose),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun SeedGrid(words: List<String>) {
    val mono = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(CashuThemeTokens.spacing.comfortable),
        verticalArrangement = Arrangement.spacedBy(CashuThemeTokens.spacing.snug),
    ) {
        words.chunked(2).forEachIndexed { rowIndex, pair ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(CashuThemeTokens.spacing.default),
            ) {
                pair.forEachIndexed { columnIndex, word ->
                    val index = rowIndex * 2 + columnIndex + 1
                    Row(
                        modifier = Modifier.weight(1f),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(CashuThemeTokens.spacing.snug),
                    ) {
                        Text(
                            text = "%2d".format(index),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(text = word, style = mono)
                    }
                }
            }
        }
    }
}

@Composable
private fun VerifyQuiz(words: List<String>) {
    val positions = remember(words) {
        if (words.size < 12) emptyList()
        else generateSequence { Random.nextInt(words.size) }
            .distinct()
            .take(3)
            .toList()
            .sorted()
    }
    val answers = remember(positions) { mutableStateMapOf<Int, String>() }
    val verified = positions.isNotEmpty() && positions.all {
        answers[it]?.trim().equals(words[it], ignoreCase = true)
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(CashuThemeTokens.spacing.comfortable),
        verticalArrangement = Arrangement.spacedBy(CashuThemeTokens.spacing.default),
    ) {
        Text(
            text = if (verified) "Looks right." else "Type the words at these positions.",
            style = MaterialTheme.typography.bodyMedium,
            color = if (verified) CashuThemeTokens.colors.received
            else MaterialTheme.colorScheme.onSurface,
        )
        positions.forEach { position ->
            CashuTextField(
                value = answers[position].orEmpty(),
                onValueChange = { answers[position] = it },
                label = "Word ${position + 1}",
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                ),
            )
        }
    }
}

