package com.weekyii.android.data.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Relation
import java.util.Date

@Entity(tableName = "weeks")
data class WeekEntity(
    @PrimaryKey @ColumnInfo(name = "week_id") val weekId: String,
    @ColumnInfo(name = "start_date") val startDate: Date,
    @ColumnInfo(name = "end_date") val endDate: Date,
    @ColumnInfo(name = "status") val status: WeekStatus,
    @ColumnInfo(name = "completed_tasks_count") val completedTasksCount: Int = 0,
    @ColumnInfo(name = "expired_tasks_count") val expiredTasksCount: Int = 0,
    @ColumnInfo(name = "total_started_days") val totalStartedDays: Int = 0
)

// Aggregated view for convenience
data class WeekWithDays(
    val week: WeekEntity,
    @Relation(parentColumn = "week_id", entityColumn = "week_owner_id")
    val days: List<DayEntity>
)
