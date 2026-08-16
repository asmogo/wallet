package com.cashu.me.Core

import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.WalletTransaction

/**
 * Sanitized startup failure shown before a wallet runtime is available.
 *
 * Startup errors can originate in CDK/FFI, secure storage, or SQLite. Keep the
 * implementation detail out of UI state and always pair the explanation with
 * an action the welcome screen can perform.
 */
data class WalletStartupFailure(
    val message: String,
    val recoveryActionLabel: String = "Try Again",
)

internal fun walletStartupFailure(hasStoredWallet: Boolean): WalletStartupFailure =
    if (hasStoredWallet) {
        WalletStartupFailure(
            message = "The saved wallet couldn't be opened. Try again. " +
                "If this keeps happening, restore it from your seed phrase.",
        )
    } else {
        WalletStartupFailure(
            message = "The wallet couldn't start. Try again in a moment.",
        )
    }

data class WalletState(
    val balance: Long = 0,
    val pendingBalance: Long = 0,
    val isInitialized: Boolean = false,
    /** True once the encrypted seed and local CDK repository are ready. */
    val isRuntimeReady: Boolean = false,
    val needsOnboarding: Boolean = true,
    val canExitOnboarding: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val startupFailure: WalletStartupFailure? = null,
    // Per-unit totals across mints ("sat" included). The primary balance model
    // stays sat-denominated; there is deliberately no global active unit — unit
    // selection lives per flow, matching iOS.
    val balancesByUnit: Map<String, Long> = emptyMap(),
    val mints: List<MintInfo> = emptyList(),
    val activeMint: MintInfo? = null,
    val transactions: List<WalletTransaction> = emptyList(),
    val pendingReceiveTokens: List<PendingReceiveToken> = emptyList(),
    val transactionUpdateVersion: Long = 0,
) {
    /** True when any unit — sat or not — holds a spendable balance. */
    val hasAnyBalance: Boolean
        get() = balance > 0 || balancesByUnit.values.any { it > 0 }
}
