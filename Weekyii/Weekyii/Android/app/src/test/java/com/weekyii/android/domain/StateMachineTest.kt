package com.weekyii.android.domain

import com.weekyii.android.data.db.dao.DayDao
import com.weekyii.android.data.db.dao.ProjectDao
import com.weekyii.android.data.db.dao.TaskDao
import com.weekyii.android.data.db.dao.WeekDao
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.DayWithTasks
import com.weekyii.android.data.db.entities.ExecutionMode
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskWithSteps
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.TaskAttachmentEntity
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.data.db.entities.WeekWithDays
import com.weekyii.android.data.repository.WeekCalculator
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.data.repository.TaskAttachmentDraft
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.Date
import java.util.UUID

class StateMachineTest {
    private val zone = ZoneId.of("Asia/Shanghai")

    @Test
    fun reconcileExpiresEveryStaleOpenDayAndKeepsOnlyCompletedTaskDetails() = runBlocking {
        val now = Instant.parse("2026-07-20T02:00:00Z")
        val staleDate = LocalDate.of(2026, 7, 6)
        val oldWeek = week(staleDate, WeekStatus.PAST)
        val staleDay = day(staleDate, oldWeek.weekId, DayStatus.EXECUTE)
        val tasks = mutableMapOf(
            staleDay.dayId to mutableListOf(
                task(staleDay.dayId, 1, TaskZone.FOCUS),
                task(staleDay.dayId, 2, TaskZone.FROZEN),
                task(staleDay.dayId, 3, TaskZone.COMPLETE)
            )
        )
        val days = RecordingDayDao(mutableMapOf(staleDay.dayId to staleDay), tasks)
        val weeks = RecordingWeekDao(mutableMapOf(oldWeek.weekId to oldWeek)) { days.values() }
        val repository = repository(weeks, days, RecordingTaskDao(tasks))
        val state = InMemoryAppStateStore().apply {
            setLastProcessedDate(LocalDate.of(2026, 7, 19))
        }

        StateMachine(repository, FixedTimeProvider(now, zone), state).reconcile(force = true)

        assertEquals(DayStatus.EXPIRED, days.findById(staleDay.dayId)?.status)
        assertEquals(2, days.findById(staleDay.dayId)?.expiredCount)
        assertEquals(listOf(TaskZone.COMPLETE), tasks.getValue(staleDay.dayId).map { it.zone })
    }

    @Test
    fun reconcileNormalizesMultipleFocusTasksAndExecutionOrder() = runBlocking {
        val now = Instant.parse("2026-07-20T10:00:00Z")
        val today = LocalDate.of(2026, 7, 20)
        val currentWeek = week(today, WeekStatus.PRESENT)
        val todayDay = day(today, currentWeek.weekId, DayStatus.EXECUTE)
        val firstFocus = task(todayDay.dayId, 3, TaskZone.FOCUS)
        val secondFocus = task(todayDay.dayId, 1, TaskZone.FOCUS)
        val frozen = task(todayDay.dayId, 9, TaskZone.FROZEN)
        val tasks = mutableMapOf(todayDay.dayId to mutableListOf(firstFocus, secondFocus, frozen))
        val days = RecordingDayDao(mutableMapOf(todayDay.dayId to todayDay), tasks)
        val weeks = RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() }
        val repository = repository(weeks, days, RecordingTaskDao(tasks))

        StateMachine(repository, FixedTimeProvider(now, zone), InMemoryAppStateStore()).reconcile(force = true)

