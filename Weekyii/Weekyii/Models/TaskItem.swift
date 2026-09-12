import Foundation
import SwiftData

@Model
final class TaskItem {
    var id: UUID = UUID()

    var title: String = ""
    var taskType: TaskType = TaskType.regular
    var taskTypeIdRaw: String = TaskType.regular.rawValue
    var order: Int = 0
    var zone: TaskZone = TaskZone.draft

    var taskDescription: String = ""
    
    @Relationship(deleteRule: .cascade, originalName: "steps", inverse: \TaskStep.task)
    private var stepRecords: [TaskStep]? = []
    @Relationship(deleteRule: .cascade, originalName: "attachments", inverse: \TaskAttachment.task)
    private var attachmentRecords: [TaskAttachment]? = []

    var startedAt: Date?
    var endedAt: Date?
    var completedOrder: Int = 0

    var day: DayModel?
    var project: ProjectModel?

    init(title: String, taskDescription: String = "", taskType: TaskType = .regular, order: Int, zone: TaskZone = .draft) {
        self.title = title
        self.taskDescription = taskDescription
        self.taskType = taskType
        self.taskTypeIdRaw = taskType.rawValue
        self.order = order
        self.zone = zone
    }

    var steps: [TaskStep] {
        get { stepRecords ?? [] }
        set { stepRecords = newValue }
    }

    var attachments: [TaskAttachment] {
        get { attachmentRecords ?? [] }
        set { attachmentRecords = newValue }
    }

    var taskNumber: String {
        String(format: "T%02d", order)
    }
}
