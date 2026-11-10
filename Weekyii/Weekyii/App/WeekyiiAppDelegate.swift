import UIKit
import UserNotifications

@MainActor
final class WeekyiiAppDelegate: NSObject, UIApplicationDelegate {
    private(set) var cloudRemoteNotificationRouter = CloudRemoteNotificationRouter()
    /// `UNUserNotificationCenter.delegate` is weak, so the app delegate owns it.
    private let notificationPresentationDelegate = NotificationPresentationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isRunningUITests = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        if !isRunningTests && !isRunningUITests {
            UNUserNotificationCenter.current().delegate = notificationPresentationDelegate
            application.registerForRemoteNotifications()
        }
        return true
    }

    func attach(coordinator: CloudSyncCoordinator) {
        cloudRemoteNotificationRouter.attach(sync: { [weak coordinator] () async -> CloudRemoteNotificationSyncOutcome in
            guard let coordinator else { return .suppressed }
            return switch await coordinator.handleRemoteNotification() {
            case .suppressed: .suppressed
            case .noData: .noData
            case .newData: .newData
            case .failed: .failed
            }
        })
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        cloudRemoteNotificationRouter.receive(userInfo) { result in
            completionHandler(result)
        }
    }
}
