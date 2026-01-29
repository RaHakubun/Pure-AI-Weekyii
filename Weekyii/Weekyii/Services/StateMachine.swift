import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class StateMachine {
    private let modelContext: ModelContext
    private let timeProvider: TimeProviding
    private let notificationService: NotificationService
    private let appState: AppState
    private let calendar = Calendar(identifier: .iso8601)
    private let weekCalculator = WeekCalculator()

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

    func processStateTransitions() {
        ensureSystemStartDate()
        processCrossDay()
        processCrossWeek()
        processKillTime()
        appState.markProcessed(at: timeProvider.now)
        try? modelContext.save()
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

        var cursor = calendar.date(byAdding: .day, value: 1, to: lastProcessed) ?? today
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

    private func processCrossWeek() {
        let currentWeekId = timeProvider.currentWeekId
        let presentWeeks = fetchWeeks(status: .present)

        if presentWeeks.isEmpty {
            createPresentWeek(for: timeProvider.today)
            return
        }

        if presentWeeks.count > 1 {
            for extra in presentWeeks.dropFirst() {
                finalizeWeekToPast(extra)
            }
        }

        guard let presentWeek = presentWeeks.first else { return }
        if presentWeek.weekId == currentWeekId {
            return
        }

        finalizeWeekToPast(presentWeek)

        if let pendingWeek = fetchWeek(weekId: currentWeekId, status: .pending) {
            pendingWeek.status = .present
        } else {
            createPresentWeek(for: timeProvider.today)
        }
    }

    private func processKillTime() {
        guard let today = fetchDay(by: timeProvider.today.dayId) else { return }
        guard today.status == .execute else { return }

        guard let killDate = killDate(for: today) else { return }
        if timeProvider.now >= killDate {
            expire(day: today, expiredCount: today.focusTaskCount + today.frozenTasks.count)
            notificationService.cancelKillTimeNotification(for: today)
        }
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

    private func finalizeWeekToPast(_ week: WeekModel) {
        week.status = .past
        week.completedTasksCount = week.days.reduce(0) { $0 + $1.completedTasks.count }
        week.expiredTasksCount = week.days.reduce(0) { $0 + $1.expiredCount }
        week.totalStartedDays = week.days.filter { [.execute, .completed, .expired].contains($0.status) }.count
    }

    private func createPresentWeek(for date: Date) {
        let week = weekCalculator.makeWeek(for: date, status: .present)
        modelContext.insert(week)
    }

    private func fetchDay(by dayId: String) -> DayModel? {
        let descriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == dayId })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchWeeks(status: WeekStatus) -> [WeekModel] {
        let descriptor = FetchDescriptor<WeekModel>()
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status == status }
    }

    private func fetchWeek(weekId: String, status: WeekStatus) -> WeekModel? {
        let descriptor = FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })
        return (try? modelContext.fetch(descriptor))?.first { $0.status == status }
    }
}

private extension DayModel {
    var focusTaskCount: Int { focusTask == nil ? 0 : 1 }
}
