package com.weekyii.android.data.db.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStatus
import com.weekyii.android.data.db.entities.SuspendedTaskStepEntity
import com.weekyii.android.data.db.entities.SuspendedTaskWithDetails
import com.weekyii.android.data.db.entities.TaskType
import kotlinx.coroutines.flow.Flow
import java.util.Date
import java.util.UUID

@Dao
interface SuspendedTaskDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(task: SuspendedTaskEntity): Long

    @Update
    suspend fun update(task: SuspendedTaskEntity)

    @Transaction
    suspend fun upsert(task: SuspendedTaskEntity) {
        if (insert(task) == -1L) update(task)
    }

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSteps(steps: List<SuspendedTaskStepEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAttachments(attachments: List<SuspendedTaskAttachmentEntity>)

    @Query("DELETE FROM suspended_task_steps WHERE suspended_task_owner_id = :taskId")
    suspend fun deleteSteps(taskId: UUID)

    @Query("DELETE FROM suspended_task_attachments WHERE suspended_task_owner_id = :taskId")
    suspend fun deleteAttachments(taskId: UUID)

    @Delete
    suspend fun delete(task: SuspendedTaskEntity)

    @Transaction
    @Query("SELECT * FROM suspended_tasks WHERE id = :id LIMIT 1")
    suspend fun findWithDetails(id: UUID): SuspendedTaskWithDetails?

    @Transaction
    @Query("SELECT * FROM suspended_tasks WHERE status = :status ORDER BY decision_deadline")
    fun observeByStatus(status: SuspendedTaskStatus): Flow<List<SuspendedTaskWithDetails>>

    @Query("SELECT * FROM suspended_tasks WHERE status = :status AND decision_deadline <= :deadline")
    suspend fun listDue(status: SuspendedTaskStatus, deadline: Date): List<SuspendedTaskEntity>

    @Query("UPDATE suspended_tasks SET task_type = :baseKind WHERE task_type_id_raw = :typeIdRaw")
    suspend fun updateTaskTypeBaseKind(typeIdRaw: String, baseKind: TaskType)

    @Query("SELECT * FROM suspended_tasks")
    suspend fun allTasks(): List<SuspendedTaskEntity>

    @Query("DELETE FROM suspended_tasks")
    suspend fun deleteAll()
}
