package org.cashu.wallet.Core

import org.cashu.wallet.Models.ClaimedToken
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.PendingReceiveToken
import org.cashu.wallet.Models.PendingToken
import org.cashu.wallet.Models.WalletTransaction

data class WalletState(
    val balance: Long = 0,
    val pendingBalance: Long = 0,
    val isInitialized: Boolean = false,
    val needsOnboarding: Boolean = true,
    val canExitOnboarding: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val activeUnit: String = "sat",
    val mints: List<MintInfo> = emptyList(),
    val activeMint: MintInfo? = null,
    val transactions: List<WalletTransaction> = emptyList(),
    val pendingTokens: List<PendingToken> = emptyList(),
    val pendingReceiveTokens: List<PendingReceiveToken> = emptyList(),
    val claimedTokens: List<ClaimedToken> = emptyList(),
    val transactionUpdateVersion: Long = 0,
)
