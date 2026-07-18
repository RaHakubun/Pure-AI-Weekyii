package com.weekyii.android.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekyii.android.data.db.entities.ExecutionMode
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.data.repository.TaskTypeDefinitionRepository
import com.weekyii.android.data.archive.WeekyiiArchiveService
import com.weekyii.android.data.archive.WeekyiiDataArchiveRepository
import com.weekyii.android.domain.UserSettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.time.LocalTime

class SettingsViewModel(
    private val settings: UserSettingsStore,
    private val taskTypes: TaskTypeDefinitionRepository,
    private val archiveRepository: WeekyiiDataArchiveRepository? = null
) : ViewModel() {
    data class UiState(
        val defaultKillTime: LocalTime = LocalTime.of(20, 0),
        val defaultExecutionMode: ExecutionMode = ExecutionMode.STRICT,
        val defaultTaskTypeId: String = "regular",
        val themeId: String = "amber",
        val appearanceMode: String = "system",
        val killTimeReminderMinutes: Int = 60,
        val fixedReminderEnabled: Boolean = false,
        val fixedReminderHour: Int = 21,
        val fixedReminderMinute: Int = 0,
        val taskTypeDefinitions: List<TaskTypeDefinitionEntity> = emptyList(),
        val importInspection: WeekyiiArchiveService.Inspection? = null,
        val isImporting: Boolean = false,
        val archiveMessage: String? = null,
        val error: String? = null
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    init {
        viewModelScope.launch {
            taskTypes.seedBuiltIns()
            data class PreferenceSnapshot(
                val killTime: LocalTime,
                val executionMode: ExecutionMode,
                val taskTypeId: String,
                val themeId: String,
                val appearanceMode: String
            )
            val preferences = combine(
                settings.defaultKillTime,
                settings.defaultExecutionMode,
                settings.defaultTaskTypeId,
                settings.themeId,
                settings.appearanceMode
            ) { time, mode, defaultTypeId, themeId, appearanceMode ->
                PreferenceSnapshot(time, mode, defaultTypeId, themeId, appearanceMode)
            }
            data class FixedReminderSnapshot(val enabled: Boolean, val hour: Int, val minute: Int)
            val fixedReminder = combine(settings.fixedReminderEnabled, settings.fixedReminderHour, settings.fixedReminderMinute) { enabled, hour, minute ->
                FixedReminderSnapshot(enabled, hour, minute)
            }
            combine(preferences, settings.killTimeReminderMinutes, fixedReminder, taskTypes.observeAll()) { pref, reminderMinutes, fixed, definitions ->
                UiState(
                    defaultKillTime = pref.killTime,
                    defaultExecutionMode = pref.executionMode,
                    defaultTaskTypeId = pref.taskTypeId,
                    themeId = pref.themeId,
                    appearanceMode = pref.appearanceMode,
                    killTimeReminderMinutes = reminderMinutes,
                    fixedReminderEnabled = fixed.enabled,
                    fixedReminderHour = fixed.hour,
                    fixedReminderMinute = fixed.minute,
                    taskTypeDefinitions = definitions
                )
            }.collect { next -> _state.value = next }
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

    fun setDefaultTaskType(idRaw: String) {
        viewModelScope.launch {
            runCatching {
                val definition = taskTypes.resolve(idRaw)
                require(!definition.isArchived) { "Archived task type cannot be the default" }
                settings.setDefaultTaskTypeId(definition.idRaw)
            }.onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun setTheme(idRaw: String) {
        viewModelScope.launch {
            runCatching { settings.setThemeId(idRaw) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun setAppearanceMode(idRaw: String) {
        viewModelScope.launch {
            runCatching { settings.setAppearanceMode(idRaw) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun setKillTimeReminderMinutes(minutes: Int) {
        viewModelScope.launch {
            runCatching { settings.setKillTimeReminderMinutes(minutes) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun setFixedReminderEnabled(enabled: Boolean) {
        viewModelScope.launch {
            runCatching { settings.setFixedReminderEnabled(enabled) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun setFixedReminderTime(hour: Int, minute: Int) {
        viewModelScope.launch {
            runCatching { settings.setFixedReminderTime(hour, minute) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun createTaskType(name: String, iconName: String, colorHex: String, baseKind: TaskType) {
        viewModelScope.launch {
            runCatching { taskTypes.create(name, iconName, colorHex, baseKind) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun updateTaskType(idRaw: String, name: String, iconName: String, colorHex: String, baseKind: TaskType) {
        viewModelScope.launch {
            runCatching {
                val updated = taskTypes.update(idRaw, name, iconName, colorHex, baseKind)
                if (settings.defaultTaskTypeId.value == idRaw) settings.setDefaultTaskTypeId(updated.idRaw)
            }.onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun archiveTaskType(idRaw: String) {
        viewModelScope.launch {
            runCatching {
                taskTypes.archive(idRaw)
                if (settings.defaultTaskTypeId.value == idRaw) settings.setDefaultTaskTypeId("regular")
            }.onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun restoreTaskType(idRaw: String) {
        viewModelScope.launch {
            runCatching { taskTypes.restore(idRaw) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun exportArchive(onReady: (ByteArray) -> Unit) {
        viewModelScope.launch {
            runCatching { archiveRepository?.exportArchive() ?: error("数据归档服务未配置") }
                .onSuccess(onReady)
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun inspectImport(data: ByteArray) {
        runCatching { archiveRepository?.inspect(data) ?: error("数据归档服务未配置") }
            .onSuccess { inspection ->
                pendingImportData = data
                _state.value = _state.value.copy(importInspection = inspection, archiveMessage = null, error = null)
            }
            .onFailure { _state.value = _state.value.copy(error = it.message) }
    }

    fun confirmImport() {
        val data = pendingImportData ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(isImporting = true, error = null)
            runCatching { archiveRepository?.importReplacing(data) ?: error("数据归档服务未配置") }
                .onSuccess { inspection ->
                    pendingImportData = null
                    _state.value = _state.value.copy(isImporting = false, importInspection = null, archiveMessage = "已恢复 ${inspection.weekCount} 周数据")
                }
                .onFailure { _state.value = _state.value.copy(isImporting = false, error = it.message) }
        }
    }

    fun cancelImport() {
        pendingImportData = null
        _state.value = _state.value.copy(importInspection = null)
    }

    private var pendingImportData: ByteArray? = null
}
