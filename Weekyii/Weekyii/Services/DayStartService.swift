import Foundation
import SwiftData

enum AutoStartSchedule {
    static func date(on day: Date, hour: Int, minute: Int) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        let calendar = WeekyiiTimeZone.calendar
        let dayStart = calendar.startOfDay(for: day)

        // If a local clock time does not exist during a daylight-saving jump,
        // use the first valid time after it. On a repeated time, use its first occurrence.
        return calendar.nextDate(
            after: dayStart.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ).flatMap { calendar.isDate($0, inSameDayAs: dayStart) ? $0 : nil }
    }
}

@MainActor
struct DayStartService {
    private struct TaskState {
        let task: TaskItem
        let zone: TaskZone
        let startedAt: Date?
    }

    private let modelContext: ModelContext
    private let appState: any AppStateStore

    init(modelContext: ModelContext, appState: any AppStateStore) {
        self.modelContext = modelContext
        self.appState = appState
    }

    func start(day: DayModel, at now: Date, executionMode: ExecutionMode) throws {
        guard day.status == .draft else { throw WeekyiiError.cannotEditStartedDay }
        let sortedTasks = day.sortedDraftTasks
        guard !sortedTasks.isEmpty else { throw WeekyiiError.cannotStartEmptyDay }

        let shouldCountStart = day.initiatedAt == nil
        let originalStatus = day.status
        let originalInitiatedAt = day.initiatedAt
        let originalExecutionMode = day.executionMode
        let originalDraftZoneUnlocked = day.isDraftZoneUnlocked
        let taskStates = sortedTasks.map {
            TaskState(task: $0, zone: $0.zone, startedAt: $0.startedAt)
        }

        day.status = .execute
        day.initiatedAt = now
        day.executionMode = executionMode
        day.isDraftZoneUnlocked = false

        if let first = sortedTasks.first {
            first.zone = .focus
            first.startedAt = now
            for task in sortedTasks.dropFirst() {
                task.zone = .frozen
            }
        }

        do {
            try modelContext.save()
        } catch {
            day.status = originalStatus
            day.initiatedAt = originalInitiatedAt
            day.executionMode = originalExecutionMode
            day.isDraftZoneUnlocked = originalDraftZoneUnlocked
            for state in taskStates {
                state.task.zone = state.zone
                state.task.startedAt = state.startedAt
            }
            throw error
        }

        // Keep the persisted counter behind the successful business-data save.
        if shouldCountStart {
            appState.incrementDaysStarted()
        }
        appState.bumpStateTransitionRevision()
    }
}
