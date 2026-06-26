package org.cashu.wallet.Core

internal fun shouldAttemptWalletDatabaseRecovery(error: Throwable): Boolean {
    val normalized = (error.message ?: error.toString()).lowercase()
    return normalized.contains("sqlite") ||
        normalized.contains("database") ||
        normalized.contains("corrupt") ||
        normalized.contains("malformed") ||
        normalized.contains("walletdb")
}
