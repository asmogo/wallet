package com.cashu.me.Core.Platform

import android.content.Context
import com.cashu.me.Core.AppLogger
import java.io.File
import java.io.IOException
import java.util.UUID

class WalletDatabasePathManager(context: Context) {
    private val files = WalletDatabaseFiles(context.applicationContext.filesDir)

    val walletDirectory: File
        get() = files.walletDirectory

    val databaseFile: File
        get() = files.databaseFile

    fun databasePathAfterLegacyMigration(): String = files.databasePathAfterLegacyMigration()

    fun backupWalletDatabaseFiles(): List<WalletFileBackup> = files.backupWalletDatabaseFiles()

    fun restoreWalletFileBackups(
        backups: List<WalletFileBackup>,
        beforeCommit: () -> Unit = {},
        onRollback: () -> Unit = {},
    ) = files.restoreWalletFileBackups(backups, beforeCommit, onRollback)

    fun removeWalletFileBackups(backups: List<WalletFileBackup>) = files.removeWalletFileBackups(backups)

    fun removeWalletDatabaseFiles() = files.removeWalletDatabaseFiles()

    fun backupCorruptedDatabase(): File? = files.backupCorruptedDatabase()
}

internal class WalletReplacementFileOperations(
    val exists: (File) -> Boolean,
    val moveItem: (File, File) -> Unit,
    val removeItem: (File) -> Unit,
) {
    companion object {
        val live = WalletReplacementFileOperations(
            exists = File::exists,
            moveItem = { source, destination ->
                if (!source.renameTo(destination)) {
                    throw IOException("Failed to move a wallet boundary item.")
                }
            },
            removeItem = { file ->
                if (file.exists() && !file.deleteRecursively()) {
                    throw IOException("Failed to remove a wallet boundary item.")
                }
            },
        )
    }
}

internal object WalletReplacementFiles {
    private data class StagedReplacement(
        val original: File,
        val displaced: File,
    )

    fun backup(
        files: List<File>,
        operations: WalletReplacementFileOperations = WalletReplacementFileOperations.live,
        backupFile: (File) -> File,
    ): List<WalletFileBackup> {
        val backups = mutableListOf<WalletFileBackup>()

        try {
            files.filter(operations.exists).forEach { original ->
                val candidate = backupFile(original)
                if (operations.exists(candidate)) operations.removeItem(candidate)

                val backup = WalletFileBackup(original, candidate)
                try {
                    operations.moveItem(original, candidate)
                    backups += backup
                } catch (error: Throwable) {
                    // Track an item that reached its destination before the
                    // move reported failure so it participates in rollback.
                    if (operations.exists(candidate)) backups += backup
                    throw error
                }
            }
        } catch (error: Throwable) {
            backups.asReversed()
                .filter { operations.exists(it.backup) }
                .forEach { backup ->
                    try {
                        if (operations.exists(backup.original)) operations.removeItem(backup.original)
                        operations.moveItem(backup.backup, backup.original)
                    } catch (rollbackError: Throwable) {
                        error.addSuppressed(rollbackError)
                    }
                }
            throw error
        }

        return backups
    }

