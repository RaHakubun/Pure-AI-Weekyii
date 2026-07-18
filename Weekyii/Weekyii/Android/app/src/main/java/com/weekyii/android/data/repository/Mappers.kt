package com.weekyii.android.data.repository

import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.TaskAttachmentEntity
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskAttachmentUi
import com.weekyii.android.ui.model.TaskStepUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.model.WeekUi
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Date
import java.util.Date

private val zone: ZoneId = ZoneId.systemDefault()

private fun Date.toLocalDate(): LocalDate = Instant.ofEpochMilli(this.time).atZone(zone).toLocalDate()
private fun Date.toLocalDateTime(): LocalDateTime = Instant.ofEpochMilli(this.time).atZone(zone).toLocalDateTime()

fun WeekEntity.toUi(days: List<DayUi> = emptyList()): WeekUi = WeekUi(
    weekId = weekId,
    startDate = startDate.toLocalDate(),
    endDate = endDate.toLocalDate(),
    status = status,
    completedTasksCount = completedTasksCount,
    expiredTasksCount = expiredTasksCount,
    totalStartedDays = totalStartedDays,
    days = days
)

fun DayEntity.toUi(tasks: List<TaskUi> = emptyList()): DayUi = DayUi(
    dayId = dayId,
    date = date.toLocalDate(),
    dayOfWeek = dayOfWeek,
    status = status,
    killHour = killHour,
    killMinute = killMinute,
    initiatedAt = initiatedAt?.toLocalDateTime(),
    closedAt = closedAt?.toLocalDateTime(),
    expiredCount = expiredCount,
    tasks = tasks
)

fun TaskEntity.toUi(steps: List<TaskStepUi> = emptyList(), attachments: List<TaskAttachmentUi> = emptyList()): TaskUi = TaskUi(
    id = id,
    title = title,
    description = description,
    taskType = taskType,
    order = order,
    zone = zone,
    startedAt = startedAt?.toLocalDateTime(),
    endedAt = endedAt?.toLocalDateTime(),
    completedOrder = completedOrder,
    projectId = projectOwnerId,
    steps = steps,
    attachments = attachments
)

fun TaskStepEntity.toUi(): TaskStepUi = TaskStepUi(
    title = title,
    isCompleted = isCompleted,
    sortOrder = sortOrder
)

fun TaskAttachmentEntity.toUi(): TaskAttachmentUi = TaskAttachmentUi(
    fileName = fileName,
    fileType = fileType,
    data = data
)
