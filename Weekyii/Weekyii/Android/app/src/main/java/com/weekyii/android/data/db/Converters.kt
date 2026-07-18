package com.weekyii.android.data.db

import androidx.room.TypeConverter
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekStatus
import java.util.Date
import java.util.UUID

class Converters {
    @TypeConverter
    fun fromTimestamp(value: Long?): Date? = value?.let { Date(it) }

    @TypeConverter
    fun dateToTimestamp(date: Date?): Long? = date?.time

    @TypeConverter
    fun fromUuid(value: String?): UUID? = value?.let { UUID.fromString(it) }

    @TypeConverter
    fun uuidToString(uuid: UUID?): String? = uuid?.toString()

    @TypeConverter
    fun weekStatusFromString(value: String?): WeekStatus? = value?.let { WeekStatus.valueOf(it) }

    @TypeConverter
    fun weekStatusToString(status: WeekStatus?): String? = status?.name

    @TypeConverter
    fun dayStatusFromString(value: String?): DayStatus? = value?.let { DayStatus.valueOf(it) }

    @TypeConverter
    fun dayStatusToString(status: DayStatus?): String? = status?.name

    @TypeConverter
    fun taskZoneFromString(value: String?): TaskZone? = value?.let { TaskZone.valueOf(it) }

    @TypeConverter
    fun taskZoneToString(zone: TaskZone?): String? = zone?.name

    @TypeConverter
    fun taskTypeFromString(value: String?): TaskType? = value?.let { TaskType.valueOf(it) }

    @TypeConverter
    fun taskTypeToString(type: TaskType?): String? = type?.name

    @TypeConverter
    fun projectStatusFromString(value: String?): ProjectStatus? = value?.let { ProjectStatus.valueOf(it) }

    @TypeConverter
    fun projectStatusToString(status: ProjectStatus?): String? = status?.name
}