        val normalized = tasks.getValue(todayDay.dayId).sortedBy { it.order }
        assertEquals(listOf(TaskZone.FOCUS, TaskZone.FROZEN, TaskZone.FROZEN), normalized.map { it.zone })
        assertEquals(listOf(1, 2, 3), normalized.map { it.order })
        assertEquals(secondFocus.id, normalized.first().id)
    }

    @Test
    fun reconcilePromotesFirstFrozenTaskWhenExecutingDayHasNoFocus() = runBlocking {
        val now = Instant.parse("2026-07-20T10:00:00Z")
        val today = LocalDate.of(2026, 7, 20)
        val currentWeek = week(today, WeekStatus.PRESENT)
        val todayDay = day(today, currentWeek.weekId, DayStatus.EXECUTE)
        val later = task(todayDay.dayId, 7, TaskZone.FROZEN)
        val first = task(todayDay.dayId, 2, TaskZone.FROZEN)
        val tasks = mutableMapOf(todayDay.dayId to mutableListOf(later, first))
        val days = RecordingDayDao(mutableMapOf(todayDay.dayId to todayDay), tasks)
        val weeks = RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() }
        val repository = repository(weeks, days, RecordingTaskDao(tasks))

        StateMachine(repository, FixedTimeProvider(now, zone), InMemoryAppStateStore()).reconcile(force = true)

        val normalized = tasks.getValue(todayDay.dayId).sortedBy { it.order }
        assertEquals(TaskZone.FOCUS, normalized.first().zone)
        assertEquals(first.id, normalized.first().id)
        assertEquals(listOf(1, 2), normalized.map { it.order })
    }

    @Test
    fun reconcilePromotesCurrentPendingWeekAndArchivesOldPresentAndStalePendingWeeks() = runBlocking {
        val now = Instant.parse("2026-07-20T02:00:00Z")
        val current = week(LocalDate.of(2026, 7, 20), WeekStatus.PENDING)
        val oldPresent = week(LocalDate.of(2026, 7, 13), WeekStatus.PRESENT)
        val stalePending = week(LocalDate.of(2026, 7, 6), WeekStatus.PENDING)
        val futurePending = week(LocalDate.of(2026, 7, 27), WeekStatus.PENDING)
        val weeks = RecordingWeekDao(
            mutableMapOf(
                current.weekId to current,
                oldPresent.weekId to oldPresent,
                stalePending.weekId to stalePending,
                futurePending.weekId to futurePending
            )
        )
        val repository = repository(weeks, RecordingDayDao(), RecordingTaskDao())

        StateMachine(repository, FixedTimeProvider(now, zone), InMemoryAppStateStore())
            .reconcile(force = true)

        assertEquals(WeekStatus.PRESENT, weeks.findById(current.weekId)?.status)
        assertEquals(WeekStatus.PAST, weeks.findById(oldPresent.weekId)?.status)
        assertEquals(WeekStatus.PAST, weeks.findById(stalePending.weekId)?.status)
        assertEquals(WeekStatus.PENDING, weeks.findById(futurePending.weekId)?.status)
        assertEquals(1, weeks.allWeeks().count { it.status == WeekStatus.PRESENT })
    }

    @Test
    fun reconcileExpiresTodayAtTheExactKillTimeBoundary() = runBlocking {
        val now = Instant.parse("2026-07-20T12:00:00Z") // 20:00 Asia/Shanghai
        val today = LocalDate.of(2026, 7, 20)
        val currentWeek = week(today, WeekStatus.PRESENT)
        val todayDay = day(today, currentWeek.weekId, DayStatus.EXECUTE).copy(killHour = 20, killMinute = 0)
        val tasks = mutableMapOf(todayDay.dayId to mutableListOf(task(todayDay.dayId, 1, TaskZone.FOCUS)))
        val days = RecordingDayDao(mutableMapOf(todayDay.dayId to todayDay), tasks)
        val weeks = RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() }
        val repository = repository(weeks, days, RecordingTaskDao(tasks))

        StateMachine(repository, FixedTimeProvider(now, zone), InMemoryAppStateStore())
            .reconcile(force = true)

        assertEquals(DayStatus.EXPIRED, days.findById(todayDay.dayId)?.status)
        assertEquals(1, days.findById(todayDay.dayId)?.expiredCount)
        assertTrue(tasks.getValue(todayDay.dayId).isEmpty())
    }

    @Test
    fun reconcileSkipsASecondRunWithinTheSameMinute() = runBlocking {
        val now = Instant.parse("2026-07-20T02:00:00Z")
        val state = InMemoryAppStateStore()
        val repository = repository(RecordingWeekDao(), RecordingDayDao(), RecordingTaskDao())
        val machine = StateMachine(repository, FixedTimeProvider(now, zone), state)

        val first = machine.reconcile(force = false)
        val second = machine.reconcile(force = false)

        assertFalse(first.skipped)
        assertTrue(second.skipped)
        assertEquals(1, state.stateTransitionRevision.value)
    }

    @Test
    fun addingBlankDraftTaskIsRejectedWithoutWritingAnEmptyTask() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val currentWeek = week(date, WeekStatus.PRESENT)
        val today = day(date, currentWeek.weekId, DayStatus.EMPTY)
        val tasks = mutableMapOf<String, MutableList<TaskEntity>>()
        val days = RecordingDayDao(mutableMapOf(today.dayId to today), tasks)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            RecordingTaskDao(tasks)
        )

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.addDraftTasks(today.dayId, listOf("  ")) }
        }
        assertTrue(days.findWithTasks(today.dayId)?.tasks.orEmpty().isEmpty())
    }

    @Test
    fun draftTaskRetainsCustomTypeIdAndUsesItsBaseKind() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val currentWeek = week(date, WeekStatus.PRESENT)
        val today = day(date, currentWeek.weekId, DayStatus.EMPTY)
        val tasks = mutableMapOf<String, MutableList<TaskEntity>>()
        val days = RecordingDayDao(mutableMapOf(today.dayId to today), tasks)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            RecordingTaskDao(tasks)
        )

        repository.addDraftTasks(today.dayId, listOf("Ship release"), TaskType.DDL, "release-sprint")

        val created = tasks.getValue(today.dayId).single()
        assertEquals(TaskType.DDL, created.taskType)
        assertEquals("release-sprint", created.taskTypeIdRaw)
    }

    @Test
    fun flexibleExecutionCanUnlockAndAppendANewFrozenTask() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val currentWeek = week(date, WeekStatus.PRESENT)
        val today = day(date, currentWeek.weekId, DayStatus.DRAFT)
        val tasks = mutableMapOf(
            today.dayId to mutableListOf(
                task(today.dayId, 1, TaskZone.DRAFT),
                task(today.dayId, 2, TaskZone.DRAFT)
            )
        )
        val days = RecordingDayDao(mutableMapOf(today.dayId to today), tasks)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            RecordingTaskDao(tasks)
        )

        repository.startDay(today.dayId, Date(1_000), ExecutionMode.FLEXIBLE)
        repository.setDraftZoneUnlocked(today.dayId, true)
        repository.addExecutionTask(today.dayId, "Late task")

        val updatedDay = days.findById(today.dayId)!!
        assertEquals(ExecutionMode.FLEXIBLE.name.lowercase(), updatedDay.executionModeRaw)
        assertTrue(updatedDay.isDraftZoneUnlocked)
        assertEquals(
            listOf(TaskZone.FOCUS, TaskZone.FROZEN, TaskZone.FROZEN),
            tasks.getValue(today.dayId).sortedBy { it.order }.map { it.zone }
        )
    }

    @Test
    fun strictExecutionCannotUnlockTheExecutionQueue() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val currentWeek = week(date, WeekStatus.PRESENT)
        val today = day(date, currentWeek.weekId, DayStatus.DRAFT)
        val tasks = mutableMapOf(today.dayId to mutableListOf(task(today.dayId, 1, TaskZone.DRAFT)))
        val days = RecordingDayDao(mutableMapOf(today.dayId to today), tasks)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            RecordingTaskDao(tasks)
        )
        repository.startDay(today.dayId, Date(1_000), ExecutionMode.STRICT)

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.setDraftZoneUnlocked(today.dayId, true) }
        }
        Unit
    }

    @Test
    fun flexibleExecutionCanExchangeFocusWithTheFirstFrozenTask() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val currentWeek = week(date, WeekStatus.PRESENT)
        val today = day(date, currentWeek.weekId, DayStatus.DRAFT)
        val first = task(today.dayId, 1, TaskZone.DRAFT)
        val second = task(today.dayId, 2, TaskZone.DRAFT)
        val tasks = mutableMapOf(today.dayId to mutableListOf(first, second))
        val days = RecordingDayDao(mutableMapOf(today.dayId to today), tasks)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            RecordingTaskDao(tasks)
        )
        repository.startDay(today.dayId, Date(1_000), ExecutionMode.FLEXIBLE)
        repository.setDraftZoneUnlocked(today.dayId, true)

        repository.exchangeFocusWithFirstFrozen(today.dayId, Date(2_000))

        val byId = tasks.getValue(today.dayId).associateBy { it.id }
        assertEquals(TaskZone.FROZEN, byId.getValue(first.id).zone)
        assertEquals(2, byId.getValue(first.id).order)
        assertEquals(TaskZone.FOCUS, byId.getValue(second.id).zone)
        assertEquals(1, byId.getValue(second.id).order)
        assertEquals(Date(2_000), byId.getValue(second.id).startedAt)
    }

    @Test
    fun flexibleUnlockedExecutionCanEditFrozenTaskDetails() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val currentWeek = week(date, WeekStatus.PRESENT)
        val today = day(date, currentWeek.weekId, DayStatus.EXECUTE).copy(
            executionModeRaw = ExecutionMode.FLEXIBLE.name.lowercase(),
            isDraftZoneUnlocked = true
        )
        val focus = task(today.dayId, 1, TaskZone.FOCUS)
        val frozen = task(today.dayId, 2, TaskZone.FROZEN)
        val tasks = mutableMapOf(today.dayId to mutableListOf(focus, frozen))
        val days = RecordingDayDao(mutableMapOf(today.dayId to today), tasks)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            RecordingTaskDao(tasks)
        )

        repository.updateFrozenTask(
            today.dayId,
            frozen.id,
            "Updated frozen",
            "Details",
            stepTitles = listOf("Step one")
        )

        val updated = tasks.getValue(today.dayId).single { it.id == frozen.id }
        assertEquals("Updated frozen", updated.title)
        assertEquals("Details", updated.description)
        assertEquals(listOf("Step one"), repository.getTaskUi(frozen.id)?.steps?.map { it.title })
    }

    @Test
    fun flexibleUnlockedExecutionCanDeleteFrozenTaskAndRepairQueueOrder() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val currentWeek = week(date, WeekStatus.PRESENT)
        val today = day(date, currentWeek.weekId, DayStatus.EXECUTE).copy(
            executionModeRaw = ExecutionMode.FLEXIBLE.name.lowercase(),
            isDraftZoneUnlocked = true
        )
        val focus = task(today.dayId, 1, TaskZone.FOCUS)
        val firstFrozen = task(today.dayId, 2, TaskZone.FROZEN)
        val secondFrozen = task(today.dayId, 3, TaskZone.FROZEN)
        val tasks = mutableMapOf(today.dayId to mutableListOf(focus, firstFrozen, secondFrozen))
        val days = RecordingDayDao(mutableMapOf(today.dayId to today), tasks)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            RecordingTaskDao(tasks)
        )

        repository.deleteFrozenTask(today.dayId, firstFrozen.id)

        val remaining = tasks.getValue(today.dayId).sortedBy { it.order }
        assertEquals(listOf(TaskZone.FOCUS, TaskZone.FROZEN), remaining.map { it.zone })
        assertEquals(listOf(1, 2), remaining.map { it.order })
        assertEquals(secondFrozen.id, remaining.last().id)
    }

    @Test
    fun flexibleUnlockedExecutionCanMoveFrozenTaskWithinQueue() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val currentWeek = week(date, WeekStatus.PRESENT)
        val today = day(date, currentWeek.weekId, DayStatus.EXECUTE).copy(
            executionModeRaw = ExecutionMode.FLEXIBLE.name.lowercase(),
            isDraftZoneUnlocked = true
        )
        val focus = task(today.dayId, 1, TaskZone.FOCUS)
        val firstFrozen = task(today.dayId, 2, TaskZone.FROZEN)
        val secondFrozen = task(today.dayId, 3, TaskZone.FROZEN)
        val tasks = mutableMapOf(today.dayId to mutableListOf(focus, firstFrozen, secondFrozen))
        val days = RecordingDayDao(mutableMapOf(today.dayId to today), tasks)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            RecordingTaskDao(tasks)
        )

        repository.moveFrozenTask(today.dayId, fromIndex = 1, toIndex = 0)

        val reordered = tasks.getValue(today.dayId).sortedBy { it.order }
        assertEquals(listOf(focus.id, secondFrozen.id, firstFrozen.id), reordered.map { it.id })
        assertEquals(listOf(1, 2, 3), reordered.map { it.order })
    }

    @Test
    fun lockedExecutionCannotMutateFrozenQueue() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val currentWeek = week(date, WeekStatus.PRESENT)
        val today = day(date, currentWeek.weekId, DayStatus.EXECUTE).copy(
            executionModeRaw = ExecutionMode.FLEXIBLE.name.lowercase(),
            isDraftZoneUnlocked = false
        )
        val frozen = task(today.dayId, 2, TaskZone.FROZEN)
        val tasks = mutableMapOf(today.dayId to mutableListOf(task(today.dayId, 1, TaskZone.FOCUS), frozen))
        val days = RecordingDayDao(mutableMapOf(today.dayId to today), tasks)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            RecordingTaskDao(tasks)
        )

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repository.deleteFrozenTask(today.dayId, frozen.id) }
        }
        assertEquals(2, tasks.getValue(today.dayId).size)
    }

    @Test
    fun reconcileSyncsDefaultKillTimeOnlyWhenTheDayRollsOver() = runBlocking {
        val now = Instant.parse("2026-07-20T02:00:00Z")
        val today = LocalDate.of(2026, 7, 20)
        val currentWeek = week(today, WeekStatus.PRESENT)
        val todayDay = day(today, currentWeek.weekId, DayStatus.EMPTY).copy(
            killHour = 20,
            killMinute = 0,
            followsDefaultKillTime = false
        )
        val days = RecordingDayDao(mutableMapOf(todayDay.dayId to todayDay))
        val weeks = RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() }
        val settings = InMemorySettingsStore(killTime = LocalTime.of(23, 59))
        val state = InMemoryAppStateStore().apply {
            setLastProcessedDate(today.minusDays(1))
        }
        val repository = repository(weeks, days, RecordingTaskDao())

        StateMachine(repository, FixedTimeProvider(now, zone), state, settings).reconcile(force = true)

        assertEquals(23, days.findById(todayDay.dayId)?.killHour)
        assertEquals(59, days.findById(todayDay.dayId)?.killMinute)
        assertTrue(days.findById(todayDay.dayId)?.followsDefaultKillTime == true)

        days.upsert(days.findById(todayDay.dayId)!!.copy(killHour = 22, killMinute = 0, followsDefaultKillTime = false))
        state.setLastProcessedDate(today)
        StateMachine(repository, FixedTimeProvider(now, zone), state, settings).reconcile(force = true)

        assertEquals(22, days.findById(todayDay.dayId)?.killHour)
        assertFalse(days.findById(todayDay.dayId)?.followsDefaultKillTime == true)
    }

    @Test
    fun postponingFocusMovesItToFutureDraftAndPromotesNextFrozenTask() = runBlocking {
        val todayDate = LocalDate.of(2026, 7, 20)
        val targetDate = todayDate.plusDays(1)
        val currentWeek = week(todayDate, WeekStatus.PRESENT)
        val today = day(todayDate, currentWeek.weekId, DayStatus.EXECUTE).copy(initiatedAt = Date(500))
        val target = day(targetDate, currentWeek.weekId, DayStatus.EMPTY)
        val focus = task(today.dayId, 1, TaskZone.FOCUS).copy(startedAt = Date(1_000))
        val frozen = task(today.dayId, 2, TaskZone.FROZEN)
        val tasks = mutableMapOf(today.dayId to mutableListOf(focus, frozen), target.dayId to mutableListOf())
        val days = RecordingDayDao(mutableMapOf(today.dayId to today, target.dayId to target), tasks)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            RecordingTaskDao(tasks)
        )

        repository.postponeTask(focus.id, targetDate, todayDate, Date(2_000))

        val sourceTasks = tasks.getValue(today.dayId).sortedBy { it.order }
        val targetTasks = tasks.getValue(target.dayId)
        assertEquals(listOf(TaskZone.FOCUS), sourceTasks.map { it.zone })
        assertEquals(frozen.id, sourceTasks.single().id)
        assertEquals(Date(2_000), sourceTasks.single().startedAt)
        assertEquals(TaskZone.DRAFT, targetTasks.single().zone)
        assertEquals(focus.id, targetTasks.single().id)
        assertEquals(DayStatus.DRAFT, days.findById(target.dayId)?.status)
    }

    @Test
    fun draftTaskResourcesRoundTripThroughRepository() = runBlocking {
        val date = LocalDate.of(2026, 7, 20)
        val currentWeek = week(date, WeekStatus.PRESENT)
        val today = day(date, currentWeek.weekId, DayStatus.DRAFT)
        val draft = task(today.dayId, 1, TaskZone.DRAFT)
        val taskMap = mutableMapOf(today.dayId to mutableListOf(draft))
        val days = RecordingDayDao(mutableMapOf(today.dayId to today), taskMap)
        val taskDao = RecordingTaskDao(taskMap)
        val repository = repository(
            RecordingWeekDao(mutableMapOf(currentWeek.weekId to currentWeek)) { days.values() },
            days,
            taskDao
        )

        repository.replaceDraftTaskResources(
            today.dayId,
            draft.id,
            listOf("First step", "Second step"),
            listOf(TaskAttachmentDraft("proof.txt", "text/plain", byteArrayOf(1, 2, 3)))
        )
        val ui = repository.getTaskUi(draft.id)!!

        assertEquals(listOf("First step", "Second step"), ui.steps.map { it.title })
        assertEquals("proof.txt", ui.attachments.single().fileName)
    }

    private fun repository(
        weekDao: RecordingWeekDao,
        dayDao: RecordingDayDao,
        taskDao: RecordingTaskDao
    ) = WeekyiiRepository(
        weekDao = weekDao,
        dayDao = dayDao,
        taskDao = taskDao,
        projectDao = RecordingProjectDao(),
        weekCalculator = WeekCalculator(),
        zoneId = zone
    )

    private fun week(date: LocalDate, status: WeekStatus): WeekEntity {
        val calculator = WeekCalculator()
        val (start, end) = calculator.weekRange(date)
        return WeekEntity(
            weekId = calculator.weekId(date),
            startDate = start.asDate(zone),
            endDate = end.asDate(zone),
            status = status
        )
    }

    private fun day(date: LocalDate, weekId: String, status: DayStatus) = DayEntity(
        dayId = date.toString(),
        date = date.asDate(zone),
        dayOfWeek = date.dayOfWeek.name.take(3),
        status = status,
        weekOwnerId = weekId
    )

    private fun task(dayId: String, order: Int, zone: TaskZone) = TaskEntity(
        title = "Task $order",
        order = order,
        zone = zone,
        dayOwnerId = dayId
    )
}