    fun restore(
        files: List<File>,
        backups: List<WalletFileBackup>,
        operations: WalletReplacementFileOperations = WalletReplacementFileOperations.live,
        displacedFile: (File) -> File,
        beforeCommit: () -> Unit = {},
        onRollback: () -> Unit = {},
    ) {
        val missingBackupError = backups
            .firstOrNull { !operations.exists(it.backup) }
            ?.let { IOException("A wallet database backup is missing.") }
        if (missingBackupError != null) {
            performExternalRollback(missingBackupError, onRollback)
            throw missingBackupError
        }

        val restorationFiles = (files + backups.map(WalletFileBackup::original))
            .distinctBy(File::getAbsolutePath)
        val stagedReplacements = mutableListOf<StagedReplacement>()

        try {
            restorationFiles.filter(operations.exists).forEach { original ->
                val displaced = displacedFile(original)
                if (operations.exists(displaced)) operations.removeItem(displaced)

                val replacement = StagedReplacement(original, displaced)
                try {
                    operations.moveItem(original, displaced)
                    stagedReplacements += replacement
                } catch (error: Throwable) {
                    if (operations.exists(displaced)) stagedReplacements += replacement
                    throw error
                }
            }
        } catch (error: Throwable) {
            restoreStagedReplacements(stagedReplacements, operations, error)
            performExternalRollback(error, onRollback)
            throw error
        }

        val restoredBackups = mutableListOf<WalletFileBackup>()
        try {
            backups.asReversed().forEach { backup ->
                try {
                    operations.moveItem(backup.backup, backup.original)
                    restoredBackups += backup
                } catch (error: Throwable) {
                    if (operations.exists(backup.original)) restoredBackups += backup
                    throw error
                }
            }

            // Keep the replacement files recoverable until the previous seed
            // has committed. A seed failure therefore rolls the files forward.
            beforeCommit()
        } catch (error: Throwable) {
            rollBackRestoredBackups(restoredBackups, operations, error)
            restoreStagedReplacements(stagedReplacements, operations, error)
            performExternalRollback(error, onRollback)
            throw error
        }

        stagedReplacements
            .filter { operations.exists(it.displaced) }
            .forEach { replacement ->
                try {
                    operations.removeItem(replacement.displaced)
                } catch (error: Throwable) {
                    // The previous seed/database pair has committed. Cleanup
                    // failure must not trigger an unsafe rollback.
                    reportWalletCleanupFailure(
                        "Failed to remove a displaced replacement database",
                        error,
                    )
                }
            }
    }

    fun removeBackups(
        backups: List<WalletFileBackup>,
        operations: WalletReplacementFileOperations = WalletReplacementFileOperations.live,
    ) {
        backups.filter { operations.exists(it.backup) }
            .forEach { operations.removeItem(it.backup) }
    }

    fun removeAll(
        files: List<File>,
        operations: WalletReplacementFileOperations = WalletReplacementFileOperations.live,
    ) {
        files.filter(operations.exists).forEach(operations.removeItem)
    }

    private fun rollBackRestoredBackups(
        backups: List<WalletFileBackup>,
        operations: WalletReplacementFileOperations,
        originalError: Throwable,
    ) {
        backups.asReversed()
            .filter { operations.exists(it.original) }
            .forEach { backup ->
                try {
                    if (operations.exists(backup.backup)) {
                        operations.removeItem(backup.original)
                    } else {
                        operations.moveItem(backup.original, backup.backup)
                    }
                } catch (rollbackError: Throwable) {
                    originalError.addSuppressed(rollbackError)
                }
            }
    }

    private fun restoreStagedReplacements(
        replacements: List<StagedReplacement>,
        operations: WalletReplacementFileOperations,
        originalError: Throwable,
    ) {
        replacements.asReversed()
            .filter { operations.exists(it.displaced) }
            .forEach { replacement ->
                try {
                    if (operations.exists(replacement.original)) {
                        operations.removeItem(replacement.displaced)
                    } else {
                        operations.moveItem(replacement.displaced, replacement.original)
                    }
                } catch (rollbackError: Throwable) {
                    originalError.addSuppressed(rollbackError)
                }
            }
    }

    private fun performExternalRollback(
        originalError: Throwable,
        onRollback: () -> Unit,
    ) {
        try {
            onRollback()
        } catch (rollbackError: Throwable) {
            originalError.addSuppressed(rollbackError)
        }
    }
}

internal data class WalletFileMove(
    val source: File,
    val destination: File,
)

internal object WalletFileMoves {
    private data class StagedDestination(
        val destination: File,
        val displaced: File,
    )

