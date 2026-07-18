package com.weekyii.android.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Delete
import androidx.room.Transaction
import androidx.room.Update
import com.weekyii.android.data.db.entities.ProjectEntity
import kotlinx.coroutines.flow.Flow
import java.util.UUID

@Dao
interface ProjectDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(project: ProjectEntity): Long

    @Update
    suspend fun update(project: ProjectEntity)

    @Transaction
    suspend fun upsert(project: ProjectEntity) {
        if (insert(project) == -1L) update(project)
    }

    @Query("SELECT * FROM projects WHERE project_id = :id LIMIT 1")
    suspend fun findById(id: UUID): ProjectEntity?

    @Delete
    suspend fun delete(project: ProjectEntity)

    @Query("SELECT * FROM projects")
    fun observeAll(): Flow<List<ProjectEntity>>

    @Query("SELECT MAX(tile_order) FROM projects")
    suspend fun maxTileOrder(): Int?

    @Query("SELECT * FROM projects")
    suspend fun allProjects(): List<ProjectEntity>

    @Query("DELETE FROM projects")
    suspend fun deleteAll()
}
