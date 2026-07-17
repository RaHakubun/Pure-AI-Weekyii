import Foundation
import CryptoKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct WeekyiiArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw WeekyiiArchiveError.unreadableFile
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum WeekyiiArchiveError: LocalizedError {
    case unreadableFile
    case unsupportedFormat
    case unsupportedVersion(Int)
    case checksumMismatch
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "无法读取所选文件。"
        case .unsupportedFormat: return "这不是有效的 Weekyii 归档。"
        case .unsupportedVersion(let version): return "归档版本 \(version) 暂不受支持，请先更新 Weekyii。"
        case .checksumMismatch: return "归档内容校验失败，文件可能已损坏或被修改。"
        case .invalidData(let reason): return "归档数据无效：\(reason)"
        }
    }
}

@MainActor
enum WeekyiiDataArchiveService {
    static let formatIdentifier = "com.fluentdesign.weekyii.archive"
    static let currentFormatVersion = 1
    static let currentSchemaVersion = 6

    struct Inspection: Equatable {
        let exportedAt: Date
        let weekCount: Int
        let dayCount: Int
        let taskCount: Int
        let projectCount: Int
        let taskTypeCount: Int

        var conciseSummary: String {
            "\(weekCount) 周 · \(dayCount) 天 · \(taskCount) 个任务 · \(projectCount) 个项目 · \(taskTypeCount) 个标签"
        }
    }

    private struct Envelope: Codable {
        let formatIdentifier: String
        let formatVersion: Int
        let schemaVersion: Int
        let exportedAt: Date
        let appVersion: String
        let payloadSHA256: String
        let payload: Data
    }

    struct Payload: Codable {
        let weeks: [WeekRecord]
        let days: [DayRecord]
        let tasks: [TaskRecord]
        let projects: [ProjectRecord]
        let mindStamps: [MindStampRecord]
        let suspendedTasks: [SuspendedTaskRecord]
        let taskTypes: [TaskTypeRecord]
        let settings: SettingsRecord
        let appState: AppStateRecord
    }

    struct WeekRecord: Codable {
        let weekId: String; let startDate: Date; let endDate: Date; let status: WeekStatus
        let completedTasksCount: Int; let expiredTasksCount: Int; let totalStartedDays: Int
    }
    struct DayRecord: Codable {
        let dayId: String; let weekId: String?; let date: Date; let dayOfWeek: String; let status: DayStatus
        let killTimeHour: Int; let killTimeMinute: Int; let followsDefaultKillTime: Bool
        let initiatedAt: Date?; let closedAt: Date?; let executionModeRaw: String
        let isDraftZoneUnlocked: Bool; let expiredCount: Int
    }
    struct StepRecord: Codable { let title: String; let isCompleted: Bool; let sortOrder: Int; let createdAt: Date }
    struct AttachmentRecord: Codable { let id: UUID; let data: Data?; let fileName: String; let fileType: String; let createdAt: Date }
    struct TaskRecord: Codable {
        let id: UUID; let dayId: String?; let projectId: UUID?; let title: String; let taskDescription: String
        let taskType: TaskType; let taskTypeIdRaw: String; let order: Int; let zone: TaskZone
        let startedAt: Date?; let endedAt: Date?; let completedOrder: Int
        let steps: [StepRecord]; let attachments: [AttachmentRecord]
    }
    struct ProjectRecord: Codable {
        let id: UUID; let name: String; let projectDescription: String; let color: String; let icon: String
        let status: ProjectStatus; let startDate: Date; let endDate: Date; let createdAt: Date
        let tileSizeRaw: String; let tileOrder: Int
    }
    struct MindStampRecord: Codable { let id: UUID; let text: String; let imageBlob: Data?; let createdAt: Date }
    struct SuspendedTaskRecord: Codable {
        let id: UUID; let title: String; let taskDescription: String; let taskType: TaskType; let taskTypeIdRaw: String
        let createdAt: Date; let decisionDeadline: Date; let preferredCountdownDays: Int; let snoozeCount: Int
        let statusRaw: String; let steps: [StepRecord]; let attachments: [AttachmentRecord]
    }
    struct TaskTypeRecord: Codable {
        let idRaw: String; let name: String; let iconName: String; let colorHex: String
        let baseKindRaw: String; let sortOrder: Int; let isBuiltIn: Bool; let isArchived: Bool
    }
    struct SettingsRecord: Codable {
        let defaultKillTimeHour: Int; let defaultKillTimeMinute: Int; let defaultTaskTypeRaw: String
        let defaultTaskTypeIdRaw: String; let defaultExecutionModeRaw: String; let killTimeReminderMinutes: Int
        let fixedReminderEnabled: Bool; let fixedReminderHour: Int; let fixedReminderMinute: Int
        let weekStartsOnMonday: Bool; let defaultProjectDurationDays: Int; let defaultProjectTileSizeRaw: String
        let pendingMonthShowRegular: Bool; let pendingMonthShowDDL: Bool; let pendingMonthShowLeisure: Bool
        let selectedThemeRaw: String; let appearanceModeRaw: String; let premiumThemeUnlocked: Bool
    }
    struct AppStateRecord: Codable {
        let daysStartedCount: Int; let dataRevision: Int; let stateTransitionRevision: Int
        let systemStartDate: Date?; let lastProcessedDate: Date?; let lastRolloverAt: Date?
    }

