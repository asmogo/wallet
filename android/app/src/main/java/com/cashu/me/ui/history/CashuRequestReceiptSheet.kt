package com.cashu.me.ui.history

import androidx.compose.runtime.Composable
import com.cashu.me.Core.CashuRequestStore
import com.cashu.me.Core.NfcReceive.NfcReceiveCoordinator
import com.cashu.me.Core.NostrService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.WalletManager
import com.cashu.me.Models.CashuRequest
import com.cashu.me.ui.receive.CashuRequestDetailScreen

/** History retains request editing, regeneration and live receive behavior in a sheet. */
@Composable
fun CashuRequestReceiptSheet(
    request: CashuRequest,
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    nostrService: NostrService,
    nfcReceiveCoordinator: NfcReceiveCoordinator,
    store: CashuRequestStore,
    onDismissRequest: () -> Unit,
    onBackdropVisibilityChanged: (Boolean) -> Unit = {},
) {
    CashuRequestDetailScreen(
        walletManager = walletManager,
        settingsManager = settingsManager,
        nostrService = nostrService,
        cashuRequestStore = store,
        nfcReceiveCoordinator = nfcReceiveCoordinator,
        requestId = request.id,
        onClose = onDismissRequest,
        asActivitySheet = true,
        onBackdropVisibilityChanged = onBackdropVisibilityChanged,
    )
}
