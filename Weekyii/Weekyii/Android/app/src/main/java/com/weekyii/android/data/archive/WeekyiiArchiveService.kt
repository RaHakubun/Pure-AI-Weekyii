package com.weekyii.android.data.archive

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.MessageDigest
import java.util.Base64

sealed class WeekyiiArchiveException(message: String) : IllegalArgumentException(message) {
    data object UnsupportedFormat : WeekyiiArchiveException("不是有效的 Weekyii 归档")
    data class UnsupportedVersion(val version: Int) : WeekyiiArchiveException("归档版本 $version 暂不受支持")
    data object ChecksumMismatch : WeekyiiArchiveException("归档内容校验失败")
    data class InvalidData(val reason: String) : WeekyiiArchiveException("归档数据无效：$reason")
}

object WeekyiiArchiveService {
    const val formatIdentifier = "com.fluentdesign.weekyii.archive"
    const val currentFormatVersion = 1
    const val currentSchemaVersion = 6

    data class Inspection(
        val exportedAt: Long,
        val weekCount: Int,
        val dayCount: Int,
        val taskCount: Int,
        val projectCount: Int,
        val taskTypeCount: Int
    )

    @Serializable
    private data class Envelope(
        val formatIdentifier: String,
        val formatVersion: Int,
        val schemaVersion: Int,
        val exportedAt: Long,
        val appVersion: String,
        val payloadSHA256: String,
        val payload: String
    )

    @Serializable
    data class Payload(
        val weeks: List<WeekRecord> = emptyList(),
        val days: List<DayRecord> = emptyList(),
        val tasks: List<TaskRecord> = emptyList(),
        val projects: List<ProjectRecord> = emptyList(),
        val mindStamps: List<MindStampRecord> = emptyList(),
        val suspendedTasks: List<SuspendedTaskRecord> = emptyList(),
        val taskTypes: List<TaskTypeRecord> = emptyList(),
        val settings: SettingsRecord = SettingsRecord(),
        val appState: AppStateRecord = AppStateRecord()
    )

    @Serializable
    data class WeekRecord(
        val weekId: String,
        val startDate: Long,
        val endDate: Long,
        val status: String,
        val completedTasksCount: Int = 0,
        val expiredTasksCount: Int = 0,
        val totalStartedDays: Int = 0
    )

    @Serializable
    data class DayRecord(
        val dayId: String,
        val weekId: String? = null,
        val date: Long,
        val dayOfWeek: String,
        val status: String,
        val killTimeHour: Int,
        val killTimeMinute: Int,
        val followsDefaultKillTime: Boolean = true,
        val initiatedAt: Long? = null,
        val closedAt: Long? = null,
        val executionModeRaw: String = "strict",
        val isDraftZoneUnlocked: Boolean = false,
        val expiredCount: Int = 0
    )

    @Serializable
    data class StepRecord(
        val title: String,
        val isCompleted: Boolean = false,
        val sortOrder: Int = 0,
        val createdAt: Long = 0
    )

    @Serializable
    data class AttachmentRecord(
        val id: String,
        @SerialName("data")
        val dataBase64: String? = null,
        val fileName: String,
        val fileType: String,
        val createdAt: Long = 0
    )

    @Serializable
    data class TaskRecord(
        val id: String,
        val dayId: String? = null,
        val projectId: String? = null,
        val title: String,
        val taskDescription: String = "",
        val taskType: String,
        val taskTypeIdRaw: String,
        val order: Int,
        val zone: String,
        val startedAt: Long? = null,
        val endedAt: Long? = null,
        val completedOrder: Int = 0,
        val steps: List<StepRecord> = emptyList(),
        val attachments: List<AttachmentRecord> = emptyList()
    )

    @Serializable
    data class ProjectRecord(
        val id: String,
        val name: String,
        val status: String,
        val startDate: Long,
        val endDate: Long,
        val projectDescription: String = "",
        val color: String = "#C46A1A",
        val icon: String = "folder.fill",
        val createdAt: Long = 0,
        val tileSizeRaw: String = "medium",
        val tileOrder: Int = 0
    )

