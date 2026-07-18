package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.DayDao
import com.weekyii.android.data.db.dao.ProjectDao
import com.weekyii.android.data.db.dao.TaskDao
import com.weekyii.android.data.db.dao.WeekDao
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.DayWithTasks
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.data.db.entities.TaskAttachmentEntity
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskWithSteps
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.data.db.entities.WeekWithDays
import com.weekyii.android.domain.TimeProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Date
import java.util.UUID

class ProjectRepositoryTaskTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private val time = object : TimeProvider {
        override val nowInstant: Instant = Instant.parse("2026-07-20T02:00:00Z")
        override val zoneId: ZoneId = zone
        override val currentWeekId: String = "2026-W30"
    }

    @Test
    fun addingTaskCreatesTargetDayAndActivatesPlanningProject() = runBlocking {
        val projects = ProjectTaskProjectDao()
        val weeks = RecordingWeekDao()
        val tasks = RecordingTaskDao()
        val days = RecordingDayDao(tasks)
        val repository = ProjectRepository(projects, time, zone, weeks, days, tasks, WeekCalculator())
        val projectId = repository.createProject(
            "Android parity", "", LocalDate.of(2026, 7, 20), LocalDate.of(2026, 7, 31)
        )

        val taskId = repository.addTask(projectId, "Wire detail", targetDate = LocalDate.of(2026, 7, 22))

        assertEquals(ProjectStatus.ACTIVE, projects.findById(projectId)?.status)
        assertEquals(DayStatus.DRAFT, days.findById("2026-07-22")?.status)
        assertEquals(projectId, tasks.findById(taskId)?.projectOwnerId)
        assertEquals("2026-07-22", tasks.findById(taskId)?.dayOwnerId)
    }

    @Test
    fun addingTaskRejectsDatesOutsideProjectRange(): Unit = runBlocking {
        val projects = ProjectTaskProjectDao()
        val weeks = RecordingWeekDao()
        val tasks = RecordingTaskDao()
        val days = RecordingDayDao(tasks)
        val repository = ProjectRepository(projects, time, zone, weeks, days, tasks, WeekCalculator())
        val projectId = repository.createProject(
            "Android parity", "", LocalDate.of(2026, 7, 20), LocalDate.of(2026, 7, 31)
        )

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.addTask(projectId, "Out", targetDate = LocalDate.of(2026, 8, 1)) }
        }
    }

    @Test
    fun activeProjectWithOpenTaskCannotComplete(): Unit = runBlocking {
        val projects = ProjectTaskProjectDao()
        val weeks = RecordingWeekDao()
        val tasks = RecordingTaskDao()
        val days = RecordingDayDao(tasks)
        val repository = ProjectRepository(projects, time, zone, weeks, days, tasks, WeekCalculator())
        val projectId = repository.createProject(
            "Android parity", "", LocalDate.of(2026, 7, 20), LocalDate.of(2026, 7, 31)
        )
        repository.addTask(projectId, "Still open", targetDate = LocalDate.of(2026, 7, 22))

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.updateStatus(projectId, ProjectStatus.COMPLETED) }
        }
        assertEquals(ProjectStatus.ACTIVE, projects.findById(projectId)?.status)
    }

    @Test
    fun draftProjectTaskCanBeUpdated() = runBlocking {
        val fixture = projectFixture()
        val taskId = fixture.repository.addTask(
            fixture.projectId, "Original", targetDate = LocalDate.of(2026, 7, 22)
        )

        fixture.repository.updateTask(
            fixture.projectId,
            taskId,
            title = "Updated",
            description = "Details",
            taskType = TaskType.DDL,
            taskTypeIdRaw = "ddl"
        )

        assertEquals("Updated", fixture.tasks.findById(taskId)?.title)
        assertEquals(TaskType.DDL, fixture.tasks.findById(taskId)?.taskType)
    }

    @Test
    fun deletingLastDraftProjectTaskReturnsDayToEmpty() = runBlocking {
        val fixture = projectFixture()
        val taskId = fixture.repository.addTask(
            fixture.projectId, "Temporary", targetDate = LocalDate.of(2026, 7, 22)
        )

        fixture.repository.deleteTask(fixture.projectId, taskId)

        assertEquals(null, fixture.tasks.findById(taskId))
        assertEquals(DayStatus.EMPTY, fixture.days.findById("2026-07-22")?.status)
    }

    @Test
    fun projectDetailComposesProgressNextTaskAndDateSections() = runBlocking {
        val fixture = projectFixture()
        val completedId = fixture.repository.addTask(
            fixture.projectId, "Completed", targetDate = LocalDate.of(2026, 7, 22)
        )
        fixture.repository.addTask(
            fixture.projectId, "Next", targetDate = LocalDate.of(2026, 7, 23)
        )
        val completed = fixture.tasks.findById(completedId)!!
        fixture.tasks.upsert(completed.copy(zone = com.weekyii.android.data.db.entities.TaskZone.COMPLETE))

        val detail = fixture.repository.projectDetail(fixture.projectId, LocalDate.of(2026, 7, 20))!!

        assertEquals(2, detail.totalCount)
        assertEquals(1, detail.completedCount)
        assertEquals(1, detail.remainingCount)
        assertEquals(0.5, detail.progress, 0.001)
        assertEquals("Next", detail.nextTaskTitle)
        assertEquals(listOf(LocalDate.of(2026, 7, 22), LocalDate.of(2026, 7, 23)), detail.sections.map { it.date })
    }

    @Test
    fun deletingOnlyProjectKeepsTasksAndRemovesTheirProjectLink() = runBlocking {
        val fixture = projectFixture()
        val taskId = fixture.repository.addTask(
            fixture.projectId, "Keep me", targetDate = LocalDate.of(2026, 7, 22)
        )

        fixture.repository.deleteProject(fixture.projectId, includeTasks = false)

        assertEquals(null, fixture.repository.projectDetail(fixture.projectId))
        assertEquals(null, fixture.tasks.findById(taskId)?.projectOwnerId)
        assertEquals("Keep me", fixture.tasks.findById(taskId)?.title)
    }

    @Test
    fun addingTasksPrevalidatesEveryDateBeforeWritingAny() = runBlocking {
        val fixture = projectFixture()
        fixture.days.upsert(
            DayEntity(
                dayId = "2026-07-23",
                date = Date.from(LocalDate.of(2026, 7, 23).atStartOfDay(zone).toInstant()),
                dayOfWeek = "THU",
                status = DayStatus.EXECUTE,
                weekOwnerId = "2026-W30"
            )
        )

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                fixture.repository.addTasks(
                    fixture.projectId,
                    "Batch",
                    targetDates = listOf(LocalDate.of(2026, 7, 22), LocalDate.of(2026, 7, 23))
                )
            }
        }
        assertEquals(0, fixture.tasks.values.size)
    }

    private suspend fun projectFixture(): ProjectFixture {
        val projects = ProjectTaskProjectDao()
        val weeks = RecordingWeekDao()
        val tasks = RecordingTaskDao()
        val days = RecordingDayDao(tasks)
        val repository = ProjectRepository(projects, time, zone, weeks, days, tasks, WeekCalculator())
        val projectId = repository.createProject(
            "Android parity", "", LocalDate.of(2026, 7, 20), LocalDate.of(2026, 7, 31)
        )
        return ProjectFixture(repository, projectId, days, tasks)
    }
}

