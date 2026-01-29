import Foundation

enum WeekyiiError: LocalizedError {
    case dayNotFound(String)
    case cannotStartEmptyDay
    case cannotEditStartedDay
    case killTimePassed
    case dateFormatInvalid

    var errorDescription: String? {
        switch self {
        case .dayNotFound(let id):
            return String(localized: "error.day_not_found") + " \(id)"
        case .cannotStartEmptyDay:
            return String(localized: "error.cannot_start_empty", defaultValue: "Task list is empty.")
        case .cannotEditStartedDay:
            return String(localized: "error.cannot_edit_started", defaultValue: "Started days cannot be edited.")
        case .killTimePassed:
            return String(localized: "error.kill_time_passed", defaultValue: "Kill time has passed.")
        case .dateFormatInvalid:
            return String(localized: "error.date_format_invalid", defaultValue: "Invalid date format.")
        }
    }
}
