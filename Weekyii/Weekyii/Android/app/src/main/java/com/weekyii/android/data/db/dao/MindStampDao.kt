package com.weekyii.android.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Delete
import com.weekyii.android.data.db.entities.MindStampEntity
import kotlinx.coroutines.flow.Flow
import java.util.UUID

@Dao
interface MindStampDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(mindStamp: MindStampEntity)

    @Query("SELECT * FROM mindstamps ORDER BY created_at DESC")
    fun observeAll(): Flow<List<MindStampEntity>>

    @Query("SELECT * FROM mindstamps WHERE id = :id LIMIT 1")
    suspend fun findById(id: UUID): MindStampEntity?

    @Delete
    suspend fun delete(mindStamp: MindStampEntity)

    @Query("SELECT * FROM mindstamps")
    suspend fun allMindStamps(): List<MindStampEntity>

    @Query("DELETE FROM mindstamps")
    suspend fun deleteAll()
}
