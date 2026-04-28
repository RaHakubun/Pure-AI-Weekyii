import Foundation
import SwiftData

struct TaskDraftPayload: Equatable {
    let title: String
    let description: String
    let type: TaskType
    let steps: [TaskStep]
    let attachments: [TaskAttachment]

    init(
        title: String,
        description: String,
        type: TaskType,
        steps: [TaskStep] = [],
        attachments: [TaskAttachment] = []
    ) {
        self.title = title
        self.description = description
        self.type = type
        self.steps = steps
        self.attachments = attachments
    }
}

enum TaskMutationResult: Equatable {
    case created(UUID)
    case updated(UUID)
    case deleted(UUID)
    case moved
}

protocol TaskMutating {
    @discardableResult
    func createTask(in day: DayModel, payload: TaskDraftPayload, zone: TaskZone, project: ProjectModel?) throws -> TaskItem
    func updateTask(_ task: TaskItem, payload: TaskDraftPayload) throws
    @discardableResult
    func deleteDraftTasks(in day: DayModel, at offsets: IndexSet) throws -> [TaskItem]
    func moveDraftTasks(in day: DayModel, from source: IndexSet, to destination: Int) throws
}

struct TaskMutationService: TaskMutating {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func createTask(in day: DayModel, payload: TaskDraftPayload, zone: TaskZone = .draft, project: ProjectModel? = nil) throws -> TaskItem {
        let normalizedTitle = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { throw WeekyiiError.taskTitleEmpty }

        let nextOrder: Int
        switch zone {
        case .draft:
            nextOrder = (day.sortedDraftTasks.last?.order ?? 0) + 1
        case .focus:
            nextOrder = 1
        case .frozen:
            nextOrder = (day.frozenTasks.last?.order ?? 0) + (day.focusTask == nil ? 1 : 2)
        case .complete:
            nextOrder = (day.completedTasks.last?.order ?? 0) + 1
        }

        let task = TaskItem(
            title: normalizedTitle,
            taskDescription: payload.description.trimmingCharacters(in: .whitespacesAndNewlines),
            taskType: payload.type,
            order: nextOrder,
            zone: zone
        )
        task.day = day
        task.project = project
        replaceTaskResources(for: task, steps: payload.steps, attachments: payload.attachments)
        day.tasks.append(task)

        if day.status == .empty, zone == .draft {
            day.status = .draft
        }
        if let project, project.status == .planning {
            project.status = .active
        }
        return task
    }

    func updateTask(_ task: TaskItem, payload: TaskDraftPayload) throws {
        let normalizedTitle = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { throw WeekyiiError.taskTitleEmpty }
        task.title = normalizedTitle
        task.taskDescription = payload.description.trimmingCharacters(in: .whitespacesAndNewlines)
        task.taskType = payload.type
        replaceTaskResources(for: task, steps: payload.steps, attachments: payload.attachments)
    }

    @discardableResult
    func deleteDraftTasks(in day: DayModel, at offsets: IndexSet) throws -> [TaskItem] {
        let tasks = day.sortedDraftTasks
        let tasksToDelete = offsets.compactMap { index in
            tasks.indices.contains(index) ? tasks[index] : nil
        }
        day.tasks.removeAll { task in tasksToDelete.contains(where: { $0.id == task.id }) }
        for task in tasksToDelete {
            modelContext.delete(task)
        }
        renumberDraftTasks(in: day)
        if day.sortedDraftTasks.isEmpty, day.status == .draft {
            day.status = .empty
        }
        return tasksToDelete
    }

    func moveDraftTasks(in day: DayModel, from source: IndexSet, to destination: Int) throws {
        let count = day.sortedDraftTasks.count
        guard source.isEmpty == false, destination >= 0, destination <= count else { return }
        var tasks = day.sortedDraftTasks
        tasks.move(fromOffsets: source, toOffset: destination)
        for (index, task) in tasks.enumerated() {
            task.order = index + 1
        }
    }

    func replaceTaskResources(for task: TaskItem, steps: [TaskStep], attachments: [TaskAttachment]) {
        task.steps.forEach { modelContext.delete($0) }
        task.steps.removeAll(keepingCapacity: true)
        task.steps.append(contentsOf: Self.normalizedStepCopies(from: steps))

        task.attachments.forEach { modelContext.delete($0) }
        task.attachments.removeAll(keepingCapacity: true)
        task.attachments.append(contentsOf: Self.attachmentCopies(from: attachments))
    }

