import Foundation
import SwiftData

protocol AppStateStore: AnyObject {
    var systemStartDate: Date? { get set }
    var lastProcessedDate: Date? { get set }
    var lastRolloverAt: Date? { get set }
    var runtimeErrorMessage: String? { get set }
    var stateTransitionRevision: Int { get set }
    func save()
    func markProcessed(at date: Date)
    func incrementDaysStarted()
    func bumpStateTransitionRevision()
}

protocol KillTimeSettings {
    var defaultKillTimeHour: Int { get }
    var defaultKillTimeMinute: Int { get }
}

extension UserSettings: KillTimeSettings {}

@MainActor
struct StateMachine {
    private let modelContainer: ModelContainer
    private let timeProvider: TimeProviding
    private let notificationService: NotificationService
    private let appState: any AppStateStore
    private let userSettings: any KillTimeSettings
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let weekCalculator = WeekCalculator()

    init(
        modelContainer: ModelContainer,
        timeProvider: TimeProviding,
        notificationService: NotificationService,
        appState: any AppStateStore,
        userSettings: any KillTimeSettings
    ) {
        self.modelContainer = modelContainer
        self.timeProvider = timeProvider
        self.notificationService = notificationService
        self.appState = appState
        self.userSettings = userSettings
    }

    private var modelContext: ModelContext {
        modelContainer.mainContext
    }

    func processStateTransitions() {
        let lastProcessedBeforeRun = appState.lastProcessedDate
        ensureSystemStartDate()
        processStaleOpenDaysBeforeToday()
        processCrossDay()
        processCrossWeek()
        syncTodayDefaultKillTimeIfNeeded(lastProcessedBeforeRun: lastProcessedBeforeRun)
        processKillTime()
        processExpiredSuspendedTasks()
        refreshWeekSummaryMetrics()
        appState.markProcessed(at: timeProvider.now)
        appState.bumpStateTransitionRevision()
        persist()
    }

    private func ensureSystemStartDate() {
        if appState.systemStartDate == nil {
            appState.systemStartDate = timeProvider.today
            appState.save()
        }
        if appState.lastProcessedDate == nil {
            appState.lastProcessedDate = timeProvider.today
            appState.lastRolloverAt = timeProvider.now
            appState.save()
        }
    }

