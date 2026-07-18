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
        val pastWeeks: List<WeekUi> = emptyList()
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    init {
        viewModelScope.launch {
            repo.observePastWeeks().collectLatest { weeks ->
                _state.value = UiState(pastWeeks = weeks)
            }
        }
    }
}
