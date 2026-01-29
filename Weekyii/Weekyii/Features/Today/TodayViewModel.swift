import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TodayViewModel {
    private let modelContext: ModelContext
    private let timeProvider: TimeProviding
    private let notificationService: NotificationService
    private let appState: AppState
    private let calendar = Calendar(identifier: .iso8601)
    private let weekCalculator = WeekCalculator()

    var today: DayModel?
    var errorMessage: String?

    init(
        modelContext: ModelContext,
        timeProvider: TimeProviding,
        notificationService: NotificationService,
        appState: AppState
    ) {
        self.modelContext = modelContext
        self.timeProvider = timeProvider
        self.notificationService = notificationService
        self.appState = appState
    }

    func refresh() {
        ensurePresentWeek()
        let dayId = timeProvider.today.dayId
        today = fetchDay(by: dayId)
        errorMessage = nil
    }

    func addTask(title: String, type: TaskType) throws {
        guard let day = today else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft || day.status == .empty else { throw WeekyiiError.cannotEditStartedDay }

        if day.status == .empty {
            day.status = .draft
        }

        let order = (day.sortedDraftTasks.last?.order ?? 0) + 1
        let task = TaskItem(title: title, taskType: type, order: order, zone: .draft)
        task.day = day
        day.tasks.append(task)
        try? modelContext.save()
    }

    func updateTask(_ task: TaskItem, title: String, type: TaskType) throws {
        guard let day = today else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft else { throw WeekyiiError.cannotEditStartedDay }
        task.title = title
        task.taskType = type
        try? modelContext.save()
    }

    func deleteTasks(at offsets: IndexSet) throws {
        guard let day = today else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft else { throw WeekyiiError.cannotEditStartedDay }
        let tasks = day.sortedDraftTasks
        for index in offsets {
            let task = tasks[index]
            modelContext.delete(task)
        }
        renumberDraftTasks(for: day)
        try? modelContext.save()
    }

    func moveDraftTasks(from source: IndexSet, to destination: Int) throws {
        guard let day = today else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft else { throw WeekyiiError.cannotEditStartedDay }
        var tasks = day.sortedDraftTasks
        tasks.move(fromOffsets: source, toOffset: destination)
        for (index, task) in tasks.enumerated() {
            task.order = index + 1
        }
        try? modelContext.save()
    }

    func startDay() throws {
        guard let day = today else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft else { throw WeekyiiError.cannotEditStartedDay }
        let sortedTasks = day.sortedDraftTasks
        guard !sortedTasks.isEmpty else { throw WeekyiiError.cannotStartEmptyDay }

        let now = timeProvider.now
        if day.initiatedAt == nil {
            appState.incrementDaysStarted()
        }
        day.status = .execute
        day.initiatedAt = now

        if let first = sortedTasks.first {
            first.zone = .focus
            first.startedAt = now
            for task in sortedTasks.dropFirst() {
                task.zone = .frozen
            }
        }

        if let killDate = killDate(for: day), now >= killDate {
            expire(day: day, expiredCount: day.focusTaskCount + day.frozenTasks.count)
            notificationService.cancelKillTimeNotification(for: day)
        } else {
            notificationService.scheduleKillTimeNotification(for: day)
        }

        try? modelContext.save()
    }

    func doneFocus() throws {
        guard let day = today else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .execute else { throw WeekyiiError.cannotEditStartedDay }
        guard let focusTask = day.focusTask else { return }

        let now = timeProvider.now
        let completedCount = day.completedTasks.count
        focusTask.zone = .complete
        focusTask.endedAt = now
        focusTask.completedOrder = completedCount + 1

        if let next = day.frozenTasks.first {
            next.zone = .focus
            next.startedAt = now
        } else {
            day.status = .completed
            day.closedAt = now
            notificationService.cancelKillTimeNotification(for: day)
        }

        try? modelContext.save()
    }

    func changeKillTime(hour: Int, minute: Int) throws {
        guard let day = today else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft || day.status == .execute else { throw WeekyiiError.cannotEditStartedDay }
        if let killDate = killDate(for: day), timeProvider.now >= killDate {
            throw WeekyiiError.killTimePassed
        }
        day.killTimeHour = hour
        day.killTimeMinute = minute
        if day.status == .execute, let newKillDate = killDate(for: day), timeProvider.now >= newKillDate {
            expire(day: day, expiredCount: day.focusTaskCount + day.frozenTasks.count)
            notificationService.cancelKillTimeNotification(for: day)
        } else if day.status == .draft || day.status == .execute {
            notificationService.scheduleKillTimeNotification(for: day)
        }
        try? modelContext.save()
    }

    private func killDate(for day: DayModel) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day.date)
        components.hour = day.killTimeHour
        components.minute = day.killTimeMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private func expire(day: DayModel, expiredCount: Int) {
        day.status = .expired
        day.expiredCount = expiredCount
        removeTasks(in: [.draft, .focus, .frozen], from: day)
        notificationService.cancelKillTimeNotification(for: day)
    }

    private func removeTasks(in zones: [TaskZone], from day: DayModel) {
        let toRemove = day.tasks.filter { zones.contains($0.zone) }
        for task in toRemove {
            modelContext.delete(task)
        }
    }

    private func renumberDraftTasks(for day: DayModel) {
        let sorted = day.sortedDraftTasks
        for (index, task) in sorted.enumerated() {
            task.order = index + 1
        }
    }

    private func fetchDay(by dayId: String) -> DayModel? {
        let descriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == dayId })
        return try? modelContext.fetch(descriptor).first
    }

    private func ensurePresentWeek() {
        let descriptor = FetchDescriptor<WeekModel>()
        let presentWeeks = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status == .present }
        if let _ = presentWeeks.first { return }
        let week = weekCalculator.makeWeek(for: timeProvider.today, status: .present)
        modelContext.insert(week)
        try? modelContext.save()
    }
}

private extension DayModel {
    var focusTaskCount: Int { focusTask == nil ? 0 : 1 }
}
