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
    suspend fun setDefaultKillTime(time: LocalTime)
    suspend fun setDefaultExecutionMode(mode: ExecutionMode)
    suspend fun setDefaultTaskTypeId(idRaw: String)
    suspend fun setThemeId(idRaw: String)
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
}
