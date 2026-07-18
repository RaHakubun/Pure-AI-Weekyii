package com.weekyii.android.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.data.repository.MindStampRepository
import com.weekyii.android.data.repository.ProjectRepository
import com.weekyii.android.data.repository.SuspendedTaskRepository
import com.weekyii.android.data.repository.TaskTypeDefinitionRepository
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.ui.model.MindStampUi
import com.weekyii.android.ui.model.ProjectUi
import com.weekyii.android.ui.model.SuspendedTaskUi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.UUID

class ExtensionsViewModel(
    private val projects: ProjectRepository,
    private val mindStamps: MindStampRepository,
    private val suspendedTasks: SuspendedTaskRepository,
    private val taskTypes: TaskTypeDefinitionRepository? = null
) : ViewModel() {
    data class UiState(
        val projects: List<ProjectUi> = emptyList(),
        val mindStamps: List<MindStampUi> = emptyList(),
        val suspendedTasks: List<SuspendedTaskUi> = emptyList(),
        val taskTypeDefinitions: List<TaskTypeDefinitionEntity> = emptyList(),
        val selectedTaskTypeId: String = "regular",
        val error: String? = null
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    init {
        viewModelScope.launch {
            taskTypes?.seedBuiltIns()
            val base = combine(projects.observeProjects(), mindStamps.observeAll(), suspendedTasks.observeActive()) { projectList, stamps, suspended ->
                Triple(projectList, stamps, suspended)
            }
            combine(base, taskTypes?.observeActive() ?: flowOf(emptyList())) { (projectList, stamps, suspended), definitions ->
                val selected = _state.value.selectedTaskTypeId.takeIf { id -> definitions.any { it.idRaw == id } }
                    ?: definitions.firstOrNull()?.idRaw ?: "regular"
                UiState(projectList, stamps, suspended, definitions, selected)
            }.collect { next -> _state.value = next }
        }
    }

    fun createProject(name: String, description: String, startDate: LocalDate, endDate: LocalDate) {
        viewModelScope.launch {
            runCatching { projects.createProject(name, description, startDate, endDate) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun updateProjectStatus(id: UUID, status: ProjectStatus) {
        viewModelScope.launch { projects.updateStatus(id, status) }
    }

    fun deleteProject(id: UUID) {
        viewModelScope.launch { projects.deleteProject(id) }
    }

    fun createMindStamp(text: String) {
        viewModelScope.launch {
            runCatching { mindStamps.create(text, null) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun deleteMindStamp(id: UUID) {
        viewModelScope.launch { mindStamps.delete(id) }
    }

    fun selectTaskType(idRaw: String) {
        _state.value = _state.value.copy(selectedTaskTypeId = idRaw)
    }

    fun createSuspendedTask(title: String, countdownDays: Int) {
        viewModelScope.launch {
            val definition = taskTypes?.resolve(_state.value.selectedTaskTypeId)
            runCatching {
                suspendedTasks.create(
                    title,
                    "",
                    definition?.baseKind ?: TaskType.REGULAR,
                    countdownDays,
                    java.util.Date(),
                    definition?.idRaw ?: TaskType.REGULAR.name.lowercase()
                )
            }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }

    fun extendSuspendedTask(id: UUID, days: Int) {
        viewModelScope.launch { suspendedTasks.extend(id, days, java.util.Date()) }
    }

    fun deleteSuspendedTask(id: UUID) {
        viewModelScope.launch { suspendedTasks.delete(id) }
    }

    fun assignSuspendedTask(id: UUID, targetDate: LocalDate) {
        viewModelScope.launch {
            runCatching { suspendedTasks.assign(id, targetDate, LocalDate.now()) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
        }
    }
}
