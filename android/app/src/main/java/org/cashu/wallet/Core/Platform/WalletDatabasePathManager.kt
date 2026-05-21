package org.cashu.wallet.Core.Platform

import android.content.Context
import java.io.File
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
        return walletBoundaryFiles()
            .filter { it.exists() }
            .map { original ->
                val backup = File(
                    original.parentFile,
                    "${original.name}.replacing.$timestamp.${UUID.randomUUID()}",
                )
                if (backup.exists()) backup.deleteRecursively()
                original.renameTo(backup)
                WalletFileBackup(original, backup)
            }
    }

    fun restoreWalletFileBackups(backups: List<WalletFileBackup>) {
        backups.asReversed().forEach { backup ->
            if (backup.original.exists()) backup.original.deleteRecursively()
            if (backup.backup.exists()) backup.backup.renameTo(backup.original)
        }
    }

    fun removeWalletFileBackups(backups: List<WalletFileBackup>) {
        backups.forEach { if (it.backup.exists()) it.backup.deleteRecursively() }
    }

    fun removeWalletDatabaseFiles() {
        walletBoundaryFiles().forEach { if (it.exists()) it.deleteRecursively() }
    }

    fun backupCorruptedDatabase(): File? {
        val database = databaseFile
        if (!database.exists()) return null
        val backup = File(walletDirectory, "$walletDatabaseFilename.corrupt.${System.currentTimeMillis() / 1000}")
        if (backup.exists()) backup.delete()
        database.renameTo(backup)
        sidecars.forEach { suffix ->
            val sidecar = File(database.absolutePath + suffix)
            if (sidecar.exists()) sidecar.renameTo(File(backup.absolutePath + suffix))
        }
        return backup
    }

    private fun migrateLegacyDatabaseIfNeeded() {
        val legacy = File(filesDir, legacyDatabaseFilename)
        val current = databaseFile
        if (!legacy.exists() || current.exists()) return
        legacy.renameTo(current)
        sidecars.forEach { suffix ->
            val legacySidecar = File(legacy.absolutePath + suffix)
            if (legacySidecar.exists()) {
                val currentSidecar = File(current.absolutePath + suffix)
                if (currentSidecar.exists()) currentSidecar.delete()
                legacySidecar.renameTo(currentSidecar)
            }
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
