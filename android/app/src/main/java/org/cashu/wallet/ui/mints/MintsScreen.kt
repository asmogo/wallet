package org.cashu.wallet.ui.mints

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.material3.rememberTopAppBarState
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.cashu.wallet.Core.MintDiscoveryManager
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.mintUrlCandidates
import org.cashu.wallet.Core.normalizeUserMintUrl
import org.cashu.wallet.Core.shortenMintUrl
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.CashuTextField
import org.cashu.wallet.ui.components.GhostButton
import org.cashu.wallet.ui.components.MintAvatar
import org.cashu.wallet.ui.components.MintMethodChips
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.theme.CashuTheme
import org.cashu.wallet.ui.theme.withMonoDigits

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MintsScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    mintDiscoveryManager: MintDiscoveryManager,
    onOpenMint: (MintInfo) -> Unit,
    onScan: () -> Unit,
    contentPadding: PaddingValues,
    scannedMintUrl: String? = null,
    onScannedMintUrlConsumed: () -> Unit = {},
) {
    val walletState by walletManager.state.collectAsState()
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current

    var url by remember { mutableStateOf("") }
    var nickname by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var pendingRemoval by remember { mutableStateOf<MintInfo?>(null) }
    var discoveryOpen by remember { mutableStateOf(false) }

    LaunchedEffect(scannedMintUrl) {
        val payload = scannedMintUrl?.trim().orEmpty()
        if (payload.isNotEmpty()) {
            url = normalizeUserMintUrl(payload) ?: payload
            error = null
            onScannedMintUrlConsumed()
        }
    }

    fun pasteFromClipboard() {
        val candidate = clipboard.getText()?.text?.let { mintUrlCandidates(it).firstOrNull() }
        if (candidate == null) {
            error = "No valid mint URL in clipboard."
        } else {
            url = candidate
            error = null
        }
    }

    fun addMint() {
        val normalized = normalizeUserMintUrl(url)
        if (normalized == null) {
            error = "Enter a valid HTTPS mint URL."
            return
        }
        error = null
        scope.launch {
            runCatching { walletManager.addMint(normalized) }
                .onSuccess {
                    url = ""
                    nickname = ""
                }
                .onFailure { error = it.message ?: "Could not add mint." }
        }
    }

    val topBarState = rememberTopAppBarState()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(state = topBarState)

    Scaffold(
        modifier = Modifier
            .padding(contentPadding)
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Mints") },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    scrolledContainerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(bottom = CashuTheme.spacing.section),
        ) {
            if (walletState.mints.isNotEmpty()) {
                items(walletState.mints, key = { it.url }) { mint ->
                    val isActive = walletState.activeMint?.url == mint.url
                    SwipeableMintRow(
                        mint = mint,
                        isActive = isActive,
                        onOpen = { onOpenMint(mint) },
                        onSetActive = {
                            if (!isActive) {
                                scope.launch { walletManager.setActiveMint(mint) }
                            }
                        },
                        onRequestRemove = { pendingRemoval = mint },
                    )
                    if (mint != walletState.mints.last()) CanvasDivider(leadingInset = 64)
                }
            }

            item("discover-row") {
                ListEntryRow(
                    leadingIcon = {
                        Box(
                            modifier = Modifier
                                .size(MINT_AVATAR_SIZE)
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                imageVector = Icons.Outlined.Search,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.size(CashuTheme.spacing.loose),
                            )
                        }
                    },
                    title = "Discover mints",
                    subtitle = "Browse mints announced over Nostr",
                    onClick = { discoveryOpen = true },
                )
            }

            item("add-form") {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(
                            horizontal = CashuTheme.spacing.comfortable,
                            vertical = CashuTheme.spacing.comfortable,
                        ),
                    verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                ) {
                    CashuTextField(
                        value = url,
                        onValueChange = { url = it; error = null },
                        label = "Mint URL",
                        placeholder = "https://…",
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            capitalization = KeyboardCapitalization.None,
                        ),
                        trailingIcon = {
                            IconButton(onClick = onScan) {
                                Icon(
                                    imageVector = Icons.Outlined.QrCodeScanner,
                                    contentDescription = "Scan",
                                )
                            }
                        },
                    )
                    CashuTextField(
                        value = nickname,
                        onValueChange = { nickname = it },
                        label = "Nickname (optional)",
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (error != null) {
                        Text(
                            text = error!!,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        GhostButton(
                            text = "Paste",
                            onClick = ::pasteFromClipboard,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    PrimaryButton(
                        text = "Add mint",
                        onClick = ::addMint,
                        enabled = url.isNotBlank() && !walletState.isLoading,
                        loading = walletState.isLoading,
                    )
                    Spacer(Modifier.height(CashuTheme.spacing.snug))
                }
            }

            walletState.errorMessage?.let { msg ->
                item("err") {
                    Text(
                        text = msg,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(
                            horizontal = CashuTheme.spacing.comfortable,
                            vertical = CashuTheme.spacing.snug,
                        ),
                    )
                }
            }
        }
    }

    if (discoveryOpen) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { discoveryOpen = false },
            sheetState = sheetState,
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = "Discover Mints",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(
                        horizontal = CashuTheme.spacing.comfortable,
                        vertical = CashuTheme.spacing.snug,
                    ),
                )
                MintDiscoveryContent(
                    walletManager = walletManager,
                    settingsManager = settingsManager,
                    mintDiscoveryManager = mintDiscoveryManager,
                )
            }
        }
    }

    pendingRemoval?.let { mint ->
        AlertDialog(
            onDismissRequest = { pendingRemoval = null },
            title = { Text("Remove Mint") },
            text = {
                Text(
                    "Remove ${mint.name}? You will lose access to any ecash issued by this mint unless you re-add it.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val target = mint
                    pendingRemoval = null
                    scope.launch { walletManager.removeMint(target) }
                }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingRemoval = null }) { Text("Cancel") }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeableMintRow(
    mint: MintInfo,
    isActive: Boolean,
    onOpen: () -> Unit,
    onSetActive: () -> Unit,
    onRequestRemove: () -> Unit,
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    onSetActive()
                    false
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    onRequestRemove()
                    false
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        },
    )
    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = !isActive,
        backgroundContent = {
            val dir = dismissState.dismissDirection
            val bg: Color
            val fg: Color
            val icon: androidx.compose.ui.graphics.vector.ImageVector?
            val label: String
            val align: Alignment
            when (dir) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    bg = CashuTheme.colors.received
                    fg = Color.White
                    icon = Icons.Outlined.Check
                    label = "Set Active"
                    align = Alignment.CenterStart
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    bg = MaterialTheme.colorScheme.error
                    fg = MaterialTheme.colorScheme.onError
                    icon = Icons.Outlined.Delete
                    label = "Remove"
                    align = Alignment.CenterEnd
                }
                SwipeToDismissBoxValue.Settled -> {
                    bg = Color.Transparent
                    fg = Color.Transparent
                    icon = null
                    label = ""
                    align = Alignment.Center
                }
            }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(bg)
                    .padding(horizontal = CashuTheme.spacing.loose),
                contentAlignment = align,
            ) {
                if (icon != null) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                    ) {
                        Icon(imageVector = icon, contentDescription = label, tint = fg)
                        Text(text = label, color = fg, style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
        },
    ) {
        MintRow(
            mint = mint,
            isActive = isActive,
            onClick = onOpen,
            onSetActiveLongPress = onSetActive,
            onRemoveLongPress = onRequestRemove,
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MintRow(
    mint: MintInfo,
    isActive: Boolean,
    onClick: () -> Unit,
    onSetActiveLongPress: () -> Unit = {},
    onRemoveLongPress: () -> Unit = {},
) {
    var menuOpen by remember { mutableStateOf(false) }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .combinedClickable(
                onClick = onClick,
                onLongClick = { menuOpen = true },
            ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.default,
                ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            Box {
                MintAvatar(mint = mint)
                if (isActive) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(CashuTheme.spacing.default)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.surface),
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(CashuTheme.spacing.snug)
                                .clip(CircleShape)
                                .background(CashuTheme.colors.received),
                        )
                    }
                }
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = mint.name,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = shortenMintUrl(mint.url),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                )
                if (mint.supportedMintMethods.isNotEmpty() || mint.supportedMeltMethods.isNotEmpty()) {
                    Spacer(Modifier.height(CashuTheme.spacing.micro))
                    MintMethodChips(mint = mint)
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = "${mint.balance}",
                    style = MaterialTheme.typography.bodyMedium.withMonoDigits(),
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "sat",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(CashuTheme.spacing.loose),
            )
        }
        DropdownMenu(
            expanded = menuOpen,
            onDismissRequest = { menuOpen = false },
        ) {
            DropdownMenuItem(
                text = { Text("Set as Active") },
                onClick = {
                    menuOpen = false
                    onSetActiveLongPress()
                },
                enabled = !isActive,
            )
            DropdownMenuItem(
                text = {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                },
                onClick = {
                    menuOpen = false
                    onRemoveLongPress()
                },
            )
        }
    }
}

// Mint avatar / leading box size — matches TransactionRow's MethodIconSize for
// vertically-aligned timeline rendering.
private val MINT_AVATAR_SIZE = 40.dp

@Composable
internal fun ListEntryRow(
    leadingIcon: @Composable () -> Unit,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(
                horizontal = CashuTheme.spacing.comfortable,
                vertical = CashuTheme.spacing.default,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        leadingIcon()
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (subtitle != null) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Icon(
            imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(CashuTheme.spacing.loose),
        )
    }
}
