package com.weekyii.android.data.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

@Entity(
    tableName = "task_attachments",
    foreignKeys = [
        ForeignKey(
            entity = TaskEntity::class,
            parentColumns = ["id"],
            childColumns = ["attachment_owner_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index(value = ["attachment_owner_id"])]
)
data class TaskAttachmentEntity(
    @PrimaryKey(autoGenerate = true) val attachmentId: Long = 0,
    @ColumnInfo(name = "data") val data: ByteArray? = null,
    @ColumnInfo(name = "file_name") val fileName: String,
    @ColumnInfo(name = "file_type") val fileType: String,
    @ColumnInfo(name = "created_at") val createdAt: java.util.Date = java.util.Date(),
    @ColumnInfo(name = "attachment_owner_id") val attachmentOwnerId: UUID
)
