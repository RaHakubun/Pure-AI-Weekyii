package com.weekyii.android.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.DayWithTasks
import kotlinx.coroutines.flow.Flow

@Dao
interface DayDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(day: DayEntity)

    @Update
    suspend fun update(day: DayEntity)

    @Transaction
    @Query("SELECT * FROM days WHERE day_id = :dayId LIMIT 1")
    suspend fun findById(dayId: String): DayEntity?

    @Transaction
    @Query("SELECT * FROM days WHERE day_id = :dayId LIMIT 1")
    suspend fun findWithTasks(dayId: String): DayWithTasks?

    @Query("SELECT * FROM days WHERE status = :status")
    fun observeByStatus(status: DayStatus): Flow<List<DayEntity>>

    @Query("SELECT * FROM days ORDER BY date")
    fun observeAll(): Flow<List<DayEntity>>

    @Query("SELECT * FROM days WHERE week_owner_id = :weekId")
    suspend fun listByWeek(weekId: String): List<DayEntity>

    @Query("SELECT * FROM days")
    suspend fun allDays(): List<DayEntity>

    @Query("DELETE FROM days")
    suspend fun deleteAll()
}
