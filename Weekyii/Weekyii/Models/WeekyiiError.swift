import Foundation

enum WeekyiiError: LocalizedError {
    case dayNotFound(String)
    case taskNotFound(UUID)
    case cannotStartEmptyDay
    case cannotEditStartedDay
    case killTimePassed
    case dateFormatInvalid
    case postponeTargetMustBeFuture
    case postponeSourceTaskNotInToday
    case cannotPostponeCompletedTask
    case postponeTargetDayUnavailable

    var errorDescription: String? {
        switch self {
        case .dayNotFound(let id):
            return String(localized: "error.day_not_found") + " \(id)"
        case .taskNotFound:
            return String(localized: "error.task_not_found", defaultValue: "Task not found.")
        case .cannotStartEmptyDay:
            return String(localized: "error.cannot_start_empty", defaultValue: "Task list is empty.")
        case .cannotEditStartedDay:
            return String(localized: "error.cannot_edit_started", defaultValue: "Started days cannot be edited.")
        case .killTimePassed:
            return String(localized: "error.kill_time_passed", defaultValue: "Kill time has passed.")
        case .dateFormatInvalid:
            return String(localized: "error.date_format_invalid", defaultValue: "Invalid date format.")
        case .postponeTargetMustBeFuture:
            return "只能后移到未来日期。"
        case .postponeSourceTaskNotInToday:
            return "只能后移今日任务。"
        case .cannotPostponeCompletedTask:
            return "已完成任务不可后移。"
        case .postponeTargetDayUnavailable:
            return "目标日期不可接收后移任务。"
        }
    }
}
