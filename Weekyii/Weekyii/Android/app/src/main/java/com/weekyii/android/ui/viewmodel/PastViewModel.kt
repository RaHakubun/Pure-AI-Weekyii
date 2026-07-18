package com.weekyii.android.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.ui.model.WeekUi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class PastViewModel(
    private val repo: WeekyiiRepository
) : ViewModel() {

    data class UiState(
        val pastWeeks: List<WeekUi> = emptyList(),
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
                val completed = weeks.sumOf { it.completedTasksCount }
                val expired = weeks.sumOf { it.expiredTasksCount }
                val total = completed + expired
                _state.value = UiState(
                    pastWeeks = weeks.sortedByDescending { it.startDate },
                    completedTasks = completed,
                    expiredTasks = expired,
                    startedDays = weeks.sumOf { it.totalStartedDays },
                    completionRate = if (total == 0) 0 else completed * 100 / total
                )
            }
        }
    }
}