private class FixedTimeProvider(
    override val nowInstant: Instant,
    override val zoneId: ZoneId
) : TimeProvider {
    override val currentWeekId: String
        get() = WeekCalculator().weekId(today)
}

private class InMemorySettingsStore(
    killTime: LocalTime = LocalTime.of(20, 0),
    executionMode: ExecutionMode = ExecutionMode.STRICT
) : UserSettingsStore {
    override val defaultKillTime = MutableStateFlow(killTime)
    override val defaultExecutionMode = MutableStateFlow(executionMode)
    override val defaultTaskTypeId = MutableStateFlow("regular")
    override val themeId = MutableStateFlow("amber")
    override val appearanceMode = MutableStateFlow("system")
    override val killTimeReminderMinutes = MutableStateFlow(60)
    override val fixedReminderEnabled = MutableStateFlow(false)
    override val fixedReminderHour = MutableStateFlow(21)
    override val fixedReminderMinute = MutableStateFlow(0)
    override val defaultProjectDurationDays = MutableStateFlow(7)
    override val defaultProjectTileSizeRaw = MutableStateFlow("medium")
    override suspend fun setDefaultKillTime(time: LocalTime) { defaultKillTime.value = time }
    override suspend fun setDefaultExecutionMode(mode: ExecutionMode) { defaultExecutionMode.value = mode }
    override suspend fun setDefaultTaskTypeId(idRaw: String) { defaultTaskTypeId.value = idRaw }
    override suspend fun setThemeId(idRaw: String) { themeId.value = idRaw }
    override suspend fun setAppearanceMode(idRaw: String) { appearanceMode.value = idRaw }
    override suspend fun setKillTimeReminderMinutes(minutes: Int) { killTimeReminderMinutes.value = minutes }
    override suspend fun setFixedReminderEnabled(enabled: Boolean) { fixedReminderEnabled.value = enabled }
    override suspend fun setFixedReminderTime(hour: Int, minute: Int) { fixedReminderHour.value = hour; fixedReminderMinute.value = minute }
    override suspend fun setDefaultProjectDurationDays(days: Int) { defaultProjectDurationDays.value = days }
    override suspend fun setDefaultProjectTileSizeRaw(idRaw: String) { defaultProjectTileSizeRaw.value = idRaw }
}

