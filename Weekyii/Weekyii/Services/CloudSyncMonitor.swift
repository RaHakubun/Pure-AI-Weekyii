import CloudKit
import CoreData
import Foundation
import Observation

enum CloudSyncUnavailableReason: Equatable {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unknown
}

enum CloudSyncState: Equatable {
    case checking
    case available
    case syncing
    case synced(Date)
    case unavailable(CloudSyncUnavailableReason)
    case failed(String)

    var detail: String {
        switch self {
        case .checking:
            return String(
                localized: "settings.icloud.status.checking",
                defaultValue: "正在检查 iCloud…"
            )
        case .available:
            return String(
                localized: "settings.icloud.status.available",
                defaultValue: "已开启，将通过 iCloud 自动同步"
            )
        case .syncing:
            return String(
                localized: "settings.icloud.status.syncing",
                defaultValue: "正在同步…"
            )
        case .synced:
            return String(
                localized: "settings.icloud.status.synced",
                defaultValue: "已同步"
            )
        case .unavailable(.noAccount):
            return String(
                localized: "settings.icloud.status.no_account",
                defaultValue: "请先在系统设置中登录 iCloud"
            )
        case .unavailable(.restricted):
            return String(
                localized: "settings.icloud.status.restricted",
                defaultValue: "此设备限制了 iCloud 访问"
            )
        case .unavailable(.temporarilyUnavailable):
            return String(
                localized: "settings.icloud.status.temporarily_unavailable",
                defaultValue: "iCloud 暂时不可用，将自动重试"
            )
        case .unavailable(.unknown):
            return String(
                localized: "settings.icloud.status.unknown",
                defaultValue: "暂时无法确认 iCloud 状态"
            )
        case .failed(let message):
            return String(
                format: String(
                    localized: "settings.icloud.status.failed",
                    defaultValue: "同步遇到问题：%@"
                ),
                message
            )
        }
    }

    var isWorking: Bool {
        switch self {
        case .checking, .syncing:
            return true
        default:
            return false
        }
    }

    var symbolName: String {
        switch self {
        case .checking, .available, .syncing:
            return "icloud.fill"
        case .synced:
            return "checkmark.icloud.fill"
        case .unavailable, .failed:
            return "exclamationmark.icloud.fill"
        }
    }
}

@MainActor
@Observable
final class CloudSyncMonitor {
    private(set) var state: CloudSyncState = .checking
    private(set) var importRevision = 0

    @ObservationIgnored private let containerIdentifier: String
    @ObservationIgnored private var cloudContainer: CKContainer?
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var eventObserver: NSObjectProtocol?
    @ObservationIgnored private var hasStarted = false

    init(
        containerIdentifier: String = WeekyiiPersistence.cloudKitContainerIdentifier,
        notificationCenter: NotificationCenter = .default
    ) {
        self.containerIdentifier = containerIdentifier
        self.notificationCenter = notificationCenter
    }

    nonisolated static func shouldStart(isRunningTests: Bool, isUITesting: Bool) -> Bool {
        !isRunningTests && !isUITesting
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        cloudContainer = CKContainer(identifier: containerIdentifier)
        eventObserver = notificationCenter.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.consume(notification)
            }
        }

        Task { await refreshAccountStatus() }
    }

    func refreshAccountStatus() async {
        guard let cloudContainer else { return }
        do {
            let accountStatus = try await cloudContainer.accountStatus()
            switch accountStatus {
            case .available:
                if state == .checking || isUnavailableOrFailed {
                    state = .available
                }
            case .noAccount:
                state = .unavailable(.noAccount)
            case .restricted:
                state = .unavailable(.restricted)
            case .temporarilyUnavailable:
                state = .unavailable(.temporarilyUnavailable)
            case .couldNotDetermine:
                state = .unavailable(.unknown)
            @unknown default:
                state = .unavailable(.unknown)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private var isUnavailableOrFailed: Bool {
        switch state {
        case .unavailable, .failed:
            return true
        default:
            return false
        }
    }

    private func consume(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else {
            return
        }

        guard event.endDate != nil else {
            state = .syncing
            return
        }

        if event.succeeded {
            state = .synced(event.endDate ?? Date())
            if event.type == .import {
                importRevision &+= 1
            }
        } else {
            state = .failed(
                event.error?.localizedDescription
                    ?? String(
                        localized: "settings.icloud.status.unknown_error",
                        defaultValue: "未知错误"
                    )
            )
        }
    }

    deinit {
        if let eventObserver {
            notificationCenter.removeObserver(eventObserver)
        }
    }
}
