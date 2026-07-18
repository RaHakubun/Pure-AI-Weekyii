package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.SuspendedTaskDao
import com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStatus
import com.weekyii.android.data.db.entities.SuspendedTaskStepEntity
import com.weekyii.android.data.db.entities.SuspendedTaskWithDetails
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.platform.SuspendedNotificationScheduler
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

    @Test
    fun createAndUpdateReplaceStepsAndAttachments() = runBlocking {
        val dao = RecordingSuspendedTaskDao()
        val repository = SuspendedTaskRepository(dao)
        val id = repository.create(
            title = "Task",
            description = "initial",
            taskType = TaskType.REGULAR,
            countdownDays = 3,
            now = now,
            stepTitles = listOf("Step one", "Step two"),
            attachments = listOf(TaskAttachmentDraft("brief.txt", "text/plain", "hello".toByteArray()))
        )

        assertEquals(listOf("Step one", "Step two"), dao.details.getValue(id).steps.map { it.title })
        assertEquals("brief.txt", dao.details.getValue(id).attachments.single().fileName)

        repository.update(
            id = id,
            title = "Renamed",
            description = "updated",
            taskType = TaskType.REGULAR,
            countdownDays = 5,
            now = now,
            stepTitles = listOf("Only step"),
            attachments = listOf(TaskAttachmentDraft("updated.pdf", "application/pdf", byteArrayOf(1, 2)))
        )

        assertEquals("Renamed", dao.values.getValue(id).title)
        assertEquals(listOf("Only step"), dao.details.getValue(id).steps.map { it.title })
        assertEquals("updated.pdf", dao.details.getValue(id).attachments.single().fileName)
    }

    @Test
    fun lifecycleReschedulesAndCancelsSuspendedReminders() = runBlocking {
        val dao = RecordingSuspendedTaskDao()
        val notifications = RecordingSuspendedNotifications()
        val repository = SuspendedTaskRepository(dao, notificationService = notifications)
        val id = repository.create("Task", "", TaskType.REGULAR, 3, now)

        repository.extend(id, 2, now)
        repository.delete(id)

        assertEquals(listOf(id, id), notifications.scheduled)
        assertEquals(listOf(id), notifications.cancelled)
    }
}

private class RecordingSuspendedNotifications : SuspendedNotificationScheduler {
    val scheduled = mutableListOf<UUID>()
    val cancelled = mutableListOf<UUID>()
    override fun scheduleSuspendedTask(taskId: UUID, decisionDeadline: LocalDateTime) { scheduled += taskId }
    override fun cancelSuspendedTask(taskId: UUID) { cancelled += taskId }
}

private class RecordingSuspendedTaskDao : SuspendedTaskDao {
    val values = linkedMapOf<UUID, SuspendedTaskEntity>()
    val details = linkedMapOf<UUID, SuspendedTaskWithDetails>()
    override suspend fun insert(task: SuspendedTaskEntity): Long { values[task.id] = task; details[task.id] = SuspendedTaskWithDetails(task, emptyList(), emptyList()); return 1L }
    override suspend fun update(task: SuspendedTaskEntity) { values[task.id] = task; details[task.id] = details.getValue(task.id).copy(task = task) }
    override suspend fun upsert(task: SuspendedTaskEntity) { values[task.id] = task; details[task.id] = details[task.id]?.copy(task = task) ?: SuspendedTaskWithDetails(task, emptyList(), emptyList()) }
    override suspend fun upsertSteps(steps: List<SuspendedTaskStepEntity>) {
        steps.groupBy { it.suspendedTaskOwnerId }.forEach { (id, valuesForTask) ->
            val current = details.getValue(id)
            details[id] = current.copy(steps = valuesForTask)
        }
    }
    override suspend fun upsertAttachments(attachments: List<SuspendedTaskAttachmentEntity>) {
        attachments.groupBy { it.suspendedTaskOwnerId }.forEach { (id, valuesForTask) ->
            val current = details.getValue(id)
            details[id] = current.copy(attachments = valuesForTask)
        }
    }
    override suspend fun deleteSteps(taskId: UUID) { details[taskId] = details.getValue(taskId).copy(steps = emptyList()) }
    override suspend fun deleteAttachments(taskId: UUID) { details[taskId] = details.getValue(taskId).copy(attachments = emptyList()) }
    override suspend fun delete(task: SuspendedTaskEntity) { values.remove(task.id); details.remove(task.id) }
    override suspend fun findWithDetails(id: UUID): SuspendedTaskWithDetails? = details[id]
    override fun observeByStatus(status: SuspendedTaskStatus): Flow<List<SuspendedTaskWithDetails>> =
        MutableStateFlow(values.values.filter { it.status == status }.map { details[it.id] ?: SuspendedTaskWithDetails(it, emptyList(), emptyList()) })
    override suspend fun listDue(status: SuspendedTaskStatus, deadline: Date): List<SuspendedTaskEntity> =
        values.values.filter { it.status == status && !it.decisionDeadline.after(deadline) }
    override suspend fun updateTaskTypeBaseKind(typeIdRaw: String, baseKind: TaskType) {
        values.replaceAll { _, task -> if (task.taskTypeIdRaw == typeIdRaw) task.copy(taskType = baseKind) else task }
    }
    override suspend fun allTasks(): List<SuspendedTaskEntity> = values.values.toList()
    override suspend fun deleteAll() { values.clear(); details.clear() }
}
