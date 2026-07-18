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

@Entity(tableName = "suspended_tasks")
data class SuspendedTaskEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    @ColumnInfo(name = "title") val title: String,
    @ColumnInfo(name = "description") val description: String = "",
    @ColumnInfo(name = "task_type") val taskType: TaskType = TaskType.REGULAR,
    @ColumnInfo(name = "task_type_id_raw") val taskTypeIdRaw: String = "regular",
    @ColumnInfo(name = "created_at") val createdAt: Date = Date(),
    @ColumnInfo(name = "decision_deadline") val decisionDeadline: Date,
    @ColumnInfo(name = "preferred_countdown_days") val preferredCountdownDays: Int,
    @ColumnInfo(name = "snooze_count") val snoozeCount: Int = 0,
    @ColumnInfo(name = "status") val status: SuspendedTaskStatus = SuspendedTaskStatus.ACTIVE
)

@Entity(
    tableName = "suspended_task_steps",
    foreignKeys = [
        ForeignKey(
            entity = SuspendedTaskEntity::class,
            parentColumns = ["id"],
            childColumns = ["suspended_task_owner_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("suspended_task_owner_id")]
)
data class SuspendedTaskStepEntity(
    @PrimaryKey(autoGenerate = true) val stepId: Long = 0,
    @ColumnInfo(name = "title") val title: String,
    @ColumnInfo(name = "is_completed") val isCompleted: Boolean = false,
    @ColumnInfo(name = "sort_order") val sortOrder: Int = 0,
    @ColumnInfo(name = "created_at") val createdAt: Date = Date(),
    @ColumnInfo(name = "suspended_task_owner_id") val suspendedTaskOwnerId: UUID
)

@Entity(
    tableName = "suspended_task_attachments",
    foreignKeys = [
        ForeignKey(
            entity = SuspendedTaskEntity::class,
            parentColumns = ["id"],
            childColumns = ["suspended_task_owner_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("suspended_task_owner_id")]
)
data class SuspendedTaskAttachmentEntity(
    @PrimaryKey(autoGenerate = true) val attachmentId: Long = 0,
    @ColumnInfo(name = "data") val data: ByteArray? = null,
    @ColumnInfo(name = "file_name") val fileName: String,
    @ColumnInfo(name = "file_type") val fileType: String,
    @ColumnInfo(name = "created_at") val createdAt: Date = Date(),
    @ColumnInfo(name = "suspended_task_owner_id") val suspendedTaskOwnerId: UUID
)

data class SuspendedTaskWithDetails(
    @Embedded val task: SuspendedTaskEntity,
    @Relation(parentColumn = "id", entityColumn = "suspended_task_owner_id")
    val steps: List<SuspendedTaskStepEntity>,
    @Relation(parentColumn = "id", entityColumn = "suspended_task_owner_id")
    val attachments: List<SuspendedTaskAttachmentEntity>
)