    @Serializable
    data class MindStampRecord(
        val id: String,
        val text: String,
        @SerialName("imageBlob")
        val imageBase64: String? = null,
        val createdAt: Long = 0
    )

    @Serializable
    data class SuspendedTaskRecord(
        val id: String,
        val title: String,
        val taskDescription: String = "",
        val taskType: String,
        val taskTypeIdRaw: String,
        val createdAt: Long,
        val decisionDeadline: Long,
        val preferredCountdownDays: Int,
        val snoozeCount: Int = 0,
        val statusRaw: String,
        val steps: List<StepRecord> = emptyList(),
        val attachments: List<AttachmentRecord> = emptyList()
    )

    @Serializable
    data class TaskTypeRecord(
        val idRaw: String,
        val name: String,
        val iconName: String,
        val colorHex: String,
        val baseKindRaw: String,
        val sortOrder: Int,
        val isBuiltIn: Boolean,
        val isArchived: Boolean
    )

    @Serializable
    data class SettingsRecord(
        val defaultKillTimeHour: Int = 20,
        val defaultKillTimeMinute: Int = 0,
        val defaultTaskTypeRaw: String = "regular",
        val defaultTaskTypeIdRaw: String = "regular",
        val defaultExecutionModeRaw: String = "strict",
        val killTimeReminderMinutes: Int = 60,
        val fixedReminderEnabled: Boolean = false,
        val fixedReminderHour: Int = 21,
        val fixedReminderMinute: Int = 0,
        val weekStartsOnMonday: Boolean = true,
        val defaultProjectDurationDays: Int = 7,
        val defaultProjectTileSizeRaw: String = "medium",
        val pendingMonthShowRegular: Boolean = false,
        val pendingMonthShowDDL: Boolean = true,
        val pendingMonthShowLeisure: Boolean = false,
        val selectedThemeRaw: String = "amber",
        val appearanceModeRaw: String = "system",
        val premiumThemeUnlocked: Boolean = false
    )

    @Serializable
    data class AppStateRecord(
        val daysStartedCount: Int = 0,
        val dataRevision: Int = 0,
        val stateTransitionRevision: Int = 0,
        val systemStartDate: Long? = null,
        val lastProcessedDate: Long? = null,
        val lastRolloverAt: Long? = null
    )

