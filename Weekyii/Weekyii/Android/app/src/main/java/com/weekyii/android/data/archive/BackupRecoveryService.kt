package com.weekyii.android.data.archive

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.security.MessageDigest
import java.time.Instant

class BackupRecoveryService(
    private val context: Context,
    private val databaseName: String = "weekyii.db"
) {
    data class SnapshotSummary(
        val folderName: String,
        val createdAt: Long,
        val fileCount: Int,
        val isValid: Boolean
    )

    @Serializable
    private data class Manifest(val createdAt: Long, val files: List<FileEntry>)

    @Serializable
    private data class FileEntry(val fileName: String, val fileSize: Long, val sha256: String)

    private val json = Json { encodeDefaults = true }

    suspend fun createSnapshot(reason: String? = null): SnapshotSummary? = withContext(Dispatchers.IO) {
        val databaseFile = context.getDatabasePath(databaseName)
        if (!databaseFile.exists()) return@withContext null
        val backupRoot = File(context.filesDir, "backups").apply { mkdirs() }
        val suffix = reason?.takeIf { it.isNotBlank() }?.let { "-${sanitize(it)}" }.orEmpty()
        val createdAt = System.currentTimeMillis()
        val snapshot = File(backupRoot, "snapshot-${Instant.ofEpochMilli(createdAt).toString().replace(':', '-')}$suffix")
        check(snapshot.mkdirs()) { "Unable to create backup directory" }

        runCatching {
            val candidates = listOf(databaseFile, File(databaseFile.path + "-wal"), File(databaseFile.path + "-shm"))
                .filter { it.exists() }
            val entries = candidates.map { source ->
                val destination = File(snapshot, source.name)
                source.copyTo(destination, overwrite = false)
                FileEntry(destination.name, destination.length(), sha256(destination.readBytes()))
            }
            require(entries.isNotEmpty()) { "No database files were available for backup" }
            File(snapshot, "manifest.json").writeText(json.encodeToString(Manifest(createdAt, entries)))
            check(verifySnapshot(snapshot)) { "Backup verification failed" }
            prune(backupRoot)
            SnapshotSummary(snapshot.name, createdAt, entries.size, true)
        }.getOrElse { error ->
            snapshot.deleteRecursively()
            throw error
        }
    }

    suspend fun listSnapshots(): List<SnapshotSummary> = withContext(Dispatchers.IO) {
        val root = File(context.filesDir, "backups")
        root.listFiles().orEmpty().filter { it.isDirectory && it.name.startsWith("snapshot-") }.map { folder ->
            val manifest = readManifest(folder)
            SnapshotSummary(
                folderName = folder.name,
                createdAt = manifest?.createdAt ?: 0,
                fileCount = manifest?.files?.size ?: 0,
                isValid = verifySnapshot(folder)
            )
        }.sortedByDescending { it.createdAt }
    }

    private fun verifySnapshot(folder: File): Boolean {
        val manifest = readManifest(folder) ?: return false
        return manifest.files.isNotEmpty() && manifest.files.all { entry ->
            val file = File(folder, entry.fileName)
            file.exists() && file.length() == entry.fileSize && sha256(file.readBytes()) == entry.sha256
        }
    }

    private fun readManifest(folder: File): Manifest? = runCatching {
        json.decodeFromString(Manifest.serializer(), File(folder, "manifest.json").readText())
    }.getOrNull()

    private fun prune(root: File) {
        root.listFiles().orEmpty().filter { it.isDirectory && it.name.startsWith("snapshot-") }
            .sortedByDescending { it.lastModified() }
            .drop(40)
            .forEach { it.deleteRecursively() }
    }

    private fun sanitize(value: String): String = value.lowercase().replace(Regex("[^a-z0-9_-]+"), "-").trim('-')

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }
}
