package com.weekyii.android.domain

import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.data.repository.WeekyiiRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.Date

class StateMachine(
    private val repo: WeekyiiRepository,
    private val timeProvider: TimeProvider,
    private val appState: AppStateStore,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default)
) {
    fun processStateTransitions() {
        scope.launch { process() }
    }

    private suspend fun process() {
        ensureSystemStartDate()
        processStaleOpenDaysBeforeToday()
        processCrossDay()
        processCrossWeek()
        processKillTime()
        refreshWeekSummaryMetrics()
        appState.setLastProcessedDate(timeProvider.today)
        appState.setLastRollover(timeProvider.nowInstant.atZone(timeProvider.zoneId).toLocalDateTime())
    }

    private suspend fun ensureSystemStartDate() {
        if (appState.systemStartDate.value == null) {
            appState.setSystemStartDate(timeProvider.today)
        }
        if (appState.lastProcessedDate.value == null) {
            appState.setLastProcessedDate(timeProvider.today)
            appState.setLastRollover(timeProvider.nowInstant.atZone(timeProvider.zoneId).toLocalDateTime())
        }
    }

    private suspend fun processCrossDay() {
        val lastProcessed = appState.lastProcessedDate.value ?: return
        val today = timeProvider.today
        if (!today.isAfter(lastProcessed)) return

        var cursor = lastProcessed
        while (cursor.isBefore(today)) {
            val dayId = cursor.toString()
            val day = repo.getDay(dayId)
            if (day != null) {
                when (day.status) {
                    DayStatus.EXECUTE -> repo.expire(dayId, expiredCount(dayId))
                    DayStatus.DRAFT -> repo.expire(dayId, 0)
                    else -> {}
                }
            }
            cursor = cursor.plusDays(1)
        }
    }

    private suspend fun expiredCount(dayId: String): Int {
        val day = repo.getDayWithTasks(dayId) ?: return 0
        val focus = day.tasks.count { it.zone == TaskZone.FOCUS }
        val frozen = day.tasks.count { it.zone == TaskZone.FROZEN }
        return focus + frozen
    }

    private suspend fun processStaleOpenDaysBeforeToday() {
        val today = timeProvider.today
        repo.listDaysByWeek(timeProvider.currentWeekId).forEach { day ->
            if (day.date.toInstant().atZone(timeProvider.zoneId).toLocalDate() < today) {
                if (day.status == DayStatus.EXECUTE || day.status == DayStatus.DRAFT) {
                    val count = if (day.status == DayStatus.DRAFT) 0 else expiredCount(day.dayId)
                    repo.expire(day.dayId, count)
                }
            }
        }
    }

    private suspend fun processCrossWeek() {
        val currentWeekId = timeProvider.currentWeekId
        // Ensure current week present
        repo.ensureWeek(timeProvider.today, WeekStatus.PRESENT)
        val presentWeeks = repo.allWeeks().filter { it.status == WeekStatus.PRESENT }
        presentWeeks.filter { it.weekId != currentWeekId }.forEach {
            repo.weekDao.upsert(it.copy(status = WeekStatus.PAST))
        }
    }

    private suspend fun processKillTime() {
        val todayId = timeProvider.today.toString()
        val day = repo.getDay(todayId) ?: return
        if (day.status != DayStatus.EXECUTE && day.status != DayStatus.DRAFT) return
        val killDate = buildKillDate(day.killHour, day.killMinute, timeProvider.today)
        if (timeProvider.now.after(killDate)) {
            val expired = if (day.status == DayStatus.DRAFT) 0 else expiredCount(day.dayId)
            repo.expire(day.dayId, expired)
        }
    }

    private fun buildKillDate(hour: Int, minute: Int, date: LocalDate): Date {
        val dt = date.atTime(hour, minute)
        return Date.from(dt.atZone(timeProvider.zoneId).toInstant())
    }

    private suspend fun refreshWeekSummaryMetrics() {
        val weeks = repo.allWeeks()
        weeks.forEach { repo.updateWeekSummary(it.weekId) }
    }
}
