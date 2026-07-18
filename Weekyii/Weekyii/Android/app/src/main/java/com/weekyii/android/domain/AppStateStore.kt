package com.weekyii.android.domain

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.LocalDate
import java.time.LocalDateTime

interface AppStateStore {
    val systemStartDate: StateFlow<LocalDate?>
    val lastProcessedDate: StateFlow<LocalDate?>
    val lastRolloverAt: StateFlow<LocalDateTime?>
    val runtimeErrorMessage: StateFlow<String?>
    val stateTransitionRevision: StateFlow<Int>

    suspend fun setSystemStartDate(date: LocalDate)
    suspend fun setLastProcessedDate(date: LocalDate)
    suspend fun setLastRollover(at: LocalDateTime)
    suspend fun setRuntimeError(message: String?)
    suspend fun incrementDaysStarted()
    suspend fun bumpStateTransitionRevision()
    val daysStartedCount: StateFlow<Int>
}

class InMemoryAppStateStore : AppStateStore {
    private val _systemStartDate = MutableStateFlow<LocalDate?>(null)
    private val _lastProcessedDate = MutableStateFlow<LocalDate?>(null)
    private val _lastRolloverAt = MutableStateFlow<LocalDateTime?>(null)
    private val _runtimeErrorMessage = MutableStateFlow<String?>(null)
    private val _daysStartedCount = MutableStateFlow(0)
    private val _stateTransitionRevision = MutableStateFlow(0)

    override val systemStartDate: StateFlow<LocalDate?> = _systemStartDate
    override val lastProcessedDate: StateFlow<LocalDate?> = _lastProcessedDate
    override val lastRolloverAt: StateFlow<LocalDateTime?> = _lastRolloverAt
    override val runtimeErrorMessage: StateFlow<String?> = _runtimeErrorMessage
    override val daysStartedCount: StateFlow<Int> = _daysStartedCount
    override val stateTransitionRevision: StateFlow<Int> = _stateTransitionRevision

    override suspend fun setSystemStartDate(date: LocalDate) { _systemStartDate.value = date }
    override suspend fun setLastProcessedDate(date: LocalDate) { _lastProcessedDate.value = date }
    override suspend fun setLastRollover(at: LocalDateTime) { _lastRolloverAt.value = at }
    override suspend fun setRuntimeError(message: String?) { _runtimeErrorMessage.value = message }
    override suspend fun incrementDaysStarted() { _daysStartedCount.value = _daysStartedCount.value + 1 }
    override suspend fun bumpStateTransitionRevision() { _stateTransitionRevision.value = _stateTransitionRevision.value + 1 }
}
