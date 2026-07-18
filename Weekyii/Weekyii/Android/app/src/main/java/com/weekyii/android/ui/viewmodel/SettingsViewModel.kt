package com.weekyii.android.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekyii.android.data.db.entities.ExecutionMode
import com.weekyii.android.domain.UserSettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.time.LocalTime

class SettingsViewModel(
    private val settings: UserSettingsStore
) : ViewModel() {
    data class UiState(
        val defaultKillTime: LocalTime = LocalTime.of(20, 0),
        val defaultExecutionMode: ExecutionMode = ExecutionMode.STRICT,
        val error: String? = null
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    init {
        viewModelScope.launch {
            combine(settings.defaultKillTime, settings.defaultExecutionMode) { time, mode -> time to mode }
                .collect { (time, mode) -> _state.value = UiState(time, mode) }
        }
    }

    fun setDefaultKillTime(time: LocalTime) {
        viewModelScope.launch {
            runCatching { settings.setDefaultKillTime(time) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun setDefaultExecutionMode(mode: ExecutionMode) {
        viewModelScope.launch {
            runCatching { settings.setDefaultExecutionMode(mode) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }
}
