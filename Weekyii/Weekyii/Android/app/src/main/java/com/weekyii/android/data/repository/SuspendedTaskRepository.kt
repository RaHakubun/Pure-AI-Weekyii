package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.SuspendedTaskDao
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStatus
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.ui.model.SuspendedTaskUi
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
    private val zoneId: ZoneId = ZoneId.systemDefault()
) : SuspendedTaskSweeper {
    fun observeActive(): Flow<List<SuspendedTaskUi>> = dao.observeByStatus(SuspendedTaskStatus.ACTIVE)
        .map { tasks -> tasks.map { it.task.toUi(zoneId) }.sortedBy { it.decisionDeadline } }

    suspend fun create(
        title: String,
        description: String,
        taskType: TaskType,
        countdownDays: Int,
        now: Date
    ): UUID {
        require(title.isNotBlank()) { "Task title cannot be empty" }
        require(countdownDays > 0) { "Countdown must be positive" }
        val task = SuspendedTaskEntity(
            title = title.trim(),
            description = description.trim(),
            taskType = taskType,
            taskTypeIdRaw = taskType.name.lowercase(),
            createdAt = now,
            decisionDeadline = deadlineFrom(now, countdownDays),
            preferredCountdownDays = countdownDays
        )
        dao.upsert(task)
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
        dao.upsert(
            task.copy(
                decisionDeadline = deadline,
                preferredCountdownDays = additionalDays,
                snoozeCount = task.snoozeCount + 1
            )
        )
    }

    suspend fun delete(id: UUID) {
        val task = dao.findWithDetails(id)?.task ?: return
        dao.delete(task)
    }

    override suspend fun sweep(now: Date): Int {
        val due = dao.listDue(SuspendedTaskStatus.ACTIVE, now)
        due.forEach { dao.delete(it) }
        return due.size
    }

    private fun deadlineFrom(now: Date, countdownDays: Int): Date {
        val start = now.toInstant().atZone(zoneId).toLocalDate()
        return Date.from(
            LocalDateTime.of(start.plusDays(countdownDays.toLong()), LocalTime.of(23, 59, 59))
                .atZone(zoneId).toInstant()
        )
    }
}

private fun SuspendedTaskEntity.toUi(zoneId: ZoneId) = SuspendedTaskUi(
    id = id,
    title = title,
    description = description,
    taskType = taskType,
    decisionDeadline = decisionDeadline.toInstant().atZone(zoneId).toLocalDateTime(),
    preferredCountdownDays = preferredCountdownDays,
    snoozeCount = snoozeCount
)
