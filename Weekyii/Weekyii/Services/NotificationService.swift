import Foundation
import UserNotifications

protocol NotificationScheduling {
    func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int, fixedReminder: DateComponents?)
    func cancelKillTimeNotification(for day: DayModel)
    func scheduleSuspendedTaskNotifications(for task: SuspendedTaskItem)
    func cancelSuspendedTaskNotifications(for task: SuspendedTaskItem)
}

final class NotificationService: NotificationScheduling {
    static let shared = NotificationService()
    private let calendar = Calendar(identifier: .iso8601)

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

        guard let killDate = killDate(for: day) else { return }
        var scheduledMinuteKeys = Set<String>()

        // Main kill-time notification
        if killDate > Date() {
            let key = minuteKey(for: killDate)
            scheduledMinuteKeys.insert(key)
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification.title")
            content.body = String(localized: "notification.kill_time")
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: killDate),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: killTimeIdentifier(for: day), content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }

        let unfinishedCount = day.sortedDraftTasks.count + day.frozenTasks.count + (day.focusTask == nil ? 0 : 1)
        guard unfinishedCount > 0 else { return }

        if let fixedReminderDate = fixedReminderDate(for: day, fixedReminder: fixedReminder), fixedReminderDate > Date() {
            let key = minuteKey(for: fixedReminderDate)
            if !scheduledMinuteKeys.contains(key) {
                scheduledMinuteKeys.insert(key)
                let reminderContent = UNMutableNotificationContent()
                reminderContent.title = String(localized: "notification.title")
                reminderContent.body = "今日任务提醒：按照你设定的时刻查看进度"
                reminderContent.sound = .default
                let reminderTrigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fixedReminderDate),
                    repeats: false
                )
                let reminderRequest = UNNotificationRequest(
                    identifier: fixedReminderIdentifier(for: day),
                    content: reminderContent,
                    trigger: reminderTrigger
                )
                UNUserNotificationCenter.current().add(reminderRequest)
            }
        }

        if reminderMinutes > 0,
           let preReminderDate = calendar.date(byAdding: .minute, value: -reminderMinutes, to: killDate),
           preReminderDate > Date() {
            let key = minuteKey(for: preReminderDate)
            if !scheduledMinuteKeys.contains(key) {
                scheduledMinuteKeys.insert(key)
                let reminderContent = UNMutableNotificationContent()
                reminderContent.title = String(localized: "notification.title")
                reminderContent.body = "今日任务即将过期，请注意截止时间"
                reminderContent.sound = .default

                let reminderTrigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: preReminderDate),
                    repeats: false
                )
                let reminderRequest = UNNotificationRequest(
                    identifier: preKillTimeIdentifier(for: day),
                    content: reminderContent,
                    trigger: reminderTrigger
                )
                UNUserNotificationCenter.current().add(reminderRequest)
            }
        }
    }

    func cancelKillTimeNotification(for day: DayModel) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [killTimeIdentifier(for: day), preKillTimeIdentifier(for: day), fixedReminderIdentifier(for: day)]
        )
    }

    func scheduleSuspendedTaskNotifications(for task: SuspendedTaskItem) {
        cancelSuspendedTaskNotifications(for: task)

        let now = Date()
        let checkpoints = suspendedReminderDates(for: task)

        for (index, reminderDate) in checkpoints.enumerated() where reminderDate > now {
            let content = UNMutableNotificationContent()
            content.title = "悬置箱提醒"
            content.body = "这不是普通 Inbox。请在到期前续期、分配到具体某一天，或删除。"
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: suspendedReminderIdentifier(for: task, index: index),
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    func cancelSuspendedTaskNotifications(for task: SuspendedTaskItem) {
        let identifiers = (0..<3).map { suspendedReminderIdentifier(for: task, index: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func killDate(for day: DayModel) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day.date)
        components.hour = day.killTimeHour
        components.minute = day.killTimeMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private func killTimeIdentifier(for day: DayModel) -> String {
        "killtime-\(day.dayId)"
    }

    private func preKillTimeIdentifier(for day: DayModel) -> String {
        "pre-killtime-\(day.dayId)"
    }

    private func fixedReminderIdentifier(for day: DayModel) -> String {
        "fixed-reminder-\(day.dayId)"
    }

    private func fixedReminderDate(for day: DayModel, fixedReminder: DateComponents?) -> Date? {
        guard let fixedReminder else { return nil }
        guard let hour = fixedReminder.hour, let minute = fixedReminder.minute else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: day.date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private func minuteKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)-\(parts.hour ?? 0)-\(parts.minute ?? 0)"
    }

    private func suspendedReminderIdentifier(for task: SuspendedTaskItem, index: Int) -> String {
        "suspended-\(task.id.uuidString)-\(index)"
    }

    private func suspendedReminderDates(for task: SuspendedTaskItem) -> [Date] {
        let dueDay = calendar.startOfDay(for: task.decisionDeadline)
        let offsets = [-3, -1, 0]
        return offsets.compactMap { offset in
            guard let reminderDay = calendar.date(byAdding: .day, value: offset, to: dueDay) else {
                return nil
            }
            var components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
            components.hour = 9
            components.minute = 0
            components.second = 0
            return calendar.date(from: components)
        }
    }
}