    static func export(modelContext: ModelContext, settings: UserSettings, appState: AppState) throws -> Data {
        try modelContext.save()
        let payload = try makePayload(modelContext: modelContext, settings: settings, appState: appState)
        let payloadData = try encoder().encode(payload)
        let envelope = Envelope(
            formatIdentifier: formatIdentifier,
            formatVersion: currentFormatVersion,
            schemaVersion: currentSchemaVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            payloadSHA256: sha256(payloadData),
            payload: payloadData
        )
        return try encoder().encode(envelope)
    }

    static func inspect(_ data: Data) throws -> Inspection {
        let (envelope, payload) = try decode(data)
        try validate(payload)
        return Inspection(
            exportedAt: envelope.exportedAt,
            weekCount: payload.weeks.count,
            dayCount: payload.days.count,
            taskCount: payload.tasks.count + payload.suspendedTasks.count,
            projectCount: payload.projects.count,
            taskTypeCount: payload.taskTypes.count
        )
    }

    @discardableResult
    static func importReplacing(
        _ data: Data,
        modelContext: ModelContext,
        settings: UserSettings,
        appState: AppState,
        storeURL: URL
    ) throws -> Inspection {
        let (envelope, payload) = try decode(data)
        try validate(payload)
        try modelContext.save()
        _ = try BackupRecoveryService.createSnapshot(storeURL: storeURL, reason: "import")

        do {
            try deleteAllData(in: modelContext)
            try insert(payload, into: modelContext)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        apply(payload.settings, to: settings)
        apply(payload.appState, to: appState)
        appState.bumpDataRevision()
        return Inspection(
            exportedAt: envelope.exportedAt,
            weekCount: payload.weeks.count,
            dayCount: payload.days.count,
            taskCount: payload.tasks.count + payload.suspendedTasks.count,
            projectCount: payload.projects.count,
            taskTypeCount: payload.taskTypes.count
        )
    }

    private static func makePayload(modelContext: ModelContext, settings: UserSettings, appState: AppState) throws -> Payload {
        let weeks = try modelContext.fetch(FetchDescriptor<WeekModel>())
        let days = try modelContext.fetch(FetchDescriptor<DayModel>())
        let tasks = try modelContext.fetch(FetchDescriptor<TaskItem>())
        let projects = try modelContext.fetch(FetchDescriptor<ProjectModel>())
        let stamps = try modelContext.fetch(FetchDescriptor<MindStampItem>())
        let suspended = try modelContext.fetch(FetchDescriptor<SuspendedTaskItem>())
        let taskTypes = try modelContext.fetch(FetchDescriptor<TaskTypeDefinition>())
        return Payload(
            weeks: weeks.map { .init(weekId: $0.weekId, startDate: $0.startDate, endDate: $0.endDate, status: $0.status, completedTasksCount: $0.completedTasksCount, expiredTasksCount: $0.expiredTasksCount, totalStartedDays: $0.totalStartedDays) },
            days: days.map { .init(dayId: $0.dayId, weekId: $0.week?.weekId, date: $0.date, dayOfWeek: $0.dayOfWeek, status: $0.status, killTimeHour: $0.killTimeHour, killTimeMinute: $0.killTimeMinute, followsDefaultKillTime: $0.followsDefaultKillTime, initiatedAt: $0.initiatedAt, closedAt: $0.closedAt, executionModeRaw: $0.executionModeRaw, isDraftZoneUnlocked: $0.isDraftZoneUnlocked, expiredCount: $0.expiredCount) },
            tasks: tasks.map { taskRecord($0) },
            projects: projects.map { .init(id: $0.id, name: $0.name, projectDescription: $0.projectDescription, color: $0.color, icon: $0.icon, status: $0.status, startDate: $0.startDate, endDate: $0.endDate, createdAt: $0.createdAt, tileSizeRaw: $0.tileSizeRaw, tileOrder: $0.tileOrder) },
            mindStamps: stamps.map { .init(id: $0.id, text: $0.text, imageBlob: $0.imageBlob, createdAt: $0.createdAt) },
            suspendedTasks: suspended.map { suspendedRecord($0) },
            taskTypes: taskTypes.map { .init(idRaw: $0.idRaw, name: $0.name, iconName: $0.iconName, colorHex: $0.colorHex, baseKindRaw: $0.baseKindRaw, sortOrder: $0.sortOrder, isBuiltIn: $0.isBuiltIn, isArchived: $0.isArchived) },
            settings: .init(defaultKillTimeHour: settings.defaultKillTimeHour, defaultKillTimeMinute: settings.defaultKillTimeMinute, defaultTaskTypeRaw: settings.defaultTaskType.rawValue, defaultTaskTypeIdRaw: settings.defaultTaskTypeIdRaw, defaultExecutionModeRaw: settings.defaultExecutionModeRaw, killTimeReminderMinutes: settings.killTimeReminderMinutes, fixedReminderEnabled: settings.fixedReminderEnabled, fixedReminderHour: settings.fixedReminderHour, fixedReminderMinute: settings.fixedReminderMinute, weekStartsOnMonday: settings.weekStartsOnMonday, defaultProjectDurationDays: settings.defaultProjectDurationDays, defaultProjectTileSizeRaw: settings.defaultProjectTileSizeRaw, pendingMonthShowRegular: settings.pendingMonthShowRegular, pendingMonthShowDDL: settings.pendingMonthShowDDL, pendingMonthShowLeisure: settings.pendingMonthShowLeisure, selectedThemeRaw: settings.selectedThemeRaw, appearanceModeRaw: settings.appearanceModeRaw, premiumThemeUnlocked: settings.premiumThemeUnlocked),
            appState: .init(daysStartedCount: appState.daysStartedCount, dataRevision: appState.dataRevision, stateTransitionRevision: appState.stateTransitionRevision, systemStartDate: appState.systemStartDate, lastProcessedDate: appState.lastProcessedDate, lastRolloverAt: appState.lastRolloverAt)
        )
    }

    private static func taskRecord(_ task: TaskItem) -> TaskRecord {
        .init(id: task.id, dayId: task.day?.dayId, projectId: task.project?.id, title: task.title, taskDescription: task.taskDescription, taskType: task.taskType, taskTypeIdRaw: task.taskTypeIdRaw, order: task.order, zone: task.zone, startedAt: task.startedAt, endedAt: task.endedAt, completedOrder: task.completedOrder, steps: task.steps.map { stepRecord($0) }, attachments: task.attachments.map { attachmentRecord($0) })
    }
    private static func suspendedRecord(_ task: SuspendedTaskItem) -> SuspendedTaskRecord {
        .init(id: task.id, title: task.title, taskDescription: task.taskDescription, taskType: task.taskType, taskTypeIdRaw: task.taskTypeIdRaw, createdAt: task.createdAt, decisionDeadline: task.decisionDeadline, preferredCountdownDays: task.preferredCountdownDays, snoozeCount: task.snoozeCount, statusRaw: task.statusRaw, steps: task.steps.map { stepRecord($0) }, attachments: task.attachments.map { attachmentRecord($0) })
    }
    private static func stepRecord(_ step: TaskStep) -> StepRecord { .init(title: step.title, isCompleted: step.isCompleted, sortOrder: step.sortOrder, createdAt: step.createdAt) }
    private static func attachmentRecord(_ item: TaskAttachment) -> AttachmentRecord { .init(id: item.id, data: item.data, fileName: item.fileName, fileType: item.fileType, createdAt: item.createdAt) }

    private static func decode(_ data: Data) throws -> (Envelope, Payload) {
        let envelope: Envelope
        do { envelope = try decoder().decode(Envelope.self, from: data) }
        catch { throw WeekyiiArchiveError.unsupportedFormat }
        guard envelope.formatIdentifier == formatIdentifier else { throw WeekyiiArchiveError.unsupportedFormat }
        guard envelope.formatVersion == currentFormatVersion else { throw WeekyiiArchiveError.unsupportedVersion(envelope.formatVersion) }
        guard envelope.schemaVersion <= currentSchemaVersion else { throw WeekyiiArchiveError.unsupportedVersion(envelope.schemaVersion) }
        guard sha256(envelope.payload) == envelope.payloadSHA256 else { throw WeekyiiArchiveError.checksumMismatch }
        do { return (envelope, try decoder().decode(Payload.self, from: envelope.payload)) }
        catch { throw WeekyiiArchiveError.invalidData("内容无法解码。") }
    }

    private static func validate(_ payload: Payload) throws {
        try requireUnique(payload.weeks.map(\.weekId), name: "周 ID")
        try requireUnique(payload.days.map(\.dayId), name: "日期 ID")
        try requireUnique(payload.tasks.map(\.id), name: "任务 ID")
        try requireUnique(payload.projects.map(\.id), name: "项目 ID")
        try requireUnique(payload.taskTypes.map(\.idRaw), name: "标签 ID")
        let weekIds = Set(payload.weeks.map(\.weekId)); let dayIds = Set(payload.days.map(\.dayId)); let projectIds = Set(payload.projects.map(\.id))
        guard payload.days.allSatisfy({ $0.weekId == nil || weekIds.contains($0.weekId!) }) else { throw WeekyiiArchiveError.invalidData("存在找不到所属周的日期。") }
        guard payload.tasks.allSatisfy({ $0.dayId == nil || dayIds.contains($0.dayId!) }) else { throw WeekyiiArchiveError.invalidData("存在找不到所属日期的任务。") }
        guard payload.tasks.allSatisfy({ $0.projectId == nil || projectIds.contains($0.projectId!) }) else { throw WeekyiiArchiveError.invalidData("存在找不到所属项目的任务。") }
        guard (0...23).contains(payload.settings.defaultKillTimeHour), (0...59).contains(payload.settings.defaultKillTimeMinute) else { throw WeekyiiArchiveError.invalidData("默认截止时间超出范围。") }
        guard payload.days.allSatisfy({ (0...23).contains($0.killTimeHour) && (0...59).contains($0.killTimeMinute) }) else { throw WeekyiiArchiveError.invalidData("日期截止时间超出范围。") }
        guard payload.suspendedTasks.allSatisfy({ SuspendedTaskStatus(rawValue: $0.statusRaw) != nil }) else { throw WeekyiiArchiveError.invalidData("暂存任务状态未知。") }
    }

    private static func requireUnique<T: Hashable>(_ values: [T], name: String) throws {
        guard Set(values).count == values.count else { throw WeekyiiArchiveError.invalidData("\(name) 重复。") }
    }

    private static func deleteAllData(in context: ModelContext) throws {
        try context.fetch(FetchDescriptor<TaskAttachment>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<TaskStep>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<TaskItem>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<DayModel>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<WeekModel>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<ProjectModel>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<MindStampItem>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<SuspendedTaskItem>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<TaskTypeDefinition>()).forEach { context.delete($0) }
    }

    private static func insert(_ payload: Payload, into context: ModelContext) throws {
        for record in payload.taskTypes {
            context.insert(TaskTypeDefinition(idRaw: record.idRaw, name: record.name, iconName: record.iconName, colorHex: record.colorHex, baseKind: TaskType(rawValue: record.baseKindRaw) ?? .regular, sortOrder: record.sortOrder, isBuiltIn: record.isBuiltIn, isArchived: record.isArchived))
        }
        var projects: [UUID: ProjectModel] = [:]
        for record in payload.projects {
            let item = ProjectModel(name: record.name, projectDescription: record.projectDescription, color: record.color, icon: record.icon, status: record.status, startDate: record.startDate, endDate: record.endDate)
            item.id = record.id; item.createdAt = record.createdAt; item.tileSizeRaw = record.tileSizeRaw; item.tileOrder = record.tileOrder
            context.insert(item); projects[record.id] = item
        }
        var weeks: [String: WeekModel] = [:]
        for record in payload.weeks {
            let item = WeekModel(weekId: record.weekId, startDate: record.startDate, endDate: record.endDate, status: record.status)
            item.completedTasksCount = record.completedTasksCount; item.expiredTasksCount = record.expiredTasksCount; item.totalStartedDays = record.totalStartedDays
            context.insert(item); weeks[record.weekId] = item
        }
        var days: [String: DayModel] = [:]
        for record in payload.days {
            let item = DayModel(dayId: record.dayId, date: record.date, status: record.status)
            item.dayOfWeek = record.dayOfWeek; item.killTimeHour = record.killTimeHour; item.killTimeMinute = record.killTimeMinute
            item.followsDefaultKillTime = record.followsDefaultKillTime; item.initiatedAt = record.initiatedAt; item.closedAt = record.closedAt
            item.executionModeRaw = record.executionModeRaw; item.isDraftZoneUnlocked = record.isDraftZoneUnlocked; item.expiredCount = record.expiredCount
            if let weekId = record.weekId { item.week = weeks[weekId] }
            context.insert(item); days[record.dayId] = item
        }
        for record in payload.tasks {
            let item = TaskItem(title: record.title, taskDescription: record.taskDescription, taskType: record.taskType, order: record.order, zone: record.zone)
            item.id = record.id; item.taskTypeIdRaw = record.taskTypeIdRaw; item.startedAt = record.startedAt; item.endedAt = record.endedAt; item.completedOrder = record.completedOrder
            item.steps = record.steps.map { makeStep($0) }; item.attachments = record.attachments.map { makeAttachment($0) }
            if let dayId = record.dayId { item.day = days[dayId] }
            if let projectId = record.projectId { item.project = projects[projectId] }
            context.insert(item)
        }
        for record in payload.mindStamps {
            let item = MindStampItem(text: record.text, imageBlob: record.imageBlob); item.id = record.id; item.createdAt = record.createdAt; context.insert(item)
        }
        for record in payload.suspendedTasks {
            let item = SuspendedTaskItem(title: record.title, taskDescription: record.taskDescription, taskType: record.taskType, createdAt: record.createdAt, decisionDeadline: record.decisionDeadline, preferredCountdownDays: record.preferredCountdownDays, snoozeCount: record.snoozeCount, status: SuspendedTaskStatus(rawValue: record.statusRaw) ?? .active)
            item.id = record.id; item.taskTypeIdRaw = record.taskTypeIdRaw; item.steps = record.steps.map { makeStep($0) }; item.attachments = record.attachments.map { makeAttachment($0) }; context.insert(item)
        }
    }

    private static func makeStep(_ record: StepRecord) -> TaskStep { let item = TaskStep(title: record.title, isCompleted: record.isCompleted, sortOrder: record.sortOrder); item.createdAt = record.createdAt; return item }
    private static func makeAttachment(_ record: AttachmentRecord) -> TaskAttachment { let item = TaskAttachment(data: record.data, fileName: record.fileName, fileType: record.fileType); item.id = record.id; item.createdAt = record.createdAt; return item }

    private static func apply(_ value: SettingsRecord, to settings: UserSettings) {
        settings.defaultKillTimeHour = value.defaultKillTimeHour; settings.defaultKillTimeMinute = value.defaultKillTimeMinute
        settings.defaultTaskType = TaskType(rawValue: value.defaultTaskTypeRaw) ?? .regular; settings.defaultTaskTypeIdRaw = value.defaultTaskTypeIdRaw
        settings.defaultExecutionModeRaw = value.defaultExecutionModeRaw; settings.killTimeReminderMinutes = value.killTimeReminderMinutes
        settings.fixedReminderEnabled = value.fixedReminderEnabled; settings.fixedReminderHour = value.fixedReminderHour; settings.fixedReminderMinute = value.fixedReminderMinute
        settings.weekStartsOnMonday = value.weekStartsOnMonday; settings.defaultProjectDurationDays = value.defaultProjectDurationDays; settings.defaultProjectTileSizeRaw = value.defaultProjectTileSizeRaw
        settings.pendingMonthShowRegular = value.pendingMonthShowRegular; settings.pendingMonthShowDDL = value.pendingMonthShowDDL; settings.pendingMonthShowLeisure = value.pendingMonthShowLeisure
        settings.selectedThemeRaw = value.selectedThemeRaw; settings.appearanceModeRaw = value.appearanceModeRaw; settings.premiumThemeUnlocked = value.premiumThemeUnlocked
    }
    private static func apply(_ value: AppStateRecord, to state: AppState) {
        state.daysStartedCount = value.daysStartedCount; state.dataRevision = value.dataRevision; state.stateTransitionRevision = value.stateTransitionRevision
        state.systemStartDate = value.systemStartDate; state.lastProcessedDate = value.lastProcessedDate; state.lastRolloverAt = value.lastRolloverAt; state.save()
    }

    private static func encoder() -> JSONEncoder { let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; value.dateEncodingStrategy = .millisecondsSince1970; return value }
    private static func decoder() -> JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .millisecondsSince1970; return value }
    private static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
