package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.DayDao
import com.weekyii.android.data.db.dao.ProjectDao
import com.weekyii.android.data.db.dao.TaskDao
import com.weekyii.android.data.db.dao.WeekDao
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.ExecutionMode
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskAttachmentEntity
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.model.WeekUi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

data class TaskAttachmentDraft(val fileName: String, val fileType: String, val data: ByteArray?)

class WeekyiiRepository(
    val weekDao: WeekDao,
    val dayDao: DayDao,
    val taskDao: TaskDao,
    val projectDao: ProjectDao,
    private val weekCalculator: WeekCalculator,
    private val zoneId: ZoneId = ZoneId.systemDefault()
) {
    // region Queries
    fun observePresentWeek(): Flow<List<WeekUi>> {
        return weekDao.observeWeeksByStatus(WeekStatus.PRESENT).combineObserveDays()
    }

    fun observePendingWeeks(): Flow<List<WeekUi>> {
        return weekDao.observeWeeksByStatus(WeekStatus.PENDING).combineObserveDays()
    }

    fun observePastWeeks(): Flow<List<WeekUi>> {
        return weekDao.observeWeeksByStatus(WeekStatus.PAST).combineObserveDays()
    }

    private fun Flow<List<WeekEntity>>.combineObserveDays(): Flow<List<WeekUi>> =
        this.combine(dayDao.observeAll()) { weeks, days -> weeks to days }
            .map { weeks ->
                weeks.first.map { week ->
                    val weekDays = weeks.second.filter { it.weekOwnerId == week.weekId }.map { day -> day.toUi() }
                    week.toUi(weekDays)
                }
            }
    // endregion

    // region Mutations aligned to Today flow
    suspend fun ensureWeek(date: LocalDate, status: WeekStatus): WeekEntity {
        val weekId = weekCalculator.weekId(date)
        val existing = weekDao.findById(weekId)
        if (existing != null) {
            val resolved = if (status == WeekStatus.PRESENT && existing.status != WeekStatus.PRESENT) {
                val promoted = existing.copy(status = WeekStatus.PRESENT)
                weekDao.upsert(promoted)
                promoted
            } else {
                existing
            }
            ensureWeekDays(resolved, date)
            return resolved
        }
        val (start, end) = weekCalculator.weekRange(date)
        val week = WeekEntity(
            weekId = weekId,
            startDate = java.util.Date.from(start.atStartOfDay(zoneId).toInstant()),
            endDate = java.util.Date.from(end.atStartOfDay(zoneId).toInstant()),
            status = status
        )
        weekDao.upsert(week)
        ensureWeekDays(week, date)
        return week
    }

    private suspend fun ensureWeekDays(week: WeekEntity, date: LocalDate) {
        val start = weekCalculator.weekRange(date).first
        val existingDayIds = dayDao.listByWeek(week.weekId).mapTo(mutableSetOf()) { it.dayId }
        repeat(7) { offset ->
            val dayDate = start.plusDays(offset.toLong())
            if (dayDate.toString() in existingDayIds) return@repeat
            val day = DayEntity(
                dayId = dayDate.toString(),
                date = java.util.Date.from(dayDate.atStartOfDay(zoneId).toInstant()),
                dayOfWeek = dayDate.dayOfWeek.name.take(3),
                status = DayStatus.EMPTY,
                weekOwnerId = week.weekId
            )
            dayDao.upsert(day)
        }
    }

    // Simple fetch helpers used by StateMachine
    suspend fun getDay(dayId: String) = dayDao.findById(dayId)
    suspend fun getDayWithTasks(dayId: String) = dayDao.findWithTasks(dayId)
    suspend fun listDaysByWeek(weekId: String) = dayDao.listByWeek(weekId)
    suspend fun allDays() = dayDao.allDays()

    suspend fun moveWeekToPast(weekId: String) {
        val week = weekDao.findById(weekId) ?: return
        if (week.status != WeekStatus.PAST) {
            weekDao.upsert(week.copy(status = WeekStatus.PAST))
            updateWeekSummary(weekId)
        }
    }
    suspend fun allWeeks() = weekDao.allWeeks()

    suspend fun createDraftDayIfNeeded(date: LocalDate) {
        val dayId = date.toString()
        val existing = dayDao.findById(dayId)
        if (existing != null) return
        val week = ensureWeek(date, WeekStatus.PRESENT)
        val day = DayEntity(
            dayId = dayId,
            date = java.util.Date.from(date.atStartOfDay(zoneId).toInstant()),
            dayOfWeek = date.dayOfWeek.name.take(3),
            status = DayStatus.DRAFT,
            weekOwnerId = week.weekId
        )
        dayDao.upsert(day)
    }

    suspend fun addDraftTasks(dayId: String, titles: List<String>) {
        val day = dayDao.findById(dayId) ?: return
        require(day.status == DayStatus.DRAFT || day.status == DayStatus.EMPTY)
        require(titles.isNotEmpty() && titles.all { it.isNotBlank() }) { "Task title cannot be empty" }
        val currentMax = dayDao.findWithTasks(dayId)?.tasks?.maxOfOrNull { it.order } ?: 0
        titles.forEachIndexed { idx, title ->
            val task = TaskEntity(
                title = title.trim(),
                order = currentMax + idx + 1,
                dayOwnerId = dayId,
                zone = TaskZone.DRAFT
            )
            taskDao.upsert(task)
        }
        val newStatus = DayStatus.DRAFT
        dayDao.upsert(day.copy(status = newStatus))
    }

    suspend fun updateDraftTask(
        dayId: String,
        taskId: UUID,
        title: String,
        description: String = "",
        taskType: TaskType = TaskType.REGULAR,
        taskTypeIdRaw: String = taskType.name.lowercase()
    ) {
        require(title.isNotBlank()) { "Task title cannot be empty" }
        val day = dayDao.findById(dayId) ?: return
        require(day.status == DayStatus.DRAFT || day.status == DayStatus.EMPTY)
        val task = taskDao.findById(taskId) ?: return
        require(task.dayOwnerId == dayId && task.zone == TaskZone.DRAFT)
        taskDao.upsert(task.copy(title = title.trim(), description = description.trim(), taskType = taskType, taskTypeIdRaw = taskTypeIdRaw))
    }

    suspend fun replaceDraftTaskResources(
        dayId: String,
        taskId: UUID,
        stepTitles: List<String>,
        attachments: List<TaskAttachmentDraft>
    ) {
        val day = dayDao.findById(dayId) ?: return
        require(day.status == DayStatus.DRAFT || day.status == DayStatus.EMPTY)
        val task = taskDao.findById(taskId) ?: return
        require(task.dayOwnerId == dayId && task.zone == TaskZone.DRAFT)
        taskDao.deleteSteps(taskId)
        taskDao.deleteAttachments(taskId)
        taskDao.upsertSteps(
            stepTitles.mapIndexedNotNull { index, title ->
                title.trim().takeIf { it.isNotEmpty() }?.let {
                    TaskStepEntity(title = it, sortOrder = index, taskOwnerId = taskId)
                }
            }
        )
        taskDao.upsertAttachments(
            attachments.map { attachment ->
                TaskAttachmentEntity(
                    data = attachment.data,
                    fileName = attachment.fileName,
                    fileType = attachment.fileType,
                    attachmentOwnerId = taskId
                )
            }
        )
    }

    suspend fun getTaskUi(taskId: UUID): TaskUi? {
        val details = taskDao.findWithSteps(taskId) ?: return null
        return details.task.toUi(
            steps = details.steps.sortedBy { it.sortOrder }.map { it.toUi() },
            attachments = details.attachments.map { it.toUi() }
        )
    }

    suspend fun deleteDraftTasks(dayId: String, taskIds: List<UUID>) {
        val day = dayDao.findById(dayId) ?: return
        require(day.status == DayStatus.DRAFT || day.status == DayStatus.EMPTY)
        taskIds.mapNotNull { taskDao.findById(it) }
            .filter { it.dayOwnerId == dayId && it.zone == TaskZone.DRAFT }
            .forEach { taskDao.delete(it) }
        renumberDraftTasks(dayId)
    }

    suspend fun moveDraftTask(dayId: String, fromIndex: Int, toIndex: Int) {
        val day = dayDao.findById(dayId) ?: return
        require(day.status == DayStatus.DRAFT || day.status == DayStatus.EMPTY)
        val drafts = dayDao.findWithTasks(dayId)?.tasks
            ?.filter { it.zone == TaskZone.DRAFT }
            ?.sortedBy { it.order }
            ?.toMutableList()
            ?: return
        if (fromIndex !in drafts.indices || toIndex !in 0..drafts.size) return
        val item = drafts.removeAt(fromIndex)
        drafts.add(toIndex.coerceAtMost(drafts.size), item)
        drafts.forEachIndexed { index, task -> taskDao.upsert(task.copy(order = index + 1)) }
    }

    private suspend fun renumberDraftTasks(dayId: String) {
        dayDao.findWithTasks(dayId)?.tasks
            ?.filter { it.zone == TaskZone.DRAFT }
            ?.sortedBy { it.order }
            ?.forEachIndexed { index, task -> taskDao.upsert(task.copy(order = index + 1)) }
    }

    suspend fun startDay(
        dayId: String,
        now: java.util.Date,
        executionMode: ExecutionMode = ExecutionMode.STRICT
    ) {
        val day = dayDao.findWithTasks(dayId) ?: return
        require(day.day.status == DayStatus.DRAFT)
        val tasks = day.tasks.sortedBy { it.order }
        if (tasks.isEmpty()) throw IllegalStateException("Cannot start empty day")
        tasks.first().copy(zone = TaskZone.FOCUS, startedAt = now).also { taskDao.upsert(it) }
        tasks.drop(1).forEach { task -> taskDao.upsert(task.copy(zone = TaskZone.FROZEN)) }
        dayDao.upsert(
            day.day.copy(
                status = DayStatus.EXECUTE,
                initiatedAt = now,
                executionModeRaw = executionMode.name.lowercase(),
                isDraftZoneUnlocked = false
            )
        )
    }

    suspend fun setDraftZoneUnlocked(dayId: String, isUnlocked: Boolean) {
        val day = dayDao.findById(dayId) ?: return
        require(day.status == DayStatus.EXECUTE) { "Day is not executing" }
        require(day.executionModeRaw == ExecutionMode.FLEXIBLE.name.lowercase()) {
            "Strict execution cannot unlock the task queue"
        }
        dayDao.upsert(day.copy(isDraftZoneUnlocked = isUnlocked))
    }

    suspend fun addExecutionTask(
        dayId: String,
        title: String,
        description: String = "",
        taskType: TaskType = TaskType.REGULAR,
        taskTypeIdRaw: String = taskType.name.lowercase()
    ) {
        require(title.isNotBlank()) { "Task title cannot be empty" }
        val day = dayDao.findWithTasks(dayId) ?: return
        require(day.day.status == DayStatus.EXECUTE) { "Day is not executing" }
        require(day.day.executionModeRaw == ExecutionMode.FLEXIBLE.name.lowercase()) {
            "Strict execution cannot edit the task queue"
        }
        require(day.day.isDraftZoneUnlocked) { "Task queue is locked" }
        val nextOrder = (day.tasks.maxOfOrNull { it.order } ?: 0) + 1
        taskDao.upsert(
            TaskEntity(
                title = title.trim(),
                description = description.trim(),
                taskType = taskType,
                taskTypeIdRaw = taskTypeIdRaw,
                order = nextOrder,
                zone = TaskZone.FROZEN,
                dayOwnerId = dayId
            )
        )
    }

    suspend fun appendDraftTask(
        dayId: String,
        title: String,
        description: String,
        taskType: TaskType,
        taskTypeIdRaw: String,
        stepTitles: List<String> = emptyList(),
        attachments: List<TaskAttachmentDraft> = emptyList()
    ): UUID {
        require(title.isNotBlank()) { "Task title cannot be empty" }
        val day = dayDao.findWithTasks(dayId) ?: error("Target day not found")
        require(day.day.status == DayStatus.EMPTY || day.day.status == DayStatus.DRAFT) {
            "Target day is unavailable"
        }
        val task = TaskEntity(
            title = title.trim(),
            description = description.trim(),
            taskType = taskType,
            taskTypeIdRaw = taskTypeIdRaw,
            order = (day.tasks.filter { it.zone == TaskZone.DRAFT }.maxOfOrNull { it.order } ?: 0) + 1,
            zone = TaskZone.DRAFT,
            dayOwnerId = dayId
        )
        taskDao.upsert(task)
        if (stepTitles.isNotEmpty() || attachments.isNotEmpty()) {
            replaceDraftTaskResources(dayId, task.id, stepTitles, attachments)
        }
        dayDao.upsert(day.day.copy(status = DayStatus.DRAFT))
        return task.id
    }

    suspend fun exchangeFocusWithFirstFrozen(dayId: String, now: java.util.Date) {
        val day = dayDao.findWithTasks(dayId) ?: return
        require(day.day.status == DayStatus.EXECUTE) { "Day is not executing" }
        require(day.day.executionModeRaw == ExecutionMode.FLEXIBLE.name.lowercase()) {
            "Strict execution cannot exchange focus"
        }
        require(day.day.isDraftZoneUnlocked) { "Task queue is locked" }
        val focus = day.tasks.firstOrNull { it.zone == TaskZone.FOCUS }
            ?: throw IllegalStateException("Focus task not found")
        val frozen = day.tasks.filter { it.zone == TaskZone.FROZEN }.sortedBy { it.order }
        val next = frozen.firstOrNull() ?: throw IllegalStateException("Execution queue is empty")

        taskDao.upsert(
            focus.copy(
                zone = TaskZone.FROZEN,
                order = 2,
                startedAt = null,
                endedAt = null,
                completedOrder = 0
            )
        )
        taskDao.upsert(
            next.copy(
                zone = TaskZone.FOCUS,
                order = 1,
                startedAt = now,
                endedAt = null,
                completedOrder = 0
            )
        )
        frozen.drop(1).forEachIndexed { index, task ->
            taskDao.upsert(task.copy(order = index + 3))
        }
    }

    suspend fun normalizeExecutionState(dayId: String, now: java.util.Date) {
        val dayWithTasks = dayDao.findWithTasks(dayId) ?: return
        if (dayWithTasks.day.status != DayStatus.EXECUTE) return

        val activeTasks = dayWithTasks.tasks
            .filter { it.zone == TaskZone.FOCUS || it.zone == TaskZone.FROZEN }
            .sortedWith(compareBy<TaskEntity> { it.order }.thenBy { it.id.toString() })
        if (activeTasks.isEmpty()) {
            dayDao.upsert(
                dayWithTasks.day.copy(
                    status = DayStatus.COMPLETED,
                    closedAt = dayWithTasks.day.closedAt ?: now,
                    isDraftZoneUnlocked = false
                )
            )
            return
        }

        val focus = activeTasks.firstOrNull { it.zone == TaskZone.FOCUS } ?: activeTasks.first()
        taskDao.upsert(
            focus.copy(
                zone = TaskZone.FOCUS,
                order = 1,
                startedAt = focus.startedAt ?: now,
                endedAt = null,
                completedOrder = 0
            )
        )
        activeTasks.filter { it.id != focus.id }.forEachIndexed { index, task ->
            taskDao.upsert(
                task.copy(
                    zone = TaskZone.FROZEN,
                    order = index + 2,
                    startedAt = null,
                    endedAt = null,
                    completedOrder = 0
                )
            )
        }
    }

    suspend fun postponeTask(
        taskId: UUID,
        targetDate: LocalDate,
        today: LocalDate,
        now: java.util.Date
    ) {
        require(targetDate.isAfter(today)) { "Postpone target must be in the future" }
        val task = taskDao.findById(taskId) ?: return
        require(task.dayOwnerId == today.toString()) { "Only today's task can be postponed" }
        require(task.zone != TaskZone.COMPLETE) { "Completed task cannot be postponed" }
        val source = dayDao.findWithTasks(today.toString()) ?: return
        val targetWeekStatus = if (weekCalculator.weekId(targetDate) == weekCalculator.weekId(today)) {
            WeekStatus.PRESENT
        } else {
            WeekStatus.PENDING
        }
        ensureWeek(targetDate, targetWeekStatus)
        val targetDay = dayDao.findWithTasks(targetDate.toString()) ?: return
        require(targetDay.day.status == DayStatus.EMPTY || targetDay.day.status == DayStatus.DRAFT) {
            "Postpone target day is unavailable"
        }

        val targetOrder = (targetDay.tasks.filter { it.zone == TaskZone.DRAFT }.maxOfOrNull { it.order } ?: 0) + 1
        taskDao.upsert(
            task.copy(
                dayOwnerId = targetDate.toString(),
                zone = TaskZone.DRAFT,
                order = targetOrder,
                startedAt = null,
                endedAt = null,
                completedOrder = 0
            )
        )
        dayDao.upsert(targetDay.day.copy(status = DayStatus.DRAFT))

        val remaining = source.tasks.filter { it.id != taskId }
        when (task.zone) {
            TaskZone.DRAFT -> {
                remaining.filter { it.zone == TaskZone.DRAFT }.sortedBy { it.order }
                    .forEachIndexed { index, item -> taskDao.upsert(item.copy(order = index + 1)) }
                if (remaining.none { it.zone == TaskZone.DRAFT }) dayDao.upsert(source.day.copy(status = DayStatus.EMPTY))
            }
            TaskZone.FOCUS -> {
                val next = remaining.filter { it.zone == TaskZone.FROZEN }.minByOrNull { it.order }
                if (next != null) {
                    taskDao.upsert(next.copy(zone = TaskZone.FOCUS, order = 1, startedAt = now))
                    remaining.filter { it.zone == TaskZone.FROZEN && it.id != next.id }
                        .sortedBy { it.order }
                        .forEachIndexed { index, item -> taskDao.upsert(item.copy(order = index + 2)) }
                } else {
                    dayDao.upsert(source.day.copy(status = DayStatus.COMPLETED, closedAt = now))
                }
            }
            TaskZone.FROZEN -> {
                remaining.filter { it.zone == TaskZone.FROZEN }.sortedBy { it.order }
                    .forEachIndexed { index, item -> taskDao.upsert(item.copy(order = index + 2)) }
                if (remaining.none { it.zone == TaskZone.FOCUS || it.zone == TaskZone.FROZEN }) {
                    dayDao.upsert(source.day.copy(status = DayStatus.COMPLETED, closedAt = now))
                }
            }
            TaskZone.COMPLETE -> error("Completed task cannot be postponed")
        }
    }

    suspend fun doneFocus(dayId: String, now: java.util.Date) {
        val day = dayDao.findWithTasks(dayId) ?: return
        val focus = day.tasks.firstOrNull { it.zone == TaskZone.FOCUS } ?: return
        val frozen = day.tasks.filter { it.zone == TaskZone.FROZEN }.sortedBy { it.order }
        val completedOrder = day.tasks.count { it.zone == TaskZone.COMPLETE } + 1
        taskDao.upsert(focus.copy(zone = TaskZone.COMPLETE, endedAt = now, completedOrder = completedOrder))
        if (frozen.isNotEmpty()) {
            val next = frozen.first()
            taskDao.upsert(next.copy(zone = TaskZone.FOCUS, startedAt = now))
            frozen.drop(1).forEach { rest -> taskDao.upsert(rest) }
        } else {
            dayDao.upsert(day.day.copy(status = DayStatus.COMPLETED, closedAt = now))
        }
    }

    suspend fun changeKillTime(
        dayId: String,
        hour: Int,
        minute: Int,
        now: java.util.Date = java.util.Date()
    ) {
        require(hour in 0..23) { "Kill Time hour must be between 0 and 23" }
        require(minute in 0..59) { "Kill Time minute must be between 0 and 59" }
        val day = dayDao.findById(dayId) ?: return
        if (day.status == DayStatus.EXPIRED || day.status == DayStatus.COMPLETED) return
        val dayDate = day.date.toInstant().atZone(zoneId).toLocalDate()
        val proposedKillTime = java.util.Date.from(dayDate.atTime(hour, minute).atZone(zoneId).toInstant())
        if (!proposedKillTime.after(now)) {
            throw IllegalStateException("Kill time has passed")
        }
        dayDao.upsert(
            day.copy(
                killHour = hour,
                killMinute = minute,
                followsDefaultKillTime = false
            )
        )
    }

    suspend fun syncDefaultKillTime(dayId: String, hour: Int, minute: Int) {
        val day = dayDao.findById(dayId) ?: return
        if (day.status == DayStatus.EXPIRED || day.status == DayStatus.COMPLETED) return
        dayDao.upsert(
            day.copy(
                killHour = hour,
                killMinute = minute,
                followsDefaultKillTime = true
            )
        )
    }

    suspend fun expire(dayId: String, expiredCount: Int) {
        val day = dayDao.findById(dayId) ?: return
        if (day.status == DayStatus.EXPIRED) return
        dayDao.upsert(day.copy(status = DayStatus.EXPIRED, expiredCount = expiredCount, isDraftZoneUnlocked = false))
        taskDao.deleteByZones(dayId, listOf(TaskZone.DRAFT.name, TaskZone.FOCUS.name, TaskZone.FROZEN.name))
    }

    suspend fun updateWeekSummary(weekId: String) {
        val week = weekDao.findWithDays(weekId) ?: return
        val completed = week.days.sumOf { day -> dayDao.findWithTasks(day.dayId)?.tasks?.count { it.zone == TaskZone.COMPLETE } ?: 0 }
        val expired = week.days.sumOf { it.expiredCount }
        val started = week.days.count { it.initiatedAt != null }
        val updated = week.week.copy(
            completedTasksCount = completed,
            expiredTasksCount = expired,
            totalStartedDays = started
        )
        weekDao.upsert(updated)
    }
    // endregion
}
