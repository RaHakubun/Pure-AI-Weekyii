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

extension WeekModel {
    func relativeWeekLabel(referenceDate: Date = Date()) -> String {
        let calendar = Calendar(identifier: .iso8601)
        let referenceStart = referenceDate.startOfWeek
        let targetStart = startDate.startOfWeek
        let diff = calendar.dateComponents([.weekOfYear], from: referenceStart, to: targetStart).weekOfYear ?? 0

        let isChinese = (Locale.current.languageCode ?? "").hasPrefix("zh")
        if diff == 0 {
            return isChinese ? "本周" : "This week"
        }

        let count = abs(diff)
        if diff > 0 {
            if isChinese {
                return count == 1 ? "未来一周" : "未来\(chineseNumber(for: count))周"
            }
            return count == 1 ? "In 1 week" : "In \(count) weeks"
        }

        if isChinese {
            return count == 1 ? "上一周" : "上\(chineseNumber(for: count))周"
        }
        return count == 1 ? "Last week" : "\(count) weeks ago"
    }
}

private func chineseNumber(for value: Int) -> String {
    switch value {
    case 1: return "一"
    case 2: return "二"
    case 3: return "三"
    case 4: return "四"
    case 5: return "五"
    case 6: return "六"
    case 7: return "七"
    case 8: return "八"
    case 9: return "九"
    case 10: return "十"
    default:
        return "\(value)"
    }
}
