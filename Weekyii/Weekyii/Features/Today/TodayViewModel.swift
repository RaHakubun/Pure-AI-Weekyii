import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TodayViewModel {
    enum KillTimeChangeImpact: Equatable {
        case normal
        case immediateExpire(expiredCount: Int)
    }

    private let modelContext: ModelContext
    private let timeProvider: TimeProviding
    private let notificationService: any NotificationScheduling
    private let appState: any AppStateStore
    private let userSettings: UserSettings
    private let randomMindStampProvider: () -> MindStampItem?
    private let calendar = Calendar(identifier: .iso8601)
    private let weekCalculator = WeekCalculator()

    var today: DayModel?
    var errorMessage: String?

    init(
        modelContext: ModelContext,
        timeProvider: TimeProviding,
        notificationService: any NotificationScheduling,
        appState: any AppStateStore,
        userSettings: UserSettings,
        randomMindStampProvider: (() -> MindStampItem?)? = nil
    ) {
        self.modelContext = modelContext
        self.timeProvider = timeProvider
        self.notificationService = notificationService
        self.appState = appState
        self.userSettings = userSettings
        self.randomMindStampProvider = randomMindStampProvider ?? {
            let descriptor = FetchDescriptor<MindStampItem>()
            let stamps = (try? modelContext.fetch(descriptor)) ?? []
            return stamps.randomElement()
        }
    }

    func refresh() {
        errorMessage = nil
        ensurePresentWeek()
        guard let day = fetchOrCreateToday() else {
            today = nil
            errorMessage = String(localized: "error.day_not_found")
            return
        }
        today = day

        var shouldPersist = false

        if day.status == .draft || day.status == .execute {
            updateNotificationSchedule(for: day)
            shouldPersist = true
        }

        if shouldPersist {
            persistOrRecordError()
        }
    }

    func seedDraftTasksForUITestsIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTestingSeedDraft") else { return }
        guard let day = fetchOrCreateToday() else { return }
        guard day.status == .draft || day.status == .empty else { return }

        let currentCount = day.sortedDraftTasks.count
        if currentCount >= 2 { return }

        let titles = ["Draft Task A", "Draft Task B"]
        for index in currentCount..<2 {
            do {
                try addTask(title: titles[index], type: .regular)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func pickStartRitualStamp() -> MindStampItem? {
        randomMindStampProvider()
    }

    func addTask(title: String, description: String = "", type: TaskType, steps: [TaskStep] = [], attachments: [TaskAttachment] = []) throws {
        guard let day = resolveToday() else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft || day.status == .empty else { throw WeekyiiError.cannotEditStartedDay }

        if day.status == .empty {
            day.status = .draft
        }

        let order = (day.sortedDraftTasks.last?.order ?? 0) + 1
        let task = TaskItem(title: title, taskDescription: description, taskType: type, order: order, zone: .draft)
        task.steps = normalizedStepCopies(from: steps)
        task.attachments = attachments
        day.tasks.append(task)
        updateNotificationSchedule(for: day)
        try modelContext.save()
        syncToday()
    }

    func updateTask(_ task: TaskItem, title: String, description: String, type: TaskType, steps: [TaskStep], attachments: [TaskAttachment]) throws {
        guard let day = resolveToday() else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft else { throw WeekyiiError.cannotEditStartedDay }
        task.title = title
        task.taskDescription = description
        task.taskType = type
        replaceSteps(for: task, with: steps)
        task.attachments = attachments
        updateNotificationSchedule(for: day)
        try modelContext.save()
        syncToday()
    }

    func deleteTasks(at offsets: IndexSet) throws {
        guard let day = resolveToday() else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft else { throw WeekyiiError.cannotEditStartedDay }
        let tasks = day.sortedDraftTasks
        let tasksToDelete = offsets.compactMap { index in
            tasks.indices.contains(index) ? tasks[index] : nil
        }
        day.tasks.removeAll { task in
            tasksToDelete.contains { $0.id == task.id }
        }
        for task in tasksToDelete {
            modelContext.delete(task)
        }
        renumberDraftTasks(for: day)
        if day.sortedDraftTasks.isEmpty {
            day.status = .empty
        }
        updateNotificationSchedule(for: day)
        try modelContext.save()
        syncToday()
    }

    func moveDraftTasks(from source: IndexSet, to destination: Int) throws {
        guard let day = resolveToday() else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft else { throw WeekyiiError.cannotEditStartedDay }
        let count = day.sortedDraftTasks.count
        guard source.isEmpty == false, destination >= 0, destination <= count else { return }
        var tasks = day.sortedDraftTasks
        tasks.move(fromOffsets: source, toOffset: destination)
        for (index, task) in tasks.enumerated() {
            task.order = index + 1
        }
        updateNotificationSchedule(for: day)
        try modelContext.save()
        syncToday()
    }

    func startDay() throws {
        guard let day = resolveToday() else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
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

        updateNotificationSchedule(for: day)

        try modelContext.save()
        syncToday()
    }

    func doneFocus() throws {
        guard let day = resolveToday() else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
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

        try modelContext.save()
        syncToday()
    }

    func evaluateKillTimeChangeImpact(hour: Int, minute: Int) throws -> KillTimeChangeImpact {
        guard let day = resolveToday() else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft || day.status == .execute else { throw WeekyiiError.cannotEditStartedDay }
        guard isValidKillTime(hour: hour, minute: minute) else { throw WeekyiiError.dateFormatInvalid }

        if willExpireImmediately(day: day, hour: hour, minute: minute) {
            return .immediateExpire(expiredCount: expiredCountForImmediateExpire(day: day))
        }
        return .normal
    }

    func changeKillTime(hour: Int, minute: Int, allowImmediateExpire: Bool = false) throws {
        guard let day = resolveToday() else { throw WeekyiiError.dayNotFound(timeProvider.today.dayId) }
        guard day.status == .draft || day.status == .execute else { throw WeekyiiError.cannotEditStartedDay }
        guard isValidKillTime(hour: hour, minute: minute) else { throw WeekyiiError.dateFormatInvalid }

        if willExpireImmediately(day: day, hour: hour, minute: minute) {
            guard allowImmediateExpire else {
                throw WeekyiiError.killTimePassed
            }
            day.killTimeHour = hour
            day.killTimeMinute = minute
            day.followsDefaultKillTime = false
            expire(day: day, expiredCount: expiredCountForImmediateExpire(day: day))
            try modelContext.save()
            syncToday()
            return
        }

        day.killTimeHour = hour
        day.killTimeMinute = minute
        day.followsDefaultKillTime = false
        updateNotificationSchedule(for: day)
        try modelContext.save()
        syncToday()
    }

    private func killDate(for day: DayModel) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day.date)
        components.hour = day.killTimeHour
        components.minute = day.killTimeMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private func isValidKillTime(hour: Int, minute: Int) -> Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    private func willExpireImmediately(day: DayModel, hour: Int, minute: Int) -> Bool {
        guard day.status == .draft || day.status == .execute else { return false }
        var components = calendar.dateComponents([.year, .month, .day], from: day.date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let newKillDate = calendar.date(from: components) else { return false }
        return timeProvider.now >= newKillDate
    }

    private func expiredCountForImmediateExpire(day: DayModel) -> Int {
        day.status == .draft ? 0 : (day.focusTaskCount + day.frozenTasks.count)
    }

    private func expire(day: DayModel, expiredCount: Int) {
        day.status = .expired
        day.expiredCount = expiredCount
        removeTasks(in: [.draft, .focus, .frozen], from: day)
        notificationService.cancelKillTimeNotification(for: day)
    }

    private func removeTasks(in zones: [TaskZone], from day: DayModel) {
        let toRemove = day.tasks.filter { zones.contains($0.zone) }
        day.tasks.removeAll { zones.contains($0.zone) }
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

    private func replaceSteps(for task: TaskItem, with steps: [TaskStep]) {
        task.steps.forEach { modelContext.delete($0) }
        task.steps = normalizedStepCopies(from: steps)
    }

    private func normalizedStepCopies(from steps: [TaskStep]) -> [TaskStep] {
        steps
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
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

    private func fetchDay(by dayId: String) -> DayModel? {
        let descriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == dayId })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchOrCreateToday() -> DayModel? {
        let dayId = timeProvider.today.dayId
        return fetchDay(by: dayId) ?? createMissingDay(for: timeProvider.today)
    }

    private func resolveToday() -> DayModel? {
        if let today {
            return today
        }
        let resolved = fetchOrCreateToday()
        self.today = resolved
        return resolved
    }

    private func ensurePresentWeek() {
        let descriptor = FetchDescriptor<WeekModel>()
        let presentWeeks = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status == .present }
        if presentWeeks.isEmpty == false { return }
        let week = weekCalculator.makeWeek(for: timeProvider.today, status: .present)
        modelContext.insert(week)
        persistOrRecordError()
    }

    private func createMissingDay(for date: Date) -> DayModel? {
        // Locate present week; if absent, bail (caller already called ensurePresentWeek)
        let descriptor = FetchDescriptor<WeekModel>()
        guard let week = try? modelContext.fetch(descriptor).first(where: { $0.status == .present }) else { return nil }
        let day = DayModel(dayId: date.dayId, date: date, status: .empty)
        week.days.append(day)
        persistOrRecordError()
        return day
    }

    private func persistOrRecordError() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateNotificationSchedule(for day: DayModel) {
        guard day.status == .draft || day.status == .execute else {
            notificationService.cancelKillTimeNotification(for: day)
            return
        }

        guard let killDate = killDate(for: day) else { return }
        if timeProvider.now >= killDate {
            let expiredCount = day.status == .draft ? 0 : (day.focusTaskCount + day.frozenTasks.count)
            expire(day: day, expiredCount: expiredCount)
            return
        }

        notificationService.scheduleKillTimeNotification(
            for: day,
            reminderMinutes: userSettings.killTimeReminderMinutes,
            fixedReminder: userSettings.fixedReminderEnabled
                ? DateComponents(hour: userSettings.fixedReminderHour, minute: userSettings.fixedReminderMinute)
                : nil
        )
    }

    private func syncToday() {
        today = fetchDay(by: timeProvider.today.dayId)
    }
}

private extension DayModel {
    var focusTaskCount: Int { focusTask == nil ? 0 : 1 }
}
