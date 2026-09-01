package com.cashu.me.ui.mints

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
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.nestedscroll.nestedScroll
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
import com.cashu.me.Core.normalizeUserMintUrl
import com.cashu.me.Core.shortenMintUrl
import com.cashu.me.Models.MintInfo
import com.cashu.me.ui.components.MintAvatar
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.TabTopBar
import com.cashu.me.ui.components.groupItemShape
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits
import com.cashu.me.ui.testing.UiTestTags
import kotlinx.coroutines.CancellationException

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun MintsScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    mintDiscoveryManager: MintDiscoveryManager,
    onOpenMint: (MintInfo) -> Unit,
    onScan: () -> Unit,
    contentPadding: PaddingValues,
    allowCleartextLocalTestMints: Boolean = false,
    scannedMintUrl: String? = null,
    onScannedMintUrlConsumed: () -> Unit = {},
) {
    val walletState by walletManager.state.collectAsState()
    val scope = rememberCoroutineScope()

    var pendingRemoval by remember { mutableStateOf<MintInfo?>(null) }
    var addMintOpen by remember { mutableStateOf(false) }
    var addMintInitialUrl by remember { mutableStateOf("") }
    var discoveryOpen by remember { mutableStateOf(false) }
    var removalError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(scannedMintUrl) {
        val payload = scannedMintUrl?.trim().orEmpty()
        if (payload.isNotEmpty()) {
            addMintInitialUrl = normalizeUserMintUrl(
                payload,
                allowCleartextLocalTestMints = allowCleartextLocalTestMints,
            ) ?: payload
            addMintOpen = true
            onScannedMintUrlConsumed()
        }
    }

    // Non-blocking NUT-06 refresh — same as iOS MintsListView `.task`.
    // Does not flip isLoading, so the list stays interactive.
    LaunchedEffect(Unit) {
        walletManager.refreshMintInfo()
    }

    val topBarState = rememberTopAppBarState()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(state = topBarState)

    Scaffold(
        modifier = Modifier
            .testTag(UiTestTags.MintsScreen)
            .padding(contentPadding)
            // The shell scaffold's padding already carries the status-bar inset;
            // consume it so the nested TopAppBar doesn't apply it a second time.
            .consumeWindowInsets(contentPadding)
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            TabTopBar(title = "Mints", scrollBehavior = scrollBehavior)
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(
                start = CashuTheme.spacing.comfortable,
                end = CashuTheme.spacing.comfortable,
                bottom = CashuTheme.spacing.section,
            ),
        ) {
            if (removalError != null) {
                item("removal-error") {
                    InlineNotice(
                        text = removalError.orEmpty(),
                        severity = NoticeSeverity.Error,
                        modifier = Modifier.padding(bottom = CashuTheme.spacing.snug),
                    )
                }
            }
            if (walletState.mints.isNotEmpty()) {
                val mintCount = walletState.mints.size
                itemsIndexed(walletState.mints, key = { _, mint -> mint.url }) { index, mint ->
                    val isActive = walletState.activeMint?.url == mint.url
                    val shape = groupItemShape(index, mintCount, MaterialTheme.shapes.medium)
                    Column(modifier = Modifier.animateItem()) {
                        SwipeableMintRow(
                            mint = mint,
                            isActive = isActive,
                            shape = shape,
                            onOpen = { onOpenMint(mint) },
                            onSetActive = {
                                if (!isActive) {
                                    scope.launch { walletManager.setActiveMint(mint) }
                                }
                            },
                            onRequestRemove = { pendingRemoval = mint },
                        )
                    }
                }

                item("cards-gap") {
                    Spacer(Modifier.height(CashuTheme.spacing.section))
                }
            }

            item("add-row") {
                ListEntryRow(
                    shape = groupItemShape(0, 2, MaterialTheme.shapes.medium),
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Outlined.Add,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(CashuTheme.spacing.loose),
                        )
                    },
                    title = "Add mint",
                    onClick = {
                        addMintInitialUrl = ""
                        addMintOpen = true
                    },
                    modifier = Modifier.semantics { contentDescription = "Add mint" },
                )
            }

            item("discover-row") {
                // Quiet nav-row weight: plain monochrome glyph, no filled circle.
                ListEntryRow(
                    shape = groupItemShape(1, 2, MaterialTheme.shapes.medium),
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Outlined.Search,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(CashuTheme.spacing.loose),
                        )
                    },
                    title = "Discover mints",
                    onClick = { discoveryOpen = true },
                )
            }
        }
    }

    if (addMintOpen) {
        AddMintSheet(
            walletManager = walletManager,
            initialUrl = addMintInitialUrl,
            allowCleartextLocalTestMints = allowCleartextLocalTestMints,
            onDismiss = { addMintOpen = false },
        )
    }

    if (discoveryOpen) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { discoveryOpen = false },
            sheetState = sheetState,
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = "Discover mints",
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
                    "Remove ${mint.name}? Any unspent ecash on this mint will need to be restored from your seed phrase.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val target = mint
                    pendingRemoval = null
                    removalError = null
                    scope.launch {
                        try {
                            walletManager.removeMint(target)
                        } catch (cancellation: CancellationException) {
                            throw cancellation
                        } catch (error: Throwable) {
                            removalError = error.userFacingWalletMessage
                        }
                    }
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
    shape: Shape,
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
                    // Black is the accessible on-fill role for the saturated
                    // system green in both schemes; white is only 2.2:1.
                    fg = Color.Black
                    icon = Icons.Outlined.Check
                    label = "Set as Default"
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
                    .clip(shape)
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
            shape = shape,
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
    shape: Shape,
    onClick: () -> Unit,
    onSetActiveLongPress: () -> Unit = {},
    onRemoveLongPress: () -> Unit = {},
) {
    var menuOpen by remember { mutableStateOf(false) }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(UiTestTags.mintRow(mint.url))
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .combinedClickable(
                onClick = onClick,
                onLongClick = { menuOpen = true },
                onLongClickLabel = "Show mint actions",
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
                    // Default-mint dot — state is also surfaced to TalkBack so
                    // it isn't encoded by colour alone.
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(CashuTheme.spacing.default)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.surface)
                            .semantics { contentDescription = "Default mint" },
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
                    fontWeight = FontWeight.Medium,
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
            }
            // Quiet trailing balance (iOS: "N sat" subheadline secondary).
            // Payment-method chips live in Mint Detail, not on list rows.
            Text(
                text = "${mint.balance} sat",
                style = MaterialTheme.typography.bodyMedium.withMonoDigits(),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
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
            shape = MaterialTheme.shapes.large,
        ) {
            DropdownMenuItem(
                text = { Text("Set as Default") },
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

@Composable
internal fun ListEntryRow(
    shape: Shape,
    leadingIcon: @Composable () -> Unit,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
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