    fun move(
        moves: List<WalletFileMove>,
        operations: WalletReplacementFileOperations = WalletReplacementFileOperations.live,
        displacedFile: (File) -> File,
    ) {
        if (moves.isEmpty()) return
        requireDistinctPaths(moves)
        moves.forEach { move ->
            if (!operations.exists(move.source)) {
                throw IOException("A wallet database move source is missing.")
            }
        }

        val stagedDestinations = mutableListOf<StagedDestination>()
        val completedMoves = mutableListOf<WalletFileMove>()
        try {
            moves.forEach { move ->
                if (!operations.exists(move.destination)) return@forEach
                val staged = StagedDestination(
                    destination = move.destination,
                    displaced = displacedFile(move.destination),
                )
                if (operations.exists(staged.displaced)) {
                    removeChecked(staged.displaced, operations)
                }
                try {
                    moveChecked(staged.destination, staged.displaced, operations)
                    stagedDestinations += staged
                } catch (error: Throwable) {
                    if (operations.exists(staged.displaced)) stagedDestinations += staged
                    throw error
                }
            }

            moves.forEach { move ->
                try {
                    moveChecked(move.source, move.destination, operations)
                    completedMoves += move
                } catch (error: Throwable) {
                    if (operations.exists(move.destination)) completedMoves += move
                    throw error
                }
            }
        } catch (error: Throwable) {
            rollBackMoves(completedMoves, operations, error)
            restoreDestinations(stagedDestinations, operations, error)
            throw error
        }

        stagedDestinations.forEach { staged ->
            if (!operations.exists(staged.displaced)) return@forEach
            try {
                removeChecked(staged.displaced, operations)
            } catch (error: Throwable) {
                reportWalletCleanupFailure(
                    "Failed to remove a displaced wallet database destination",
                    error,
                )
            }
        }
    }

    private fun requireDistinctPaths(moves: List<WalletFileMove>) {
        val sources = moves.map { it.source.absolutePath }
        val destinations = moves.map { it.destination.absolutePath }
        if (sources.distinct().size != sources.size || destinations.distinct().size != destinations.size) {
            throw IOException("Wallet database moves contain duplicate paths.")
        }
        if (sources.toSet().intersect(destinations.toSet()).isNotEmpty()) {
            throw IOException("Wallet database moves contain overlapping source and destination paths.")
        }
    }

    private fun rollBackMoves(
        moves: List<WalletFileMove>,
        operations: WalletReplacementFileOperations,
        originalError: Throwable,
    ) {
        moves.asReversed().forEach { move ->
            if (!operations.exists(move.destination)) return@forEach
            try {
                if (operations.exists(move.source)) {
                    removeChecked(move.destination, operations)
                } else {
                    moveChecked(move.destination, move.source, operations)
                }
            } catch (rollbackError: Throwable) {
                originalError.addSuppressed(rollbackError)
            }
        }
    }

    private fun restoreDestinations(
        destinations: List<StagedDestination>,
        operations: WalletReplacementFileOperations,
        originalError: Throwable,
    ) {
        destinations.asReversed().forEach { staged ->
            if (!operations.exists(staged.displaced)) return@forEach
            try {
                if (!operations.exists(staged.destination)) {
                    moveChecked(staged.displaced, staged.destination, operations)
                }
            } catch (rollbackError: Throwable) {
                originalError.addSuppressed(rollbackError)
            }
        }
    }

    private fun moveChecked(
        source: File,
        destination: File,
        operations: WalletReplacementFileOperations,
    ) {
        if (!operations.exists(source) || operations.exists(destination)) {
            throw IOException("A wallet database move has invalid source or destination state.")
        }
        operations.moveItem(source, destination)
        if (operations.exists(source) || !operations.exists(destination)) {
            throw IOException("A wallet database move did not reach its destination.")
        }
    }

    private fun removeChecked(
        file: File,
        operations: WalletReplacementFileOperations,
    ) {
        operations.removeItem(file)
        if (operations.exists(file)) {
            throw IOException("A wallet database file could not be removed.")
        }
    }
}

private fun reportWalletCleanupFailure(message: String, error: Throwable) {
    // Cleanup runs after the new database state has committed. Neither cleanup
    // nor diagnostics may make that successful transaction appear to fail.
    runCatching { AppLogger.wallet.error(message, error) }
}

