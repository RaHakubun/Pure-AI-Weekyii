import Foundation
import SwiftData

@Model
final class WeekModel {
    @Attribute(.unique) var weekId: String
    var startDate: Date
    var endDate: Date
    var status: WeekStatus

    @Relationship(deleteRule: .cascade, inverse: \DayModel.week)
    var days: [DayModel] = []

    var completedTasksCount: Int = 0
    var expiredTasksCount: Int = 0
    var totalStartedDays: Int = 0

    init(weekId: String, startDate: Date, endDate: Date, status: WeekStatus = .pending) {
        self.weekId = weekId
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
    }

    var weekNumber: Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: startDate)
    }
}
