package com.weekyii.android.data.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.Date
import java.util.UUID

@Entity(tableName = "mindstamps")
data class MindStampEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    @ColumnInfo(name = "text") val text: String,
    @ColumnInfo(name = "image_blob") val imageBlob: ByteArray? = null,
    @ColumnInfo(name = "created_at") val createdAt: Date = Date()
) {
    val hasContent: Boolean
        get() = text.isNotBlank() || imageBlob != null
}