    func replaceTaskResources(for task: SuspendedTaskItem, steps: [TaskStep], attachments: [TaskAttachment]) {
        task.steps.forEach { modelContext.delete($0) }
        task.steps.removeAll(keepingCapacity: true)
        task.steps.append(contentsOf: Self.normalizedStepCopies(from: steps))

        task.attachments.forEach { modelContext.delete($0) }
        task.attachments.removeAll(keepingCapacity: true)
        task.attachments.append(contentsOf: Self.attachmentCopies(from: attachments))
    }

    static func normalizedStepCopies(from steps: [TaskStep]) -> [TaskStep] {
        steps
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
            .enumerated()
            .map { index, step in
                TaskStep(
                    title: step.title,
                    isCompleted: step.isCompleted,
                    sortOrder: index
                )
            }
    }

    static func attachmentCopies(from attachments: [TaskAttachment]) -> [TaskAttachment] {
        attachments.map { attachment in
            TaskAttachment(
                data: attachment.data,
                fileName: attachment.fileName,
                fileType: attachment.fileType
            )
        }
    }

    private func renumberDraftTasks(in day: DayModel) {
        for (index, task) in day.sortedDraftTasks.enumerated() {
            task.order = index + 1
        }
    }
}

struct TaskPostponeService {
    struct Preview {
        let taskID: UUID
        let targetDate: Date
        let targetDayId: String
        let targetWeekId: String
        let requiresWeekCreation: Bool
    }

    struct ExecutionResult {
        let sourceDayId: String
        let targetDayId: String
        let targetDate: Date
        let createdWeek: Bool
    }

    private let modelContainer: ModelContainer
    private let calendar = Calendar(identifier: .iso8601)
    private let weekCalculator = WeekCalculator()

    private var modelContext: ModelContext {
        modelContainer.mainContext
    }

    init(modelContext: ModelContext) {
        self.modelContainer = modelContext.container
    }

    func preview(taskID: UUID, targetDate: Date, today: Date) throws -> Preview {
        let todayStart = calendar.startOfDay(for: today)
        let normalizedTargetDate = calendar.startOfDay(for: targetDate)
        guard normalizedTargetDate > todayStart else {
            throw WeekyiiError.postponeTargetMustBeFuture
        }

        let task = try fetchTask(by: taskID)
        try validateSourceTask(task, todayDayId: todayStart.dayId)

        let targetDayId = normalizedTargetDate.dayId
        let targetWeekId = normalizedTargetDate.weekId

        if let existingTargetDay = fetchDay(by: targetDayId) {
            guard isAcceptableTargetDayStatus(existingTargetDay.status) else {
                throw WeekyiiError.postponeTargetDayUnavailable
            }
            return Preview(
                taskID: taskID,
                targetDate: normalizedTargetDate,
                targetDayId: targetDayId,
                targetWeekId: targetWeekId,
                requiresWeekCreation: false
            )
        }

        let hasWeek = fetchWeek(by: targetWeekId) != nil
        return Preview(
            taskID: taskID,
            targetDate: normalizedTargetDate,
            targetDayId: targetDayId,
            targetWeekId: targetWeekId,
            requiresWeekCreation: !hasWeek
        )
    }

    func execute(preview: Preview, allowCreateWeek: Bool, today: Date, now: Date) throws -> ExecutionResult {
        let task = try fetchTask(by: preview.taskID)
        let sourceZone = task.zone
        let sourceDay = try resolveSourceDay(for: task)

        let todayDayId = calendar.startOfDay(for: today).dayId
        guard sourceDay.dayId == todayDayId else {
            throw WeekyiiError.postponeSourceTaskNotInToday
        }
        try validateSourceTask(task, todayDayId: todayDayId)

        let resolution = try resolveTargetDay(preview: preview, today: today, allowCreateWeek: allowCreateWeek)
        let targetDay = resolution.day
        guard isAcceptableTargetDayStatus(targetDay.status) else {
            throw WeekyiiError.postponeTargetDayUnavailable
        }

        sourceDay.tasks.removeAll { $0.id == task.id }

        task.day = targetDay
        if targetDay.tasks.contains(where: { $0.id == task.id }) == false {
            targetDay.tasks.append(task)
        }
        if targetDay.status == .empty {
            targetDay.status = .draft
        }

        task.zone = .draft
        task.order = nextDraftOrder(in: targetDay)
        task.startedAt = nil
        task.endedAt = nil
        task.completedOrder = 0

        repairSourceDayAfterRemoval(sourceDay, removedZone: sourceZone, now: now)
        renumberDraftTasks(in: targetDay)

        return ExecutionResult(
            sourceDayId: sourceDay.dayId,
            targetDayId: targetDay.dayId,
            targetDate: preview.targetDate,
            createdWeek: resolution.createdWeek
        )
    }