    private func processCrossDay() {
        guard let lastProcessed = appState.lastProcessedDate else { return }
        let today = timeProvider.today
        guard today > lastProcessed else { return }

        // Include the last processed day itself so missed rollover states are recovered.
        var cursor = lastProcessed
        while cursor < today {
            let dayId = cursor.dayId
            if let day = fetchDay(by: dayId) {
                switch day.status {
                case .execute:
                    expire(day: day, expiredCount: day.focusTaskCount + day.frozenTasks.count)
                case .draft:
                    expire(day: day, expiredCount: 0)
                default:
                    break
                }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today
        }
    }

    private func processStaleOpenDaysBeforeToday() {
        let today = timeProvider.today
        let descriptor = FetchDescriptor<DayModel>()
        let allDays = (try? modelContext.fetch(descriptor)) ?? []
        for day in allDays where day.date < today {
            guard day.status == .execute || day.status == .draft else { continue }
            let expiredCount = day.status == .draft ? 0 : (day.focusTaskCount + day.frozenTasks.count)
            expire(day: day, expiredCount: expiredCount)
        }
    }

    private func processCrossWeek() {
        let currentWeekId = timeProvider.currentWeekId
        let presentWeeks = fetchWeeks(status: .present).sorted { $0.startDate < $1.startDate }

        if presentWeeks.isEmpty {
            if let existingCurrent = fetchWeek(weekId: currentWeekId) {
                existingCurrent.status = .present
            } else {
                createPresentWeek(for: timeProvider.today)
            }
            return
        }

        if let currentPresent = presentWeeks.first(where: { $0.weekId == currentWeekId }) {
            for extra in presentWeeks where extra.weekId != currentPresent.weekId {
                finalizeWeekToPast(extra)
            }
            return
        }

        if let existingCurrent = fetchWeek(weekId: currentWeekId) {
            existingCurrent.status = .present
            for week in presentWeeks {
                finalizeWeekToPast(week)
            }
            return
        }

        for week in presentWeeks {
            finalizeWeekToPast(week)
        }
        createPresentWeek(for: timeProvider.today)
    }

    private func processKillTime() {
        guard let today = fetchDay(by: timeProvider.today.dayId) else { return }
        guard today.status == .execute || today.status == .draft else { return }

        guard let killDate = killDate(for: today) else { return }
        if timeProvider.now >= killDate {
            let expiredCount: Int
            if today.status == .draft {
                expiredCount = 0
            } else {
                expiredCount = today.focusTaskCount + today.frozenTasks.count
            }
            expire(day: today, expiredCount: expiredCount)
            notificationService.cancelKillTimeNotification(for: today)
        }
    }

    private func syncTodayDefaultKillTimeIfNeeded(lastProcessedBeforeRun: Date?) {
        let today = timeProvider.today
        let shouldSyncTodayDefault: Bool
        if let lastProcessedBeforeRun {
            shouldSyncTodayDefault = today > lastProcessedBeforeRun
        } else {
            shouldSyncTodayDefault = true
        }
        guard shouldSyncTodayDefault else { return }
        guard let todayDay = fetchOrCreateTodayDay() else { return }

        todayDay.killTimeHour = userSettings.defaultKillTimeHour
        todayDay.killTimeMinute = userSettings.defaultKillTimeMinute
        todayDay.followsDefaultKillTime = true
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
        day.tasks.removeAll { zones.contains($0.zone) }
        for task in toRemove {
            modelContext.delete(task)
        }
    }

    private func finalizeWeekToPast(_ week: WeekModel) {
        week.status = .past
        updateMetrics(for: week)
    }

    private func createPresentWeek(for date: Date) {
        let week = weekCalculator.makeWeek(for: date, status: .present)
        modelContext.insert(week)
        persist()
    }

    private func fetchDay(by dayId: String) -> DayModel? {
        let descriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == dayId })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchOrCreateTodayDay() -> DayModel? {
        let dayId = timeProvider.today.dayId
        if let existing = fetchDay(by: dayId) {
            return existing
        }

        guard let presentWeek = fetchWeeks(status: .present).sorted(by: { $0.startDate < $1.startDate }).first else {
            return nil
        }

        let day = DayModel(dayId: dayId, date: timeProvider.today, status: .empty)
        presentWeek.days.append(day)
        return day
    }

    private func fetchWeeks(status: WeekStatus) -> [WeekModel] {
        let descriptor = FetchDescriptor<WeekModel>()
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status == status }
    }

    private func fetchWeek(weekId: String) -> WeekModel? {
        let descriptor = FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })
        return try? modelContext.fetch(descriptor).first
    }

    private func refreshWeekSummaryMetrics() {
        let weeks = fetchWeeks(status: .past) + fetchWeeks(status: .present) + fetchWeeks(status: .pending)
        for week in weeks {
            updateMetrics(for: week)
        }
    }

    private func processExpiredSuspendedTasks() {
        let service = SuspendedTaskLifecycleService(modelContext: modelContext, notificationService: notificationService)
        do {
            _ = try service.sweepExpiredTasks(now: timeProvider.now)
        } catch {
            appState.runtimeErrorMessage = error.localizedDescription
        }
    }

    private func updateMetrics(for week: WeekModel) {
        week.completedTasksCount = week.days.reduce(0) { $0 + $1.completedTasks.count }
        week.expiredTasksCount = week.days.reduce(0) { $0 + $1.expiredCount }
        week.totalStartedDays = week.days.filter { [.execute, .completed, .expired].contains($0.status) }.count
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            appState.runtimeErrorMessage = error.localizedDescription
        }
    }
}

private extension DayModel {
    var focusTaskCount: Int { focusTask == nil ? 0 : 1 }
}
