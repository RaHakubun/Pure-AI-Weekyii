import Foundation
import SwiftData

@MainActor
protocol CloudSyncLocalStore: AnyObject {
    func currentSnapshot() throws -> WeekyiiBusinessSnapshot
    func apply(_ snapshot: WeekyiiBusinessSnapshot) throws
}

@MainActor
final class SwiftDataCloudSyncLocalStore: CloudSyncLocalStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func currentSnapshot() throws -> WeekyiiBusinessSnapshot {
        try WeekyiiSnapshotRepository.requireCleanSnapshot(from: context)
    }

    /// Applies normalized business entities directly to the existing canonical
    /// ModelContext. It never touches UserSettings/AppState or replaces the store.
    func apply(_ snapshot: WeekyiiBusinessSnapshot) throws {
        let current = try currentSnapshot()
        guard current != snapshot else { return }

        let desiredKeys = Set(snapshot.entityKeys())
        let existingKeys = Set(current.entityKeys())
        let keysToDelete = existingKeys.subtracting(desiredKeys)

        // Delete children before parents so SwiftData cascade rules cannot erase a
        // surviving item that the next two passes are about to rebuild.
        let attachments = try context.fetch(FetchDescriptor<TaskAttachment>())
        for value in attachments where keysToDelete.contains(value.cloudSyncEntityKey) { context.delete(value) }
        let habitDayRecords = try context.fetch(FetchDescriptor<HabitDayRecord>())
        for value in habitDayRecords where keysToDelete.contains(value.cloudSyncEntityKey) { context.delete(value) }
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        for value in tasks where keysToDelete.contains(value.cloudSyncEntityKey) { context.delete(value) }
        let suspendedTasks = try context.fetch(FetchDescriptor<SuspendedTaskItem>())
        for value in suspendedTasks where keysToDelete.contains(value.cloudSyncEntityKey) { context.delete(value) }
        let days = try context.fetch(FetchDescriptor<DayModel>())
        for value in days where keysToDelete.contains(value.cloudSyncEntityKey) { context.delete(value) }
        let weeks = try context.fetch(FetchDescriptor<WeekModel>())
        for value in weeks where keysToDelete.contains(value.cloudSyncEntityKey) { context.delete(value) }
        let projects = try context.fetch(FetchDescriptor<ProjectModel>())
        for value in projects where keysToDelete.contains(value.cloudSyncEntityKey) { context.delete(value) }
        let habits = try context.fetch(FetchDescriptor<HabitModel>())
        for value in habits where keysToDelete.contains(value.cloudSyncEntityKey) { context.delete(value) }
        let mindStamps = try context.fetch(FetchDescriptor<MindStampItem>())
        for value in mindStamps where keysToDelete.contains(value.cloudSyncEntityKey) { context.delete(value) }
        let taskTypes = try context.fetch(FetchDescriptor<TaskTypeDefinition>())
        for value in taskTypes where keysToDelete.contains(value.cloudSyncEntityKey) { context.delete(value) }

        let old = maps(for: current)
        var weekModels = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WeekModel>()).map { ($0.weekId, $0) })
        var dayModels = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<DayModel>()).map { ($0.dayId, $0) })
        var projectModels = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ProjectModel>()).map { ($0.id, $0) })
        var habitModels = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<HabitModel>()).map { ($0.id, $0) })
        var taskModels = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskItem>()).map { ($0.id, $0) })
        var suspendedModels = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SuspendedTaskItem>()).map { ($0.id, $0) })
        var attachmentModels = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskAttachment>()).map { ($0.id, $0) })
        var stampModels = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<MindStampItem>()).map { ($0.id, $0) })
        var typeModels = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskTypeDefinition>()).map { ($0.idRaw, $0) })
        var recordModels = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<HabitDayRecord>()).map { ($0.id, $0) })

        // Pass 1: create and update scalar payloads only.
        for value in snapshot.weeks {
            let model = weekModels[value.weekId] ?? WeekModel(weekId: value.weekId, startDate: value.startDate, endDate: value.endDate, status: value.status)
            if weekModels[value.weekId] == nil { context.insert(model); weekModels[value.weekId] = model }
            if old.weeks[value.weekId] != value {
                model.startDate = value.startDate; model.endDate = value.endDate; model.status = value.status
                model.completedTasksCount = value.completedTasksCount; model.expiredTasksCount = value.expiredTasksCount
                model.totalStartedDays = value.totalStartedDays
            }
        }
        for value in snapshot.days {
            let model = dayModels[value.dayId] ?? DayModel(dayId: value.dayId, date: value.date, status: value.status)
            if dayModels[value.dayId] == nil { context.insert(model); dayModels[value.dayId] = model }
            if old.days[value.dayId] != value {
                model.date = value.date; model.dayOfWeek = value.dayOfWeek; model.status = value.status
                model.killTimeHour = value.killTimeHour; model.killTimeMinute = value.killTimeMinute
                model.followsDefaultKillTime = value.followsDefaultKillTime; model.initiatedAt = value.initiatedAt
                model.closedAt = value.closedAt; model.executionModeRaw = value.executionModeRaw
                model.isDraftZoneUnlocked = value.isDraftZoneUnlocked; model.expiredCount = value.expiredCount
            }
        }
        for value in snapshot.projects {
            let model = projectModels[value.id] ?? ProjectModel(name: value.name, startDate: value.startDate, endDate: value.endDate)
            model.id = value.id
            if projectModels[value.id] == nil { context.insert(model); projectModels[value.id] = model }
            if old.projects[value.id] != value {
                model.name = value.name; model.projectDescription = value.projectDescription; model.color = value.color
                model.icon = value.icon; model.status = value.status; model.startDate = value.startDate
                model.endDate = value.endDate; model.createdAt = value.createdAt
                model.tileSizeRaw = value.tileSizeRaw; model.tileOrder = value.tileOrder
            }
        }
        for value in snapshot.habits {
            let model = habitModels[value.id] ?? HabitModel(name: value.name, startDayId: value.startDayId)
            model.id = value.id
            if habitModels[value.id] == nil { context.insert(model); habitModels[value.id] = model }
            if old.habits[value.id] != value {
                model.name = value.name; model.iconName = value.iconName; model.colorHex = value.colorHex
                model.categoryRaw = value.categoryRaw; model.scheduleKindRaw = value.scheduleKindRaw
                model.scheduleWeekdaysRaw = value.scheduleWeekdaysRaw; model.scheduleMonthDaysRaw = value.scheduleMonthDaysRaw
                model.startDayId = value.startDayId; model.isActive = value.isActive
                model.createdAt = value.createdAt; model.sortOrder = value.sortOrder
                // generatedThroughDayId is deliberately device-local and untouched.
            }
        }
        for value in snapshot.tasks {
            let model = taskModels[value.id] ?? TaskItem(title: value.title, taskDescription: value.taskDescription, taskType: value.taskType, order: value.order, zone: value.zone)
            model.id = value.id
            if taskModels[value.id] == nil { context.insert(model); taskModels[value.id] = model }
            if old.tasks[value.id] != value {
                model.title = value.title; model.taskDescription = value.taskDescription; model.taskType = value.taskType
                model.taskTypeIdRaw = value.taskTypeIdRaw; model.order = value.order; model.zone = value.zone
                model.startedAt = value.startedAt; model.endedAt = value.endedAt; model.completedOrder = value.completedOrder
                if old.tasks[value.id]?.steps != value.steps {
                    model.steps = value.steps.map { TaskStep(title: $0.title, isCompleted: $0.isCompleted, sortOrder: $0.sortOrder, createdAt: $0.createdAt) }
                }
            }
        }
        for value in snapshot.suspendedTasks {
            let model = suspendedModels[value.id] ?? SuspendedTaskItem(title: value.title, taskDescription: value.taskDescription, taskType: value.taskType, createdAt: value.createdAt, decisionDeadline: value.decisionDeadline, preferredCountdownDays: value.preferredCountdownDays)
            model.id = value.id
            if suspendedModels[value.id] == nil { context.insert(model); suspendedModels[value.id] = model }
            if old.suspendedTasks[value.id] != value {
                model.title = value.title; model.taskDescription = value.taskDescription; model.taskType = value.taskType
                model.taskTypeIdRaw = value.taskTypeIdRaw; model.createdAt = value.createdAt
                model.decisionDeadline = value.decisionDeadline; model.preferredCountdownDays = value.preferredCountdownDays
                model.snoozeCount = value.snoozeCount; model.statusRaw = value.statusRaw
                if old.suspendedTasks[value.id]?.steps != value.steps {
                    model.steps = value.steps.map { TaskStep(title: $0.title, isCompleted: $0.isCompleted, sortOrder: $0.sortOrder, createdAt: $0.createdAt) }
                }
            }
        }
        for value in snapshot.attachments {
            let model = attachmentModels[value.id] ?? TaskAttachment(id: value.id, data: value.data, fileName: value.fileName, fileType: value.fileType, createdAt: value.createdAt)
            if attachmentModels[value.id] == nil { context.insert(model); attachmentModels[value.id] = model }
            if old.attachments[value.id] != value {
                model.data = value.data; model.fileName = value.fileName; model.fileType = value.fileType; model.createdAt = value.createdAt
            }
        }
        for value in snapshot.mindStamps {
            let model = stampModels[value.id] ?? MindStampItem(text: value.text, imageBlob: value.imageBlob)
            model.id = value.id
            if stampModels[value.id] == nil { context.insert(model); stampModels[value.id] = model }
            if old.mindStamps[value.id] != value {
                model.text = value.text; model.imageBlob = value.imageBlob; model.createdAt = value.createdAt
            }
        }
        for value in snapshot.taskTypes {
            let model = typeModels[value.idRaw] ?? TaskTypeDefinition(idRaw: value.idRaw, name: value.name, iconName: value.iconName, colorHex: value.colorHex, baseKind: TaskType(rawValue: value.baseKindRaw) ?? .regular, sortOrder: value.sortOrder, isBuiltIn: value.isBuiltIn, isArchived: value.isArchived)
            if typeModels[value.idRaw] == nil { context.insert(model); typeModels[value.idRaw] = model }
            if old.taskTypes[value.idRaw] != value {
                model.name = value.name; model.iconName = value.iconName; model.colorHex = value.colorHex
                model.baseKindRaw = value.baseKindRaw; model.sortOrder = value.sortOrder
                model.isBuiltIn = value.isBuiltIn; model.isArchived = value.isArchived
            }
        }
        for value in snapshot.habitDayRecords {
            let model: HabitDayRecord
            if let existing = recordModels[value.id] {
                model = existing
            } else {
                model = HabitDayRecord(dayId: value.dayId, createdAt: value.createdAt)
                model.id = value.id
            }
            if recordModels[value.id] == nil { context.insert(model); recordModels[value.id] = model }
            if old.habitDayRecords[value.id] != value {
                model.dayId = value.dayId; model.statusRaw = value.statusRaw
                model.createdAt = value.createdAt; model.completedAt = value.completedAt
            }
        }

        // Pass 2: rebuild every relationship after all targets exist. Assigning the
        // inverse ends with a graph consistent with the normalized child→parent data.
        for value in snapshot.days { dayModels[value.dayId]?.week = value.weekId.flatMap { weekModels[$0] } }
        for value in snapshot.tasks {
            guard let model = taskModels[value.id] else { continue }
            model.day = value.dayId.flatMap { dayModels[$0] }
            model.project = value.projectId.flatMap { projectModels[$0] }
            model.habit = value.habitId.flatMap { habitModels[$0] }
        }
        for value in snapshot.attachments {
            guard let model = attachmentModels[value.id] else { continue }
            model.task = nil; model.suspendedTask = nil
            switch value.owner {
            case .task(let id): model.task = taskModels[id]
            case .suspendedTask(let id): model.suspendedTask = suspendedModels[id]
            }
        }
        for value in snapshot.habitDayRecords { recordModels[value.id]?.habit = value.habitId.flatMap { habitModels[$0] } }

        if context.hasChanges { try context.save() }
    }

    private struct SnapshotMaps {
        var weeks: [String: WeekSnapshot]
        var days: [String: DaySnapshot]
        var tasks: [UUID: TaskSnapshot]
        var suspendedTasks: [UUID: SuspendedTaskSnapshot]
        var attachments: [UUID: AttachmentSnapshot]
        var projects: [UUID: ProjectSnapshot]
        var mindStamps: [UUID: MindStampSnapshot]
        var taskTypes: [String: TaskTypeSnapshot]
        var habits: [UUID: HabitSnapshot]
        var habitDayRecords: [UUID: HabitDayRecordSnapshot]
    }

    private func maps(for snapshot: WeekyiiBusinessSnapshot) -> SnapshotMaps {
        SnapshotMaps(
            weeks: Dictionary(uniqueKeysWithValues: snapshot.weeks.map { ($0.weekId, $0) }),
            days: Dictionary(uniqueKeysWithValues: snapshot.days.map { ($0.dayId, $0) }),
            tasks: Dictionary(uniqueKeysWithValues: snapshot.tasks.map { ($0.id, $0) }),
            suspendedTasks: Dictionary(uniqueKeysWithValues: snapshot.suspendedTasks.map { ($0.id, $0) }),
            attachments: Dictionary(uniqueKeysWithValues: snapshot.attachments.map { ($0.id, $0) }),
            projects: Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) }),
            mindStamps: Dictionary(uniqueKeysWithValues: snapshot.mindStamps.map { ($0.id, $0) }),
            taskTypes: Dictionary(uniqueKeysWithValues: snapshot.taskTypes.map { ($0.idRaw, $0) }),
            habits: Dictionary(uniqueKeysWithValues: snapshot.habits.map { ($0.id, $0) }),
            habitDayRecords: Dictionary(uniqueKeysWithValues: snapshot.habitDayRecords.map { ($0.id, $0) })
        )
    }
}

