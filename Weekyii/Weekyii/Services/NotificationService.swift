import Foundation
import UserNotifications

/// How aggressively the suspended box reminds the user before a decision deadline.
enum SuspendedReminderIntensity: String, CaseIterable, Codable, Identifiable {
    /// Only the due-day morning and evening checkpoints.
    case minimal
    /// One day before, plus the due-day checkpoints.
    case standard
    /// `advanceDays` before, one day before, plus the due-day checkpoints.
    case full

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimal: String(localized: "settings.suspended.reminder.intensity.minimal", defaultValue: "精简")
        case .standard: String(localized: "settings.suspended.reminder.intensity.standard", defaultValue: "标准")
        case .full: String(localized: "settings.suspended.reminder.intensity.full", defaultValue: "充分")
        }
    }

    var summary: String {
        switch self {
        case .minimal: String(localized: "settings.suspended.reminder.intensity.minimal.summary", defaultValue: "只在到期当天提醒")
        case .standard: String(localized: "settings.suspended.reminder.intensity.standard.summary", defaultValue: "提前一天与到期当天提醒")
        case .full: String(localized: "settings.suspended.reminder.intensity.full.summary", defaultValue: "提前多天、提前一天与到期当天提醒")
        }
    }
}

/// User-configurable reminder rhythm. The default value reproduces the historical
/// hardcoded behaviour so existing call sites and tests keep working unchanged.
struct NotificationConfiguration: Equatable {
    var morningHour: Int = 9
    var morningMinute: Int = 0
    var suspendedReminderEnabled: Bool = true
    var suspendedReminderIntensity: SuspendedReminderIntensity = .full
    var suspendedAdvanceDays: Int = 3
    var suspendedEveningHour: Int = 19
    var suspendedEveningMinute: Int = 30
    /// Carried here so the due-day reminder can tell the truth about what
    /// happens if the user does nothing.
    var suspendedExpiryPolicy: SuspendedExpiryPolicy = .autoDelete

    static let `default` = NotificationConfiguration()
}

protocol NotificationScheduling {
    func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int, fixedReminder: DateComponents?)
    func cancelKillTimeNotification(for day: DayModel)
    func removeDeliveredKillTimeNotifications(for day: DayModel)
    func scheduleSuspendedTaskNotifications(for task: SuspendedTaskItem)
    func cancelSuspendedTaskNotifications(for task: SuspendedTaskItem)
}

final class NotificationService: NotificationScheduling {
    struct ReminderPlanItem: Equatable {
        let identifier: String
        let title: String
        let body: String
        let fireDate: Date
    }

    struct KillTimeInput: Equatable {
        let dayId: String
        let dayDate: Date
        let killTimeHour: Int
        let killTimeMinute: Int
        let unfinishedCount: Int
    }

    struct SuspendedInput: Equatable {
        let taskID: UUID
        let decisionDeadline: Date
    }

    static let shared = NotificationService()
    private let calendar = Calendar(identifier: .iso8601)
    private let finalReminderLeadMinutes = 5

    /// Reminder rhythm driven by `UserSettings`. Updated whenever settings are saved.
    var configuration: NotificationConfiguration = .default
    
