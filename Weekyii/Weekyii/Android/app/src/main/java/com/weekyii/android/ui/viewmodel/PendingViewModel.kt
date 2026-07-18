package com.weekyii.android.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.data.repository.WeekCalculator
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.domain.TimeProvider
import com.weekyii.android.ui.model.WeekUi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.time.LocalDate

class PendingViewModel(
    private val repo: WeekyiiRepository,
    private val calculator: WeekCalculator,
    private val timeProvider: TimeProvider
) : ViewModel() {

    data class UiState(
        val pendingWeeks: List<WeekUi> = emptyList(),
        val error: String? = null
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    init { observePending() }

    private fun observePending() {
        viewModelScope.launch {
            repo.observePendingWeeks().collectLatest { weeks ->
                _state.value = UiState(pendingWeeks = weeks)
            }
        }
    }

    fun createWeekForDate(date: LocalDate) {
        viewModelScope.launch {
            val week = repo.ensureWeek(date, WeekStatus.PENDING)
            // week already created will be returned, no-op
        }
    }

    fun createWeekById(weekId: String) {
        viewModelScope.launch {
            val startDate = calculator.weekStartDate(weekId)
            if (startDate == null) {
                _state.value = _state.value.copy(error = "周格式无效")
                return@launch
            }
            repo.ensureWeek(startDate, WeekStatus.PENDING)
        }
    }
}