private class RecordingWeekDao(
    private val values: MutableMap<String, WeekEntity> = mutableMapOf(),
    private val days: () -> Collection<DayEntity> = { emptyList() }
) : WeekDao {
    override suspend fun insert(week: WeekEntity): Long { values[week.weekId] = week; return 1L }
    override suspend fun upsert(week: WeekEntity) { values[week.weekId] = week }
    override suspend fun update(week: WeekEntity) { values[week.weekId] = week }
    override suspend fun findById(weekId: String): WeekEntity? = values[weekId]
    override suspend fun findWithDays(weekId: String): WeekWithDays? =
        values[weekId]?.let { WeekWithDays(it, days().filter { day -> day.weekOwnerId == weekId }) }
    override fun observeWeeksByStatus(status: WeekStatus): Flow<List<WeekEntity>> =
        MutableStateFlow(values.values.filter { it.status == status })
    override suspend fun allWeeks(): List<WeekEntity> = values.values.toList()
    override suspend fun deleteAll() { values.clear() }
}

private class RecordingDayDao(
    private val values: MutableMap<String, DayEntity> = mutableMapOf(),
    private val tasks: MutableMap<String, MutableList<TaskEntity>> = mutableMapOf()
) : DayDao {
    fun values(): Collection<DayEntity> = values.values
    override suspend fun insert(day: DayEntity): Long { values[day.dayId] = day; return 1L }
    override suspend fun upsert(day: DayEntity) { values[day.dayId] = day }
    override suspend fun update(day: DayEntity) { values[day.dayId] = day }
    override suspend fun findById(dayId: String): DayEntity? = values[dayId]
    override suspend fun findWithTasks(dayId: String): DayWithTasks? =
        values[dayId]?.let { DayWithTasks(it, tasks[dayId].orEmpty().toList()) }
    override fun observeByStatus(status: DayStatus): Flow<List<DayEntity>> =
        MutableStateFlow(values.values.filter { it.status == status })
    override fun observeAll(): Flow<List<DayEntity>> = MutableStateFlow(values.values.toList())
    override suspend fun listByWeek(weekId: String): List<DayEntity> =
        values.values.filter { it.weekOwnerId == weekId }
    override suspend fun allDays(): List<DayEntity> = values.values.toList()
    override suspend fun deleteAll() { values.clear(); tasks.clear() }
}

