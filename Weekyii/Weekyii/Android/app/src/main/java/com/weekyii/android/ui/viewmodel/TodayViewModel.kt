package com.weekyii.android.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.data.repository.toUi
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.domain.TimeProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate

class TodayViewModel(
    private val repo: WeekyiiRepository,
    private val timeProvider: TimeProvider
) : ViewModel() {

    data class UiState(
        val date: LocalDate = LocalDate.now(),
        val day: DayUi? = null,
        val focus: TaskUi? = null,
        val frozen: List<TaskUi> = emptyList(),
        val complete: List<TaskUi> = emptyList(),
        val error: String? = null
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            val today = timeProvider.today
            repo.createDraftDayIfNeeded(today)
            val day = repo.getDayWithTasks(today.toString())
            val tasks = day?.tasks?.sortedBy { it.order } ?: emptyList()
            val focus = tasks.firstOrNull { it.zone.name == "FOCUS" }?.toUi()
            val frozen = tasks.filter { it.zone.name == "FROZEN" }.sortedBy { it.order }.map { it.toUi() }
            val complete = tasks.filter { it.zone.name == "COMPLETE" }.sortedBy { it.completedOrder }.map { it.toUi() }
            _state.value = UiState(
                date = today,
                day = day?.day?.toUi(tasks = tasks.map { it.toUi() }),
                focus = focus,
                frozen = frozen,
                complete = complete,
                error = null
            )
        }
    }

    fun createDraft(titles: List<String>) {
        viewModelScope.launch {
            repo.createDraftDayIfNeeded(timeProvider.today)
            repo.addDraftTasks(timeProvider.today.toString(), titles)
            refresh()
        }
    }

    fun startDay() {
        viewModelScope.launch {
            try {
                repo.startDay(timeProvider.today.toString(), timeProvider.now)
                refresh()
                appIncrementDayStarted()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    private suspend fun appIncrementDayStarted() {
        // placeholder, real increment由StateMachine的AppStateStore处理
    }

    fun doneFocus() {
        viewModelScope.launch {
            repo.doneFocus(timeProvider.today.toString(), timeProvider.now)
            refresh()
        }
    }

    fun changeKillTime(hour: Int, minute: Int) {
        viewModelScope.launch {
            repo.changeKillTime(timeProvider.today.toString(), hour, minute)
            refresh()
        }
    }
}