    private init() {}

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int, fixedReminder: DateComponents?) {
        cancelKillTimeNotification(for: day)
        let plan = killTimeReminderPlan(
            for: day,
            reminderMinutes: reminderMinutes,
            fixedReminder: fixedReminder,
            now: Date()
        )
        schedule(plan: plan)
    }

    func cancelKillTimeNotification(for day: DayModel) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: killTimeIdentifiers(for: day)
        )
    }

    func removeDeliveredKillTimeNotifications(for day: DayModel) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: killTimeIdentifiers(for: day)
        )
    }

    func scheduleSuspendedTaskNotifications(for task: SuspendedTaskItem) {
        cancelSuspendedTaskNotifications(for: task)
        let plan = suspendedReminderPlan(for: task, now: Date())
        schedule(plan: plan)
    }

    func cancelSuspendedTaskNotifications(for task: SuspendedTaskItem) {
        let identifiers = suspendedReminderIdentifiers(for: task)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func killTimeReminderPlan(
        for day: DayModel,
        reminderMinutes: Int,
        fixedReminder: DateComponents?,
        now: Date
    ) -> [ReminderPlanItem] {
        let unfinishedCount = day.sortedDraftTasks.count + day.frozenTasks.count + (day.focusTask == nil ? 0 : 1)
        let input = KillTimeInput(
            dayId: day.dayId,
            dayDate: day.date,
            killTimeHour: day.killTimeHour,
            killTimeMinute: day.killTimeMinute,
            unfinishedCount: unfinishedCount
        )

        return killTimeReminderPlan(
            for: input,
            reminderMinutes: reminderMinutes,
            fixedReminder: fixedReminder,
            now: now,
            configuration: configuration
        )
    }

    func killTimeReminderPlan(
        for input: KillTimeInput,
        reminderMinutes: Int,
        fixedReminder: DateComponents?,
        now: Date,
        configuration: NotificationConfiguration = .default
    ) -> [ReminderPlanItem] {
        guard let killDate = killDate(for: input), killDate > now else { return [] }
        guard input.unfinishedCount > 0 else { return [] }

        let title = String(localized: "notification.title")
        let killTimeString = formattedTime(for: killDate)

        var candidates: [ReminderPlanItem] = [
            ReminderPlanItem(
                identifier: killTimeIdentifier(for: input.dayId),
                title: title,
                body: String(localized: "notification.kill_time"),
                fireDate: killDate
            )
        ]

        if let morningDate = morningReminderDate(for: input.dayDate, configuration: configuration), morningDate > now {
            candidates.append(
                ReminderPlanItem(
                    identifier: morningReminderIdentifier(for: input.dayId),
                    title: title,
                    body: "今天还有\(input.unfinishedCount)项待处理，截止时间 \(killTimeString)",
                    fireDate: morningDate
                )
            )
        }

        if let fixedReminderDate = fixedReminderDate(for: input.dayDate, fixedReminder: fixedReminder), fixedReminderDate > now {
            candidates.append(
                ReminderPlanItem(
                    identifier: fixedReminderIdentifier(for: input.dayId),
                    title: title,
                    body: "固定时刻提醒：当前还有\(input.unfinishedCount)项待处理任务",
                    fireDate: fixedReminderDate
                )
            )
        }

        if reminderMinutes > 0,
           let preReminderDate = calendar.date(byAdding: .minute, value: -reminderMinutes, to: killDate),
           preReminderDate > now {
            candidates.append(
                ReminderPlanItem(
                    identifier: preKillTimeIdentifier(for: input.dayId),
                    title: title,
                    body: "距离截止还有 \(reminderMinutes) 分钟，请尽快推进任务",
                    fireDate: preReminderDate
                )
            )
        }

        if let finalReminderDate = calendar.date(byAdding: .minute, value: -finalReminderLeadMinutes, to: killDate),
           finalReminderDate > now {
            candidates.append(
                ReminderPlanItem(
                    identifier: finalKillTimeIdentifier(for: input.dayId),
                    title: title,
                    body: "最后提醒：\(killTimeString) 截止，未完成内容将进入过期",
                    fireDate: finalReminderDate
                )
            )
        }

        return dedupedAndSorted(candidates, now: now)
    }

    func suspendedReminderPlan(for task: SuspendedTaskItem, now: Date) -> [ReminderPlanItem] {
        let input = SuspendedInput(
            taskID: task.id,
            decisionDeadline: task.decisionDeadline
        )
        return suspendedReminderPlan(for: input, now: now, configuration: configuration)
    }

    func suspendedReminderPlan(
        for input: SuspendedInput,
        now: Date,
        configuration: NotificationConfiguration = .default
    ) -> [ReminderPlanItem] {
        guard configuration.suspendedReminderEnabled else { return [] }

        let title = String(localized: "notification.suspended.title", defaultValue: "悬置箱提醒")
        let dueDay = calendar.startOfDay(for: input.decisionDeadline)

        let morningHour = configuration.morningHour
        let morningMinute = configuration.morningMinute
        let eveningHour = configuration.suspendedEveningHour
        let eveningMinute = configuration.suspendedEveningMinute

        var checkpoints: [(suffix: String, offset: Int, hour: Int, minute: Int, body: String)] = []

        if configuration.suspendedReminderIntensity == .full {
            let advanceDays = min(max(configuration.suspendedAdvanceDays, 1), 14)
            checkpoints.append((
                "d\(advanceDays)",
                -advanceDays,
                morningHour,
                morningMinute,
                "还有 \(advanceDays) 天到期：请续期、分配到具体某一天，或删除。"
            ))
        }

        if configuration.suspendedReminderIntensity != .minimal {
            checkpoints.append(("d1", -1, morningHour, morningMinute, "明天到期：请尽快处理这个悬置任务。"))
        }

        checkpoints.append(("d0m", 0, morningHour, morningMinute, "今天到期：建议现在续期或分配到具体日期。"))
        let eveningBody = configuration.suspendedExpiryPolicy == .autoDelete
            ? String(
                localized: "notification.suspended.d0e.auto_delete",
                defaultValue: "今晚到期：若仍未处理，系统将自动删除该任务。"
            )
            : String(
                localized: "notification.suspended.d0e.keep_overdue",
                defaultValue: "今晚到期：若仍未处理，任务会留在悬置箱并标记为已逾期。"
            )
        checkpoints.append(("d0e", 0, eveningHour, eveningMinute, eveningBody))

        var items: [ReminderPlanItem] = []
        for checkpoint in checkpoints {
            guard let reminderDay = calendar.date(byAdding: .day, value: checkpoint.offset, to: dueDay) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
            components.hour = checkpoint.hour
            components.minute = checkpoint.minute
            components.second = 0
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            items.append(
                ReminderPlanItem(
                    identifier: "suspended-\(input.taskID.uuidString)-\(checkpoint.suffix)",
                    title: title,
                    body: checkpoint.body,
                    fireDate: fireDate
                )
            )
        }

        return dedupedAndSorted(items, now: now)
    }

    private func killDate(for input: KillTimeInput) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: input.dayDate)
        components.hour = input.killTimeHour
        components.minute = input.killTimeMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private func killTimeIdentifier(for day: DayModel) -> String {
        killTimeIdentifier(for: day.dayId)
    }

    private func killTimeIdentifier(for dayID: String) -> String {
        "killtime-\(dayID)"
    }

    private func preKillTimeIdentifier(for day: DayModel) -> String {
        preKillTimeIdentifier(for: day.dayId)
    }

    private func preKillTimeIdentifier(for dayID: String) -> String {
        "pre-killtime-\(dayID)"
    }

    private func morningReminderIdentifier(for day: DayModel) -> String {
        morningReminderIdentifier(for: day.dayId)
    }

    private func morningReminderIdentifier(for dayID: String) -> String {
        "morning-reminder-\(dayID)"
    }

    private func finalKillTimeIdentifier(for day: DayModel) -> String {
        finalKillTimeIdentifier(for: day.dayId)
    }

    private func finalKillTimeIdentifier(for dayID: String) -> String {
        "final-killtime-\(dayID)"
    }

    private func fixedReminderIdentifier(for day: DayModel) -> String {
        fixedReminderIdentifier(for: day.dayId)
    }

    private func fixedReminderIdentifier(for dayID: String) -> String {
        "fixed-reminder-\(dayID)"
    }

    private func killTimeIdentifiers(for day: DayModel) -> [String] {
        Self.killTimeNotificationIdentifiers(for: day.dayId)
    }

    static func killTimeNotificationIdentifiers(for dayID: String) -> [String] {
        [
            "killtime-\(dayID)",
            "morning-reminder-\(dayID)",
            "pre-killtime-\(dayID)",
            "final-killtime-\(dayID)",
            "fixed-reminder-\(dayID)"
        ]
    }

    private func fixedReminderDate(for dayDate: Date, fixedReminder: DateComponents?) -> Date? {
        guard let fixedReminder else { return nil }
        guard let hour = fixedReminder.hour, let minute = fixedReminder.minute else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: dayDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    func minuteKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)-\(parts.hour ?? 0)-\(parts.minute ?? 0)"
    }

    private func morningReminderDate(for dayDate: Date, configuration: NotificationConfiguration) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: dayDate)
        components.hour = configuration.morningHour
        components.minute = configuration.morningMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private func formattedTime(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func schedule(plan: [ReminderPlanItem]) {
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func dedupedAndSorted(_ items: [ReminderPlanItem], now: Date) -> [ReminderPlanItem] {
        var seenMinute = Set<String>()
        var seenIdentifiers = Set<String>()
        let ordered = items.sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate {
                return lhs.fireDate < rhs.fireDate
            }
            return lhs.identifier < rhs.identifier
        }

        var result: [ReminderPlanItem] = []
        for item in ordered where item.fireDate > now {
            let minute = minuteKey(for: item.fireDate)
            guard !seenIdentifiers.contains(item.identifier) else { continue }
            guard !seenMinute.contains(minute) else { continue }
            seenIdentifiers.insert(item.identifier)
            seenMinute.insert(minute)
            result.append(item)
        }
        return result
    }

    private func suspendedReminderIdentifiers(for task: SuspendedTaskItem) -> [String] {
        // The advance reminder suffix depends on the configured advance window, so the
        // removal set covers the whole supported range.
        let advance = (1...14).map { "d\($0)" }
        let staged = advance + ["d1", "d0m", "d0e"]
        let identifiers = staged.map { suffix in
            "suspended-\(task.id.uuidString)-\(suffix)"
        }
        // Backward compatibility: remove old checkpoint ids as well.
        let legacy = (0..<3).map { "suspended-\(task.id.uuidString)-\($0)" }
        return Array(Set(identifiers + legacy))
    }
}
