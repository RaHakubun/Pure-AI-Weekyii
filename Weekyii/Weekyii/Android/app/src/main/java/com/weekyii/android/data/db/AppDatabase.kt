package com.weekyii.android.data.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.weekyii.android.data.db.dao.DayDao
import com.weekyii.android.data.db.dao.MindStampDao
import com.weekyii.android.data.db.dao.ProjectDao
import com.weekyii.android.data.db.dao.TaskDao
import com.weekyii.android.data.db.dao.TaskTypeDefinitionDao
import com.weekyii.android.data.db.dao.SuspendedTaskDao
import com.weekyii.android.data.db.dao.WeekDao
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.MindStampEntity
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.TaskAttachmentEntity
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStepEntity
import com.weekyii.android.data.db.entities.WeekEntity

@Database(
    entities = [
        WeekEntity::class,
        DayEntity::class,
        TaskEntity::class,
        TaskStepEntity::class,
        TaskAttachmentEntity::class,
        ProjectEntity::class,
        MindStampEntity::class,
        SuspendedTaskEntity::class,
        SuspendedTaskStepEntity::class,
        SuspendedTaskAttachmentEntity::class,
        TaskTypeDefinitionEntity::class
    ],
    version = 2,
    exportSchema = true
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun weekDao(): WeekDao
    abstract fun dayDao(): DayDao
    abstract fun taskDao(): TaskDao
    abstract fun projectDao(): ProjectDao
    abstract fun mindStampDao(): MindStampDao
    abstract fun suspendedTaskDao(): SuspendedTaskDao
    abstract fun taskTypeDefinitionDao(): TaskTypeDefinitionDao
}
