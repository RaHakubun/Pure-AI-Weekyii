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
    val fixedReminderEnabled: StateFlow<Boolean>
    val fixedReminderHour: StateFlow<Int>
    val fixedReminderMinute: StateFlow<Int>
    val defaultProjectDurationDays: StateFlow<Int>
    val defaultProjectTileSizeRaw: StateFlow<String>
    val weekStartsOnMonday: StateFlow<Boolean>
    val pendingMonthShowRegular: StateFlow<Boolean>
    val pendingMonthShowDDL: StateFlow<Boolean>
    val pendingMonthShowLeisure: StateFlow<Boolean>
    suspend fun setDefaultKillTime(time: LocalTime)
    suspend fun setDefaultExecutionMode(mode: ExecutionMode)
    suspend fun setDefaultTaskTypeId(idRaw: String)
    suspend fun setThemeId(idRaw: String)
    suspend fun setAppearanceMode(idRaw: String)
    suspend fun setKillTimeReminderMinutes(minutes: Int)
    suspend fun setFixedReminderEnabled(enabled: Boolean)
    suspend fun setFixedReminderTime(hour: Int, minute: Int)
    suspend fun setDefaultProjectDurationDays(days: Int)
    suspend fun setDefaultProjectTileSizeRaw(idRaw: String)
    suspend fun setWeekStartsOnMonday(enabled: Boolean)
    suspend fun setPendingMonthMarkers(regular: Boolean, ddl: Boolean, leisure: Boolean)
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
        val fixedReminderEnabled = stringPreferencesKey("fixed_reminder_enabled")
        val fixedReminderHour = stringPreferencesKey("fixed_reminder_hour")
        val fixedReminderMinute = stringPreferencesKey("fixed_reminder_minute")
        val defaultProjectDurationDays = stringPreferencesKey("default_project_duration_days")
        val defaultProjectTileSizeRaw = stringPreferencesKey("default_project_tile_size")
        val weekStartsOnMonday = stringPreferencesKey("week_starts_on_monday")
        val pendingMonthShowRegular = stringPreferencesKey("pending_month_show_regular")
        val pendingMonthShowDDL = stringPreferencesKey("pending_month_show_ddl")
        val pendingMonthShowLeisure = stringPreferencesKey("pending_month_show_leisure")
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

    override val fixedReminderEnabled: StateFlow<Boolean> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.fixedReminderEnabled]?.toBoolean() ?: false }
        .stateIn(scope, SharingStarted.Eagerly, false)

    override val fixedReminderHour: StateFlow<Int> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.fixedReminderHour]?.toIntOrNull()?.coerceIn(0, 23) ?: 21 }
        .stateIn(scope, SharingStarted.Eagerly, 21)

    override val fixedReminderMinute: StateFlow<Int> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.fixedReminderMinute]?.toIntOrNull()?.coerceIn(0, 59) ?: 0 }
        .stateIn(scope, SharingStarted.Eagerly, 0)

    override val defaultProjectDurationDays: StateFlow<Int> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.defaultProjectDurationDays]?.toIntOrNull()?.coerceIn(1, 365) ?: 7 }
        .stateIn(scope, SharingStarted.Eagerly, 7)

    override val defaultProjectTileSizeRaw: StateFlow<String> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.defaultProjectTileSizeRaw] ?: "medium" }
        .stateIn(scope, SharingStarted.Eagerly, "medium")

    override val weekStartsOnMonday: StateFlow<Boolean> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.weekStartsOnMonday]?.toBoolean() ?: true }
        .stateIn(scope, SharingStarted.Eagerly, true)

    override val pendingMonthShowRegular: StateFlow<Boolean> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.pendingMonthShowRegular]?.toBoolean() ?: false }
        .stateIn(scope, SharingStarted.Eagerly, false)

    override val pendingMonthShowDDL: StateFlow<Boolean> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.pendingMonthShowDDL]?.toBoolean() ?: true }
        .stateIn(scope, SharingStarted.Eagerly, true)

    override val pendingMonthShowLeisure: StateFlow<Boolean> = context.weekyiiSettingsDataStore.data
        .map { preferences -> preferences[Keys.pendingMonthShowLeisure]?.toBoolean() ?: false }
        .stateIn(scope, SharingStarted.Eagerly, false)

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

    override suspend fun setFixedReminderEnabled(enabled: Boolean) {
        context.weekyiiSettingsDataStore.edit { it[Keys.fixedReminderEnabled] = enabled.toString() }
    }

    override suspend fun setFixedReminderTime(hour: Int, minute: Int) {
        require(hour in 0..23 && minute in 0..59) { "Fixed reminder time is invalid" }
        context.weekyiiSettingsDataStore.edit {
            it[Keys.fixedReminderHour] = hour.toString()
            it[Keys.fixedReminderMinute] = minute.toString()
        }
    }

    override suspend fun setDefaultProjectDurationDays(days: Int) {
        require(days in 1..365) { "Project duration must be between 1 and 365 days" }
        context.weekyiiSettingsDataStore.edit { it[Keys.defaultProjectDurationDays] = days.toString() }
    }

    override suspend fun setDefaultProjectTileSizeRaw(idRaw: String) {
        require(idRaw in setOf("mini", "small", "medium", "wide")) { "Unknown project tile size" }
        context.weekyiiSettingsDataStore.edit { it[Keys.defaultProjectTileSizeRaw] = idRaw }
    }

    override suspend fun setWeekStartsOnMonday(enabled: Boolean) {
        context.weekyiiSettingsDataStore.edit { it[Keys.weekStartsOnMonday] = enabled.toString() }
    }

    override suspend fun setPendingMonthMarkers(regular: Boolean, ddl: Boolean, leisure: Boolean) {
        context.weekyiiSettingsDataStore.edit {
            it[Keys.pendingMonthShowRegular] = regular.toString()
            it[Keys.pendingMonthShowDDL] = ddl.toString()
            it[Keys.pendingMonthShowLeisure] = leisure.toString()
        }
    }
}