    private func resolveSourceDay(for task: TaskItem) throws -> DayModel {
        guard let sourceDay = task.day else {
            throw WeekyiiError.dayNotFound("unknown")
        }
        return sourceDay
    }

    private func validateSourceTask(_ task: TaskItem, todayDayId: String) throws {
        guard let sourceDay = task.day else {
            throw WeekyiiError.dayNotFound(todayDayId)
        }
        guard sourceDay.dayId == todayDayId else {
            throw WeekyiiError.postponeSourceTaskNotInToday
        }

        switch task.zone {
        case .draft, .focus, .frozen:
            break
        case .complete:
            throw WeekyiiError.cannotPostponeCompletedTask
        }
    }

    private func isAcceptableTargetDayStatus(_ status: DayStatus) -> Bool {
        status == .empty || status == .draft
    }

    private func resolveTargetDay(preview: Preview, today: Date, allowCreateWeek: Bool) throws -> (day: DayModel, createdWeek: Bool) {
        if let existingDay = fetchDay(by: preview.targetDayId) {
            return (existingDay, false)
        }

        if let existingWeek = fetchWeek(by: preview.targetWeekId) {
            let day = DayModel(dayId: preview.targetDayId, date: preview.targetDate, status: .empty)
            existingWeek.days.append(day)
            return (day, false)
        }

        guard allowCreateWeek else {
            throw WeekyiiError.postponeTargetDayUnavailable
        }

        let status = statusForNewWeek(targetDate: preview.targetDate, today: today)
        let week = weekCalculator.makeWeek(for: preview.targetDate, status: status)
        modelContext.insert(week)

        guard let day = week.days.first(where: { $0.dayId == preview.targetDayId }) else {
            let createdDay = DayModel(dayId: preview.targetDayId, date: preview.targetDate, status: .empty)
            week.days.append(createdDay)
            return (createdDay, true)
        }
        return (day, true)
    }

    private func statusForNewWeek(targetDate: Date, today: Date) -> WeekStatus {
        let targetWeekStart = calendar.startOfDay(for: targetDate).startOfWeek
        let todayWeekStart = calendar.startOfDay(for: today).startOfWeek
        if targetWeekStart == todayWeekStart {
            return .present
        }
        if targetWeekStart > todayWeekStart {
            return .pending
        }
        return .past
    }

    private func nextDraftOrder(in day: DayModel) -> Int {
        (day.sortedDraftTasks.last?.order ?? 0) + 1
    }

    private func renumberDraftTasks(in day: DayModel) {
        let sorted = day.sortedDraftTasks
        for (index, task) in sorted.enumerated() {
            task.order = index + 1
        }
    }

    private func repairSourceDayAfterRemoval(_ day: DayModel, removedZone: TaskZone, now: Date) {
        switch removedZone {
        case .draft:
            renumberDraftTasks(in: day)
            if day.sortedDraftTasks.isEmpty {
                day.status = .empty
            }

        case .focus:
            if let nextFocus = day.frozenTasks.first {
                nextFocus.zone = .focus
                if nextFocus.startedAt == nil {
                    nextFocus.startedAt = now
                }
                renumberExecutionQueue(in: day)
            } else {
                day.status = .completed
                day.closedAt = now
            }

        case .frozen:
            renumberExecutionQueue(in: day)
            if day.status == .draft {
                renumberDraftTasks(in: day)
                if day.sortedDraftTasks.isEmpty {
                    day.status = .empty
                }
            } else if day.status == .execute, day.focusTask == nil, day.frozenTasks.isEmpty {
                day.status = .completed
                day.closedAt = now
            }

        case .complete:
            break
        }
    }

    private func renumberExecutionQueue(in day: DayModel) {
        guard day.status == .execute else { return }
        var order = 1
        if let focus = day.focusTask {
            focus.order = order
            order += 1
        }
        for task in day.frozenTasks {
            task.order = order
            order += 1
        }
    }

    private func fetchTask(by taskID: UUID) throws -> TaskItem {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == taskID })
        if let task = try modelContext.fetch(descriptor).first {
            return task
        }
        throw WeekyiiError.taskNotFound(taskID)
    }

    private func fetchDay(by dayId: String) -> DayModel? {
        let descriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == dayId })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchWeek(by weekId: String) -> WeekModel? {
        let descriptor = FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })
        return try? modelContext.fetch(descriptor).first
    }
}
