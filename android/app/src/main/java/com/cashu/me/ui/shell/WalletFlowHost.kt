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

/**
 * The money flows presented over the shell (iOS `WalletFlow` sheets).
 * These are native M3 modal bottom sheets, not pushed destinations:
 * Receive Ecash wraps its content (≈ iOS `.medium` detent), the others
 * fill the sheet (≈ iOS `.large`).
 */
sealed interface WalletFlow {
    data object ReceiveEcash : WalletFlow
    data object ReceiveLightning : WalletFlow
    data object Send : WalletFlow
    data object SendEcash : WalletFlow

    /**
     * Connect-a-mint, opened from the wallet-home empty state. Hosted here rather
     * than as a Home-local sheet so its URL step can hand off to the camera
     * through [WalletFlowHandoffCoordinator] — overlays render under the sheet's
     * dialog window, so the sheet has to close first.
     */
    data object ConnectMint : WalletFlow
}

/**
 * Defers activity-window overlays until the modal sheet's hide animation has
 * completed. Starting an overlay while the sheet is still composed lets a fast
 * result route back into the outgoing flow before [onDismissed] clears it.
 */
internal class WalletFlowHandoffCoordinator {
    private var pending: Destination? = null
    private var mintScanReturnFlow: WalletFlow? = null

    fun requestScanner(close: () -> Unit) {
        pending = Destination.Scanner
        close()
    }

    fun requestContactless(close: () -> Unit) {
        pending = Destination.Contactless
        close()
    }

    /**
     * Scan a mint URL from a flow's add-mint step. [returnTo] is replayed once the
     * scan resolves, so the user lands back on the step they left rather than on
     * whichever surface the payload would otherwise route to.
     */
    fun requestMintScanner(returnTo: WalletFlow, close: () -> Unit) {
        pending = Destination.MintScanner
        mintScanReturnFlow = returnTo
        close()
    }

    fun completeDismissal(
        openScanner: () -> Unit,
        openContactless: () -> Unit,
        openMintScanner: (returnTo: WalletFlow) -> Unit,
    ) {
        when (pending.also { pending = null }) {
            Destination.Scanner -> openScanner()
            Destination.Contactless -> openContactless()
            Destination.MintScanner ->
                mintScanReturnFlow?.also { mintScanReturnFlow = null }?.let(openMintScanner)
            null -> Unit
        }
    }

    private enum class Destination {
        Scanner,
        Contactless,
        MintScanner,
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