    private val json = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
        prettyPrint = false
        isLenient = false
    }

    fun encode(payload: Payload, exportedAt: Long = System.currentTimeMillis(), appVersion: String = "unknown"): ByteArray {
        val payloadBytes = json.encodeToString(payload).encodeToByteArray()
        val envelope = Envelope(
            formatIdentifier = formatIdentifier,
            formatVersion = currentFormatVersion,
            schemaVersion = currentSchemaVersion,
            exportedAt = exportedAt,
            appVersion = appVersion,
            payloadSHA256 = sha256(payloadBytes),
            payload = Base64.getEncoder().encodeToString(payloadBytes)
        )
        return json.encodeToString(envelope).encodeToByteArray()
    }

    fun inspect(data: ByteArray): Inspection {
        val (envelope, payload) = decode(data)
        validate(payload)
        return Inspection(
            exportedAt = envelope.exportedAt,
            weekCount = payload.weeks.size,
            dayCount = payload.days.size,
            taskCount = payload.tasks.size + payload.suspendedTasks.size,
            projectCount = payload.projects.size,
            taskTypeCount = payload.taskTypes.size
        )
    }

    fun decodePayload(data: ByteArray): Payload = decode(data).second.also(::validate)

    private fun decode(data: ByteArray): Pair<Envelope, Payload> {
        val envelope = runCatching { json.decodeFromString(Envelope.serializer(), data.decodeToString()) }
            .getOrElse { throw WeekyiiArchiveException.UnsupportedFormat }
        if (envelope.formatIdentifier != formatIdentifier) throw WeekyiiArchiveException.UnsupportedFormat
        if (envelope.formatVersion != currentFormatVersion) throw WeekyiiArchiveException.UnsupportedVersion(envelope.formatVersion)
        if (envelope.schemaVersion > currentSchemaVersion) throw WeekyiiArchiveException.UnsupportedVersion(envelope.schemaVersion)
        val payloadBytes = runCatching { Base64.getDecoder().decode(envelope.payload) }
            .getOrElse { throw WeekyiiArchiveException.UnsupportedFormat }
        if (sha256(payloadBytes) != envelope.payloadSHA256) throw WeekyiiArchiveException.ChecksumMismatch
        val payload = runCatching { json.decodeFromString(Payload.serializer(), payloadBytes.decodeToString()) }
            .getOrElse { throw WeekyiiArchiveException.InvalidData("内容无法解码") }
        return envelope to payload
    }

    private fun validate(payload: Payload) {
        requireUnique(payload.weeks.map { it.weekId }, "周 ID")
        requireUnique(payload.days.map { it.dayId }, "日期 ID")
        requireUnique(payload.tasks.map { it.id }, "任务 ID")
        requireUnique(payload.projects.map { it.id }, "项目 ID")
        requireUnique(payload.mindStamps.map { it.id }, "MindStamp ID")
        requireUnique(payload.suspendedTasks.map { it.id }, "悬置任务 ID")
        requireUnique(payload.taskTypes.map { it.idRaw }, "任务类型 ID")
        val weekIds = payload.weeks.mapTo(hashSetOf()) { it.weekId }
        val dayIds = payload.days.mapTo(hashSetOf()) { it.dayId }
        val projectIds = payload.projects.mapTo(hashSetOf()) { it.id }
        if (payload.days.any { it.weekId != null && it.weekId !in weekIds }) throw WeekyiiArchiveException.InvalidData("存在找不到所属周的日期")
        if (payload.tasks.any { it.dayId != null && it.dayId !in dayIds }) throw WeekyiiArchiveException.InvalidData("存在找不到所属日期的任务")
        if (payload.tasks.any { it.projectId != null && it.projectId !in projectIds }) throw WeekyiiArchiveException.InvalidData("存在找不到所属项目的任务")
        if (payload.settings.defaultKillTimeHour !in 0..23 || payload.settings.defaultKillTimeMinute !in 0..59) {
            throw WeekyiiArchiveException.InvalidData("默认截止时间超出范围")
        }
        if (payload.days.any { it.killTimeHour !in 0..23 || it.killTimeMinute !in 0..59 }) {
            throw WeekyiiArchiveException.InvalidData("日期截止时间超出范围")
        }
        if (payload.settings.killTimeReminderMinutes !in 0..120) {
            throw WeekyiiArchiveException.InvalidData("提前提醒分钟数超出范围")
        }
        if (payload.settings.appearanceModeRaw !in setOf("system", "light", "dark")) {
            throw WeekyiiArchiveException.InvalidData("外观模式未知")
        }
        if (payload.settings.selectedThemeRaw.isBlank()) {
            throw WeekyiiArchiveException.InvalidData("主题不能为空")
        }
        val validTaskTypes = setOf("regular", "ddl", "leisure")
        if (payload.taskTypes.any { it.baseKindRaw !in validTaskTypes }) throw WeekyiiArchiveException.InvalidData("任务类型行为未知")
        if (payload.suspendedTasks.any { it.statusRaw !in setOf("active", "assigned") }) {
            throw WeekyiiArchiveException.InvalidData("悬置任务状态未知")
        }
    }

    private fun requireUnique(values: List<String>, name: String) {
        if (values.toSet().size != values.size) throw WeekyiiArchiveException.InvalidData("$name 重复")
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { byte -> "%02x".format(byte) }
}
