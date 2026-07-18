package com.weekyii.android.ui.model

import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekStatus
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.UUID

data class WeekUi(
    val weekId: String,
    val startDate: LocalDate,
    val endDate: LocalDate,
    val status: WeekStatus,
    val completedTasksCount: Int,
    val expiredTasksCount: Int,
    val totalStartedDays: Int,
    val days: List<DayUi> = emptyList()
)

data class DayUi(
    val dayId: String,
    val date: LocalDate,
    val dayOfWeek: String,
    val status: DayStatus,
    val killHour: Int,
    val killMinute: Int,
    val initiatedAt: LocalDateTime?,
    val closedAt: LocalDateTime?,
    val expiredCount: Int,
    val tasks: List<TaskUi> = emptyList()
)

data class TaskUi(
    val id: UUID,
    val title: String,
    val description: String,
    val taskType: TaskType,
    val order: Int,
    val zone: TaskZone,
    val startedAt: LocalDateTime?,
    val endedAt: LocalDateTime?,
    val completedOrder: Int,
    val projectId: UUID?,
    val steps: List<TaskStepUi> = emptyList(),
    val attachments: List<TaskAttachmentUi> = emptyList()
)

data class TaskStepUi(
    val title: String,
    val isCompleted: Boolean,
    val sortOrder: Int
)

data class TaskAttachmentUi(
    val fileName: String,
    val fileType: String,
    val data: ByteArray?
)

data class ProjectUi(
    val id: UUID,
    val name: String,
    val description: String,
    val color: String,
    val icon: String,
    val status: ProjectStatus,
    val startDate: LocalDate,
    val endDate: LocalDate,
    val createdAt: LocalDateTime
)

data class MindStampUi(
    val id: UUID,
    val text: String,
    val imageBlob: ByteArray?,
    val createdAt: LocalDateTime
) {
    val hasContent: Boolean get() = text.isNotBlank() || imageBlob != null
}
