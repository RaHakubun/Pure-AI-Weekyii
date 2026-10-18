import Foundation
import SwiftData

struct WeekCalculator {
    private let calendar = Calendar(identifier: .iso8601)

    func weekId(for date: Date) -> String {
        date.weekId
    }

    func weekRange(for date: Date) -> (start: Date, end: Date) {
        let start = date.startOfWeek
        let end = start.addingDays(6)
        return (start, end)
    }

    func makeWeek(for date: Date, status: WeekStatus) -> WeekModel {
        let range = weekRange(for: date)
        let week = WeekModel(weekId: date.weekId, startDate: range.start, endDate: range.end, status: status)
        for dayDate in calendar.datesInWeek(of: date) {
            let day = DayModel(dayId: dayDate.dayId, date: dayDate, status: .empty)
            week.days.append(day)
        }
        return week
    }

    func makeWeek(weekId: String, startDate: Date, status: WeekStatus) -> WeekModel {
        let endDate = startDate.addingDays(6)
        let week = WeekModel(weekId: weekId, startDate: startDate, endDate: endDate, status: status)
        for offset in 0..<7 {
            let dayDate = startDate.addingDays(offset)
            let day = DayModel(dayId: dayDate.dayId, date: dayDate, status: .empty)
            week.days.append(day)
        }
        return week
    }

    func isValidWeekId(_ weekId: String) -> Bool {
        weekStartDate(for: weekId) != nil
    }

    func weekStartDate(for weekId: String) -> Date? {
        let normalized = weekId.uppercased()
        let parts = normalized.split(separator: "-")
        guard parts.count == 2 else { return nil }

        let yearPart = String(parts[0])
        let weekPart = String(parts[1])
        guard yearPart.count == 4, yearPart.allSatisfy(\.isNumber) else { return nil }
        guard weekPart.count == 3, weekPart.first == "W" else { return nil }

        let weekDigits = weekPart.dropFirst()
        guard weekDigits.allSatisfy(\.isNumber), let week = Int(weekDigits), (1...53).contains(week),
              let year = Int(yearPart) else {
            return nil
        }

        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 2
        guard let startDate = calendar.date(from: components) else { return nil }

        return startDate.weekId == normalized ? startDate : nil
    }
}
