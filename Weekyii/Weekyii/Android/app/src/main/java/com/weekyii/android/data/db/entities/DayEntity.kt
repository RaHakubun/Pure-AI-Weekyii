package com.weekyii.android.data.db.entities

import androidx.room.ColumnInfo
import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.Relation
import java.util.Date

@Entity(
    tableName = "days",
    foreignKeys = [
        ForeignKey(
            entity = WeekEntity::class,
            parentColumns = ["week_id"],
            childColumns = ["week_owner_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index(value = ["day_id"], unique = true), Index(value = ["week_owner_id"])]
)
data class DayEntity(
    @PrimaryKey @ColumnInfo(name = "day_id") val dayId: String,
    @ColumnInfo(name = "date") val date: Date,
    @ColumnInfo(name = "day_of_week") val dayOfWeek: String,
    @ColumnInfo(name = "status") val status: DayStatus,
    @ColumnInfo(name = "kill_hour") val killHour: Int = 20,
    @ColumnInfo(name = "kill_minute") val killMinute: Int = 0,
    @ColumnInfo(name = "initiated_at") val initiatedAt: Date? = null,
    @ColumnInfo(name = "closed_at") val closedAt: Date? = null,
    @ColumnInfo(name = "week_owner_id") val weekOwnerId: String,
    @ColumnInfo(name = "expired_count") val expiredCount: Int = 0
)

data class DayWithTasks(
    @Embedded
    val day: DayEntity,
    @Relation(parentColumn = "day_id", entityColumn = "day_owner_id")
    val tasks: List<TaskEntity>
)
