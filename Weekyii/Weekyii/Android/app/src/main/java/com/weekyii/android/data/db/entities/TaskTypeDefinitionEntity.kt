package com.weekyii.android.data.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "task_type_definitions")
data class TaskTypeDefinitionEntity(
    @PrimaryKey @ColumnInfo(name = "id_raw") val idRaw: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "icon_name") val iconName: String,
    @ColumnInfo(name = "color_hex") val colorHex: String,
    @ColumnInfo(name = "base_kind") val baseKind: TaskType,
    @ColumnInfo(name = "sort_order") val sortOrder: Int,
    @ColumnInfo(name = "is_built_in") val isBuiltIn: Boolean = false,
    @ColumnInfo(name = "is_archived") val isArchived: Boolean = false
) {
    companion object {
        fun builtIns(): List<TaskTypeDefinitionEntity> = listOf(
            TaskTypeDefinitionEntity("regular", "常规", "check_circle", "#4A90A4", TaskType.REGULAR, 0, true),
            TaskTypeDefinitionEntity("ddl", "DDL", "schedule", "#C46A1A", TaskType.DDL, 1, true),
            TaskTypeDefinitionEntity("leisure", "空闲", "self_improvement", "#8B5A83", TaskType.LEISURE, 2, true)
        )
    }
}
