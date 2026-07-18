package com.weekyii.android.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.weekyii.android.data.db.entities.ProjectEntity
import kotlinx.coroutines.flow.Flow
import java.util.UUID

@Dao
interface ProjectDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(project: ProjectEntity)

    @Query("SELECT * FROM projects WHERE project_id = :id LIMIT 1")
    suspend fun findById(id: UUID): ProjectEntity?

    @Query("SELECT * FROM projects")
    fun observeAll(): Flow<List<ProjectEntity>>
}
