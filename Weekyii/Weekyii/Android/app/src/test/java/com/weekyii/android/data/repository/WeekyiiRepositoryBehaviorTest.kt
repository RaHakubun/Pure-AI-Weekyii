package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.DayDao
import com.weekyii.android.data.db.dao.MindStampDao
import com.weekyii.android.data.db.dao.ProjectDao
import com.weekyii.android.data.db.dao.TaskDao
import com.weekyii.android.data.db.dao.WeekDao
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.DayWithTasks
import com.weekyii.android.data.db.entities.MindStampEntity
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskWithSteps
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.TaskAttachmentEntity
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.data.db.entities.WeekWithDays
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Date
import java.util.UUID

class WeekyiiRepositoryBehaviorTest {
    @Test
    fun existingPendingWeekIsPromotedWhenItBecomesCurrent() = runBlocking {
        val weekId = "2026-W30"
        val pending = week(weekId, WeekStatus.PENDING)
        val weeks = FakeWeekDao(mutableMapOf(weekId to pending))
        val repository = repository(weeks)

        repository.ensureWeek(LocalDate.of(2026, 7, 20), WeekStatus.PRESENT)

        assertEquals(WeekStatus.PRESENT, weeks.findById(weekId)?.status)
    }

    @Test
    fun existingWeekIsFilledWithMissingDayRows() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val weekId = "2026-W30"
        val weeks = FakeWeekDao(mutableMapOf(weekId to week(weekId, WeekStatus.PRESENT)))
        val days = FakeDayDao()
        val repository = repository(weekDao = weeks, dayDao = days)

        repository.ensureWeek(date, WeekStatus.PRESENT)

        assertEquals(7, days.listByWeek(weekId).size)
        assertEquals(
            (0L..6L).map { date.plusDays(it).toString() },
            days.listByWeek(weekId).sortedBy { it.date }.map { it.dayId }
        )
    }

    @Test
    fun invalidKillTimeIsRejectedBeforePersistence() = runBlocking {
        val day = day("2026-07-20", DayStatus.DRAFT)
        val days = FakeDayDao(mutableMapOf(day.dayId to day))
        val repository = repository(dayDao = days)

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.changeKillTime(day.dayId, 24, 0) }
        }
        assertEquals(20, days.findById(day.dayId)?.killHour)
    }

    @Test
    fun weekSummaryCountsOnlyDaysThatWereActuallyStarted() = runBlocking {
        val weekId = "2026-W30"
        val expiredDraft = day("2026-07-20", DayStatus.EXPIRED, weekId = weekId)
        val completed = day("2026-07-21", DayStatus.COMPLETED, weekId = weekId).copy(
            initiatedAt = Date(1_000),
            closedAt = Date(2_000)
        )
        val weekDao = FakeWeekDao(mutableMapOf(weekId to week(weekId, WeekStatus.PAST)))
        weekDao.withDays = WeekWithDays(weekDao.findById(weekId)!!, listOf(expiredDraft, completed))
        val repository = repository(weekDao = weekDao, dayDao = FakeDayDao())

        repository.updateWeekSummary(weekId)

        assertEquals(1, weekDao.findById(weekId)?.totalStartedDays)
    }

    @Test
    fun killTimeAtOrBeforeNowIsRejectedButFutureTimeCanBeSaved() = runBlocking {
        val zone = ZoneId.of("Asia/Shanghai")
        val date = LocalDate.of(2026, 7, 20)
        val day = day(date.toString(), DayStatus.DRAFT).copy(
            date = Date.from(date.atStartOfDay(zone).toInstant())
        )
        val days = FakeDayDao(mutableMapOf(day.dayId to day))
        val repository = repository(dayDao = days)
        val now = Date.from(LocalDateTime.of(2026, 7, 20, 20, 1).atZone(zone).toInstant())

        assertThrows(IllegalStateException::class.java) {
            runBlocking { repository.changeKillTime(day.dayId, 20, 0, now) }
        }
        repository.changeKillTime(day.dayId, 21, 0, now)
        assertEquals(21, days.findById(day.dayId)?.killHour)
    }

    private fun repository(
        weekDao: FakeWeekDao = FakeWeekDao(),
        dayDao: FakeDayDao = FakeDayDao(),
        taskDao: FakeTaskDao = FakeTaskDao()
    ) = WeekyiiRepository(
        weekDao = weekDao,
        dayDao = dayDao,
        taskDao = taskDao,
        projectDao = FakeProjectDao(),
        weekCalculator = WeekCalculator(),
        zoneId = ZoneId.of("Asia/Shanghai")
    )

    private fun week(id: String, status: WeekStatus) = WeekEntity(
        weekId = id,
        startDate = Date(0),
        endDate = Date(6 * 86_400_000L),
        status = status
    )

    private fun day(
        id: String,
        status: DayStatus,
        weekId: String = "2026-W30"
    ) = DayEntity(
        dayId = id,
        date = Date(0),
        dayOfWeek = "MON",
        status = status,
        weekOwnerId = weekId
    )
}

