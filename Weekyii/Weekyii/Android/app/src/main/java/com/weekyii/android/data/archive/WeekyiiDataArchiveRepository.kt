package com.weekyii.android.data.archive

import androidx.room.withTransaction
import com.weekyii.android.data.db.AppDatabase
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.ExecutionMode
import com.weekyii.android.data.db.entities.MindStampEntity
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStatus
import com.weekyii.android.data.db.entities.TaskAttachmentEntity
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.domain.AppStateStore
import com.weekyii.android.domain.UserSettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Base64
import java.util.Date
import java.util.UUID
import java.time.LocalDateTime
import java.time.ZoneId

class WeekyiiDataArchiveRepository(
    private val database: AppDatabase,
    private val settings: UserSettingsStore,
    private val appState: AppStateStore,
    private val backupRecovery: BackupRecoveryService,
    private val zoneId: ZoneId = ZoneId.systemDefault()
) {
    suspend fun exportArchive(appVersion: String = "unknown"): ByteArray = withContext(Dispatchers.IO) {
        val payload = database.withTransaction { buildPayload() }
        WeekyiiArchiveService.encode(payload, appVersion = appVersion)
    }

    fun inspect(data: ByteArray): WeekyiiArchiveService.Inspection = WeekyiiArchiveService.inspect(data)

    suspend fun importReplacing(data: ByteArray): WeekyiiArchiveService.Inspection = withContext(Dispatchers.IO) {
        val archiveInspection = WeekyiiArchiveService.inspect(data)
        val payload = WeekyiiArchiveService.decodePayload(data)
        backupRecovery.createSnapshot(reason = "import")
        database.withTransaction { replaceDatabase(payload) }
        applySettings(payload.settings)
        applyAppState(payload.appState)
        archiveInspection
    }

    private suspend fun buildPayload(): WeekyiiArchiveService.Payload {
        val weeks = database.weekDao().allWeeks()
        val days = database.dayDao().allDays()
        val tasks = database.taskDao().allTasks().map { task ->
            val detail = database.taskDao().findWithSteps(task.id)
                ?: throw IllegalStateException("Task details unavailable for ${task.id}")
            task.toRecord(detail.steps, detail.attachments)
        }
        val projects = database.projectDao().allProjects().map { it.toRecord() }
        val stamps = database.mindStampDao().allMindStamps().map { it.toRecord() }
        val suspended = database.suspendedTaskDao().allTasks().map { task ->
            val detail = database.suspendedTaskDao().findWithDetails(task.id)
                ?: throw IllegalStateException("Suspended task details unavailable for ${task.id}")
            task.toRecord(detail.steps, detail.attachments)
        }
        val taskTypes = database.taskTypeDefinitionDao().listAll().map { it.toRecord() }
        return WeekyiiArchiveService.Payload(
            weeks = weeks.map { it.toRecord() },
            days = days.map { it.toRecord() },
            tasks = tasks,
            projects = projects,
            mindStamps = stamps,
            suspendedTasks = suspended,
            taskTypes = taskTypes,
            settings = WeekyiiArchiveService.SettingsRecord(
                defaultKillTimeHour = settings.defaultKillTime.value.hour,
                defaultKillTimeMinute = settings.defaultKillTime.value.minute,
                defaultTaskTypeIdRaw = settings.defaultTaskTypeId.value,
                defaultTaskTypeRaw = taskTypeBaseFor(settings.defaultTaskTypeId.value),
                defaultExecutionModeRaw = settings.defaultExecutionMode.value.name.lowercase()
            ),
            appState = WeekyiiArchiveService.AppStateRecord(
                daysStartedCount = appState.daysStartedCount.value,
                stateTransitionRevision = appState.stateTransitionRevision.value,
                systemStartDate = appState.systemStartDate.value?.atStartOfDay(zoneId)?.toInstant()?.toEpochMilli(),
                lastProcessedDate = appState.lastProcessedDate.value?.atStartOfDay(zoneId)?.toInstant()?.toEpochMilli(),
                lastRolloverAt = appState.lastRolloverAt.value?.atZone(zoneId)?.toInstant()?.toEpochMilli()
            )
        )
    }

    private suspend fun replaceDatabase(payload: WeekyiiArchiveService.Payload) {
        val taskDao = database.taskDao()
        val dayDao = database.dayDao()
        val weekDao = database.weekDao()
        val projectDao = database.projectDao()
        val mindStampDao = database.mindStampDao()
        val suspendedDao = database.suspendedTaskDao()
        val typeDao = database.taskTypeDefinitionDao()

        taskDao.deleteAll()
        dayDao.deleteAll()
        weekDao.deleteAll()
        projectDao.deleteAll()
        mindStampDao.deleteAll()
        suspendedDao.deleteAll()
        typeDao.deleteAll()

        payload.taskTypes.forEach { typeDao.upsert(it.toEntity()) }
        payload.projects.forEach { projectDao.upsert(it.toEntity()) }
        payload.weeks.forEach { weekDao.upsert(it.toEntity()) }
        payload.days.forEach { dayDao.upsert(it.toEntity()) }
        payload.tasks.forEach { record ->
            val taskId = uuid(record.id, "task")
            taskDao.upsert(record.toEntity(taskId))
            taskDao.upsertSteps(record.steps.map { it.toEntity(taskId) })
            taskDao.upsertAttachments(record.attachments.map { it.toEntity(taskId) })
        }
        payload.mindStamps.forEach { mindStampDao.upsert(it.toEntity()) }
        payload.suspendedTasks.forEach { record ->
            val taskId = uuid(record.id, "suspended task")
            suspendedDao.upsert(record.toEntity(taskId))
            suspendedDao.upsertSteps(record.steps.map { it.toSuspendedEntity(taskId) })
            suspendedDao.upsertAttachments(record.attachments.map { it.toSuspendedEntity(taskId) })
        }
    }

    private suspend fun applySettings(value: WeekyiiArchiveService.SettingsRecord) {
        settings.setDefaultKillTime(java.time.LocalTime.of(value.defaultKillTimeHour, value.defaultKillTimeMinute))
        settings.setDefaultExecutionMode(enum(value.defaultExecutionModeRaw, "execution mode"))
        settings.setDefaultTaskTypeId(value.defaultTaskTypeIdRaw)
    }

    private suspend fun applyAppState(value: WeekyiiArchiveService.AppStateRecord) {
        appState.setDaysStartedCount(value.daysStartedCount)
        appState.setStateTransitionRevision(value.stateTransitionRevision)
        appState.setSystemStartDate(value.systemStartDate?.let { Date(it).toLocalDate() })
        appState.setLastProcessedDate(value.lastProcessedDate?.let { Date(it).toLocalDate() })
        appState.setLastRollover(value.lastRolloverAt?.let { Date(it).toLocalDateTime() })
    }

    private suspend fun taskTypeBaseFor(idRaw: String): String =
        database.taskTypeDefinitionDao().findById(idRaw)?.baseKind?.name?.lowercase() ?: "regular"

    private fun enum(raw: String, label: String): ExecutionMode = runCatching {
        ExecutionMode.entries.first { it.name.equals(raw, ignoreCase = true) }
    }.getOrElse { throw WeekyiiArchiveException.InvalidData("$label 未知") }

    private fun uuid(raw: String, label: String): UUID = runCatching { UUID.fromString(raw) }
        .getOrElse { throw WeekyiiArchiveException.InvalidData("$label ID 无效") }

    private fun Long.toDate(): Date = Date(this)
    private fun Date.toLocalDate() = toInstant().atZone(zoneId).toLocalDate()
    private fun Date.toLocalDateTime(): LocalDateTime = toInstant().atZone(zoneId).toLocalDateTime()

    private fun WeekEntity.toRecord() = WeekyiiArchiveService.WeekRecord(weekId, startDate.time, endDate.time, status.name.lowercase(), completedTasksCount, expiredTasksCount, totalStartedDays)
    private fun DayEntity.toRecord() = WeekyiiArchiveService.DayRecord(dayId, weekOwnerId, date.time, dayOfWeek, status.name.lowercase(), killHour, killMinute, followsDefaultKillTime, initiatedAt?.time, closedAt?.time, executionModeRaw, isDraftZoneUnlocked, expiredCount)
    private fun ProjectEntity.toRecord() = WeekyiiArchiveService.ProjectRecord(projectId.toString(), name, status.name.lowercase(), startDate.time, endDate.time, description, color, icon, createdAt.time, tileSizeRaw, tileOrder)
    private fun MindStampEntity.toRecord() = WeekyiiArchiveService.MindStampRecord(id.toString(), text, imageBlob?.let { Base64.getEncoder().encodeToString(it) }, createdAt.time)
    private fun TaskTypeDefinitionEntity.toRecord() = WeekyiiArchiveService.TaskTypeRecord(idRaw, name, iconName, colorHex, baseKind.name.lowercase(), sortOrder, isBuiltIn, isArchived)

    private fun TaskEntity.toRecord(steps: List<TaskStepEntity>, attachments: List<TaskAttachmentEntity>) = WeekyiiArchiveService.TaskRecord(
        id = id.toString(), dayId = dayOwnerId, projectId = projectOwnerId?.toString(), title = title, taskDescription = description,
        taskType = taskType.name.lowercase(), taskTypeIdRaw = taskTypeIdRaw, order = order, zone = zone.name.lowercase(),
        startedAt = startedAt?.time, endedAt = endedAt?.time, completedOrder = completedOrder,
        steps = steps.map { WeekyiiArchiveService.StepRecord(it.title, it.isCompleted, it.sortOrder, it.createdAt.time) },
        attachments = attachments.map { it.toRecord(id) }
    )

    private fun SuspendedTaskEntity.toRecord(steps: List<com.weekyii.android.data.db.entities.SuspendedTaskStepEntity>, attachments: List<com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity>) = WeekyiiArchiveService.SuspendedTaskRecord(
        id = id.toString(), title = title, taskDescription = description, taskType = taskType.name.lowercase(), taskTypeIdRaw = taskTypeIdRaw,
        createdAt = createdAt.time, decisionDeadline = decisionDeadline.time, preferredCountdownDays = preferredCountdownDays, snoozeCount = snoozeCount,
        statusRaw = status.name.lowercase(), steps = steps.map { WeekyiiArchiveService.StepRecord(it.title, it.isCompleted, it.sortOrder, it.createdAt.time) },
        attachments = attachments.map { it.toRecord(id) }
    )

    private fun TaskAttachmentEntity.toRecord(owner: UUID) = WeekyiiArchiveService.AttachmentRecord(
        id = UUID.nameUUIDFromBytes("$owner:$attachmentId".toByteArray()).toString(),
        dataBase64 = data?.let { Base64.getEncoder().encodeToString(it) }, fileName = fileName, fileType = fileType, createdAt = createdAt.time
    )

    private fun com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity.toRecord(owner: UUID) = WeekyiiArchiveService.AttachmentRecord(
        id = UUID.nameUUIDFromBytes("$owner:$attachmentId".toByteArray()).toString(),
        dataBase64 = data?.let { Base64.getEncoder().encodeToString(it) }, fileName = fileName, fileType = fileType, createdAt = createdAt.time
    )

    private fun WeekyiiArchiveService.WeekRecord.toEntity() = WeekEntity(weekId, startDate.toDate(), endDate.toDate(), enumWeek(status), completedTasksCount, expiredTasksCount, totalStartedDays)
    private fun WeekyiiArchiveService.DayRecord.toEntity() = DayEntity(dayId, date.toDate(), dayOfWeek, enumDay(status), killTimeHour, killTimeMinute, followsDefaultKillTime, initiatedAt?.toDate(), closedAt?.toDate(), executionModeRaw, isDraftZoneUnlocked, weekId ?: throw WeekyiiArchiveException.InvalidData("日期缺少所属周"), expiredCount)
    private fun WeekyiiArchiveService.ProjectRecord.toEntity() = ProjectEntity(uuid(id, "project"), name, projectDescription, color, icon, enumProject(status), startDate.toDate(), endDate.toDate(), createdAt.toDate(), tileSizeRaw, tileOrder)
    private fun WeekyiiArchiveService.MindStampRecord.toEntity() = MindStampEntity(uuid(id, "MindStamp"), text, imageBase64?.let { Base64.getDecoder().decode(it) }, createdAt.toDate())
    private fun WeekyiiArchiveService.TaskTypeRecord.toEntity() = TaskTypeDefinitionEntity(idRaw, name, iconName, colorHex, enumTaskType(baseKindRaw), sortOrder, isBuiltIn, isArchived)
    private fun WeekyiiArchiveService.TaskRecord.toEntity(taskId: UUID) = TaskEntity(taskId, title, taskDescription, enumTaskType(taskType), taskTypeIdRaw, order, enumZone(zone), startedAt?.toDate(), endedAt?.toDate(), completedOrder, dayId ?: throw WeekyiiArchiveException.InvalidData("任务缺少所属日期"), projectId?.let { uuid(it, "project") })
    private fun WeekyiiArchiveService.StepRecord.toEntity(owner: UUID) = TaskStepEntity(title = title, isCompleted = isCompleted, sortOrder = sortOrder, createdAt = createdAt.toDate(), taskOwnerId = owner)
    private fun WeekyiiArchiveService.AttachmentRecord.toEntity(owner: UUID) = TaskAttachmentEntity(data = dataBase64?.let { Base64.getDecoder().decode(it) }, fileName = fileName, fileType = fileType, createdAt = createdAt.toDate(), attachmentOwnerId = owner)
    private fun WeekyiiArchiveService.SuspendedTaskRecord.toEntity(taskId: UUID) = SuspendedTaskEntity(taskId, title, taskDescription, enumTaskType(taskType), taskTypeIdRaw, createdAt.toDate(), decisionDeadline.toDate(), preferredCountdownDays, snoozeCount, enumSuspendedStatus(statusRaw))
    private fun WeekyiiArchiveService.StepRecord.toSuspendedEntity(owner: UUID) = com.weekyii.android.data.db.entities.SuspendedTaskStepEntity(title = title, isCompleted = isCompleted, sortOrder = sortOrder, createdAt = createdAt.toDate(), suspendedTaskOwnerId = owner)
    private fun WeekyiiArchiveService.AttachmentRecord.toSuspendedEntity(owner: UUID) = com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity(data = dataBase64?.let { Base64.getDecoder().decode(it) }, fileName = fileName, fileType = fileType, createdAt = createdAt.toDate(), suspendedTaskOwnerId = owner)

    private fun enumWeek(raw: String) = WeekStatus.entries.firstOrNull { it.name.equals(raw, true) } ?: throw WeekyiiArchiveException.InvalidData("周状态未知")
    private fun enumDay(raw: String) = DayStatus.entries.firstOrNull { it.name.equals(raw, true) } ?: throw WeekyiiArchiveException.InvalidData("日期状态未知")
    private fun enumProject(raw: String) = ProjectStatus.entries.firstOrNull { it.name.equals(raw, true) } ?: throw WeekyiiArchiveException.InvalidData("项目状态未知")
    private fun enumTaskType(raw: String) = TaskType.entries.firstOrNull { it.name.equals(raw, true) } ?: throw WeekyiiArchiveException.InvalidData("任务类型未知")
    private fun enumZone(raw: String) = TaskZone.entries.firstOrNull { it.name.equals(raw, true) } ?: throw WeekyiiArchiveException.InvalidData("任务区域未知")
    private fun enumSuspendedStatus(raw: String) = SuspendedTaskStatus.entries.firstOrNull { it.name.equals(raw, true) } ?: throw WeekyiiArchiveException.InvalidData("悬置任务状态未知")
}
