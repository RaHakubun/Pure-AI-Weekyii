import Foundation

enum WeekyiiTimeZone {
    static let anchorKey = "weekyii.timeZoneAnchor"

    static var identifier: String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: anchorKey), TimeZone(identifier: stored) != nil {
            return stored
        }
        let current = TimeZone.current.identifier
        defaults.set(current, forKey: anchorKey)
        return current
    }

    static var timeZone: TimeZone {
        TimeZone(identifier: identifier) ?? .current
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar
    }
}

extension Date {
    var dayId: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = WeekyiiTimeZone.timeZone
        return formatter.string(from: self)
    }

    var weekId: String {
        let calendar = WeekyiiTimeZone.calendar
        let week = calendar.component(.weekOfYear, from: self)
        let year = calendar.component(.yearForWeekOfYear, from: self)
        return String(format: "%04d-W%02d", year, week)
    }

    var dayOfWeekShort: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = WeekyiiTimeZone.timeZone
        return formatter.string(from: self)
    }

    var startOfDay: Date {
        WeekyiiTimeZone.calendar.startOfDay(for: self)
    }

    var startOfWeek: Date {
        var calendar = WeekyiiTimeZone.calendar
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }

    func addingDays(_ days: Int) -> Date {
        WeekyiiTimeZone.calendar.date(byAdding: .day, value: days, to: self) ?? self
    }
}

extension Date {
    /// ISO weekday：1 = 周一 ... 7 = 周日。
var isoWeekday: Int {
        let weekday = WeekyiiTimeZone.calendar.component(.weekday, from: self)
        return weekday == 1 ? 7 : weekday - 1
    }
}

/// YYYY-MM-DD ↔ Date 的稳定互转（与 `Date.dayId` 的格式/时区一致）。
enum WeekyiiDayId {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = WeekyiiTimeZone.timeZone
        return formatter
    }()

    static func date(from dayId: String) -> Date? {
        guard !dayId.isEmpty else { return nil }
        return formatter.date(from: dayId)
    }
}

/// weekday 展示辅助（locale 驱动；`veryShortWeekdaySymbols` 为周日打头）。
enum WeekyiiWeekday {
    static var localizedShortSymbols: [String] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = .autoupdatingCurrent
        return calendar.veryShortWeekdaySymbols
    }

    static func localizedSymbol(for isoWeekday: Int) -> String {
        let symbols = localizedShortSymbols
        guard !symbols.isEmpty else { return "\(isoWeekday)" }
        return symbols[isoWeekday % 7]
    }
}
