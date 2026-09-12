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
    
    init(title: String, isCompleted: Bool = false, sortOrder: Int = 0) {
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
