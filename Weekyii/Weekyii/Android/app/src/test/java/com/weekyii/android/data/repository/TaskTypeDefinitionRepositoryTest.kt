package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.SuspendedTaskDao
import com.weekyii.android.data.db.dao.TaskDao
import com.weekyii.android.data.db.dao.TaskTypeDefinitionDao
import com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStatus
import com.weekyii.android.data.db.entities.SuspendedTaskStepEntity
import com.weekyii.android.data.db.entities.SuspendedTaskWithDetails
import com.weekyii.android.data.db.entities.TaskAttachmentEntity
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.data.db.entities.TaskWithSteps
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Date
import java.util.UUID

class TaskTypeDefinitionRepositoryTest {
    @Test
    fun seedBuiltInsIsIdempotentAndKeepsAllThreeSystemTypes() = runBlocking {
        val dao = RecordingTaskTypeDefinitionDao()
        val repository = TaskTypeDefinitionRepository(dao, TaskTypeRecordingTaskDao(), TaskTypeRecordingSuspendedDao())

        repository.seedBuiltIns()
        repository.seedBuiltIns()

        assertEquals(listOf("regular", "ddl", "leisure"), dao.values.values.sortedBy { it.sortOrder }.map { it.idRaw })
        assertTrue(dao.values.values.all { it.isBuiltIn })
    }

    @Test
    fun customTypeLifecycleRejectsDuplicateNamesAndExcludesArchivedTypes() = runBlocking {
        val dao = RecordingTaskTypeDefinitionDao()
        val repository = TaskTypeDefinitionRepository(dao, TaskTypeRecordingTaskDao(), TaskTypeRecordingSuspendedDao())
        repository.seedBuiltIns()

        val custom = repository.create("深度工作", "bolt", "#6C5CE7", TaskType.REGULAR)

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.create(" 深度工作 ", "star", "#000000", TaskType.LEISURE) }
        }
        repository.archive(custom.idRaw)
        assertFalse(repository.listActive().any { it.idRaw == custom.idRaw })
        repository.restore(custom.idRaw)
        assertTrue(repository.listActive().any { it.idRaw == custom.idRaw })
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.archive("regular") }
        }
        Unit
    }

    @Test
    fun updatingCustomBaseKindPropagatesToExistingTasksAndSuspendedTasks() = runBlocking {
        val dao = RecordingTaskTypeDefinitionDao()
        val tasks = TaskTypeRecordingTaskDao()
        val suspended = TaskTypeRecordingSuspendedDao()
        val repository = TaskTypeDefinitionRepository(dao, tasks, suspended)
        val custom = repository.create("冲刺", "flame", "#E15759", TaskType.REGULAR)

        repository.update(custom.idRaw, "冲刺任务", "schedule", "#C46A1A", TaskType.DDL)

        assertEquals(TaskType.DDL, dao.values.getValue(custom.idRaw).baseKind)
        assertEquals(custom.idRaw to TaskType.DDL, tasks.lastTypeUpdate)
        assertEquals(custom.idRaw to TaskType.DDL, suspended.lastTypeUpdate)
    }
}

private class RecordingTaskTypeDefinitionDao : TaskTypeDefinitionDao {
    val values = linkedMapOf<String, TaskTypeDefinitionEntity>()
    override suspend fun upsert(definition: TaskTypeDefinitionEntity) { values[definition.idRaw] = definition }
    override suspend fun insertIfMissing(definitions: List<TaskTypeDefinitionEntity>) {
        definitions.forEach { values.putIfAbsent(it.idRaw, it) }
    }
    override fun observeAll(): Flow<List<TaskTypeDefinitionEntity>> = MutableStateFlow(values.values.toList())
    override suspend fun listAll(): List<TaskTypeDefinitionEntity> = values.values.toList()
    override suspend fun findById(idRaw: String): TaskTypeDefinitionEntity? = values[idRaw]
    override suspend fun deleteAll() { values.clear() }
}

private class TaskTypeRecordingTaskDao : TaskDao {
    var lastTypeUpdate: Pair<String, TaskType>? = null
    override suspend fun insert(task: TaskEntity): Long = 1L
    override suspend fun upsert(task: TaskEntity) = Unit
    override suspend fun update(task: TaskEntity) = Unit
    override suspend fun delete(task: TaskEntity) = Unit
    override suspend fun findById(id: UUID): TaskEntity? = null
    override fun observeTasksForDay(dayId: String): Flow<List<TaskEntity>> = MutableStateFlow(emptyList())
    override fun observeAll(): Flow<List<TaskEntity>> = MutableStateFlow(emptyList())
    override suspend fun findWithSteps(id: UUID): TaskWithSteps? = null
    override suspend fun upsertSteps(steps: List<TaskStepEntity>) = Unit
    override suspend fun upsertAttachments(attachments: List<TaskAttachmentEntity>) = Unit
    override suspend fun deleteSteps(taskId: UUID) = Unit
    override suspend fun deleteAttachments(taskId: UUID) = Unit
    override suspend fun deleteByZones(dayId: String, zones: List<String>) = Unit
    override suspend fun updateTaskTypeBaseKind(typeIdRaw: String, baseKind: TaskType) {
        lastTypeUpdate = typeIdRaw to baseKind
    }
    override suspend fun allTasks(): List<TaskEntity> = emptyList()
    override suspend fun deleteAll() = Unit
}

private class TaskTypeRecordingSuspendedDao : SuspendedTaskDao {
    var lastTypeUpdate: Pair<String, TaskType>? = null
    override suspend fun insert(task: SuspendedTaskEntity): Long = 1L
    override suspend fun update(task: SuspendedTaskEntity) = Unit
    override suspend fun upsert(task: SuspendedTaskEntity) = Unit
    override suspend fun upsertSteps(steps: List<SuspendedTaskStepEntity>) = Unit
    override suspend fun upsertAttachments(attachments: List<SuspendedTaskAttachmentEntity>) = Unit
    override suspend fun deleteSteps(taskId: UUID) = Unit
    override suspend fun deleteAttachments(taskId: UUID) = Unit
    override suspend fun delete(task: SuspendedTaskEntity) = Unit
    override suspend fun findWithDetails(id: UUID): SuspendedTaskWithDetails? = null
    override fun observeByStatus(status: SuspendedTaskStatus): Flow<List<SuspendedTaskWithDetails>> = MutableStateFlow(emptyList())
    override suspend fun listDue(status: SuspendedTaskStatus, deadline: Date): List<SuspendedTaskEntity> = emptyList()
    override suspend fun updateTaskTypeBaseKind(typeIdRaw: String, baseKind: TaskType) {
        lastTypeUpdate = typeIdRaw to baseKind
    }
    override suspend fun allTasks(): List<SuspendedTaskEntity> = emptyList()
    override suspend fun deleteAll() = Unit
}
