package com.weekyii.android.domain

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.weekyii.android.data.db.entities.ExecutionMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import java.time.LocalTime

interface UserSettingsStore {
    val defaultKillTime: StateFlow<LocalTime>
    val defaultExecutionMode: StateFlow<ExecutionMode>
    val defaultTaskTypeId: StateFlow<String>
    val themeId: StateFlow<String>
    val appearanceMode: StateFlow<String>
    val killTimeReminderMinutes: StateFlow<Int>
    suspend fun setDefaultKillTime(time: LocalTime)
    suspend fun setDefaultExecutionMode(mode: ExecutionMode)
    suspend fun setDefaultTaskTypeId(idRaw: String)
    suspend fun setThemeId(idRaw: String)
    suspend fun setAppearanceMode(idRaw: String)
    suspend fun setKillTimeReminderMinutes(minutes: Int)
}

private val Context.weekyiiSettingsDataStore by preferencesDataStore(name = "weekyii_settings")

class DataStoreUserSettingsStore(
    private val context: Context,
    scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) : UserSettingsStore {
    private object Keys {
        val defaultKillTime = stringPreferencesKey("default_kill_time")
        val defaultExecutionMode = stringPreferencesKey("default_execution_mode")
        val defaultTaskTypeId = stringPreferencesKey("default_task_type_id")
        val themeId = stringPreferencesKey("theme_id")
        val appearanceMode = stringPreferencesKey("appearance_mode")
        val killTimeReminderMinutes = stringPreferencesKey("kill_time_reminder_minutes")
    }

    override val defaultKillTime: StateFlow<LocalTime> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.defaultKillTime]?.let(LocalTime::parse) ?: LocalTime.of(20, 0) }
        .stateIn(scope, SharingStarted.Eagerly, LocalTime.of(20, 0))

    override val defaultExecutionMode: StateFlow<ExecutionMode> = context.weekyiiSettingsDataStore.data
        .map { preferences ->
            preferences[Keys.defaultExecutionMode]
                ?.let { raw -> runCatching { ExecutionMode.valueOf(raw) }.getOrNull() }
                ?: ExecutionMode.STRICT
        }
        .stateIn(scope, SharingStarted.Eagerly, ExecutionMode.STRICT)

    override val defaultTaskTypeId: StateFlow<String> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.defaultTaskTypeId] ?: "regular" }
        .stateIn(scope, SharingStarted.Eagerly, "regular")

    override val themeId: StateFlow<String> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.themeId] ?: "amber" }
        .stateIn(scope, SharingStarted.Eagerly, "amber")

    override val appearanceMode: StateFlow<String> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.appearanceMode] ?: "system" }
        .stateIn(scope, SharingStarted.Eagerly, "system")

    override val killTimeReminderMinutes: StateFlow<Int> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.killTimeReminderMinutes]?.toIntOrNull()?.coerceIn(0, 120) ?: 60 }
        .stateIn(scope, SharingStarted.Eagerly, 60)

    override suspend fun setDefaultKillTime(time: LocalTime) {
        context.weekyiiSettingsDataStore.edit { it[Keys.defaultKillTime] = time.toString() }
    }

    override suspend fun setDefaultExecutionMode(mode: ExecutionMode) {
        context.weekyiiSettingsDataStore.edit { it[Keys.defaultExecutionMode] = mode.name }
    }

    override suspend fun setDefaultTaskTypeId(idRaw: String) {
        require(idRaw.isNotBlank()) { "Default task type cannot be empty" }
        context.weekyiiSettingsDataStore.edit { it[Keys.defaultTaskTypeId] = idRaw }
    }

    override suspend fun setThemeId(idRaw: String) {
        require(idRaw.isNotBlank()) { "Theme cannot be empty" }
        context.weekyiiSettingsDataStore.edit { it[Keys.themeId] = idRaw }
    }

    override suspend fun setAppearanceMode(idRaw: String) {
        require(idRaw in setOf("system", "light", "dark")) { "Unknown appearance mode" }
        context.weekyiiSettingsDataStore.edit { it[Keys.appearanceMode] = idRaw }
    }

    override suspend fun setKillTimeReminderMinutes(minutes: Int) {
        require(minutes in 0..120) { "Reminder minutes must be between 0 and 120" }
        context.weekyiiSettingsDataStore.edit { it[Keys.killTimeReminderMinutes] = minutes.toString() }
    }
}