private extension WeekModel { var cloudSyncEntityKey: SyncEntityKey { SyncEntityKey(kind: .week, businessId: weekId) } }
private extension DayModel { var cloudSyncEntityKey: SyncEntityKey { SyncEntityKey(kind: .day, businessId: dayId) } }
private extension TaskItem { var cloudSyncEntityKey: SyncEntityKey { SyncEntityKey(kind: .task, id: id) } }
private extension SuspendedTaskItem { var cloudSyncEntityKey: SyncEntityKey { SyncEntityKey(kind: .suspendedTask, id: id) } }
private extension TaskAttachment { var cloudSyncEntityKey: SyncEntityKey { SyncEntityKey(kind: .attachment, id: id) } }
private extension ProjectModel { var cloudSyncEntityKey: SyncEntityKey { SyncEntityKey(kind: .project, id: id) } }
private extension MindStampItem { var cloudSyncEntityKey: SyncEntityKey { SyncEntityKey(kind: .mindStamp, id: id) } }
private extension TaskTypeDefinition { var cloudSyncEntityKey: SyncEntityKey { SyncEntityKey(kind: .taskType, businessId: idRaw) } }
private extension HabitModel { var cloudSyncEntityKey: SyncEntityKey { SyncEntityKey(kind: .habit, id: id) } }
private extension HabitDayRecord { var cloudSyncEntityKey: SyncEntityKey { SyncEntityKey(kind: .habitDayRecord, id: id) } }
