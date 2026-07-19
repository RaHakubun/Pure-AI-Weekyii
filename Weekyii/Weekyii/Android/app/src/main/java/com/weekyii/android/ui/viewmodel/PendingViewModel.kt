package com.weekyii.android.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.repository.WeekCalculator
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.data.repository.TaskTypeDefinitionRepository
import com.weekyii.android.domain.TimeProvider
import com.weekyii.android.domain.UserSettingsStore
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.model.WeekUi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth
import java.time.DayOfWeek
import java.time.temporal.TemporalAdjusters
import java.util.UUID

class PendingViewModel(
    private val repo: WeekyiiRepository,
    private val calculator: WeekCalculator,
    private val timeProvider: TimeProvider,
    private val taskTypes: TaskTypeDefinitionRepository? = null,
    private val settings: UserSettingsStore? = null
) : ViewModel() {

    enum class WeekOutlookTone {
        RELAXED, STEADY, FRONT_LOOSE_BACK_TIGHT, MIDWEEK_CONGESTION, DEADLINE_RUSH, OVERLOAD_WARNING
    }

    data class WeekTypeCounts(val regular: Int, val ddl: Int, val leisure: Int)

    data class WeekOutlookSnapshot(
        val tone: WeekOutlookTone,
        val headline: String,
        val advice: String,
        val typeCounts: WeekTypeCounts,
        val peakDays: List<String>,
        val dayLoadSeries: List<Double>
    )

    data class MonthDaySummary(
        val date: LocalDate,
        val regularCount: Int,
        val ddlCount: Int,
        val leisureCount: Int,
        val hasAnyRecord: Boolean
    ) {
        val taskCount: Int get() = regularCount + ddlCount + leisureCount
    }

    data class MonthCell(
        val date: LocalDate,
        val isInSelectedMonth: Boolean,
        val summary: MonthDaySummary?
    )

    data class UiState(
        val pendingWeeks: List<WeekUi> = emptyList(),
        val nextWeekId: String = "",
        val currentDate: LocalDate = LocalDate.now(),
        val selectedMonth: YearMonth = YearMonth.now(),
        val selectedWeekId: String? = null,
        val selectedDayId: String? = null,
        val taskTypeDefinitions: List<TaskTypeDefinitionEntity> = emptyList(),
        val weekStartsOnMonday: Boolean = true,
        val pendingMonthShowRegular: Boolean = false,
        val pendingMonthShowDDL: Boolean = true,
        val pendingMonthShowLeisure: Boolean = false,
        val error: String? = null
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    companion object {
        fun buildMonthCells(
            month: YearMonth,
            summaries: Map<LocalDate, MonthDaySummary>,
            startsOnMonday: Boolean = true
        ): List<MonthCell> {
            val startDay = if (startsOnMonday) DayOfWeek.MONDAY else DayOfWeek.SUNDAY
            val endDay = if (startsOnMonday) DayOfWeek.SUNDAY else DayOfWeek.SATURDAY
            val first = month.atDay(1).with(TemporalAdjusters.previousOrSame(startDay))
            val last = month.atEndOfMonth().with(TemporalAdjusters.nextOrSame(endDay))
            return generateSequence(first) { date -> date.plusDays(1) }
                .takeWhile { date -> !date.isAfter(last) }
                .map { date ->
                    MonthCell(
                        date = date,
                        isInSelectedMonth = YearMonth.from(date) == month,
                        summary = summaries[date]
                    )
                }
                .toList()
        }

        fun buildWeekOutlook(week: WeekUi): WeekOutlookSnapshot {
            val sortedDays = week.days.sortedBy { it.date }
            val regularSeries = sortedDays.map { day -> day.tasks.count { it.taskType == TaskType.REGULAR } }
            val ddlSeries = sortedDays.map { day -> day.tasks.count { it.taskType == TaskType.DDL } }
            val leisureSeries = sortedDays.map { day -> day.tasks.count { it.taskType == TaskType.LEISURE } }
            val dayLoadSeries = regularSeries.indices.map { index ->
                regularSeries[index].toDouble() + ddlSeries[index] * 2.0 + leisureSeries[index] * 0.6
            }
            val totalRegular = regularSeries.sum()
            val totalDDL = ddlSeries.sum()
            val totalLeisure = leisureSeries.sum()
            val totalLoad = dayLoadSeries.sum()
            val peakLoad = dayLoadSeries.maxOrNull() ?: 0.0
            val activeDays = dayLoadSeries.count { it > 0 }
            val maxPairDDL = if (ddlSeries.size >= 2) {
                ddlSeries.zipWithNext { left, right -> left + right }.maxOrNull() ?: 0
            } else ddlSeries.firstOrNull() ?: 0
            val ddlClusterRatio = if (totalDDL > 0) maxPairDDL.toDouble() / totalDDL else 0.0
            val midweekLoad = dayLoadSeries.withIndex().filter { it.index in 2..4 }.sumOf { it.value }
            val midweekShare = if (totalLoad > 0) midweekLoad / totalLoad else 0.0
            val frontLoad = dayLoadSeries.take(3).sum()
            val backLoad = dayLoadSeries.takeLast(4).sum()
            val backVsFrontGapRatio = if (frontLoad > 0) (backLoad - frontLoad) / frontLoad else 0.0
            val peakIndices = dayLoadSeries.withIndex()
                .filter { it.value > 0 && it.value == peakLoad }
                .map { it.index }
                .take(2)
            val labels = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
            val peakDays = peakIndices.map { labels.getOrElse(it) { "" } }
            val peakText = if (peakDays.isEmpty()) "节奏分布较均匀" else "高压在${peakDays.joinToString("/")}"
            val tone = when {
                peakLoad >= 8 || totalLoad >= 28 -> WeekOutlookTone.OVERLOAD_WARNING
                totalDDL >= 4 && ddlClusterRatio >= 0.6 -> WeekOutlookTone.DEADLINE_RUSH
                midweekShare >= 0.6 -> WeekOutlookTone.MIDWEEK_CONGESTION
                backLoad > frontLoad && backVsFrontGapRatio >= 0.3 -> WeekOutlookTone.FRONT_LOOSE_BACK_TIGHT
                totalLoad <= 6 && totalDDL <= 1 -> WeekOutlookTone.RELAXED
                else -> WeekOutlookTone.STEADY
            }
            val (headline, advice) = when (tone) {
                WeekOutlookTone.RELAXED ->
                    if (activeDays == 0) "这一周任务较空，适合先定一个主目标" to "保持节奏并留1天机动"
                    else "整体负载偏轻，按节奏推进即可" to "保持节奏并留1天机动"
                WeekOutlookTone.STEADY ->
                    (if (peakDays.isEmpty()) "节奏平稳，可按日常推进" else "$peakText，整体可控") to "每天推进1-2个关键项"
                WeekOutlookTone.FRONT_LOOSE_BACK_TIGHT -> "后半周会明显变紧，建议提前启动关键事项" to "周一周二先清关键任务"
                WeekOutlookTone.MIDWEEK_CONGESTION -> "周中任务明显聚集，$peakText" to "把周中任务前移一天"
                WeekOutlookTone.DEADLINE_RUSH -> "DDL集中出现，$peakText" to "先做DDL，再推进常规"
                WeekOutlookTone.OVERLOAD_WARNING -> "本周负载偏高，$peakText" to "建议拆分或减载安排"
            }
            return WeekOutlookSnapshot(
                tone = tone,
                headline = headline,
                advice = advice,
                typeCounts = WeekTypeCounts(totalRegular, totalDDL, totalLeisure),
                peakDays = peakDays,
                dayLoadSeries = dayLoadSeries
            )
        }
    }

    init {
        _state.value = _state.value.copy(
            currentDate = timeProvider.today,
            selectedMonth = YearMonth.from(timeProvider.today)
        )
        observePending()
        observeTaskTypes()
        observeSettings()
    }

    private fun observeSettings() {
        val store = settings ?: return
        viewModelScope.launch {
            kotlinx.coroutines.flow.combine(
                store.weekStartsOnMonday,
                store.pendingMonthShowRegular,
                store.pendingMonthShowDDL,
                store.pendingMonthShowLeisure
            ) { startsOnMonday, showRegular, showDDL, showLeisure ->
                listOf(startsOnMonday, showRegular, showDDL, showLeisure)
            }.collectLatest { values ->
                _state.value = _state.value.copy(
                    weekStartsOnMonday = values[0],
                    pendingMonthShowRegular = values[1],
                    pendingMonthShowDDL = values[2],
                    pendingMonthShowLeisure = values[3]
                )
            }
        }
    }

    private fun observeTaskTypes() {
        val repository = taskTypes ?: return
        viewModelScope.launch {
            repository.seedBuiltIns()
            repository.observeActive().collectLatest { definitions ->
                _state.value = _state.value.copy(taskTypeDefinitions = definitions)
            }
        }
    }

    private fun observePending() {
        viewModelScope.launch {
            repo.observePlanningWeeks().collectLatest { weeks ->
                val sorted = weeks.sortedBy { it.startDate }
                val current = _state.value
                val selectedWeek = current.selectedWeekId?.takeIf { id -> sorted.any { it.weekId == id } }
                val selectedDay = current.selectedDayId?.takeIf { dayId -> sorted.any { week -> week.days.any { it.dayId == dayId } } }
                _state.value = _state.value.copy(
                    pendingWeeks = sorted,
                    nextWeekId = calculator.weekId(timeProvider.today.plusWeeks(1)),
                    selectedWeekId = selectedWeek,
                    selectedDayId = selectedDay,
                    error = null
                )
            }
        }
    }

    fun selectPreviousMonth() {
        _state.value = _state.value.copy(selectedMonth = _state.value.selectedMonth.minusMonths(1))
    }

    fun selectNextMonth() {
        _state.value = _state.value.copy(selectedMonth = _state.value.selectedMonth.plusMonths(1))
    }

    fun weeksInSelectedMonth(): List<WeekUi> {
        val month = _state.value.selectedMonth
        val start = month.atDay(1)
        val end = month.plusMonths(1).atDay(1)
        return _state.value.pendingWeeks.filter { it.startDate < end && !it.endDate.isBefore(start) }
    }

    fun monthDaySummaries(): Map<LocalDate, MonthDaySummary> {
        val month = _state.value.selectedMonth
        return _state.value.pendingWeeks.flatMap { it.days }
            .filter { YearMonth.from(it.date) == month }
            .associate { day ->
                val regular = day.tasks.count { it.taskType == TaskType.REGULAR }
                val ddl = day.tasks.count { it.taskType == TaskType.DDL }
                val leisure = day.tasks.count { it.taskType == TaskType.LEISURE }
                day.date to MonthDaySummary(
                    date = day.date,
                    regularCount = regular,
                    ddlCount = ddl,
                    leisureCount = leisure,
                    hasAnyRecord = day.status != DayStatus.EMPTY || day.tasks.isNotEmpty()
                )
            }
    }

    fun openWeek(weekId: String, preferredDayId: String? = null) {
        val week = _state.value.pendingWeeks.firstOrNull { it.weekId == weekId } ?: return
        val dayId = preferredDayId?.takeIf { id -> week.days.any { it.dayId == id } }
            ?: week.days.firstOrNull { it.status == DayStatus.DRAFT }?.dayId
            ?: week.days.minByOrNull { it.date }?.dayId
        _state.value = _state.value.copy(selectedWeekId = weekId, selectedDayId = dayId, error = null)
    }

    fun closeWeek() {
        _state.value = _state.value.copy(selectedWeekId = null, selectedDayId = null, error = null)
    }

    fun selectDay(dayId: String) {
        _state.value = _state.value.copy(selectedDayId = dayId, error = null)
    }

    fun openOrCreateDate(date: LocalDate) {
        viewModelScope.launch {
            runCatching {
                require(!date.isBefore(timeProvider.today)) { "过去日期不可添加任务" }
                val status = if (calculator.weekId(date) == timeProvider.currentWeekId) WeekStatus.PRESENT else WeekStatus.PENDING
                repo.ensureWeek(date, status)
            }.onFailure {
                _state.value = _state.value.copy(error = it.message)
            }.onSuccess {
                val weekId = calculator.weekId(date)
                _state.value = _state.value.copy(selectedWeekId = weekId, selectedDayId = date.toString(), error = null)
            }
        }
    }

    fun addDraftTask(dayId: String, title: String, description: String, typeIdRaw: String) {
        viewModelScope.launch {
            runCatching {
                val definition = taskTypes?.resolve(typeIdRaw)
                repo.appendDraftTask(
                    dayId = dayId,
                    title = title,
                    description = description,
                    taskType = definition?.baseKind ?: TaskType.REGULAR,
                    taskTypeIdRaw = definition?.idRaw ?: typeIdRaw
                )
            }.onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun updateDraftTask(dayId: String, task: TaskUi, title: String, description: String, typeIdRaw: String) {
        viewModelScope.launch {
            runCatching {
                val definition = taskTypes?.resolve(typeIdRaw)
                repo.updateDraftTask(
                    dayId = dayId,
                    taskId = task.id,
                    title = title,
                    description = description,
                    taskType = definition?.baseKind ?: task.taskType,
                    taskTypeIdRaw = definition?.idRaw ?: typeIdRaw
                )
            }.onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun deleteDraftTask(dayId: String, taskId: UUID) {
        viewModelScope.launch {
            runCatching { repo.deleteDraftTasks(dayId, listOf(taskId)) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun moveDraftTask(dayId: String, fromIndex: Int, toIndex: Int) {
        viewModelScope.launch {
            runCatching { repo.moveDraftTask(dayId, fromIndex, toIndex) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun createWeekForDate(date: LocalDate) {
        viewModelScope.launch {
            if (date.isBefore(timeProvider.today)) {
                _state.value = _state.value.copy(error = "只能创建今天或未来日期所属的周")
                return@launch
            }
            repo.ensureWeek(date, WeekStatus.PENDING)
            _state.value = _state.value.copy(error = null)
        }
    }

    fun createNextWeek() = createWeekForDate(timeProvider.today.plusWeeks(1))

    fun createWeekById(weekId: String) {
        viewModelScope.launch {
            val startDate = calculator.weekStartDate(weekId)
            if (startDate == null) {
                _state.value = _state.value.copy(error = "周格式无效")
                return@launch
            }
            if (!startDate.isAfter(timeProvider.today)) {
                _state.value = _state.value.copy(error = "只能创建未来周")
                return@launch
            }
            repo.ensureWeek(startDate, WeekStatus.PENDING)
            _state.value = _state.value.copy(error = null)
        }
    }
}
