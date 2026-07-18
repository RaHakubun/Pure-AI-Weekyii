package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.SuspendedTaskDao
import com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStatus
import com.weekyii.android.data.db.entities.SuspendedTaskStepEntity
import com.weekyii.android.data.db.entities.SuspendedTaskWithDetails
import com.weekyii.android.data.db.entities.TaskType
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Date
import java.util.UUID

class SuspendedTaskRepositoryTest {
    private val now = Date.from(Instant.parse("2026-07-20T02:00:00Z"))

    @Test
    fun createRequiresTitleAndPositiveCountdown() = runBlocking {
        val repository = SuspendedTaskRepository(RecordingSuspendedTaskDao())

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.create(" ", "", TaskType.REGULAR, 3, now) }
        }
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.create("Task", "", TaskType.REGULAR, 0, now) }
        }
        Unit
    }

    @Test
    fun extendingTaskMovesDeadlineAndIncrementsSnoozeCount() = runBlocking {
        val dao = RecordingSuspendedTaskDao()
        val repository = SuspendedTaskRepository(dao)
        val id = repository.create("Task", "", TaskType.REGULAR, 3, now)

        repository.extend(id, 10, now)

        assertEquals(1, dao.values.getValue(id).snoozeCount)
        assertTrue(dao.values.getValue(id).decisionDeadline.after(now))
        assertEquals(10, dao.values.getValue(id).preferredCountdownDays)
    }

    @Test
    fun sweepingDueActiveTasksDeletesOnlyDueRecords() = runBlocking {
        val dao = RecordingSuspendedTaskDao()
        val repository = SuspendedTaskRepository(dao)
        val due = repository.create("Due", "", TaskType.REGULAR, 1, now)
        val active = repository.create("Active", "", TaskType.REGULAR, 10, now)
        val deadline = dao.values.getValue(due).decisionDeadline

        val deleted = repository.sweep(deadline)

        assertEquals(1, deleted)
        assertTrue(!dao.values.containsKey(due))
        assertTrue(dao.values.containsKey(active))
    }
}

private class RecordingSuspendedTaskDao : SuspendedTaskDao {
    val values = linkedMapOf<UUID, SuspendedTaskEntity>()
    override suspend fun upsert(task: SuspendedTaskEntity) { values[task.id] = task }
    override suspend fun upsertSteps(steps: List<SuspendedTaskStepEntity>) = Unit
    override suspend fun upsertAttachments(attachments: List<SuspendedTaskAttachmentEntity>) = Unit
    override suspend fun delete(task: SuspendedTaskEntity) { values.remove(task.id) }
    override suspend fun findWithDetails(id: UUID): SuspendedTaskWithDetails? = values[id]?.let { SuspendedTaskWithDetails(it, emptyList(), emptyList()) }
    override fun observeByStatus(status: SuspendedTaskStatus): Flow<List<SuspendedTaskWithDetails>> =
        MutableStateFlow(values.values.filter { it.status == status }.map { SuspendedTaskWithDetails(it, emptyList(), emptyList()) })
    override suspend fun listDue(status: SuspendedTaskStatus, deadline: Date): List<SuspendedTaskEntity> =
        values.values.filter { it.status == status && !it.decisionDeadline.after(deadline) }
    override suspend fun updateTaskTypeBaseKind(typeIdRaw: String, baseKind: TaskType) {
        values.replaceAll { _, task -> if (task.taskTypeIdRaw == typeIdRaw) task.copy(taskType = baseKind) else task }
    }
}
