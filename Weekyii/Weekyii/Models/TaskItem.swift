import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID = UUID()

    var title: String
    var taskType: TaskType
    var order: Int
    var zone: TaskZone

    var taskDescription: String = ""
    
    @Relationship(deleteRule: .cascade) var steps: [TaskStep] = []
    @Relationship(deleteRule: .cascade) var attachments: [TaskAttachment] = []

    var startedAt: Date?
    var endedAt: Date?
    var completedOrder: Int = 0

    var day: DayModel?

    init(title: String, taskDescription: String = "", taskType: TaskType = .regular, order: Int, zone: TaskZone = .draft) {
        self.title = title
        self.taskDescription = taskDescription
        self.taskType = taskType
        self.order = order
        self.zone = zone
    }

    var taskNumber: String {
        String(format: "T%02d", order)
    }
}
