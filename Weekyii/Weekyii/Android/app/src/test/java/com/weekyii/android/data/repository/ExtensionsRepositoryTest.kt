package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.MindStampDao
import com.weekyii.android.data.db.dao.ProjectDao
import com.weekyii.android.data.db.entities.MindStampEntity
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.domain.TimeProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

class ExtensionsRepositoryTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private val time = object : TimeProvider {
        override val nowInstant: Instant = Instant.parse("2026-07-20T02:00:00Z")
        override val zoneId: ZoneId = zone
        override val currentWeekId: String = "2026-W30"
    }

    @Test
    fun projectRequiresANonPastValidDateRange() = runBlocking {
        val repository = ProjectRepository(RecordingProjectDao(), time, zone)

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                repository.createProject("Past", "", LocalDate.of(2026, 7, 19), LocalDate.of(2026, 7, 20))
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                repository.createProject("Reverse", "", LocalDate.of(2026, 7, 22), LocalDate.of(2026, 7, 21))
            }
        }
        Unit
    }

    @Test
    fun projectCanBeCreatedAndMovedThroughItsLifecycle() = runBlocking {
        val dao = RecordingProjectDao()
        val repository = ProjectRepository(dao, time, zone)

        val id = repository.createProject(
            name = "Android parity",
            description = "Finish the port",
            startDate = LocalDate.of(2026, 7, 20),
            endDate = LocalDate.of(2026, 8, 20)
        )
        repository.updateStatus(id, ProjectStatus.ACTIVE)

        assertEquals(ProjectStatus.ACTIVE, dao.findById(id)?.status)
        assertEquals("Android parity", dao.findById(id)?.name)
    }

    @Test
    fun mindStampRejectsEmptyContentAndPersistsText() = runBlocking {
        val dao = RecordingMindStampDao()
        val repository = MindStampRepository(dao)

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.create("   ", null) }
        }
        repository.create("Keep moving", null)

        assertEquals(1, dao.values.size)
        assertTrue(dao.values.values.single().hasContent)
    }
}

private class RecordingProjectDao : ProjectDao {
    val values = linkedMapOf<UUID, ProjectEntity>()
    override suspend fun upsert(project: ProjectEntity) { values[project.projectId] = project }
    override suspend fun findById(id: UUID): ProjectEntity? = values[id]
    override fun observeAll(): Flow<List<ProjectEntity>> = MutableStateFlow(values.values.toList())
    override suspend fun delete(project: ProjectEntity) { values.remove(project.projectId) }
    override suspend fun maxTileOrder(): Int? = values.values.maxOfOrNull { it.tileOrder }
}

private class RecordingMindStampDao : MindStampDao {
    val values = linkedMapOf<UUID, MindStampEntity>()
    override suspend fun upsert(mindStamp: MindStampEntity) { values[mindStamp.id] = mindStamp }
    override fun observeAll(): Flow<List<MindStampEntity>> = MutableStateFlow(values.values.toList())
    override suspend fun findById(id: UUID): MindStampEntity? = values[id]
    override suspend fun delete(mindStamp: MindStampEntity) { values.remove(mindStamp.id) }
}
