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

struct StateReconcileReport: Equatable {
    var skipped: Bool = false
    var processedAt: Date?
    var staleDaysExpiredCount: Int = 0
    var crossDayExpiredCount: Int = 0
    var crossWeekAdjustedCount: Int = 0
    var killTimeExpiredCount: Int = 0
    var suspendedAutoDeletedCount: Int = 0
    var repairedFocusCount: Int = 0
    var repairedStatusCount: Int = 0
    var repairedOrderCount: Int = 0
    var createdTodayDayCount: Int = 0

    var totalRepairCount: Int {
        repairedFocusCount + repairedStatusCount + repairedOrderCount + createdTodayDayCount
    }
}

struct DataInvariantRepairReport: Equatable {
    var repairedFocusCount: Int = 0
    var repairedStatusCount: Int = 0
    var repairedOrderCount: Int = 0
    var createdTodayDayCount: Int = 0

    var totalRepairs: Int {
        repairedFocusCount + repairedStatusCount + repairedOrderCount + createdTodayDayCount
    }
}

protocol DataInvariantRepairing {
    func repair(referenceDate: Date) -> DataInvariantRepairReport
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
    private let repairService: any DataInvariantRepairing
    private let calendar = Calendar(identifier: .iso8601)
    private let weekCalculator = WeekCalculator()

    init(
        modelContainer: ModelContainer,
        timeProvider: TimeProviding,
        notificationService: NotificationService,
        appState: any AppStateStore,
        userSettings: any KillTimeSettings,
        repairService: (any DataInvariantRepairing)? = nil
    ) {
        self.modelContainer = modelContainer
        self.timeProvider = timeProvider
        self.notificationService = notificationService
        self.appState = appState
        self.userSettings = userSettings
        self.repairService = repairService ?? DataInvariantRepairService(modelContainer: modelContainer)
    }

    private var modelContext: ModelContext {
        modelContainer.mainContext
    }

    func processStateTransitions() {
        _ = reconcile(now: timeProvider.now)
    }

