package com.weekyii.android.ui.viewmodel

import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.model.WeekUi
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.YearMonth
import java.util.UUID

class PastViewModelTest {
    @Test
    fun monthlyStatsCountOnlyStartedDaysAndComputeFocusTime() {
        val completedTask = task("Done", TaskZone.COMPLETE, LocalDateTime.of(2026, 7, 20, 9, 0), LocalDateTime.of(2026, 7, 20, 10, 30))
        val week = week(
            days = listOf(
                day(LocalDate.of(2026, 7, 20), DayStatus.COMPLETED, listOf(completedTask), expired = 0, started = true),
                day(LocalDate.of(2026, 7, 21), DayStatus.EXPIRED, emptyList(), expired = 2, started = true),
                day(LocalDate.of(2026, 7, 22), DayStatus.DRAFT, listOf(task("Draft", TaskZone.DRAFT, null, null)), expired = 0, started = false)
            )
        )

        val stats = PastViewModel.buildStats(listOf(week), YearMonth.of(2026, 7))

        assertEquals(1, stats.totalCompletedTasks)
        assertEquals(2, stats.totalExpiredTasks)
        assertEquals(33, (stats.completionRate * 100).toInt())
        assertEquals(90, stats.totalFocusMinutes)
        assertEquals(2, stats.totalStartedDays)
    }

    @Test
    fun heatmapClassifiesExpiredAndCompletionBands() {
        assertEquals(PastViewModel.HeatmapStatus.EXPIRED, PastViewModel.heatmapStatus(0.9, expired = true))
        assertEquals(PastViewModel.HeatmapStatus.LOW, PastViewModel.heatmapStatus(0.2, expired = false))
        assertEquals(PastViewModel.HeatmapStatus.MID, PastViewModel.heatmapStatus(0.6, expired = false))
        assertEquals(PastViewModel.HeatmapStatus.HIGH, PastViewModel.heatmapStatus(0.9, expired = false))
        assertEquals(PastViewModel.HeatmapStatus.EMPTY, PastViewModel.heatmapStatus(null, expired = false))
    }

    private fun week(days: List<DayUi>) = WeekUi("2026-W30", LocalDate.of(2026, 7, 20), LocalDate.of(2026, 7, 26), com.weekyii.android.data.db.entities.WeekStatus.PAST, 0, 0, 2, days)

    private fun day(date: LocalDate, status: DayStatus, tasks: List<TaskUi>, expired: Int, started: Boolean) = DayUi(
        dayId = date.toString(), date = date, dayOfWeek = date.dayOfWeek.name.take(3), status = status,
        killHour = 20, killMinute = 0, followsDefaultKillTime = true, executionModeRaw = "strict", isDraftZoneUnlocked = false,
        initiatedAt = if (started) date.atTime(8, 0) else null, closedAt = null, expiredCount = expired, tasks = tasks
    )

    private fun task(title: String, zone: TaskZone, start: LocalDateTime?, end: LocalDateTime?) = TaskUi(
        UUID.randomUUID(), title, "", TaskType.REGULAR, "regular", 1, zone, start, end, 1, null
    )
}
