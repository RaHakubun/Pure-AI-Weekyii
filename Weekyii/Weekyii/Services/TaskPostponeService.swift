import Foundation
import SwiftData

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
