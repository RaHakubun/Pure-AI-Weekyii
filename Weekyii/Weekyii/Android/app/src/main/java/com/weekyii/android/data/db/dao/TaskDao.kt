package com.weekyii.android.data.db.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.TaskAttachmentEntity
import com.weekyii.android.data.db.entities.TaskWithSteps
import kotlinx.coroutines.flow.Flow
import java.util.UUID

@Dao
interface TaskDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(task: TaskEntity)

    @Update
    suspend fun update(task: TaskEntity)

    @Delete
    suspend fun delete(task: TaskEntity)

    @Query("SELECT * FROM tasks WHERE id = :id LIMIT 1")
    suspend fun findById(id: UUID): TaskEntity?

    @Transaction
    @Query("SELECT * FROM tasks WHERE day_owner_id = :dayId ORDER BY `order`")
    fun observeTasksForDay(dayId: String): Flow<List<TaskEntity>>

    @Transaction
    @Query("SELECT * FROM tasks WHERE id = :id LIMIT 1")
    suspend fun findWithSteps(id: UUID): TaskWithSteps?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSteps(steps: List<TaskStepEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAttachments(attachments: List<TaskAttachmentEntity>)

    @Query("DELETE FROM task_steps WHERE task_owner_id = :taskId")
    suspend fun deleteSteps(taskId: UUID)

    @Query("DELETE FROM task_attachments WHERE attachment_owner_id = :taskId")
    suspend fun deleteAttachments(taskId: UUID)

    @Query("DELETE FROM tasks WHERE day_owner_id = :dayId AND zone IN (:zones)")
    suspend fun deleteByZones(dayId: String, zones: List<String>)
}
