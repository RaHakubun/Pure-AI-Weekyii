import Foundation

extension Date {
    var dayId: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: self)
    }

    var weekId: String {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: self)
        let year = calendar.component(.yearForWeekOfYear, from: self)
        return String(format: "%04d-W%02d", year, week)
    }

    var dayOfWeekShort: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: self)
    }

    var startOfDay: Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: self)
    }

    var startOfWeek: Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }

    func addingDays(_ days: Int) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(byAdding: .day, value: days, to: self) ?? self
    }
}
