import Foundation

extension Calendar {
    func datesInWeek(of date: Date) -> [Date] {
        let start = date.startOfWeek
        return (0..<7).map { start.addingDays($0) }
    }

    func isDate(_ date1: Date, inSameWeekAs date2: Date) -> Bool {
        date1.weekId == date2.weekId
    }
}
