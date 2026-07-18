package com.weekyii.android.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.WeekUi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.LocalDate
import java.time.YearMonth

class PastViewModel(private val repo: WeekyiiRepository) : ViewModel() {
    enum class DisplayMode { WEEK_LIST, MONTH }
    enum class HeatmapStatus { EMPTY, LOW, MID, HIGH, EXPIRED }

    data class Stats(
        val totalCompletedTasks: Int,
        val totalExpiredTasks: Int,
        val completionRate: Double,
        val totalFocusMinutes: Long,
        val averageTaskMinutes: Long,
        val totalStartedDays: Int
    )

    data class DayTaskPoint(val date: LocalDate, val label: String, val completedCount: Int, val expiredCount: Int)
    data class HeatmapPoint(val date: LocalDate, val status: HeatmapStatus)
    data class MonthDaySummary(val date: LocalDate, val completedCount: Int, val expiredCount: Int, val hasRecord: Boolean)

    data class UiState(
        val pastWeeks: List<WeekUi> = emptyList(),
        val selectedMonth: YearMonth = YearMonth.now(),
        val selectedDate: LocalDate = LocalDate.now(),
        val displayMode: DisplayMode = DisplayMode.WEEK_LIST,
        val monthWeeks: List<WeekUi> = emptyList(),
        val monthDays: List<DayUi> = emptyList(),
        val monthSummaries: List<MonthDaySummary> = emptyList(),
        val stats: Stats = Stats(0, 0, 0.0, 0, 0, 0),
        val trend: List<DayTaskPoint> = emptyList(),
        val heatmap: List<HeatmapPoint> = emptyList(),
        val completedTasks: Int = 0,
        val expiredTasks: Int = 0,
        val startedDays: Int = 0,
        val completionRate: Int = 0
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    init {
        viewModelScope.launch {
            repo.observePastWeeks().collectLatest { weeks ->
                recompute(weeks)
            }
        }
    }

    companion object {
        fun heatmapStatus(completionRate: Double?, expired: Boolean): HeatmapStatus = when {
            expired -> HeatmapStatus.EXPIRED
            completionRate == null -> HeatmapStatus.EMPTY
            completionRate < .5 -> HeatmapStatus.LOW
            completionRate < .8 -> HeatmapStatus.MID
            else -> HeatmapStatus.HIGH
        }

        fun buildStats(weeks: List<WeekUi>, month: YearMonth): Stats {
            val days = weeks.flatMap { it.days }.filter { YearMonth.from(it.date) == month }
            val started = days.filter { it.initiatedAt != null || it.status in setOf(DayStatus.EXECUTE, DayStatus.COMPLETED, DayStatus.EXPIRED) }
            val completed = started.sumOf { day -> day.tasks.count { it.zone == TaskZone.COMPLETE } }
            val expired = started.sumOf { it.expiredCount }
            val completedTasks = started.flatMap { day -> day.tasks.filter { it.zone == TaskZone.COMPLETE } }
            val durations = completedTasks.mapNotNull { task ->
                val start = task.startedAt
                val end = task.endedAt
                if (start != null && end != null) Duration.between(start, end).toMinutes() else null
            }
            val totalMinutes = durations.sum()
            return Stats(
                totalCompletedTasks = completed,
                totalExpiredTasks = expired,
                completionRate = if (completed + expired == 0) 0.0 else completed.toDouble() / (completed + expired),
                totalFocusMinutes = totalMinutes,
                averageTaskMinutes = if (durations.isEmpty()) 0 else totalMinutes / durations.size,
                totalStartedDays = started.size
            )
        }
    }

    private fun recompute(weeks: List<WeekUi>) {
        val current = _state.value
        val month = current.selectedMonth
        val monthWeeks = weeks.filter { it.startDate <= month.atEndOfMonth() && it.endDate >= month.atDay(1) }
        val monthDays = monthWeeks.flatMap { it.days }.filter { YearMonth.from(it.date) == month }.distinctBy { it.dayId }.sortedBy { it.date }
        val summaries = monthDays.map { day ->
            MonthDaySummary(day.date, day.tasks.count { it.zone == TaskZone.COMPLETE }, day.expiredCount, day.status != DayStatus.EMPTY || day.tasks.isNotEmpty() || day.expiredCount > 0)
        }
        val trend = month.atEndOfMonth().let { end ->
            (1..end.dayOfMonth).map { dayOfMonth ->
                val date = month.atDay(dayOfMonth)
                val day = monthDays.firstOrNull { it.date == date }
                DayTaskPoint(date, dayOfMonth.toString(), day?.tasks?.count { it.zone == TaskZone.COMPLETE } ?: 0, day?.expiredCount ?: 0)
            }
        }
        val heatmap = buildHeatmap(month, monthDays)
        val stats = buildStats(weeks, month)
        _state.value = current.copy(
            pastWeeks = weeks.sortedByDescending { it.startDate },
            monthWeeks = monthWeeks.sortedBy { it.startDate },
            monthDays = monthDays,
            monthSummaries = summaries,
            stats = stats,
            completedTasks = stats.totalCompletedTasks,
            expiredTasks = stats.totalExpiredTasks,
            startedDays = stats.totalStartedDays,
            completionRate = (stats.completionRate * 100).toInt(),
            trend = trend,
            heatmap = heatmap
        )
    }

    private fun buildHeatmap(month: YearMonth, days: List<DayUi>): List<HeatmapPoint> {
        val start = month.atDay(1).minusDays((month.atDay(1).dayOfWeek.value - 1).toLong())
        val end = month.atEndOfMonth().plusDays((7 - month.atEndOfMonth().dayOfWeek.value).toLong())
        return generateSequence(start) { it.plusDays(1) }.takeWhile { !it.isAfter(end) }.map { date ->
            val day = days.firstOrNull { it.date == date }
            val completed = day?.tasks?.count { it.zone == TaskZone.COMPLETE } ?: 0
            val expired = day?.expiredCount ?: 0
            val rate = if (completed + expired == 0) null else completed.toDouble() / (completed + expired)
            HeatmapPoint(date, heatmapStatus(rate, day?.status == DayStatus.EXPIRED))
        }.toList()
    }

    fun previousMonth() { _state.value = _state.value.copy(selectedMonth = _state.value.selectedMonth.minusMonths(1), selectedDate = _state.value.selectedMonth.minusMonths(1).atDay(1)); recompute(_state.value.pastWeeks) }
    fun nextMonth() { _state.value = _state.value.copy(selectedMonth = _state.value.selectedMonth.plusMonths(1), selectedDate = _state.value.selectedMonth.plusMonths(1).atDay(1)); recompute(_state.value.pastWeeks) }
    fun setDisplayMode(mode: DisplayMode) { _state.value = _state.value.copy(displayMode = mode) }
    fun selectDate(date: LocalDate) { _state.value = _state.value.copy(selectedDate = date) }

}
