import Foundation
import SwiftData

enum SuspendedTaskStatus: String, Codable, CaseIterable {
    case active
    case assigned
}

@Model
final class MindStampItem {
    var id: UUID = UUID()

    var text: String = ""
    @Attribute(.externalStorage) var imageBlob: Data?
    var createdAt: Date = Date()

    init(text: String = "", imageBlob: Data? = nil) {
        self.text = text
        self.imageBlob = imageBlob
        self.createdAt = Date()
    }

    /// Whether this stamp has any content
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageBlob != nil
    }
}

@Model
final class SuspendedTaskItem {
    var id: UUID = UUID()

    var title: String = ""
    var taskDescription: String = ""
    var taskType: TaskType = TaskType.regular
    var taskTypeIdRaw: String = TaskType.regular.rawValue
    var createdAt: Date = Date()
    var decisionDeadline: Date = Date()
    var preferredCountdownDays: Int = 0
    var snoozeCount: Int = 0
    var statusRaw: String = SuspendedTaskStatus.active.rawValue
    @Relationship(deleteRule: .cascade, originalName: "steps", inverse: \TaskStep.suspendedTask)
    private var stepRecords: [TaskStep]? = []
    @Relationship(deleteRule: .cascade, originalName: "attachments", inverse: \TaskAttachment.suspendedTask)
    private var attachmentRecords: [TaskAttachment]? = []

    init(
        title: String,
        taskDescription: String = "",
        taskType: TaskType = .regular,
        createdAt: Date = Date(),
        decisionDeadline: Date,
        preferredCountdownDays: Int,
        snoozeCount: Int = 0,
        status: SuspendedTaskStatus = .active
    ) {
        self.title = title
        self.taskDescription = taskDescription
        self.taskType = taskType
        self.taskTypeIdRaw = taskType.rawValue
        self.createdAt = createdAt
        self.decisionDeadline = decisionDeadline
        self.preferredCountdownDays = preferredCountdownDays
        self.snoozeCount = snoozeCount
        self.statusRaw = status.rawValue
    }

    var steps: [TaskStep] {
        get { stepRecords ?? [] }
        set { stepRecords = newValue }
    }

    var attachments: [TaskAttachment] {
        get { attachmentRecords ?? [] }
        set { attachmentRecords = newValue }
    }

    var status: SuspendedTaskStatus {
        get { SuspendedTaskStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    func remainingDays(from referenceDate: Date = Date()) -> Int {
        let calendar = Calendar(identifier: .iso8601)
        let start = calendar.startOfDay(for: referenceDate)
        let deadline = calendar.startOfDay(for: decisionDeadline)
        return calendar.dateComponents([.day], from: start, to: deadline).day ?? 0
    }
}
