package com.weekyii.android.data.db.entities

import androidx.room.ColumnInfo
import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.Relation
import java.util.Date
import java.util.UUID

@Entity(
    tableName = "tasks",
    foreignKeys = [
        ForeignKey(
            entity = DayEntity::class,
            parentColumns = ["day_id"],
            childColumns = ["day_owner_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = ProjectEntity::class,
            parentColumns = ["project_id"],
            childColumns = ["project_owner_id"],
            onDelete = ForeignKey.SET_NULL
        )
    ],
    indices = [Index(value = ["id"], unique = true), Index(value = ["day_owner_id"]), Index(value = ["project_owner_id"])]
)
data class TaskEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    @ColumnInfo(name = "title") val title: String,
    @ColumnInfo(name = "description") val description: String = "",
    @ColumnInfo(name = "task_type") val taskType: TaskType = TaskType.REGULAR,
    @ColumnInfo(name = "task_type_id_raw") val taskTypeIdRaw: String = "regular",
    @ColumnInfo(name = "order") val order: Int,
    @ColumnInfo(name = "zone") val zone: TaskZone = TaskZone.DRAFT,
    @ColumnInfo(name = "started_at") val startedAt: Date? = null,
    @ColumnInfo(name = "ended_at") val endedAt: Date? = null,
    @ColumnInfo(name = "completed_order") val completedOrder: Int = 0,
    @ColumnInfo(name = "day_owner_id") val dayOwnerId: String,
    @ColumnInfo(name = "project_owner_id") val projectOwnerId: UUID? = null
)

data class TaskWithSteps(
    @Embedded
    val task: TaskEntity,
    @Relation(parentColumn = "id", entityColumn = "task_owner_id")
    val steps: List<TaskStepEntity>,
    @Relation(parentColumn = "id", entityColumn = "attachment_owner_id")
    val attachments: List<TaskAttachmentEntity>
)
