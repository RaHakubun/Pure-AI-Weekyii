package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.DayDao
import com.weekyii.android.data.db.dao.ProjectDao
import com.weekyii.android.data.db.dao.TaskDao
import com.weekyii.android.data.db.dao.WeekDao
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.model.WeekUi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

class WeekyiiRepository(
    val weekDao: WeekDao,
    val dayDao: DayDao,
    val taskDao: TaskDao,
    val projectDao: ProjectDao,
    private val weekCalculator: WeekCalculator,
    private val zoneId: ZoneId = ZoneId.systemDefault()
) {
    // region Queries
    fun observePresentWeek(): Flow<List<WeekUi>> {
        return weekDao.observeWeeksByStatus(WeekStatus.PRESENT).combineObserveDays()
    }

    fun observePendingWeeks(): Flow<List<WeekUi>> {
        return weekDao.observeWeeksByStatus(WeekStatus.PENDING).combineObserveDays()
    }

    fun observePastWeeks(): Flow<List<WeekUi>> {
        return weekDao.observeWeeksByStatus(WeekStatus.PAST).combineObserveDays()
    }

    private fun Flow<List<WeekEntity>>.combineObserveDays(): Flow<List<WeekUi>> =
        this.combine(dayDao.observeByStatus(DayStatus.EXECUTE)) { weeks, _ -> weeks }
            .map { weeks ->
                weeks.map { week ->
                    val days = dayDao.listByWeek(week.weekId).map { day -> day.toUi() }
                    week.toUi(days)
                }
            }
    // endregion

    // region Mutations aligned to Today flow
    suspend fun ensureWeek(date: LocalDate, status: WeekStatus): WeekEntity {
        val weekId = weekCalculator.weekId(date)
        val existing = weekDao.findById(weekId)
        if (existing != null) {
            if (status == WeekStatus.PRESENT && existing.status != WeekStatus.PRESENT) {
                val promoted = existing.copy(status = WeekStatus.PRESENT)
                weekDao.upsert(promoted)
                return promoted
            }
            return existing
        }
        val (start, end) = weekCalculator.weekRange(date)
        val week = WeekEntity(
            weekId = weekId,
            startDate = java.util.Date.from(start.atStartOfDay(zoneId).toInstant()),
            endDate = java.util.Date.from(end.atStartOfDay(zoneId).toInstant()),
            status = status
        )
        weekDao.upsert(week)
        // create 7 empty days
        repeat(7) { offset ->
            val dayDate = start.plusDays(offset.toLong())
            val day = DayEntity(
                dayId = dayDate.toString(),
                date = java.util.Date.from(dayDate.atStartOfDay(zoneId).toInstant()),
                dayOfWeek = dayDate.dayOfWeek.name.take(3),
                status = DayStatus.EMPTY,
                weekOwnerId = weekId
            )
            dayDao.upsert(day)
        }
        return week
    }

    // Simple fetch helpers used by StateMachine
    suspend fun getDay(dayId: String) = dayDao.findById(dayId)
    suspend fun getDayWithTasks(dayId: String) = dayDao.findWithTasks(dayId)
    suspend fun listDaysByWeek(weekId: String) = dayDao.listByWeek(weekId)
    suspend fun allWeeks() = weekDao.allWeeks()

    suspend fun createDraftDayIfNeeded(date: LocalDate) {
        val dayId = date.toString()
        val existing = dayDao.findById(dayId)
        if (existing != null) return
        val week = ensureWeek(date, WeekStatus.PRESENT)
        val day = DayEntity(
            dayId = dayId,
            date = java.util.Date.from(date.atStartOfDay(zoneId).toInstant()),
            dayOfWeek = date.dayOfWeek.name.take(3),
            status = DayStatus.DRAFT,
            weekOwnerId = week.weekId
        )
        dayDao.upsert(day)
    }

    suspend fun addDraftTasks(dayId: String, titles: List<String>) {
        val day = dayDao.findById(dayId) ?: return
        require(day.status == DayStatus.DRAFT || day.status == DayStatus.EMPTY)
        val currentMax = dayDao.findWithTasks(dayId)?.tasks?.maxOfOrNull { it.order } ?: 0
        titles.forEachIndexed { idx, title ->
            val task = TaskEntity(
                title = title,
                order = currentMax + idx + 1,
                dayOwnerId = dayId,
                zone = TaskZone.DRAFT
            )
            taskDao.upsert(task)
        }
        val newStatus = DayStatus.DRAFT
        dayDao.upsert(day.copy(status = newStatus))
    }

    suspend fun startDay(dayId: String, now: java.util.Date) {
        val day = dayDao.findWithTasks(dayId) ?: return
        require(day.day.status == DayStatus.DRAFT)
        val tasks = day.tasks.sortedBy { it.order }
        if (tasks.isEmpty()) throw IllegalStateException("Cannot start empty day")
        tasks.first().copy(zone = TaskZone.FOCUS, startedAt = now).also { taskDao.upsert(it) }
        tasks.drop(1).forEach { task -> taskDao.upsert(task.copy(zone = TaskZone.FROZEN)) }
        dayDao.upsert(day.day.copy(status = DayStatus.EXECUTE, initiatedAt = now))
    }

    suspend fun doneFocus(dayId: String, now: java.util.Date) {
        val day = dayDao.findWithTasks(dayId) ?: return
        val focus = day.tasks.firstOrNull { it.zone == TaskZone.FOCUS } ?: return
        val frozen = day.tasks.filter { it.zone == TaskZone.FROZEN }.sortedBy { it.order }
        val completedOrder = day.tasks.count { it.zone == TaskZone.COMPLETE } + 1
        taskDao.upsert(focus.copy(zone = TaskZone.COMPLETE, endedAt = now, completedOrder = completedOrder))
        if (frozen.isNotEmpty()) {
            val next = frozen.first()
            taskDao.upsert(next.copy(zone = TaskZone.FOCUS, startedAt = now))
            frozen.drop(1).forEach { rest -> taskDao.upsert(rest) }
        } else {
            dayDao.upsert(day.day.copy(status = DayStatus.COMPLETED, closedAt = now))
        }
    }

    suspend fun changeKillTime(dayId: String, hour: Int, minute: Int) {
        require(hour in 0..23) { "Kill Time hour must be between 0 and 23" }
        require(minute in 0..59) { "Kill Time minute must be between 0 and 59" }
        val day = dayDao.findById(dayId) ?: return
        if (day.status == DayStatus.EXPIRED || day.status == DayStatus.COMPLETED) return
        dayDao.upsert(day.copy(killHour = hour, killMinute = minute))
    }

    suspend fun expire(dayId: String, expiredCount: Int) {
        val day = dayDao.findById(dayId) ?: return
        dayDao.upsert(day.copy(status = DayStatus.EXPIRED, expiredCount = expiredCount))
        taskDao.deleteByZones(dayId, listOf(TaskZone.DRAFT.name, TaskZone.FOCUS.name, TaskZone.FROZEN.name))
    }

    suspend fun updateWeekSummary(weekId: String) {
        val week = weekDao.findWithDays(weekId) ?: return
        val completed = week.days.sumOf { day -> dayDao.findWithTasks(day.dayId)?.tasks?.count { it.zone == TaskZone.COMPLETE } ?: 0 }
        val expired = week.days.sumOf { it.expiredCount }
        val started = week.days.count { it.initiatedAt != null }
        val updated = week.week.copy(
            completedTasksCount = completed,
            expiredTasksCount = expired,
            totalStartedDays = started
        )
        weekDao.upsert(updated)
    }
    // endregion
}
