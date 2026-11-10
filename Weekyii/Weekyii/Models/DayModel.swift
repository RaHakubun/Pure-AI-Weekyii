import Foundation
import SwiftData

@Model
final class DayModel {
    var dayId: String = ""
    var date: Date = Date.distantPast
    var dayOfWeek: String = ""
    var status: DayStatus = DayStatus.empty

    var killTimeHour: Int = 23
    var killTimeMinute: Int = 45
    var followsDefaultKillTime: Bool = true

    var initiatedAt: Date?
    var closedAt: Date?
    var executionModeRaw: String = ExecutionMode.strict.rawValue
    var isDraftZoneUnlocked: Bool = false

    var week: WeekModel?

    @Relationship(deleteRule: .cascade, originalName: "tasks", inverse: \TaskItem.day)
    private var taskRecords: [TaskItem]? = []

    var expiredCount: Int = 0

    init(dayId: String, date: Date, status: DayStatus = .empty) {
        self.dayId = dayId
        self.date = date
        self.dayOfWeek = date.dayOfWeekShort
        self.status = status
    }

    var tasks: [TaskItem] {
        get { taskRecords ?? [] }
        set { taskRecords = newValue }
    }

    var killTime: DateComponents {
        DateComponents(hour: killTimeHour, minute: killTimeMinute)
    }

    var sortedDraftTasks: [TaskItem] {
        guard !isTerminal else { return [] }
        return tasks.filter { $0.zone == .draft }.sorted { $0.order < $1.order }
    }

    var focusTask: TaskItem? {
        guard !isTerminal else { return nil }
        return tasks.filter { $0.zone == .focus }.min { $0.order < $1.order }
    }

    var frozenTasks: [TaskItem] {
        guard !isTerminal else { return [] }
        return tasks.filter { $0.zone == .frozen }.sorted { $0.order < $1.order }
    }

    var completedTasks: [TaskItem] {
        tasks.filter { $0.zone == .complete }.sorted { $0.completedOrder < $1.completedOrder }
    }

    var hasSingleFocus: Bool {
        guard !isTerminal else { return true }
        return tasks.filter { $0.zone == .focus }.count <= 1
    }

    /// A terminal day hides late-arriving open-zone tasks from user-facing getters
    /// without deleting the raw synchronized records. `closedAt` is the only hard
    /// completion evidence; status alone may still be a soft derived value.
    var isTerminal: Bool {
        status == .expired || status == .completed
    }

    var executionMode: ExecutionMode {
        get { ExecutionMode(rawValue: executionModeRaw) ?? .strict }
        set { executionModeRaw = newValue.rawValue }
    }
}