private class FakeWeekDao(
    private val values: MutableMap<String, WeekEntity> = mutableMapOf()
) : WeekDao {
    var withDays: WeekWithDays? = null

    override suspend fun upsert(week: WeekEntity) { values[week.weekId] = week }
    override suspend fun update(week: WeekEntity) { values[week.weekId] = week }
    override suspend fun findById(weekId: String): WeekEntity? = values[weekId]
    override suspend fun findWithDays(weekId: String): WeekWithDays? = withDays
    override fun observeWeeksByStatus(status: WeekStatus): Flow<List<WeekEntity>> =
        MutableStateFlow(values.values.filter { it.status == status })
    override suspend fun allWeeks(): List<WeekEntity> = values.values.toList()
}

private class FakeDayDao(
    private val values: MutableMap<String, DayEntity> = mutableMapOf()
) : DayDao {
    override suspend fun upsert(day: DayEntity) { values[day.dayId] = day }
    override suspend fun update(day: DayEntity) { values[day.dayId] = day }
    override suspend fun findById(dayId: String): DayEntity? = values[dayId]
    override suspend fun findWithTasks(dayId: String): DayWithTasks? = values[dayId]?.let { DayWithTasks(it, emptyList()) }
    override fun observeByStatus(status: DayStatus): Flow<List<DayEntity>> =
        MutableStateFlow(values.values.filter { it.status == status })
    override fun observeAll(): Flow<List<DayEntity>> = MutableStateFlow(values.values.toList())
    override suspend fun listByWeek(weekId: String): List<DayEntity> = values.values.filter { it.weekOwnerId == weekId }
    override suspend fun allDays(): List<DayEntity> = values.values.toList()
}

private class FakeTaskDao : TaskDao {
    override suspend fun upsert(task: TaskEntity) = Unit
    override suspend fun update(task: TaskEntity) = Unit
    override suspend fun delete(task: TaskEntity) = Unit
    override suspend fun findById(id: UUID): TaskEntity? = null
    override fun observeTasksForDay(dayId: String): Flow<List<TaskEntity>> = MutableStateFlow(emptyList())
    override suspend fun findWithSteps(id: UUID): TaskWithSteps? = null
    override suspend fun upsertSteps(steps: List<TaskStepEntity>) = Unit
    override suspend fun upsertAttachments(attachments: List<TaskAttachmentEntity>) = Unit
    override suspend fun deleteSteps(taskId: UUID) = Unit
    override suspend fun deleteAttachments(taskId: UUID) = Unit
    override suspend fun deleteByZones(dayId: String, zones: List<String>) = Unit
    override suspend fun updateTaskTypeBaseKind(typeIdRaw: String, baseKind: com.weekyii.android.data.db.entities.TaskType) = Unit
}

private class FakeProjectDao : ProjectDao {
    override suspend fun upsert(project: ProjectEntity) = Unit
    override suspend fun findById(id: UUID): ProjectEntity? = null
    override fun observeAll(): Flow<List<ProjectEntity>> = MutableStateFlow(emptyList())
    override suspend fun delete(project: ProjectEntity) = Unit
    override suspend fun maxTileOrder(): Int? = null
}

private class FakeMindStampDao : MindStampDao {
    override suspend fun upsert(mindStamp: MindStampEntity) = Unit
    override fun observeAll(): Flow<List<MindStampEntity>> = MutableStateFlow(emptyList())
    override suspend fun findById(id: UUID): MindStampEntity? = null
    override suspend fun delete(mindStamp: MindStampEntity) = Unit
}
