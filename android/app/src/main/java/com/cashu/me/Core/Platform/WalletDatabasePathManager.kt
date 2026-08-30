package com.cashu.me.Core.Platform

import android.content.Context
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

    fun restoreWalletFileBackups(backups: List<WalletFileBackup>) = files.restoreWalletFileBackups(backups)

    fun removeWalletFileBackups(backups: List<WalletFileBackup>) = files.removeWalletFileBackups(backups)

    fun removeWalletDatabaseFiles() = files.removeWalletDatabaseFiles()

    fun backupCorruptedDatabase(): File? = files.backupCorruptedDatabase()
}

internal class WalletDatabaseFiles(
    private val filesDir: File,
    private val walletDirectoryName: String = "cashu-kotlin",
    private val walletDatabaseFilename: String = "wallet.db",
    private val legacyDatabaseFilename: String = "cashu_wallet.db",
    private val sidecars: List<String> = listOf("-wal", "-shm", "-journal"),
    private val moveFile: (File, File) -> Boolean = { source, destination -> source.renameTo(destination) },
    private val deleteFile: (File) -> Boolean = { file -> file.deleteRecursively() },
) {
    val walletDirectory: File
        get() = File(filesDir, walletDirectoryName).also { it.mkdirs() }

    val databaseFile: File
        get() = File(walletDirectory, walletDatabaseFilename)

    fun databasePathAfterLegacyMigration(): String {
        migrateLegacyDatabaseIfNeeded()
        return databaseFile.absolutePath
    }

    fun backupWalletDatabaseFiles(): List<WalletFileBackup> {
        val timestamp = System.currentTimeMillis() / 1000
        val completed = mutableListOf<WalletFileBackup>()
        try {
            walletBoundaryFiles()
                .filter { it.exists() }
                .forEach { original ->
                    val backup = File(
                        original.parentFile,
                        "${original.name}.replacing.$timestamp.${UUID.randomUUID()}",
                    )
                    deleteChecked(backup, "stale wallet replacement backup")
                    moveChecked(original, backup, "back up wallet database")
                    completed += WalletFileBackup(original, backup)
                }
            return completed
        } catch (error: Throwable) {
            runCatching { rollbackPartialBackups(completed) }
                .exceptionOrNull()
                ?.let(error::addSuppressed)
            throw error
        }
    }

    private fun rollbackPartialBackups(backups: List<WalletFileBackup>) {
        var failure: Throwable? = null
        backups.asReversed().forEach { backup ->
            runCatching {
                if (backup.original.exists()) {
                    throw IOException(
                        "Cannot roll back wallet database backup because ${backup.original.name} already exists.",
                    )
                }
                moveChecked(backup.backup, backup.original, "roll back wallet database backup")
            }.onFailure { error ->
                if (failure == null) failure = error else failure?.addSuppressed(error)
            }
        }
        failure?.let { throw it }
    }

    fun restoreWalletFileBackups(backups: List<WalletFileBackup>) {
        val missingBackup = backups.firstOrNull { !it.backup.exists() }
        if (missingBackup != null) {
            throw IOException(
                "Cannot restore missing wallet database backup ${missingBackup.backup.name}.",
            )
        }

        val staged = mutableListOf<StagedWalletFileBackup>()
        val restored = mutableListOf<StagedWalletFileBackup>()
        try {
            backups.forEach { backup ->
                val displacedOriginal = backup.original
                    .takeIf(File::exists)
                    ?.let { original ->
                        File(
                            original.parentFile,
                            "${original.name}.restore-displaced.${UUID.randomUUID()}",
                        ).also { displaced ->
                            moveChecked(original, displaced, "stage live wallet database for restore")
                        }
                    }
                staged += StagedWalletFileBackup(backup, displacedOriginal)
            }

            staged.asReversed().forEach { stagedBackup ->
                moveChecked(
                    stagedBackup.backup.backup,
                    stagedBackup.backup.original,
                    "restore wallet database backup",
                )
                restored += stagedBackup
            }
        } catch (error: Throwable) {
            rollbackRestoreTransaction(staged, restored, error)
            throw error
        }

        staged.forEach { stagedBackup ->
            stagedBackup.displacedOriginal?.let { deleteChecked(it, "displaced wallet database") }
        }
    }

    fun removeWalletFileBackups(backups: List<WalletFileBackup>) {
        backups.forEach { deleteChecked(it.backup, "wallet replacement backup") }
    }

    fun removeWalletDatabaseFiles() {
        walletBoundaryFiles().forEach { deleteChecked(it, "wallet database") }
    }

    private fun rollbackRestoreTransaction(
        staged: List<StagedWalletFileBackup>,
        restored: List<StagedWalletFileBackup>,
        failure: Throwable,
    ) {
        restored.asReversed().forEach { stagedBackup ->
            runCatching {
                moveChecked(
                    stagedBackup.backup.original,
                    stagedBackup.backup.backup,
                    "roll back restored wallet database backup",
                )
            }.exceptionOrNull()?.let(failure::addSuppressed)
        }

        staged.asReversed().forEach { stagedBackup ->
            val displacedOriginal = stagedBackup.displacedOriginal ?: return@forEach
            runCatching {
                if (stagedBackup.backup.original.exists()) {
                    throw IOException(
                        "Cannot restore staged live wallet database because " +
                            "${stagedBackup.backup.original.name} already exists.",
                    )
                }
                moveChecked(
                    displacedOriginal,
                    stagedBackup.backup.original,
                    "restore staged live wallet database",
                )
            }.exceptionOrNull()?.let(failure::addSuppressed)
        }
    }

    private fun moveChecked(source: File, destination: File, operation: String) {
        if (!source.exists()) throw IOException("Cannot $operation: ${source.name} does not exist.")
        if (destination.exists()) throw IOException("Cannot $operation: ${destination.name} already exists.")
        val moved = moveFile(source, destination)
        if (!moved || source.exists() || !destination.exists()) {
            throw IOException("Failed to $operation from ${source.name} to ${destination.name}.")
        }
    }

    private fun deleteChecked(file: File, description: String) {
        if (!file.exists()) return
        val deleted = deleteFile(file)
        if (!deleted || file.exists()) throw IOException("Failed to delete $description ${file.name}.")
    }

    fun backupCorruptedDatabase(): File? {
        val database = databaseFile
        if (!database.exists()) return null
        val backup = File(walletDirectory, "$walletDatabaseFilename.corrupt.${System.currentTimeMillis() / 1000}")
        val moves = buildList {
            add(database to backup)
            sidecars.forEach { suffix ->
                val sidecar = File(database.absolutePath + suffix)
                if (sidecar.exists()) add(sidecar to File(backup.absolutePath + suffix))
            }
        }
        moves.forEach { (_, destination) ->
            deleteChecked(destination, "stale corrupt database backup")
        }
        moveTransaction(moves, "back up corrupted wallet database")
        return backup
    }

    private fun migrateLegacyDatabaseIfNeeded() {
        val legacy = File(filesDir, legacyDatabaseFilename)
        val current = databaseFile
        if (!legacy.exists() || current.exists()) return
        val moves = buildList {
            add(legacy to current)
            sidecars.forEach { suffix ->
                val legacySidecar = File(legacy.absolutePath + suffix)
                if (legacySidecar.exists()) {
                    add(legacySidecar to File(current.absolutePath + suffix))
                }
            }
        }
        moves.forEach { (_, destination) ->
            deleteChecked(destination, "stale migrated database file")
        }
        moveTransaction(moves, "migrate legacy wallet database")
    }

    private fun moveTransaction(
        moves: List<Pair<File, File>>,
        operation: String,
    ) {
        val completed = mutableListOf<Pair<File, File>>()
        try {
            moves.forEach { (source, destination) ->
                moveChecked(source, destination, operation)
                completed += source to destination
            }
        } catch (error: Throwable) {
            completed.asReversed().forEach { (source, destination) ->
                runCatching {
                    moveChecked(destination, source, "roll back $operation")
                }.exceptionOrNull()?.let(error::addSuppressed)
            }
            throw error
        }
    }

    private fun walletBoundaryFiles(): List<File> {
        val legacy = File(filesDir, legacyDatabaseFilename)
        return listOf(walletDirectory, legacy) + sidecars.map { File(legacy.absolutePath + it) }
    }
}

data class WalletFileBackup(
    val original: File,
    val backup: File,
)

private data class StagedWalletFileBackup(
    val backup: WalletFileBackup,
    val displacedOriginal: File?,
)
