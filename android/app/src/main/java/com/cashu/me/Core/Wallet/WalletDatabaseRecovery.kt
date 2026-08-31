package com.cashu.me.Core

// Moving the live database aside is safe only for definitive corruption signals.
// Busy, I/O, permission, and generic open failures must preserve it for retry.
private val walletDatabaseCorruptionIndicators = listOf(
    "sqlite_corrupt",
    "sqlite_notadb",
    "database disk image is malformed",
    "malformed database schema",
    "database disk image is corrupt",
    "file is not a database",
    "database corruption",
    "database is corrupt",
    "database is corrupted",
    "corrupt database",
)

internal fun shouldAttemptWalletDatabaseRecovery(error: Throwable): Boolean {
    val normalized = (error.message ?: error.toString()).lowercase()
    return walletDatabaseCorruptionIndicators.any { normalized.contains(it) }
}
