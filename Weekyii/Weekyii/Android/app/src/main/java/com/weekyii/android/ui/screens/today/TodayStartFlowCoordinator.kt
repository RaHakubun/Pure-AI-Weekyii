package com.weekyii.android.ui.screens.today

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class TodayStartFlowStep { WARNING, RITUAL }

data class TodayStartFlowState(
    val isVisible: Boolean = false,
    val step: TodayStartFlowStep = TodayStartFlowStep.WARNING
)

/** Coordinates the two-step commitment flow without coupling it to Compose UI. */
class TodayStartFlowCoordinator {
    private val _state = MutableStateFlow(TodayStartFlowState())
    val state: StateFlow<TodayStartFlowState> = _state.asStateFlow()

    fun present() {
        _state.value = TodayStartFlowState(isVisible = true)
    }

    fun continueToRitual() {
        if (_state.value.isVisible) {
            _state.value = _state.value.copy(step = TodayStartFlowStep.RITUAL)
        }
    }

    fun finish() {
        _state.value = TodayStartFlowState()
    }

    fun dismiss() {
        _state.value = TodayStartFlowState()
    }
}
