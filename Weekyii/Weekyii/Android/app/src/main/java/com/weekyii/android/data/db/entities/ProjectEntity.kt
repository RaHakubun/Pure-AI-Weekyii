package com.weekyii.android.data.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.Date
import java.util.UUID

@Entity(tableName = "projects")
data class ProjectEntity(
    @PrimaryKey @ColumnInfo(name = "project_id") val projectId: UUID = UUID.randomUUID(),
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "description") val description: String = "",
    @ColumnInfo(name = "color") val color: String = "#C46A1A",
    @ColumnInfo(name = "icon") val icon: String = "folder.fill",
    @ColumnInfo(name = "status") val status: ProjectStatus = ProjectStatus.PLANNING,
    @ColumnInfo(name = "start_date") val startDate: Date,
    @ColumnInfo(name = "end_date") val endDate: Date,
    @ColumnInfo(name = "created_at") val createdAt: Date = Date(),
    @ColumnInfo(name = "tile_size_raw") val tileSizeRaw: String = "medium",
    @ColumnInfo(name = "tile_order") val tileOrder: Int = 0
)
