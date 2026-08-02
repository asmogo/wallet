package com.cashu.me.ui.shell

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import kotlinx.coroutines.launch
import com.cashu.me.ui.navigation.TopTab

/**
 * The money flows presented over the shell (iOS `WalletFlow` sheets).
 * These are native M3 modal bottom sheets, not pushed destinations:
 * Receive Ecash and Contactless wrap their content (≈ iOS `.medium` detent),
 * the others fill the sheet (≈ iOS `.large`).
 */
sealed interface WalletFlow {
    data object ReceiveEcash : WalletFlow
    data object ReceiveLightning : WalletFlow
    data object Send : WalletFlow
    data object SendEcash : WalletFlow
    data object Contactless : WalletFlow

    /**
     * Connect-a-mint, opened from the wallet-home empty state. Hosted here rather
     * than as a Home-local sheet so its URL step can hand off to the camera
     * through [WalletFlowHandoffCoordinator] — overlays render under the sheet's
     * dialog window, so the sheet has to close first.
     */
    data object ConnectMint : WalletFlow
}

/**
 * A transition from the open flow sheet to a *different* surface.
 *
 * Two-tier rule: swapping content between flows assigns `activeFlow` directly
 * (the sheet stays up and AnimatedContent cross-fades); moving to any other
 * surface — camera overlay, full-screen claim page, a pushed route or tab —
 * parks the destination here so the sheet's hide animation completes before
 * the new surface mounts. Camera overlays render in the activity window,
 * underneath the sheet's dialog window, and a page mounted under a
 * still-dismissing sheet plays two animations at once.
 */
internal sealed interface FlowHandoffDestination {
    data class Scanner(val target: ScannerTarget) : FlowHandoffDestination

    /**
     * Scan a mint URL from a flow's add-mint step. [returnTo] is replayed once
     * the scan resolves, so the user lands back on the step they left rather
     * than on whichever surface the payload would otherwise route to.
     */
    data class MintScanner(val returnTo: WalletFlow) : FlowHandoffDestination
    data class ReceiveDetail(val token: String) : FlowHandoffDestination
    data class NavRoute(val route: String) : FlowHandoffDestination
    data class NavTab(val tab: TopTab) : FlowHandoffDestination
}

/**
 * Defers a [FlowHandoffDestination] until the modal sheet's hide animation has
 * completed. Consume-once; a second [request] before dismissal replaces the
 * first (last wins).
 */
internal class WalletFlowHandoffCoordinator {
    private var pending: FlowHandoffDestination? = null

    fun request(destination: FlowHandoffDestination, close: () -> Unit) {
        pending = destination
        close()
    }

    fun completeDismissal(dispatch: (FlowHandoffDestination) -> Unit) {
        pending.also { pending = null }?.let(dispatch)
    }
}

/**
 * Single ModalBottomSheet hosting whichever flow is active. Keeping one sheet
 * (instead of one per flow) lets Send → Send Ecash swap content inside the
 * open sheet rather than tearing the window down and re-presenting.
 *
 * [dismissLocked] blocks swipe/scrim/back dismissal while money is moving
 * (a payment mid-melt must not lose its UI to an accidental drag).
 *
 * Content receives a `close` lambda that plays the hide animation before
 * clearing the flow — callbacks must use it instead of clearing state
 * directly, or the sheet vanishes with a hard cut.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WalletFlowSheetHost(
    flow: WalletFlow?,
    dismissLocked: Boolean,
    onDismissed: () -> Unit,
    snackbarHostState: SnackbarHostState,
    content: @Composable (flow: WalletFlow, close: () -> Unit) -> Unit,
) {
    if (flow == null) return
    val locked by rememberUpdatedState(dismissLocked)
    // Stable lambda: rememberModalBottomSheetState keys its saver on it.
    val confirmValueChange = remember {
        { value: SheetValue -> value != SheetValue.Hidden || !locked }
    }
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = confirmValueChange,
    )
    val scope = rememberCoroutineScope()
    val close: () -> Unit = {
        scope.launch { sheetState.hide() }.invokeOnCompletion { onDismissed() }
    }
    ModalBottomSheet(
        onDismissRequest = onDismissed,
        sheetState = sheetState,
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            AnimatedContent(
                targetState = flow,
                transitionSpec = {
                    fadeIn(spring(stiffness = Spring.StiffnessMedium))
                        .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
                },
                label = "wallet-flow",
            ) { current ->
                content(current, close)
            }
            // Sheet renders in its own Android Window — the root-mounted host
            // in CashuApp.kt can't reach here, so mount a second one observing
            // the same SnackbarHostState.
            SnackbarHost(
                hostState = snackbarHostState,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
    }
}
