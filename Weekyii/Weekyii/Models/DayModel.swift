import Foundation
import SwiftData

@Model
final class DayModel {
    @Attribute(.unique) var dayId: String
    var date: Date
    var dayOfWeek: String
    var status: DayStatus

    var killTimeHour: Int = 20
    var killTimeMinute: Int = 0

    var initiatedAt: Date?
    var closedAt: Date?

    var week: WeekModel?

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.day)
    var tasks: [TaskItem] = []

    var expiredCount: Int = 0

    init(dayId: String, date: Date, status: DayStatus = .empty) {
        self.dayId = dayId
        self.date = date
        self.dayOfWeek = date.dayOfWeekShort
        self.status = status
    }

    var killTime: DateComponents {
        DateComponents(hour: killTimeHour, minute: killTimeMinute)
    }

    var sortedDraftTasks: [TaskItem] {
        tasks.filter { $0.zone == .draft }.sorted { $0.order < $1.order }
    }

    var focusTask: TaskItem? {
        tasks.filter { $0.zone == .focus }.min { $0.order < $1.order }
    }

    var frozenTasks: [TaskItem] {
        tasks.filter { $0.zone == .frozen }.sorted { $0.order < $1.order }
    }

    var completedTasks: [TaskItem] {
        tasks.filter { $0.zone == .complete }.sorted { $0.completedOrder < $1.completedOrder }
    }

    var hasSingleFocus: Bool {
        tasks.filter { $0.zone == .focus }.count <= 1
    }
}
