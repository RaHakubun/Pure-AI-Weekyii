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
            day.week = week
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
            day.week = week
            week.days.append(day)
        }
        return week
    }
}
