package com.weekyii.android.ui.viewmodel

import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.model.WeekUi
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth
import java.util.UUID

class PendingViewModelTest {
    @Test
    fun concentratedDeadlinesProduceDeadlineRushOutlook() {
        val week = weekWithTasks(
            mapOf(
                3L to listOf(TaskType.DDL, TaskType.DDL),
                4L to listOf(TaskType.DDL, TaskType.DDL)
            )
        )

        val outlook = PendingViewModel.buildWeekOutlook(week)

        assertEquals(PendingViewModel.WeekOutlookTone.DEADLINE_RUSH, outlook.tone)
        assertEquals(4, outlook.typeCounts.ddl)
        assertEquals(listOf("周四", "周五"), outlook.peakDays)
    }

    @Test
    fun monthCalendarStartsOnMondayAndCarriesTaskSummaries() {
        val month = YearMonth.of(2026, 8)
        val taskDate = LocalDate.of(2026, 8, 3)
        val summary = PendingViewModel.MonthDaySummary(
            date = taskDate,
            regularCount = 1,
            ddlCount = 2,
            leisureCount = 1,
            hasAnyRecord = true
        )

        val cells = PendingViewModel.buildMonthCells(month, mapOf(taskDate to summary))

        assertEquals(LocalDate.of(2026, 7, 27), cells.first().date)
        assertEquals(LocalDate.of(2026, 9, 6), cells.last().date)
        assertEquals(42, cells.size)
        assertEquals(summary, cells.single { it.date == taskDate }.summary)
        assertEquals(false, cells.first().isInSelectedMonth)
        assertEquals(true, cells.single { it.date == taskDate }.isInSelectedMonth)
    }

    private fun weekWithTasks(typesByOffset: Map<Long, List<TaskType>>): WeekUi {
        val start = LocalDate.of(2026, 7, 20)
        val days = (0L..6L).map { offset ->
            val date = start.plusDays(offset)
            DayUi(
                dayId = date.toString(),
                date = date,
                dayOfWeek = date.dayOfWeek.name.take(3),
                status = DayStatus.DRAFT,
                killHour = 20,
                killMinute = 0,
                followsDefaultKillTime = true,
                executionModeRaw = "strict",
                isDraftZoneUnlocked = false,
                initiatedAt = null,
                closedAt = null,
                expiredCount = 0,
                tasks = typesByOffset[offset].orEmpty().mapIndexed { index, type ->
                    TaskUi(
                        id = UUID.randomUUID(),
                        title = type.name,
                        description = "",
                        taskType = type,
                        taskTypeIdRaw = type.name.lowercase(),
                        order = index + 1,
                        zone = TaskZone.DRAFT,
                        startedAt = null,
                        endedAt = null,
                        completedOrder = 0,
                        projectId = null
                    )
                }
            )
        }
        return WeekUi("2026-W30", start, start.plusDays(6), WeekStatus.PENDING, 0, 0, 0, days)
    }
}
