package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.MindStampDao
import com.weekyii.android.data.db.dao.ProjectDao
import com.weekyii.android.data.db.entities.MindStampEntity
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStatus
import com.weekyii.android.data.db.dao.SuspendedTaskDao
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
    fun projectRejectsLifecycleTransitionsThatSkipStates() = runBlocking {
        val dao = RecordingProjectDao()
        val repository = ProjectRepository(dao, time, zone)
        val id = repository.createProject(
            name = "Android parity",
            description = "Finish the port",
            startDate = LocalDate.of(2026, 7, 20),
            endDate = LocalDate.of(2026, 8, 20)
        )

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.updateStatus(id, ProjectStatus.COMPLETED) }
        }
        assertEquals(ProjectStatus.PLANNING, dao.findById(id)?.status)
        Unit
    }

    @Test
    fun completedProjectMetadataIsReadOnly() = runBlocking {
        val dao = RecordingProjectDao()
        val project = ProjectEntity(
            name = "Released",
            status = ProjectStatus.COMPLETED,
            startDate = java.util.Date.from(LocalDate.of(2026, 7, 20).atStartOfDay(zone).toInstant()),
            endDate = java.util.Date.from(LocalDate.of(2026, 8, 20).atStartOfDay(zone).toInstant())
        )
        dao.upsert(project)
        val repository = ProjectRepository(dao, time, zone)

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.updateProject(project.projectId, "Changed", "Changed") }
        }
        assertEquals("Released", dao.findById(project.projectId)?.name)
        Unit
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

    @Test
    fun mindStampRitualProviderReturnsPersistedContent() = runBlocking {
        val dao = RecordingMindStampDao()
        dao.upsert(MindStampEntity(text = "Begin gently"))

        val result = MindStampRepository(dao).random()

        assertEquals("Begin gently", result?.text)
    }

    @Test
    fun suspendedTaskCanBeEditedAndDeadlineRecomputed() = runBlocking {
        val dao = EditingSuspendedTaskDao()
        val repository = SuspendedTaskRepository(dao, zone)
        val id = repository.create("Old", "", com.weekyii.android.data.db.entities.TaskType.REGULAR, 5, java.util.Date.from(time.nowInstant))

        repository.update(id, "New", "Details", com.weekyii.android.data.db.entities.TaskType.DDL, 3, java.util.Date.from(time.nowInstant), "ddl")

        assertEquals("New", dao.values[id]?.title)
        assertEquals("ddl", dao.values[id]?.taskTypeIdRaw)
        assertEquals(3, dao.values[id]?.preferredCountdownDays)
    }
}

private class RecordingProjectDao : ProjectDao {
    val values = linkedMapOf<UUID, ProjectEntity>()
    override suspend fun insert(project: ProjectEntity): Long { values[project.projectId] = project; return 1L }
    override suspend fun update(project: ProjectEntity) { values[project.projectId] = project }
    override suspend fun upsert(project: ProjectEntity) { values[project.projectId] = project }
    override suspend fun findById(id: UUID): ProjectEntity? = values[id]
    override fun observeAll(): Flow<List<ProjectEntity>> = MutableStateFlow(values.values.toList())
    override suspend fun delete(project: ProjectEntity) { values.remove(project.projectId) }
    override suspend fun maxTileOrder(): Int? = values.values.maxOfOrNull { it.tileOrder }
    override suspend fun allProjects(): List<ProjectEntity> = values.values.toList()
    override suspend fun deleteAll() { values.clear() }
}

private class RecordingMindStampDao : MindStampDao {
    val values = linkedMapOf<UUID, MindStampEntity>()
    override suspend fun upsert(mindStamp: MindStampEntity) { values[mindStamp.id] = mindStamp }
    override fun observeAll(): Flow<List<MindStampEntity>> = MutableStateFlow(values.values.toList())
    override suspend fun findById(id: UUID): MindStampEntity? = values[id]
    override suspend fun delete(mindStamp: MindStampEntity) { values.remove(mindStamp.id) }
    override suspend fun allMindStamps(): List<MindStampEntity> = values.values.toList()
    override suspend fun deleteAll() { values.clear() }
}

private class EditingSuspendedTaskDao : SuspendedTaskDao {
    val values = linkedMapOf<UUID, SuspendedTaskEntity>()
    override suspend fun insert(task: SuspendedTaskEntity): Long { if (values.containsKey(task.id)) return -1; values[task.id] = task; return 1 }
    override suspend fun update(task: SuspendedTaskEntity) { values[task.id] = task }
    override suspend fun upsert(task: SuspendedTaskEntity) { values[task.id] = task }
    override suspend fun delete(task: SuspendedTaskEntity) { values.remove(task.id) }
    override suspend fun findWithDetails(id: UUID): com.weekyii.android.data.db.entities.SuspendedTaskWithDetails? = values[id]?.let { com.weekyii.android.data.db.entities.SuspendedTaskWithDetails(it, emptyList(), emptyList()) }
    override fun observeByStatus(status: SuspendedTaskStatus): Flow<List<com.weekyii.android.data.db.entities.SuspendedTaskWithDetails>> = MutableStateFlow(values.values.filter { it.status == status }.map { com.weekyii.android.data.db.entities.SuspendedTaskWithDetails(it, emptyList(), emptyList()) })
    override suspend fun listDue(status: SuspendedTaskStatus, deadline: java.util.Date): List<SuspendedTaskEntity> = values.values.filter { it.status == status && !it.decisionDeadline.after(deadline) }
    override suspend fun updateTaskTypeBaseKind(typeIdRaw: String, baseKind: com.weekyii.android.data.db.entities.TaskType) = Unit
    override suspend fun allTasks(): List<SuspendedTaskEntity> = values.values.toList()
    override suspend fun deleteAll() { values.clear() }
    override suspend fun upsertSteps(steps: List<com.weekyii.android.data.db.entities.SuspendedTaskStepEntity>) = Unit
    override suspend fun upsertAttachments(attachments: List<com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity>) = Unit
    override suspend fun deleteSteps(taskId: UUID) = Unit
    override suspend fun deleteAttachments(taskId: UUID) = Unit
}
