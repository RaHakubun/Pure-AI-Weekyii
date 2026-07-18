package com.weekyii.android.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.data.db.entities.WeekWithDays
import kotlinx.coroutines.flow.Flow

@Dao
interface WeekDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(week: WeekEntity)

    @Update
    suspend fun update(week: WeekEntity)

    @Query("SELECT * FROM weeks WHERE week_id = :weekId LIMIT 1")
    suspend fun findById(weekId: String): WeekEntity?

    @Transaction
    @Query("SELECT * FROM weeks WHERE week_id = :weekId LIMIT 1")
    suspend fun findWithDays(weekId: String): WeekWithDays?

    @Transaction
    @Query("SELECT * FROM weeks WHERE status = :status")
    fun observeWeeksByStatus(status: WeekStatus): Flow<List<WeekEntity>>

    @Transaction
    @Query("SELECT * FROM weeks")
    suspend fun allWeeks(): List<WeekEntity>

    @Query("DELETE FROM weeks")
    suspend fun deleteAll()
}
