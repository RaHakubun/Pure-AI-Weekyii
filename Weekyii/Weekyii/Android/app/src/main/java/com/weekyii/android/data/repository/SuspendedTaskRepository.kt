package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.SuspendedTaskDao
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStepEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStatus
import com.weekyii.android.data.db.entities.SuspendedTaskWithDetails
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.ui.model.TaskAttachmentUi
import com.weekyii.android.ui.model.TaskStepUi
import com.weekyii.android.ui.model.SuspendedTaskUi
import com.weekyii.android.platform.SuspendedNotificationScheduler
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.util.Date
import java.util.UUID

interface SuspendedTaskSweeper {
    suspend fun sweep(now: Date): Int
}

class SuspendedTaskRepository(
    private val dao: SuspendedTaskDao,
    private val zoneId: ZoneId = ZoneId.systemDefault(),
    private val weekyiiRepository: WeekyiiRepository? = null,
    private val notificationService: SuspendedNotificationScheduler? = null
) : SuspendedTaskSweeper {
    fun observeActive(): Flow<List<SuspendedTaskUi>> = dao.observeByStatus(SuspendedTaskStatus.ACTIVE)
        .map { tasks -> tasks.map { it.toUi(zoneId) }.sortedBy { it.decisionDeadline } }

    suspend fun create(
        title: String,
        description: String,
        taskType: TaskType,
        countdownDays: Int,
        now: Date,
        taskTypeIdRaw: String = taskType.name.lowercase(),
        stepTitles: List<String> = emptyList(),
        attachments: List<TaskAttachmentDraft> = emptyList()
    ): UUID {
        require(title.isNotBlank()) { "Task title cannot be empty" }
        require(countdownDays > 0) { "Countdown must be positive" }
        val task = SuspendedTaskEntity(
            title = title.trim(),
            description = description.trim(),
            taskType = taskType,
            taskTypeIdRaw = taskTypeIdRaw,
            createdAt = now,
            decisionDeadline = deadlineFrom(now, countdownDays),
            preferredCountdownDays = countdownDays
        )
        dao.upsert(task)
        replaceResources(task.id, stepTitles, attachments, now)
        scheduleReminder(task)
        return task.id
    }

    suspend fun extend(id: UUID, additionalDays: Int, now: Date) {
        require(additionalDays > 0) { "Extension must be positive" }
        val task = dao.findWithDetails(id)?.task ?: return
        val currentDay = task.decisionDeadline.toInstant().atZone(zoneId).toLocalDate()
        val today = now.toInstant().atZone(zoneId).toLocalDate()
        val baseline = if (currentDay.isAfter(today)) currentDay else today
        val deadline = Date.from(
            LocalDateTime.of(baseline.plusDays(additionalDays.toLong()), LocalTime.of(23, 59, 59))
                .atZone(zoneId).toInstant()
        )
        val updated = task.copy(
            decisionDeadline = deadline,
            preferredCountdownDays = additionalDays,
            snoozeCount = task.snoozeCount + 1
        )
        dao.upsert(updated)
        scheduleReminder(updated)
    }

    suspend fun update(
        id: UUID,
        title: String,
        description: String,
        taskType: TaskType,
        countdownDays: Int,
        now: Date,
        taskTypeIdRaw: String = taskType.name.lowercase(),
        stepTitles: List<String> = emptyList(),
        attachments: List<TaskAttachmentDraft> = emptyList()
    ) {
        require(title.isNotBlank()) { "Task title cannot be empty" }
        require(countdownDays > 0) { "Countdown must be positive" }
        val task = dao.findWithDetails(id)?.task ?: return
        require(task.status == SuspendedTaskStatus.ACTIVE) { "Suspended task is no longer active" }
        val updated = task.copy(
            title = title.trim(),
            description = description.trim(),
            taskType = taskType,
            taskTypeIdRaw = taskTypeIdRaw,
            decisionDeadline = deadlineFrom(now, countdownDays),
            preferredCountdownDays = countdownDays
        )
        dao.upsert(updated)
        replaceResources(id, stepTitles, attachments, now)
        scheduleReminder(updated)
    }

    suspend fun delete(id: UUID) {
        val task = dao.findWithDetails(id)?.task ?: return
        notificationService?.cancelSuspendedTask(id)
        dao.delete(task)
    }

    suspend fun assign(id: UUID, targetDate: LocalDate, today: LocalDate): UUID {
        require(!targetDate.isBefore(today)) { "Assignment target must not be in the past" }
        val task = dao.findWithDetails(id) ?: error("Suspended task not found")
        require(task.task.status == SuspendedTaskStatus.ACTIVE) { "Suspended task is no longer active" }
        val repository = weekyiiRepository ?: error("Task assignment is not configured")
        val weekStatus = if (repositoryWeekId(targetDate) == repositoryWeekId(today)) {
            com.weekyii.android.data.db.entities.WeekStatus.PRESENT
        } else {
            com.weekyii.android.data.db.entities.WeekStatus.PENDING
        }
        repository.ensureWeek(targetDate, weekStatus)
        val newTaskId = repository.appendDraftTask(
            dayId = targetDate.toString(),
            title = task.task.title,
            description = task.task.description,
            taskType = task.task.taskType,
            taskTypeIdRaw = task.task.taskTypeIdRaw,
            stepTitles = task.steps.sortedBy { it.sortOrder }.map { it.title },
            attachments = task.attachments.map { TaskAttachmentDraft(it.fileName, it.fileType, it.data) }
        )
        notificationService?.cancelSuspendedTask(task.task.id)
        dao.delete(task.task)
        return newTaskId
    }

    private fun repositoryWeekId(date: LocalDate): String = WeekCalculator().weekId(date)

    private suspend fun replaceResources(
        taskId: UUID,
        stepTitles: List<String>,
        attachments: List<TaskAttachmentDraft>,
        now: Date
    ) {
        dao.deleteSteps(taskId)
        dao.deleteAttachments(taskId)
        dao.upsertSteps(
            stepTitles.mapIndexedNotNull { index, title ->
                title.trim().takeIf { it.isNotEmpty() }?.let {
                    SuspendedTaskStepEntity(title = it, sortOrder = index, createdAt = now, suspendedTaskOwnerId = taskId)
                }
            }
        )
        dao.upsertAttachments(
            attachments.map {
                SuspendedTaskAttachmentEntity(
                    data = it.data,
                    fileName = it.fileName,
                    fileType = it.fileType,
                    createdAt = now,
                    suspendedTaskOwnerId = taskId
                )
            }
        )
    }

    override suspend fun sweep(now: Date): Int {
        val due = dao.listDue(SuspendedTaskStatus.ACTIVE, now)
        due.forEach {
            notificationService?.cancelSuspendedTask(it.id)
            dao.delete(it)
        }
        return due.size
    }

    private fun scheduleReminder(task: SuspendedTaskEntity) {
        notificationService?.scheduleSuspendedTask(
            task.id,
            task.decisionDeadline.toInstant().atZone(zoneId).toLocalDateTime()
        )
    }

    private fun deadlineFrom(now: Date, countdownDays: Int): Date {
        val start = now.toInstant().atZone(zoneId).toLocalDate()
        return Date.from(
            LocalDateTime.of(start.plusDays(countdownDays.toLong()), LocalTime.of(23, 59, 59))
                .atZone(zoneId).toInstant()
        )
    }
}

private fun SuspendedTaskWithDetails.toUi(zoneId: ZoneId) = SuspendedTaskUi(
    id = task.id,
    title = task.title,
    description = task.description,
    taskType = task.taskType,
    taskTypeIdRaw = task.taskTypeIdRaw,
    decisionDeadline = task.decisionDeadline.toInstant().atZone(zoneId).toLocalDateTime(),
    preferredCountdownDays = task.preferredCountdownDays,
    snoozeCount = task.snoozeCount,
    steps = steps.sortedBy { it.sortOrder }.map { TaskStepUi(it.title, it.isCompleted, it.sortOrder) },
    attachments = attachments.map { TaskAttachmentUi(it.fileName, it.fileType, it.data) }
)
