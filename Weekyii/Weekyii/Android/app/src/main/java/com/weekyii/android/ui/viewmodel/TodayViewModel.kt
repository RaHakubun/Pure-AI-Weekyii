package com.weekyii.android.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.data.repository.toUi
import com.weekyii.android.data.repository.TaskAttachmentDraft
import com.weekyii.android.data.db.entities.ExecutionMode
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.data.repository.TaskTypeDefinitionRepository
import com.weekyii.android.data.repository.MindStampRepository
import com.weekyii.android.platform.WeekyiiNotificationService
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.domain.TimeProvider
import com.weekyii.android.domain.AppStateStore
import com.weekyii.android.domain.UserSettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate

class TodayViewModel(
    private val repo: WeekyiiRepository,
    private val timeProvider: TimeProvider,
    private val appState: AppStateStore,
    private val settings: UserSettingsStore? = null,
    private val taskTypeRepository: TaskTypeDefinitionRepository? = null,
    private val mindStampRepository: MindStampRepository? = null,
    private val notificationService: WeekyiiNotificationService? = null
) : ViewModel() {

    data class UiState(
        val date: LocalDate = LocalDate.now(),
        val day: DayUi? = null,
        val draft: List<TaskUi> = emptyList(),
        val focus: TaskUi? = null,
        val frozen: List<TaskUi> = emptyList(),
        val complete: List<TaskUi> = emptyList(),
        val startExecutionMode: ExecutionMode = ExecutionMode.STRICT,
        val taskTypeDefinitions: List<TaskTypeDefinitionEntity> = emptyList(),
        val selectedTaskTypeId: String = "regular",
        val ritualStamp: com.weekyii.android.ui.model.MindStampUi? = null,
        val error: String? = null
    )

    private val _state = MutableStateFlow(
        UiState(startExecutionMode = settings?.defaultExecutionMode?.value ?: ExecutionMode.STRICT)
    )
    val state: StateFlow<UiState> = _state

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            val today = timeProvider.today
            repo.createDraftDayIfNeeded(today)
            val day = repo.getDayWithTasks(today.toString())
            val tasks = day?.tasks?.sortedBy { it.order } ?: emptyList()
            val definitions = taskTypeRepository?.listActive().orEmpty()
            val preferredTypeId = _state.value.selectedTaskTypeId
                .takeIf { candidate -> definitions.any { it.idRaw == candidate } }
                ?: settings?.defaultTaskTypeId?.value
                    ?.takeIf { candidate -> definitions.any { it.idRaw == candidate } }
                ?: definitions.firstOrNull()?.idRaw
                ?: "regular"
            val taskUi = tasks.associate { task -> task.id to (repo.getTaskUi(task.id) ?: task.toUi()) }
            val focus = tasks.firstOrNull { it.zone.name == "FOCUS" }?.let { taskUi.getValue(it.id) }
            val frozen = tasks.filter { it.zone.name == "FROZEN" }.sortedBy { it.order }.map { taskUi.getValue(it.id) }
            val complete = tasks.filter { it.zone.name == "COMPLETE" }.sortedBy { it.completedOrder }.map { taskUi.getValue(it.id) }
            val selectedMode = _state.value.startExecutionMode
            _state.value = UiState(
                date = today,
                day = day?.day?.toUi(tasks = tasks.map { taskUi.getValue(it.id) }),
                draft = tasks.filter { it.zone.name == "DRAFT" }.sortedBy { it.order }.map { taskUi.getValue(it.id) },
                focus = focus,
                frozen = frozen,
                complete = complete,
                startExecutionMode = selectedMode,
                taskTypeDefinitions = definitions,
                selectedTaskTypeId = preferredTypeId,
                ritualStamp = _state.value.ritualStamp,
                error = null
            )
            val currentDay = _state.value.day
            if (currentDay != null && currentDay.status in setOf(com.weekyii.android.data.db.entities.DayStatus.DRAFT, com.weekyii.android.data.db.entities.DayStatus.EXECUTE)) {
                val unfinished = _state.value.draft.size + (if (_state.value.focus != null) 1 else 0) + _state.value.frozen.size
                notificationService?.scheduleKillTime(
                    dayId = currentDay.dayId,
                    at = today.atTime(currentDay.killHour, currentDay.killMinute),
                    unfinishedCount = unfinished
                )
            } else {
                notificationService?.cancelKillTime(today.toString())
            }
        }
    }

    fun createDraft(titles: List<String>) {
        viewModelScope.launch {
            repo.createDraftDayIfNeeded(timeProvider.today)
            val definition = taskTypeRepository?.resolve(_state.value.selectedTaskTypeId)
            repo.addDraftTasks(
                timeProvider.today.toString(),
                titles,
                definition?.baseKind ?: TaskType.REGULAR,
                definition?.idRaw ?: TaskType.REGULAR.name.lowercase()
            )
            refresh()
        }
    }

    fun selectTaskType(idRaw: String) {
        _state.update { it.copy(selectedTaskTypeId = idRaw) }
    }

    fun startDay() {
        viewModelScope.launch {
            try {
                repo.startDay(timeProvider.today.toString(), timeProvider.now, _state.value.startExecutionMode)
                val ritualStamp = mindStampRepository?.random()
                refresh()
                _state.update { it.copy(ritualStamp = ritualStamp) }
                appState.incrementDaysStarted()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun dismissRitual() { _state.update { it.copy(ritualStamp = null) } }

    fun selectExecutionMode(mode: ExecutionMode) {
        _state.update { it.copy(startExecutionMode = mode) }
    }

    fun setDraftZoneUnlocked(isUnlocked: Boolean) {
        viewModelScope.launch {
            try {
                repo.setDraftZoneUnlocked(timeProvider.today.toString(), isUnlocked)
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun addExecutionTask(title: String) {
        viewModelScope.launch {
            try {
                val definition = taskTypeRepository?.resolve(_state.value.selectedTaskTypeId)
                repo.addExecutionTask(
                    timeProvider.today.toString(),
                    title,
                    taskType = definition?.baseKind ?: TaskType.REGULAR,
                    taskTypeIdRaw = definition?.idRaw ?: TaskType.REGULAR.name.lowercase()
                )
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun updateFrozenTask(
        task: TaskUi,
        title: String,
        description: String = "",
        stepTitles: List<String> = task.steps.map { it.title },
        attachments: List<com.weekyii.android.ui.model.TaskAttachmentUi> = task.attachments,
        taskType: TaskType = task.taskType,
        taskTypeIdRaw: String = task.taskTypeIdRaw
    ) {
        viewModelScope.launch {
            try {
                repo.updateFrozenTask(
                    dayId = timeProvider.today.toString(),
                    taskId = task.id,
                    title = title,
                    description = description,
                    taskType = taskType,
                    taskTypeIdRaw = taskTypeIdRaw,
                    stepTitles = stepTitles,
                    attachments = attachments.map { attachment ->
                        TaskAttachmentDraft(attachment.fileName, attachment.fileType, attachment.data)
                    }
                )
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun deleteFrozenTask(task: TaskUi) {
        viewModelScope.launch {
            try {
                repo.deleteFrozenTask(timeProvider.today.toString(), task.id)
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun moveFrozenTask(fromIndex: Int, toIndex: Int) {
        viewModelScope.launch {
            try {
                repo.moveFrozenTask(timeProvider.today.toString(), fromIndex, toIndex)
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun exchangeFocusWithFirstFrozen() {
        viewModelScope.launch {
            try {
                repo.exchangeFocusWithFirstFrozen(timeProvider.today.toString(), timeProvider.now)
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun postponeTask(task: TaskUi, targetDate: LocalDate) {
        viewModelScope.launch {
            try {
                repo.postponeTask(task.id, targetDate, timeProvider.today, timeProvider.now)
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun doneFocus() {
        viewModelScope.launch {
            try {
                repo.doneFocus(timeProvider.today.toString(), timeProvider.now)
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun changeKillTime(hour: Int, minute: Int) {
        viewModelScope.launch {
            try {
                repo.changeKillTime(timeProvider.today.toString(), hour, minute, timeProvider.now)
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun updateDraftTask(
        task: TaskUi,
        title: String,
        description: String = "",
        stepTitles: List<String> = task.steps.map { it.title },
        attachments: List<com.weekyii.android.ui.model.TaskAttachmentUi> = task.attachments,
        taskType: TaskType = task.taskType,
        taskTypeIdRaw: String = task.taskTypeIdRaw
    ) {
        viewModelScope.launch {
            try {
                repo.updateDraftTask(timeProvider.today.toString(), task.id, title, description, taskType, taskTypeIdRaw)
                repo.replaceDraftTaskResources(
                    timeProvider.today.toString(),
                    task.id,
                    stepTitles,
                    attachments.map { attachment -> TaskAttachmentDraft(attachment.fileName, attachment.fileType, attachment.data) }
                )
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun deleteDraftTask(task: TaskUi) {
        viewModelScope.launch {
            try {
                repo.deleteDraftTasks(timeProvider.today.toString(), listOf(task.id))
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun moveDraftTask(fromIndex: Int, toIndex: Int) {
        viewModelScope.launch {
            try {
                repo.moveDraftTask(timeProvider.today.toString(), fromIndex, toIndex)
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }
}
