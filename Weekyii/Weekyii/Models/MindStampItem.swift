import Foundation
import SwiftData

enum SuspendedTaskStatus: String, Codable, CaseIterable {
    case active
    case assigned
}

/// What happens to a suspended task once its decision deadline has passed.
///
/// Stored as a raw string in `UserDefaults`, so adding cases does not touch the
/// SwiftData schema.
enum SuspendedExpiryPolicy: String, CaseIterable, Codable, Identifiable {
    /// Delete the record silently. This is the historical behaviour and stays
    /// the default so existing installs do not change.
    case autoDelete
    /// Keep the record in the suspended box as an overdue item, so the user
    /// still gets to renew, assign or delete it themselves.
    case keepOverdue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .autoDelete:
            String(localized: "settings.suspended.expiry.auto_delete", defaultValue: "到期自动删除")
        case .keepOverdue:
            String(localized: "settings.suspended.expiry.keep_overdue", defaultValue: "保留为逾期待处理")
        }
    }

    var summary: String {
        switch self {
        case .autoDelete:
            String(localized: "settings.suspended.expiry.auto_delete.summary", defaultValue: "到期后直接删除，不留记录。")
        case .keepOverdue:
            String(localized: "settings.suspended.expiry.keep_overdue.summary", defaultValue: "到期后保留在悬置箱并标记为已逾期，由你决定续期、分配或删除。")
        }
    }
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
