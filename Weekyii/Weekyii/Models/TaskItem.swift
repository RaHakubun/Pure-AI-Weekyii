import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID = UUID()

    var title: String
    var taskType: TaskType
    var order: Int
    var zone: TaskZone

    var startedAt: Date?
    var endedAt: Date?
    var completedOrder: Int = 0

    var day: DayModel?

    var subtasks: [String] = []

    init(title: String, taskType: TaskType = .regular, order: Int, zone: TaskZone = .draft) {
        self.title = title
        self.taskType = taskType
        self.order = order
        self.zone = zone
    }

    var taskNumber: String {
        String(format: "T%02d", order)
    }
}
