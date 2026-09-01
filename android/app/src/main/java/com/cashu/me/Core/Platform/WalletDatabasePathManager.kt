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
                    AppLogger.wallet.error("Failed to remove a displaced replacement database", error)
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
        if (operations.exists(backup)) operations.removeItem(backup)
        operations.moveItem(database, backup)
        sidecars.forEach { suffix ->
            val sidecar = File(database.absolutePath + suffix)
            if (operations.exists(sidecar)) {
                val backupSidecar = File(backup.absolutePath + suffix)
                if (operations.exists(backupSidecar)) operations.removeItem(backupSidecar)
                operations.moveItem(sidecar, backupSidecar)
            }
        }
        return backup
    }

    private fun migrateLegacyDatabaseIfNeeded() {
        val legacy = File(filesDir, legacyDatabaseFilename)
        val current = databaseFile
        if (!operations.exists(legacy) || operations.exists(current)) return
        operations.moveItem(legacy, current)
        sidecars.forEach { suffix ->
            val legacySidecar = File(legacy.absolutePath + suffix)
            if (operations.exists(legacySidecar)) {
                val currentSidecar = File(current.absolutePath + suffix)
                if (operations.exists(currentSidecar)) operations.removeItem(currentSidecar)
                operations.moveItem(legacySidecar, currentSidecar)
            }
        }
    }

    private fun walletBoundaryFiles(): List<File> {
        val legacy = File(filesDir, legacyDatabaseFilename)
        return listOf(walletDirectoryFile, legacy) + sidecars.map { File(legacy.absolutePath + it) }
    }
}

data class WalletFileBackup(
    val original: File,
    val backup: File,
)
