package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.SuspendedTaskDao
import com.weekyii.android.data.db.dao.TaskDao
import com.weekyii.android.data.db.dao.TaskTypeDefinitionDao
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.util.Locale
import java.util.UUID

class TaskTypeDefinitionRepository(
    private val dao: TaskTypeDefinitionDao,
    private val taskDao: TaskDao,
    private val suspendedTaskDao: SuspendedTaskDao
) {
    fun observeAll(): Flow<List<TaskTypeDefinitionEntity>> = dao.observeAll()

    fun observeActive(): Flow<List<TaskTypeDefinitionEntity>> = dao.observeAll().map(::activeSorted)

    suspend fun seedBuiltIns() {
        dao.insertIfMissing(TaskTypeDefinitionEntity.builtIns())
    }

    suspend fun listActive(): List<TaskTypeDefinitionEntity> {
        seedBuiltIns()
        return activeSorted(dao.listAll())
    }

    suspend fun resolve(idRaw: String): TaskTypeDefinitionEntity {
        seedBuiltIns()
        return dao.findById(idRaw)
            ?: dao.findById(TaskType.REGULAR.name.lowercase())
            ?: TaskTypeDefinitionEntity.builtIns().first()
    }

    suspend fun create(
        name: String,
        iconName: String,
        colorHex: String,
        baseKind: TaskType
    ): TaskTypeDefinitionEntity {
        seedBuiltIns()
        val normalizedName = validateDefinitionFields(name, iconName, colorHex)
        ensureUniqueName(normalizedName)
        val nextOrder = (dao.listAll().maxOfOrNull { it.sortOrder } ?: 2) + 1
        return TaskTypeDefinitionEntity(
            idRaw = UUID.randomUUID().toString(),
            name = normalizedName,
            iconName = iconName.trim(),
            colorHex = colorHex.uppercase(Locale.ROOT),
            baseKind = baseKind,
            sortOrder = nextOrder
        ).also { dao.upsert(it) }
    }

    suspend fun update(
        idRaw: String,
        name: String,
        iconName: String,
        colorHex: String,
        baseKind: TaskType
    ): TaskTypeDefinitionEntity {
        val existing = dao.findById(idRaw) ?: error("Task type not found")
        require(!existing.isBuiltIn) { "Built-in task types cannot be edited" }
        val normalizedName = validateDefinitionFields(name, iconName, colorHex)
        ensureUniqueName(normalizedName, excludingId = idRaw)
        val updated = existing.copy(
            name = normalizedName,
            iconName = iconName.trim(),
            colorHex = colorHex.uppercase(Locale.ROOT),
            baseKind = baseKind
        )
        dao.upsert(updated)
        taskDao.updateTaskTypeBaseKind(idRaw, baseKind)
        suspendedTaskDao.updateTaskTypeBaseKind(idRaw, baseKind)
        return updated
    }

    suspend fun archive(idRaw: String) {
        val existing = dao.findById(idRaw) ?: return
        require(!existing.isBuiltIn) { "Built-in task types cannot be archived" }
        dao.upsert(existing.copy(isArchived = true))
    }

    suspend fun restore(idRaw: String) {
        val existing = dao.findById(idRaw) ?: return
        require(!existing.isBuiltIn) { "Built-in task types do not need restoring" }
        dao.upsert(existing.copy(isArchived = false))
    }

    private suspend fun ensureUniqueName(name: String, excludingId: String? = null) {
        val duplicate = dao.listAll().any { definition ->
            definition.idRaw != excludingId && definition.name.trim().equals(name, ignoreCase = true)
        }
        require(!duplicate) { "A task type with this name already exists" }
    }

    private fun validateDefinitionFields(name: String, iconName: String, colorHex: String): String {
        val normalizedName = name.trim()
        require(normalizedName.isNotEmpty()) { "Task type name cannot be empty" }
        require(iconName.isNotBlank()) { "Task type icon cannot be empty" }
        require(Regex("^#[0-9A-Fa-f]{6}$").matches(colorHex)) { "Task type color must be #RRGGBB" }
        return normalizedName
    }

    private fun activeSorted(definitions: List<TaskTypeDefinitionEntity>): List<TaskTypeDefinitionEntity> =
        definitions.filterNot { it.isArchived }.sortedWith(
            compareBy<TaskTypeDefinitionEntity> { it.sortOrder }.thenBy { it.name.lowercase(Locale.getDefault()) }
        )
}
