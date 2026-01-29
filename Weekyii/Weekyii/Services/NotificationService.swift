import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func scheduleKillTimeNotification(for day: DayModel) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.title")
        content.body = String(localized: "notification.kill_time")
        content.sound = .default

        let calendar = Calendar(identifier: .iso8601)
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: day.date)
        dateComponents.hour = day.killTimeHour
        dateComponents.minute = day.killTimeMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let identifier = "killtime-\(day.dayId)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelKillTimeNotification(for day: DayModel) {
        let identifier = "killtime-\(day.dayId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
