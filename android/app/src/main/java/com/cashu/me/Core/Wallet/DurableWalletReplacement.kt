package com.cashu.me.Core

import com.cashu.me.Core.Protocols.SecureStorage
import java.io.File
import java.io.IOException
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** The journal (including the previous seed) lives in encrypted, synchronously committed storage.
 * Backups are copies of a closed database and are never consumed by rollback, so recovery itself
 * can be killed and safely repeated. No seed or preferences are read by startup before recovery.
 */
internal class DurableWalletReplacement(
    private val storage: SecureStorage,
    private val files: List<File>,
) {
    @Serializable
    private data class Record(val phase: Phase, val existed: List<Boolean>, val state: String)
    @Serializable
    private enum class Phase { Preparing, Installing, Committed, Restored }

    private val backups get() = files.map { File(it.path + ".replacement-backup-v1") }
    private fun read(): Record? = storage.loadString(KEY)?.let {
        try { Json.decodeFromString<Record>(it) }
        catch (_: Exception) { throw IOException("Wallet recovery journal could not be decoded.") }
    }
    private fun write(record: Record) = storage.saveString(KEY, Json.encodeToString(record))

    fun begin(state: String) {
        check(read() == null) { "Wallet replacement recovery must finish first." }
        check(backups.none(File::exists)) { "An unclaimed wallet backup needs recovery." }
        val record = Record(Phase.Preparing, files.map(File::exists), state)
        write(record)
        files.forEachIndexed { i, file -> if (record.existed[i]) copy(file, backups[i]) }
        // Until this write, the original database and preferences are untouched.
        write(record.copy(phase = Phase.Installing))
        files.forEach(::remove)
    }

    fun commit() {
        val record = checkNotNull(read())
        check(record.phase == Phase.Installing)
        write(record.copy(phase = Phase.Committed))
    }

    suspend fun recover(
        restoreState: suspend (String) -> Unit,
        cleanupCommittedState: suspend (String) -> Unit,
    ) {
        var record = read() ?: return
        check(record.existed.size == files.size) { "Unknown wallet replacement journal format." }
        if (record.phase == Phase.Installing) {
            check(backups.indices.all { !record.existed[it] || backups[it].exists() }) {
                "A wallet recovery backup is missing."
            }
            files.forEachIndexed { i, file ->
                remove(file)
                if (record.existed[i]) copy(backups[i], file)
            }
            restoreState(record.state)
            record = record.copy(phase = Phase.Restored)
            write(record)
        }
        if (record.phase == Phase.Committed) cleanupCommittedState(record.state)
        backups.forEach(::remove)
        storage.delete(KEY)
    }

    private fun remove(file: File) {
        if (file.exists() && !file.deleteRecursively()) throw IOException("Wallet recovery cleanup failed.")
    }

    private fun copy(source: File, destination: File) {
        if (source.isDirectory) {
            check(destination.mkdirs() || destination.isDirectory)
            val children = source.listFiles() ?: throw IOException("Cannot read wallet recovery directory.")
            children.forEach { copy(it, File(destination, it.name)) }
        } else {
            source.inputStream().use { input ->
                destination.outputStream().use { output -> input.copyTo(output); output.fd.sync() }
            }
        }
    }

    companion object { const val KEY = "wallet_replacement_journal_v1" }
}
