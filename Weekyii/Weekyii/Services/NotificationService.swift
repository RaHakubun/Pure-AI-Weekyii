import Foundation
import UserNotifications

final class NotificationService {
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

    func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int) {
        cancelKillTimeNotification(for: day)

        guard let killDate = killDate(for: day) else { return }

        // Main kill-time notification
        if killDate > Date() {
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

        // Pre-kill-time reminder (only when there are unfinished tasks)
        guard reminderMinutes > 0 else { return }
        let unfinishedCount = day.sortedDraftTasks.count + day.frozenTasks.count + (day.focusTask == nil ? 0 : 1)
        guard unfinishedCount > 0 else { return }
        guard let preReminderDate = calendar.date(byAdding: .minute, value: -reminderMinutes, to: killDate), preReminderDate > Date() else { return }

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

    func cancelKillTimeNotification(for day: DayModel) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [killTimeIdentifier(for: day), preKillTimeIdentifier(for: day)]
        )
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
}
