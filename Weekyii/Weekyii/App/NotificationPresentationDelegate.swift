import Foundation
import UserNotifications

/// The app historically had no delegate, so every notification stayed silent in the
/// foreground. Only the scheduled-start confirmation is surfaced; anything else keeps
/// the existing behaviour.
final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let options: UNNotificationPresentationOptions = NotificationService.isAutoStartIdentifier(
            notification.request.identifier
        ) ? [.banner, .list, .sound] : []
        completionHandler(options)
    }
}
