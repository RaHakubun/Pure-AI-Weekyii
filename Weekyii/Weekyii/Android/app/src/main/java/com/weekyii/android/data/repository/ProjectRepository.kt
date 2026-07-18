package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.ProjectDao
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.domain.TimeProvider
import com.weekyii.android.ui.model.ProjectUi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.LocalDate
import java.time.ZoneId
import java.util.Date
import java.util.UUID

class ProjectRepository(
    private val projectDao: ProjectDao,
    private val timeProvider: TimeProvider,
    private val zoneId: ZoneId = ZoneId.systemDefault()
) {
    fun observeProjects(): Flow<List<ProjectUi>> = projectDao.observeAll()
        .map { projects -> projects.sortedBy { it.tileOrder }.map { it.toUi(zoneId) } }

    suspend fun createProject(
        name: String,
        description: String,
        startDate: LocalDate,
        endDate: LocalDate
    ): UUID {
        require(name.isNotBlank()) { "Project name cannot be empty" }
        require(!startDate.isBefore(timeProvider.today)) { "Project cannot start in the past" }
        require(!endDate.isBefore(startDate)) { "Project end date must not precede start date" }
        val project = ProjectEntity(
            name = name.trim(),
            description = description.trim(),
            startDate = startDate.asDate(zoneId),
            endDate = endDate.asDate(zoneId),
            tileOrder = (projectDao.maxTileOrder() ?: -1) + 1
        )
        projectDao.upsert(project)
        return project.projectId
    }

    suspend fun updateStatus(id: UUID, status: ProjectStatus) {
        val project = projectDao.findById(id) ?: return
        projectDao.upsert(project.copy(status = status))
    }

    suspend fun updateProject(id: UUID, name: String, description: String) {
        require(name.isNotBlank()) { "Project name cannot be empty" }
        val project = projectDao.findById(id) ?: return
        projectDao.upsert(project.copy(name = name.trim(), description = description.trim()))
    }

    suspend fun deleteProject(id: UUID) {
        val project = projectDao.findById(id) ?: return
        projectDao.delete(project)
    }
}

private fun ProjectEntity.toUi(zoneId: ZoneId) = ProjectUi(
    id = projectId,
    name = name,
    description = description,
    color = color,
    icon = icon,
    status = status,
    startDate = startDate.toInstant().atZone(zoneId).toLocalDate(),
    endDate = endDate.toInstant().atZone(zoneId).toLocalDate(),
    createdAt = createdAt.toInstant().atZone(zoneId).toLocalDateTime()
)

private fun LocalDate.asDate(zoneId: ZoneId): Date = Date.from(atStartOfDay(zoneId).toInstant())
