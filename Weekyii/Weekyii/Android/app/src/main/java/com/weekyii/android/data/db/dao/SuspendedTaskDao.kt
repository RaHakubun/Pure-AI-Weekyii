package com.weekyii.android.data.db.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStatus
import com.weekyii.android.data.db.entities.SuspendedTaskStepEntity
import com.weekyii.android.data.db.entities.SuspendedTaskWithDetails
import kotlinx.coroutines.flow.Flow
import java.util.Date
import java.util.UUID

@Dao
interface SuspendedTaskDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(task: SuspendedTaskEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSteps(steps: List<SuspendedTaskStepEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAttachments(attachments: List<SuspendedTaskAttachmentEntity>)

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
}
