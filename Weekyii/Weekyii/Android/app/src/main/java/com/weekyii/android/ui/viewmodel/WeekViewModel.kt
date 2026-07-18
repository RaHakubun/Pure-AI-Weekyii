package com.weekyii.android.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.repository.TaskTypeDefinitionRepository
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.domain.TimeProvider
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.model.WeekUi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.UUID

class WeekViewModel(
    private val repo: WeekyiiRepository,
    private val timeProvider: TimeProvider,
    private val taskTypes: TaskTypeDefinitionRepository? = null
) : ViewModel() {
    enum class DisplayMode { CARDS, STRIPS, COLLAPSED }
    enum class DayHighlightKind { FOCUS, DRAFT, FROZEN, COMPLETED, EXPIRED, EMPTY }

    data class DaySummary(
        val highlightKind: DayHighlightKind,
        val highlightText: String,
        val draftCount: Int,
        val remainingCount: Int,
        val completedCount: Int,
        val forgottenCount: Int,
        val totalCount: Int
    )

    data class UiState(
        val presentWeek: WeekUi? = null,
        val selectedDayId: String? = null,
        val displayMode: DisplayMode = DisplayMode.CARDS,
        val currentDate: LocalDate = LocalDate.now(),
        val taskTypeDefinitions: List<TaskTypeDefinitionEntity> = emptyList(),
        val error: String? = null
    )

    private val _state = MutableStateFlow(UiState(currentDate = timeProvider.today))
    val state: StateFlow<UiState> = _state

    init {
        observeWeek()
        observeTaskTypes()
    }

    private fun observeWeek() {
        viewModelScope.launch {
            repo.observePresentWeek().collectLatest { weeks ->
                val week = weeks.firstOrNull()
                val selected = _state.value.selectedDayId?.takeIf { id -> week?.days?.any { it.dayId == id } == true }
                    ?: week?.days?.firstOrNull { it.date == timeProvider.today }?.dayId
                    ?: week?.days?.minByOrNull { it.date }?.dayId
                _state.value = _state.value.copy(presentWeek = week, selectedDayId = selected, error = null)
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

    companion object {
        fun buildDaySummary(day: DayUi): DaySummary {
            val sorted = day.tasks.sortedBy { it.order }
            val focus = sorted.firstOrNull { it.zone == TaskZone.FOCUS }
            val draft = sorted.firstOrNull { it.zone == TaskZone.DRAFT }
            val frozen = sorted.firstOrNull { it.zone == TaskZone.FROZEN }
            val completed = sorted.count { it.zone == TaskZone.COMPLETE }
            val remaining = sorted.count { it.zone == TaskZone.FOCUS || it.zone == TaskZone.FROZEN || it.zone == TaskZone.DRAFT }
            val (kind, text) = when {
                focus != null -> DayHighlightKind.FOCUS to focus.title
                draft != null -> DayHighlightKind.DRAFT to draft.title
                frozen != null -> DayHighlightKind.FROZEN to frozen.title
                completed > 0 -> DayHighlightKind.COMPLETED to "$completed 项已完成"
                day.expiredCount > 0 -> DayHighlightKind.EXPIRED to "${day.expiredCount} 项已过期"
                else -> DayHighlightKind.EMPTY to "当天暂无可展示内容"
            }
            return DaySummary(kind, text, sorted.count { it.zone == TaskZone.DRAFT }, remaining, completed, day.expiredCount, remaining + completed + day.expiredCount)
        }
    }

    fun selectDay(dayId: String) { _state.value = _state.value.copy(selectedDayId = dayId, error = null) }

    fun cycleDisplayMode() {
        val next = when (_state.value.displayMode) {
            DisplayMode.CARDS -> DisplayMode.STRIPS
            DisplayMode.STRIPS -> DisplayMode.COLLAPSED
            DisplayMode.COLLAPSED -> DisplayMode.CARDS
        }
        _state.value = _state.value.copy(displayMode = next)
    }

    fun setDisplayMode(mode: DisplayMode) { _state.value = _state.value.copy(displayMode = mode) }

    fun addDraftTask(dayId: String, title: String, description: String, typeIdRaw: String) {
        mutate {
            val definition = taskTypes?.resolve(typeIdRaw)
            repo.appendDraftTask(dayId, title, description, definition?.baseKind ?: TaskType.REGULAR, definition?.idRaw ?: typeIdRaw)
        }
    }

    fun updateDraftTask(dayId: String, task: TaskUi, title: String, description: String, typeIdRaw: String) {
        mutate {
            val definition = taskTypes?.resolve(typeIdRaw)
            repo.updateDraftTask(dayId, task.id, title, description, definition?.baseKind ?: task.taskType, definition?.idRaw ?: typeIdRaw)
        }
    }

    fun deleteDraftTask(dayId: String, taskId: UUID) { mutate { repo.deleteDraftTasks(dayId, listOf(taskId)) } }

    fun moveDraftTask(dayId: String, fromIndex: Int, toIndex: Int) { mutate { repo.moveDraftTask(dayId, fromIndex, toIndex) } }

    private fun mutate(block: suspend () -> Unit) {
        viewModelScope.launch {
            runCatching { block() }.onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }
}