private class RecordingTaskDao(
    private val tasks: MutableMap<String, MutableList<TaskEntity>> = mutableMapOf()
) : TaskDao {
    private val steps = mutableMapOf<UUID, MutableList<TaskStepEntity>>()
    private val attachments = mutableMapOf<UUID, MutableList<TaskAttachmentEntity>>()
    override suspend fun insert(task: TaskEntity): Long { upsert(task); return 1L }
    override suspend fun upsert(task: TaskEntity) {
        tasks.values.forEach { dayTasks -> dayTasks.removeAll { it.id == task.id } }
        val dayTasks = tasks.getOrPut(task.dayOwnerId) { mutableListOf() }
        dayTasks += task
    }
    override suspend fun update(task: TaskEntity) = upsert(task)
    override suspend fun delete(task: TaskEntity) {
        tasks[task.dayOwnerId]?.removeAll { it.id == task.id }
    }
    override suspend fun findById(id: UUID): TaskEntity? = tasks.values.flatten().firstOrNull { it.id == id }
    override fun observeTasksForDay(dayId: String): Flow<List<TaskEntity>> =
        MutableStateFlow(tasks[dayId].orEmpty())
    override fun observeAll(): Flow<List<TaskEntity>> = MutableStateFlow(tasks.values.flatten())
    override suspend fun findWithSteps(id: UUID): TaskWithSteps? = tasks.values.flatten().firstOrNull { it.id == id }?.let {
        TaskWithSteps(it, steps[id].orEmpty(), attachments[id].orEmpty())
    }
    override suspend fun upsertSteps(steps: List<TaskStepEntity>) {
        steps.forEach { value -> this.steps.getOrPut(value.taskOwnerId) { mutableListOf() }.add(value) }
    }
    override suspend fun upsertAttachments(attachments: List<TaskAttachmentEntity>) {
        attachments.forEach { value -> this.attachments.getOrPut(value.attachmentOwnerId) { mutableListOf() }.add(value) }
    }
    override suspend fun deleteSteps(taskId: UUID) { steps.remove(taskId) }
    override suspend fun deleteAttachments(taskId: UUID) { attachments.remove(taskId) }
    override suspend fun deleteByZones(dayId: String, zones: List<String>) {
        tasks[dayId]?.removeAll { it.zone.name in zones }
    }
    override suspend fun updateTaskTypeBaseKind(typeIdRaw: String, baseKind: TaskType) {
        tasks.values.forEach { dayTasks ->
            dayTasks.replaceAll { task ->
                if (task.taskTypeIdRaw == typeIdRaw) task.copy(taskType = baseKind) else task
            }
        }
    }
    override suspend fun allTasks(): List<TaskEntity> = tasks.values.flatten()
    override suspend fun deleteAll() { tasks.clear() }
}

private class RecordingProjectDao : ProjectDao {
    override suspend fun insert(project: ProjectEntity): Long = 1L
    override suspend fun update(project: ProjectEntity) = Unit
    override suspend fun upsert(project: ProjectEntity) = Unit
    override suspend fun findById(id: UUID): ProjectEntity? = null
    override fun observeAll(): Flow<List<ProjectEntity>> = MutableStateFlow(emptyList())
    override suspend fun delete(project: ProjectEntity) = Unit
    override suspend fun maxTileOrder(): Int? = null
    override suspend fun allProjects(): List<ProjectEntity> = emptyList()
    override suspend fun deleteAll() = Unit
}

private fun LocalDate.asDate(zoneId: ZoneId): Date = Date.from(atStartOfDay(zoneId).toInstant())
