import Foundation
import SwiftData

@Model
final class TaskStep {
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: Date
    
    init(title: String, isCompleted: Bool = false, sortOrder: Int = 0) {
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