    @discardableResult
    func reconcile(now: Date, force: Bool = false) -> StateReconcileReport {
        if !force, shouldSkipReconcile(now: now) {
            var skipped = StateReconcileReport()
            skipped.skipped = true
            skipped.processedAt = now
            return skipped
        }

        var report = StateReconcileReport()
        let lastProcessedBeforeRun = appState.lastProcessedDate
        ensureSystemStartDate()
        report.staleDaysExpiredCount = processStaleOpenDaysBeforeToday()
        report.crossDayExpiredCount = processCrossDay()
        report.crossWeekAdjustedCount = processCrossWeek()
        syncTodayDefaultKillTimeIfNeeded(lastProcessedBeforeRun: lastProcessedBeforeRun)
        report.killTimeExpiredCount = processKillTime()
        report.suspendedAutoDeletedCount = processExpiredSuspendedTasks()

        let repairReport = repairService.repair(referenceDate: now)
        report.repairedFocusCount = repairReport.repairedFocusCount
        report.repairedStatusCount = repairReport.repairedStatusCount
        report.repairedOrderCount = repairReport.repairedOrderCount
        report.createdTodayDayCount = repairReport.createdTodayDayCount

        refreshWeekSummaryMetrics()
        appState.markProcessed(at: now)
        appState.bumpStateTransitionRevision()
        persist()
        report.processedAt = now
        return report
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

    private func processCrossDay() -> Int {
        guard let lastProcessed = appState.lastProcessedDate else { return 0 }
        let today = timeProvider.today
        guard today > lastProcessed else { return 0 }

        // Include the last processed day itself so missed rollover states are recovered.
        var cursor = lastProcessed
        var expiredCount = 0
        while cursor < today {
            let dayId = cursor.dayId
            if let day = fetchDay(by: dayId) {
                switch day.status {
                case .execute:
                    if expire(day: day, expiredCount: day.focusTaskCount + day.frozenTasks.count) {
                        expiredCount += 1
                    }
                case .draft:
                    if expire(day: day, expiredCount: 0) {
                        expiredCount += 1
                    }
                default:
                    break
                }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today
        }
        return expiredCount
    }

    private func processStaleOpenDaysBeforeToday() -> Int {
        let today = timeProvider.today
        let descriptor = FetchDescriptor<DayModel>()
        let allDays = (try? modelContext.fetch(descriptor)) ?? []
        var expiredCount = 0
        for day in allDays where day.date < today {
            guard day.status == .execute || day.status == .draft else { continue }
            let pendingExpiredCount = day.status == .draft ? 0 : (day.focusTaskCount + day.frozenTasks.count)
            if expire(day: day, expiredCount: pendingExpiredCount) {
                expiredCount += 1
            }
        }
        return expiredCount
    }

    private func processCrossWeek() -> Int {
        let currentWeekId = timeProvider.currentWeekId
        let presentWeeks = fetchWeeks(status: .present).sorted { $0.startDate < $1.startDate }
        var adjustments = 0

        if presentWeeks.isEmpty {
            if let existingCurrent = fetchWeek(weekId: currentWeekId) {
                existingCurrent.status = .present
                adjustments += 1
            } else {
                createPresentWeek(for: timeProvider.today)
                adjustments += 1
            }
            return adjustments
        }

        if let currentPresent = presentWeeks.first(where: { $0.weekId == currentWeekId }) {
            for extra in presentWeeks where extra.weekId != currentPresent.weekId {
                finalizeWeekToPast(extra)
                adjustments += 1
            }
            return adjustments
        }

        if let existingCurrent = fetchWeek(weekId: currentWeekId) {
            existingCurrent.status = .present
            adjustments += 1
            for week in presentWeeks {
                finalizeWeekToPast(week)
                adjustments += 1
            }
            return adjustments
        }

        for week in presentWeeks {
            finalizeWeekToPast(week)
            adjustments += 1
        }
        createPresentWeek(for: timeProvider.today)
        adjustments += 1
        return adjustments
    }

    private func processKillTime() -> Int {
        guard let today = fetchDay(by: timeProvider.today.dayId) else { return 0 }
        guard today.status == .execute || today.status == .draft else { return 0 }

        guard let killDate = killDate(for: today) else { return 0 }
        if timeProvider.now >= killDate {
            let expiredCount: Int
            if today.status == .draft {
                expiredCount = 0
            } else {
                expiredCount = today.focusTaskCount + today.frozenTasks.count
            }
            _ = expire(day: today, expiredCount: expiredCount)
            notificationService.cancelKillTimeNotification(for: today)
            return 1
        }
        return 0
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

    @discardableResult
    private func expire(day: DayModel, expiredCount: Int) -> Bool {
        guard day.status != .expired else { return false }
        day.status = .expired
        day.expiredCount = expiredCount
        removeTasks(in: [.draft, .focus, .frozen], from: day)
        notificationService.cancelKillTimeNotification(for: day)
        return true
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

    private func processExpiredSuspendedTasks() -> Int {
        let service = SuspendedTaskLifecycleService(modelContext: modelContext, notificationService: notificationService)
        do {
            return try service.sweepExpiredTasks(now: timeProvider.now)
        } catch {
            appState.runtimeErrorMessage = error.localizedDescription
            return 0
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

    private func shouldSkipReconcile(now: Date) -> Bool {
        guard let lastProcessed = appState.lastProcessedDate else { return false }
        guard let lastRollover = appState.lastRolloverAt else { return false }
        let lastDay = calendar.startOfDay(for: lastProcessed)
        let nowDay = calendar.startOfDay(for: now)
        guard lastDay == nowDay else { return false }
        return minuteKey(for: lastRollover) == minuteKey(for: now)
    }

    private func minuteKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)-\(parts.hour ?? 0)-\(parts.minute ?? 0)"
    }
}

private extension DayModel {
    var focusTaskCount: Int { focusTask == nil ? 0 : 1 }
}

@MainActor
struct DataInvariantRepairService: DataInvariantRepairing {
    private let modelContainer: ModelContainer
    private let calendar = Calendar(identifier: .iso8601)
    private let weekCalculator = WeekCalculator()

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private var modelContext: ModelContext {
        modelContainer.mainContext
    }

    func repair(referenceDate: Date) -> DataInvariantRepairReport {
        var report = DataInvariantRepairReport()
        let days = (try? modelContext.fetch(FetchDescriptor<DayModel>())) ?? []
        let today = calendar.startOfDay(for: referenceDate)

        for day in days {
            if normalizeFocusZone(in: day) {
                report.repairedFocusCount += 1
            }
            if normalizeTaskOrder(in: day) {
                report.repairedOrderCount += 1
            }
            if normalizeStatus(in: day, now: referenceDate) {
                report.repairedStatusCount += 1
            }
        }

        if ensureTodayExists(today: today) {
            report.createdTodayDayCount += 1
        }

        if report.totalRepairs > 0 {
            try? modelContext.save()
        }
        return report
    }

    private func normalizeFocusZone(in day: DayModel) -> Bool {
        let focusTasks = day.tasks.filter { $0.zone == .focus }.sorted { $0.order < $1.order }
        guard focusTasks.count > 1 else { return false }
        for task in focusTasks.dropFirst() {
            task.zone = .frozen
        }
        return true
    }

    private func normalizeTaskOrder(in day: DayModel) -> Bool {
        var changed = false

        let draft = day.sortedDraftTasks
        for (index, task) in draft.enumerated() where task.order != index + 1 {
            task.order = index + 1
            changed = true
        }

        if day.status == .execute {
            var sequence = 1
            if let focus = day.focusTask, focus.order != sequence {
                focus.order = sequence
                changed = true
            }
            if day.focusTask != nil { sequence += 1 }
            for frozen in day.frozenTasks where frozen.order != sequence {
                frozen.order = sequence
                sequence += 1
                changed = true
            }
        }

        return changed
    }

    private func normalizeStatus(in day: DayModel, now: Date) -> Bool {
        let draftCount = day.tasks.filter { $0.zone == .draft }.count
        let focusCount = day.tasks.filter { $0.zone == .focus }.count
        let frozenCount = day.tasks.filter { $0.zone == .frozen }.count
        let completedCount = day.tasks.filter { $0.zone == .complete }.count

        let hasOpen = draftCount + focusCount + frozenCount > 0
        let newStatus: DayStatus

        switch day.status {
        case .expired:
            if hasOpen {
                newStatus = focusCount + frozenCount > 0 ? .execute : .draft
            } else {
                newStatus = .expired
            }
        case .empty:
            if focusCount + frozenCount > 0 {
                newStatus = .execute
            } else if draftCount > 0 {
                newStatus = .draft
            } else if completedCount > 0 {
                newStatus = .completed
            } else {
                newStatus = .empty
            }
        case .draft:
            if focusCount + frozenCount > 0 {
                newStatus = .execute
            } else if draftCount == 0 && completedCount > 0 {
                newStatus = .completed
            } else if draftCount == 0 {
                newStatus = .empty
            } else {
                newStatus = .draft
            }
        case .execute:
            if focusCount + frozenCount > 0 {
                newStatus = .execute
            } else if draftCount > 0 {
                newStatus = .draft
            } else if completedCount > 0 {
                newStatus = .completed
            } else {
                newStatus = .empty
            }
        case .completed:
            if focusCount + frozenCount > 0 {
                newStatus = .execute
            } else if draftCount > 0 {
                newStatus = .draft
            } else if completedCount > 0 {
                newStatus = .completed
            } else {
                newStatus = .empty
            }
            if newStatus == .completed && day.closedAt == nil {
                day.closedAt = now
            }
        }

        guard newStatus != day.status else { return false }
        day.status = newStatus
        return true
    }

    private func ensureTodayExists(today: Date) -> Bool {
        if fetchDay(by: today.dayId) != nil {
            return false
        }

        let weekId = today.weekId
        let week: WeekModel
        if let existing = fetchWeek(by: weekId) {
            week = existing
            if week.status != .present {
                week.status = .present
            }
        } else {
            week = weekCalculator.makeWeek(for: today, status: .present)
            modelContext.insert(week)
        }

        if week.days.contains(where: { $0.dayId == today.dayId }) == false {
            let day = DayModel(dayId: today.dayId, date: today, status: .empty)
            week.days.append(day)
        }

        return true
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