private data class ProjectFixture(
    val repository: ProjectRepository,
    val projectId: UUID,
    val days: RecordingDayDao,
    val tasks: RecordingTaskDao
)

private class ProjectTaskProjectDao : ProjectDao {
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

private class RecordingWeekDao : WeekDao {
    val values = linkedMapOf<String, WeekEntity>()
    override suspend fun insert(week: WeekEntity): Long { values[week.weekId] = week; return 1L }
    override suspend fun upsert(week: WeekEntity) { values[week.weekId] = week }
    override suspend fun update(week: WeekEntity) { values[week.weekId] = week }
    override suspend fun findById(weekId: String): WeekEntity? = values[weekId]
    override suspend fun findWithDays(weekId: String): WeekWithDays? = null
    override fun observeWeeksByStatus(status: WeekStatus): Flow<List<WeekEntity>> = MutableStateFlow(values.values.filter { it.status == status })
    override suspend fun allWeeks(): List<WeekEntity> = values.values.toList()
    override suspend fun deleteAll() { values.clear() }
}

private class RecordingDayDao(private val tasks: RecordingTaskDao) : DayDao {
    val values = linkedMapOf<String, DayEntity>()
    override suspend fun insert(day: DayEntity): Long { values[day.dayId] = day; return 1L }
    override suspend fun upsert(day: DayEntity) { values[day.dayId] = day }
    override suspend fun update(day: DayEntity) { values[day.dayId] = day }
    override suspend fun findById(dayId: String): DayEntity? = values[dayId]
    override suspend fun findWithTasks(dayId: String): DayWithTasks? = values[dayId]?.let { day -> DayWithTasks(day, tasks.values.values.filter { it.dayOwnerId == dayId }) }
    override fun observeByStatus(status: DayStatus): Flow<List<DayEntity>> = MutableStateFlow(values.values.filter { it.status == status })
    override fun observeAll(): Flow<List<DayEntity>> = MutableStateFlow(values.values.toList())
    override suspend fun listByWeek(weekId: String): List<DayEntity> = values.values.filter { it.weekOwnerId == weekId }
    override suspend fun allDays(): List<DayEntity> = values.values.toList()
    override suspend fun deleteAll() { values.clear() }
}

private class RecordingTaskDao : TaskDao {
    val values = linkedMapOf<UUID, TaskEntity>()
    override suspend fun insert(task: TaskEntity): Long { values[task.id] = task; return 1L }
    override suspend fun upsert(task: TaskEntity) { values[task.id] = task }
    override suspend fun update(task: TaskEntity) { values[task.id] = task }
    override suspend fun delete(task: TaskEntity) { values.remove(task.id) }
    override suspend fun findById(id: UUID): TaskEntity? = values[id]
    override fun observeTasksForDay(dayId: String): Flow<List<TaskEntity>> = MutableStateFlow(values.values.filter { it.dayOwnerId == dayId })
    override fun observeAll(): Flow<List<TaskEntity>> = MutableStateFlow(values.values.toList())
    override suspend fun findWithSteps(id: UUID): TaskWithSteps? = values[id]?.let { TaskWithSteps(it, emptyList(), emptyList()) }
    override suspend fun upsertSteps(steps: List<TaskStepEntity>) = Unit
    override suspend fun upsertAttachments(attachments: List<TaskAttachmentEntity>) = Unit
    override suspend fun deleteSteps(taskId: UUID) = Unit
    override suspend fun deleteAttachments(taskId: UUID) = Unit
    override suspend fun deleteByZones(dayId: String, zones: List<String>) = Unit
    override suspend fun updateTaskTypeBaseKind(typeIdRaw: String, baseKind: TaskType) = Unit
    override suspend fun allTasks(): List<TaskEntity> = values.values.toList()
    override suspend fun deleteAll() { values.clear() }
}
