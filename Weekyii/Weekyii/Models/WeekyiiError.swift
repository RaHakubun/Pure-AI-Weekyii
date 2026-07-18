import Foundation

enum WeekyiiError: LocalizedError, Equatable {
    case dayNotFound(String)
    case taskNotFound(UUID)
    case cannotStartEmptyDay
    case cannotEditStartedDay
    case killTimePassed
    case dateFormatInvalid
    case taskTitleEmpty
    case operationFailedRetry
    case postponeTargetMustBeFuture
    case postponeSourceTaskNotInToday
    case cannotPostponeCompletedTask
    case postponeTargetDayUnavailable
    case flexibleModeRequired
    case draftZoneLocked
    case executionQueueEmpty
    case projectReadOnly
    case projectHasOpenTasks
    case projectDateOutOfRange
    case projectTaskStateLocked

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
        case .taskTitleEmpty:
            return String(localized: "project.error.task_title_empty", defaultValue: "Task title cannot be empty.")
        case .operationFailedRetry:
            return String(localized: "error.operation_failed_retry", defaultValue: "Operation failed, please try again.")
        case .postponeTargetMustBeFuture:
            return "只能后移到未来日期。"
        case .postponeSourceTaskNotInToday:
            return "只能后移今日任务。"
        case .cannotPostponeCompletedTask:
            return "已完成任务不可后移。"
        case .postponeTargetDayUnavailable:
            return "目标日期不可接收后移任务。"
        case .flexibleModeRequired:
            return "该操作仅适用于灵动模式。"
        case .draftZoneLocked:
            return "草稿区仍处于冻结状态。"
        case .executionQueueEmpty:
            return "草稿区没有可交换的任务。"
        case .projectReadOnly:
            return "已完成或已归档的项目为只读状态，请先重新打开项目。"
        case .projectHasOpenTasks:
            return "项目仍有未完成任务，暂时不能结项。"
        case .projectDateOutOfRange:
            return "任务日期必须位于项目的开始与结束日期之间。"
        case .projectTaskStateLocked:
            return "该任务所属日期已启动或结束，不能从项目页面修改。"
        }
    }
}
