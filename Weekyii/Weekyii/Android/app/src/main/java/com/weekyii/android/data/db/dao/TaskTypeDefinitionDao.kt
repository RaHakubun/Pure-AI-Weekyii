package com.weekyii.android.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TaskTypeDefinitionDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(definition: TaskTypeDefinitionEntity)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfMissing(definitions: List<TaskTypeDefinitionEntity>)

    @Query("SELECT * FROM task_type_definitions ORDER BY sort_order, name")
    fun observeAll(): Flow<List<TaskTypeDefinitionEntity>>

    @Query("SELECT * FROM task_type_definitions ORDER BY sort_order, name")
    suspend fun listAll(): List<TaskTypeDefinitionEntity>
}
