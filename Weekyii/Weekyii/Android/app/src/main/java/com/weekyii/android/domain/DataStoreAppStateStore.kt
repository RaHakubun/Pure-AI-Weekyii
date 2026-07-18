package com.weekyii.android.domain

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import java.time.LocalDate
import java.time.LocalDateTime

private val Context.weekyiiDataStore by preferencesDataStore(name = "weekyii_state")

class DataStoreAppStateStore(
    private val context: Context,
    scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) : AppStateStore {
    private object Keys {
        val systemStartDate = stringPreferencesKey("system_start_date")
        val lastProcessedDate = stringPreferencesKey("last_processed_date")
        val lastRolloverAt = stringPreferencesKey("last_rollover_at")
        val runtimeErrorMessage = stringPreferencesKey("runtime_error_message")
        val daysStartedCount = intPreferencesKey("days_started_count")
        val stateTransitionRevision = intPreferencesKey("state_transition_revision")
    }

    private val initialSnapshot = runBlocking(Dispatchers.IO) {
        context.weekyiiDataStore.data.first().toSnapshot()
    }

    private val snapshot = context.weekyiiDataStore.data
        .map { it.toSnapshot() }
        .stateIn(scope, SharingStarted.Eagerly, initialSnapshot)

    override val systemStartDate: StateFlow<LocalDate?> = snapshot.mapState(scope) { it.systemStartDate }
    override val lastProcessedDate: StateFlow<LocalDate?> = snapshot.mapState(scope) { it.lastProcessedDate }
    override val lastRolloverAt: StateFlow<LocalDateTime?> = snapshot.mapState(scope) { it.lastRolloverAt }
    override val runtimeErrorMessage: StateFlow<String?> = snapshot.mapState(scope) { it.runtimeErrorMessage }
    override val daysStartedCount: StateFlow<Int> = snapshot.mapState(scope) { it.daysStartedCount }
    override val stateTransitionRevision: StateFlow<Int> = snapshot.mapState(scope) { it.stateTransitionRevision }

    override suspend fun setSystemStartDate(date: LocalDate?) {
        context.weekyiiDataStore.edit { preferences ->
            if (date == null) preferences.remove(Keys.systemStartDate) else preferences[Keys.systemStartDate] = date.toString()
        }
    }

    override suspend fun setLastProcessedDate(date: LocalDate?) {
        context.weekyiiDataStore.edit { preferences ->
            if (date == null) preferences.remove(Keys.lastProcessedDate) else preferences[Keys.lastProcessedDate] = date.toString()
        }
    }

    override suspend fun setLastRollover(at: LocalDateTime?) {
        context.weekyiiDataStore.edit { preferences ->
            if (at == null) preferences.remove(Keys.lastRolloverAt) else preferences[Keys.lastRolloverAt] = at.toString()
        }
    }

    override suspend fun setRuntimeError(message: String?) {
        context.weekyiiDataStore.edit {
            if (message == null) it.remove(Keys.runtimeErrorMessage) else it[Keys.runtimeErrorMessage] = message
        }
    }

    override suspend fun incrementDaysStarted() {
        context.weekyiiDataStore.edit { preferences ->
            preferences[Keys.daysStartedCount] = (preferences[Keys.daysStartedCount] ?: 0) + 1
        }
    }

    override suspend fun bumpStateTransitionRevision() {
        context.weekyiiDataStore.edit { preferences ->
            preferences[Keys.stateTransitionRevision] = (preferences[Keys.stateTransitionRevision] ?: 0) + 1
        }
    }

    override suspend fun setDaysStartedCount(value: Int) {
        context.weekyiiDataStore.edit { it[Keys.daysStartedCount] = value.coerceAtLeast(0) }
    }

    override suspend fun setStateTransitionRevision(value: Int) {
        context.weekyiiDataStore.edit { it[Keys.stateTransitionRevision] = value.coerceAtLeast(0) }
    }

    private data class Snapshot(
        val systemStartDate: LocalDate? = null,
        val lastProcessedDate: LocalDate? = null,
        val lastRolloverAt: LocalDateTime? = null,
        val runtimeErrorMessage: String? = null,
        val daysStartedCount: Int = 0,
        val stateTransitionRevision: Int = 0
    )

    private fun androidx.datastore.preferences.core.Preferences.toSnapshot() = Snapshot(
        systemStartDate = this[Keys.systemStartDate]?.let(LocalDate::parse),
        lastProcessedDate = this[Keys.lastProcessedDate]?.let(LocalDate::parse),
        lastRolloverAt = this[Keys.lastRolloverAt]?.let(LocalDateTime::parse),
        runtimeErrorMessage = this[Keys.runtimeErrorMessage],
        daysStartedCount = this[Keys.daysStartedCount] ?: 0,
        stateTransitionRevision = this[Keys.stateTransitionRevision] ?: 0
    )
}

private fun <T, R> StateFlow<T>.mapState(
    scope: CoroutineScope,
    transform: (T) -> R
): StateFlow<R> = map(transform).stateIn(scope, SharingStarted.Eagerly, transform(value))