internal class WalletDatabaseFiles(
    private val filesDir: File,
    private val walletDirectoryName: String = "cashu-kotlin",
    private val walletDatabaseFilename: String = "wallet.db",
    private val legacyDatabaseFilename: String = "cashu_wallet.db",
    private val sidecars: List<String> = listOf("-wal", "-shm", "-journal"),
    private val operations: WalletReplacementFileOperations = WalletReplacementFileOperations.live,
) {
    private val walletDirectoryFile: File
        get() = File(filesDir, walletDirectoryName)

    val walletDirectory: File
        get() = walletDirectoryFile.also { directory ->
            if (!directory.exists() && !directory.mkdirs()) {
                throw IOException("Failed to create the wallet database directory.")
            }
        }

    val databaseFile: File
        get() = File(walletDirectory, walletDatabaseFilename)

    fun databasePathAfterLegacyMigration(): String {
        migrateLegacyDatabaseIfNeeded()
        return databaseFile.absolutePath
    }

    fun backupWalletDatabaseFiles(): List<WalletFileBackup> {
        val timestamp = System.currentTimeMillis() / 1000
        return WalletReplacementFiles.backup(
            files = walletBoundaryFiles(),
            operations = operations,
            backupFile = { original ->
                File(
                    original.parentFile,
                    "${original.name}.replacing.$timestamp.${UUID.randomUUID()}",
                )
            },
        )
    }

    fun restoreWalletFileBackups(
        backups: List<WalletFileBackup>,
        beforeCommit: () -> Unit = {},
        onRollback: () -> Unit = {},
    ) {
        WalletReplacementFiles.restore(
            files = walletBoundaryFiles(),
            backups = backups,
            operations = operations,
            displacedFile = { original ->
                File(original.parentFile, "${original.name}.rollback.${UUID.randomUUID()}")
            },
            beforeCommit = beforeCommit,
            onRollback = onRollback,
        )
    }

    fun removeWalletFileBackups(backups: List<WalletFileBackup>) {
        WalletReplacementFiles.removeBackups(backups, operations)
    }

    fun removeWalletDatabaseFiles() {
        WalletReplacementFiles.removeAll(walletBoundaryFiles(), operations)
    }

    fun backupCorruptedDatabase(): File? {
        val database = databaseFile
        if (!operations.exists(database)) return null
        val backup = File(walletDirectory, "$walletDatabaseFilename.corrupt.${System.currentTimeMillis() / 1000}")
        val moves = buildList {
            add(WalletFileMove(database, backup))
            sidecars.forEach { suffix ->
                val sidecar = File(database.absolutePath + suffix)
                if (operations.exists(sidecar)) {
                    add(WalletFileMove(sidecar, File(backup.absolutePath + suffix)))
                }
            }
        }
        WalletFileMoves.move(
            moves = moves,
            operations = operations,
            displacedFile = ::displacedMoveDestination,
        )
        return backup
    }

    private fun migrateLegacyDatabaseIfNeeded() {
        val legacy = File(filesDir, legacyDatabaseFilename)
        val current = databaseFile
        if (!operations.exists(legacy) || operations.exists(current)) return
        val moves = buildList {
            add(WalletFileMove(legacy, current))
            sidecars.forEach { suffix ->
                val legacySidecar = File(legacy.absolutePath + suffix)
                if (operations.exists(legacySidecar)) {
                    add(WalletFileMove(legacySidecar, File(current.absolutePath + suffix)))
                }
            }
        }
        WalletFileMoves.move(
            moves = moves,
            operations = operations,
            displacedFile = ::displacedMoveDestination,
        )
    }

    private fun displacedMoveDestination(destination: File): File = File(
        destination.parentFile,
        "${destination.name}.move-displaced.${UUID.randomUUID()}",
    )

    private fun walletBoundaryFiles(): List<File> {
        val legacy = File(filesDir, legacyDatabaseFilename)
        return listOf(walletDirectoryFile, legacy) + sidecars.map { File(legacy.absolutePath + it) }
    }
}

data class WalletFileBackup(
    val original: File,
    val backup: File,
)
