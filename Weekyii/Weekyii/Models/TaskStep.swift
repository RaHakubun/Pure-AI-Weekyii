import Foundation
import SwiftData

@Model
final class TaskStep {
    var title: String = ""
    var isCompleted: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var task: TaskItem?
    var suspendedTask: SuspendedTaskItem?
    
    /// Creates a step.
    ///
    /// A step has no business key of its own — it is embedded in its owner's
    /// snapshot rather than addressed individually. `createdAt` is therefore the
    /// only identity-ish field, and callers that re-create a step on behalf of an
    /// existing one must carry the original value across so that a no-op save
    /// does not look like a content change.
    ///
    /// Adds no persisted property; the schema stays at V8.
    init(title: String, isCompleted: Bool = false, sortOrder: Int = 0, createdAt: Date = Date()) {
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
