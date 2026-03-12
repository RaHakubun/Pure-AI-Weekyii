import Foundation
import SwiftData

enum SuspendedTaskStatus: String, Codable, CaseIterable {
    case active
    case assigned
}

@Model
final class MindStampItem {
    @Attribute(.unique) var id: UUID = UUID()

    var text: String
    @Attribute(.externalStorage) var imageBlob: Data?
    var createdAt: Date

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
    @Attribute(.unique) var id: UUID = UUID()

    var title: String
    var taskDescription: String
    var taskType: TaskType
    var createdAt: Date
    var decisionDeadline: Date
    var preferredCountdownDays: Int
    var snoozeCount: Int
    var statusRaw: String
    @Relationship(deleteRule: .cascade) var steps: [TaskStep] = []
    @Relationship(deleteRule: .cascade) var attachments: [TaskAttachment] = []

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
        self.createdAt = createdAt
        self.decisionDeadline = decisionDeadline
        self.preferredCountdownDays = preferredCountdownDays
        self.snoozeCount = snoozeCount
        self.statusRaw = status.rawValue
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
