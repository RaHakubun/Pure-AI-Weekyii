package com.weekyii.android.ui.viewmodel

import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.util.UUID

class WeekViewModelTest {
    @Test
    fun daySummaryPrioritizesFocusAndCountsForgottenTasks() {
        val day = day(
            status = DayStatus.EXECUTE,
            expiredCount = 2,
            tasks = listOf(
                task("Later", TaskZone.FROZEN, 2),
                task("Now", TaskZone.FOCUS, 1),
                task("Done", TaskZone.COMPLETE, 3)
            )
        )

        val summary = WeekViewModel.buildDaySummary(day)

        assertEquals(WeekViewModel.DayHighlightKind.FOCUS, summary.highlightKind)
        assertEquals("Now", summary.highlightText)
        assertEquals(2, summary.remainingCount)
        assertEquals(1, summary.completedCount)
        assertEquals(2, summary.forgottenCount)
    }

    @Test
    fun completedDayFallsBackToCompletionSummary() {
        val summary = WeekViewModel.buildDaySummary(
            day(DayStatus.COMPLETED, tasks = listOf(task("Done", TaskZone.COMPLETE, 1)))
        )

        assertEquals(WeekViewModel.DayHighlightKind.COMPLETED, summary.highlightKind)
        assertEquals("1 项已完成", summary.highlightText)
    }

    private fun day(
        status: DayStatus,
        expiredCount: Int = 0,
        tasks: List<TaskUi> = emptyList()
    ) = DayUi(
        dayId = "2026-07-20",
        date = LocalDate.of(2026, 7, 20),
        dayOfWeek = "MON",
        status = status,
        killHour = 20,
        killMinute = 0,
        followsDefaultKillTime = true,
        executionModeRaw = "strict",
        isDraftZoneUnlocked = false,
        initiatedAt = null,
        closedAt = null,
        expiredCount = expiredCount,
        tasks = tasks
    )

    private fun task(title: String, zone: TaskZone, order: Int) = TaskUi(
        id = UUID.randomUUID(),
        title = title,
        description = "",
        taskType = TaskType.REGULAR,
        taskTypeIdRaw = "regular",
        order = order,
        zone = zone,
        startedAt = null,
        endedAt = null,
        completedOrder = if (zone == TaskZone.COMPLETE) order else 0,
        projectId = null
    )
}
