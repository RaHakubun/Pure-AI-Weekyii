package com.weekyii.android.domain

import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.data.repository.SuspendedTaskSweeper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Date

data class StateReconcileReport(
    val skipped: Boolean = false,
    val processedAt: LocalDateTime? = null,
    val staleDaysExpiredCount: Int = 0,
    val crossDayExpiredCount: Int = 0,
    val crossWeekAdjustedCount: Int = 0,
    val killTimeExpiredCount: Int = 0,
    val suspendedAutoDeletedCount: Int = 0
)

class StateMachine(
    private val repo: WeekyiiRepository,
    private val timeProvider: TimeProvider,
    private val appState: AppStateStore,
    private val settings: UserSettingsStore? = null,
    private val suspendedTaskSweeper: SuspendedTaskSweeper? = null,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default)
) {
    private val reconcileMutex = Mutex()

    fun processStateTransitions() {
        scope.launch { reconcile() }
    }

    suspend fun reconcile(force: Boolean = false): StateReconcileReport = reconcileMutex.withLock {
        val now = timeProvider.nowInstant.atZone(timeProvider.zoneId).toLocalDateTime()
        if (!force && shouldSkipReconcile(now)) {
            return@withLock StateReconcileReport(skipped = true, processedAt = now)
        }

        val lastProcessedBeforeRun = appState.lastProcessedDate.value
        ensureSystemStartDate(now)
        val staleDays = processStaleOpenDaysBeforeToday()
        val crossDay = processCrossDay()
        val crossWeek = processCrossWeek()
        syncTodayDefaultKillTime(lastProcessedBeforeRun)
        repo.normalizeExecutionState(timeProvider.today.toString(), timeProvider.now)
        val killTime = processKillTime()
        val suspendedDeleted = suspendedTaskSweeper?.sweep(timeProvider.now) ?: 0
        refreshWeekSummaryMetrics()
        appState.setLastProcessedDate(timeProvider.today)
        appState.setLastRollover(now)
        appState.bumpStateTransitionRevision()
        return@withLock StateReconcileReport(
            processedAt = now,
            staleDaysExpiredCount = staleDays,
            crossDayExpiredCount = crossDay,
            crossWeekAdjustedCount = crossWeek,
            killTimeExpiredCount = killTime,
            suspendedAutoDeletedCount = suspendedDeleted
        )
    }

    private suspend fun syncTodayDefaultKillTime(lastProcessedBeforeRun: LocalDate?) {
        val settings = settings ?: return
        val shouldSync = lastProcessedBeforeRun == null || timeProvider.today.isAfter(lastProcessedBeforeRun)
        if (!shouldSync) return
        val time = settings.defaultKillTime.value
        repo.syncDefaultKillTime(timeProvider.today.toString(), time.hour, time.minute)
    }

    private suspend fun ensureSystemStartDate(now: LocalDateTime) {
        if (appState.systemStartDate.value == null) {
            appState.setSystemStartDate(timeProvider.today)
        }
        if (appState.lastProcessedDate.value == null) {
            appState.setLastProcessedDate(timeProvider.today)
            appState.setLastRollover(now)
        }
    }

    private suspend fun processCrossDay(): Int {
        val lastProcessed = appState.lastProcessedDate.value ?: return 0
        val today = timeProvider.today
        if (!today.isAfter(lastProcessed)) return 0

        var cursor = lastProcessed
        var expired = 0
        while (cursor.isBefore(today)) {
            val dayId = cursor.toString()
            val day = repo.getDay(dayId)
            if (day != null) {
                val count = when (day.status) {
                    DayStatus.EXECUTE -> expiredCount(dayId)
                    DayStatus.DRAFT -> 0
                    else -> null
                }
                if (count != null) {
                    repo.expire(dayId, count)
                    expired += 1
                }
            }
            cursor = cursor.plusDays(1)
        }
        return expired
    }

    private suspend fun processStaleOpenDaysBeforeToday(): Int {
        val today = timeProvider.today
        var expired = 0
        for (day in repo.allDays()) {
            val dayDate = day.date.toLocalDate(timeProvider.zoneId)
            if (dayDate.isBefore(today) && (day.status == DayStatus.EXECUTE || day.status == DayStatus.DRAFT)) {
                val count = if (day.status == DayStatus.EXECUTE) expiredCount(day.dayId) else 0
                repo.expire(day.dayId, count)
                expired += 1
            }
        }
        return expired
    }

    private suspend fun processCrossWeek(): Int {
        val today = timeProvider.today
        var adjustments = 0

        for (week in repo.allWeeks()) {
            if (week.status == WeekStatus.PENDING && week.endDate.toLocalDate(timeProvider.zoneId).isBefore(today)) {
                repo.moveWeekToPast(week.weekId)
                adjustments += 1
            }
        }

        val currentWeek = repo.ensureWeek(today, WeekStatus.PRESENT)
        for (week in repo.allWeeks()) {
            if (week.status == WeekStatus.PRESENT && week.weekId != currentWeek.weekId) {
                repo.moveWeekToPast(week.weekId)
                adjustments += 1
            }
        }
        return adjustments
    }

    private suspend fun processKillTime(): Int {
        val day = repo.getDay(timeProvider.today.toString()) ?: return 0
        if (day.status != DayStatus.EXECUTE && day.status != DayStatus.DRAFT) return 0
        val killDate = timeProvider.today
            .atTime(day.killHour, day.killMinute)
            .atZone(timeProvider.zoneId)
            .toInstant()
        if (timeProvider.nowInstant >= killDate) {
            val count = if (day.status == DayStatus.EXECUTE) expiredCount(day.dayId) else 0
            repo.expire(day.dayId, count)
            return 1
        }
        return 0
    }

    private suspend fun expiredCount(dayId: String): Int {
        val day = repo.getDayWithTasks(dayId) ?: return 0
        return day.tasks.count { it.zone == TaskZone.FOCUS || it.zone == TaskZone.FROZEN }
    }

    private suspend fun refreshWeekSummaryMetrics() {
        repo.allWeeks().forEach { repo.updateWeekSummary(it.weekId) }
    }

    private fun shouldSkipReconcile(now: LocalDateTime): Boolean {
        val lastDate = appState.lastProcessedDate.value ?: return false
        val lastRollover = appState.lastRolloverAt.value ?: return false
        return lastDate == timeProvider.today &&
            lastRollover.toLocalDate() == now.toLocalDate() &&
            lastRollover.hour == now.hour &&
            lastRollover.minute == now.minute
    }
}

private fun Date.toLocalDate(zoneId: ZoneId): LocalDate =
    toInstant().atZone(zoneId).toLocalDate()
