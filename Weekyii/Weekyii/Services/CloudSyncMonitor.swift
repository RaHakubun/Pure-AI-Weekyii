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

enum CloudSyncAccountState: Equatable {
    case checking
    case available
    case unavailable(CloudSyncUnavailableReason)
    case failed(String)
}

enum CloudSyncEventState: Equatable {
    case idle
    case syncing
    case synced(Date)
    case failed(String)
}

enum CloudSyncState: Equatable {
    case checking
    case available
    case syncing
    case synced(Date)
    case unavailable(CloudSyncUnavailableReason)
    case failed(String)

    static func resolve(
        account: CloudSyncAccountState,
        event: CloudSyncEventState
    ) -> CloudSyncState {
        switch account {
        case .checking:
            return .checking
        case .unavailable(let reason):
            return .unavailable(reason)
        case .failed(let message):
            return .failed(message)
        case .available:
            switch event {
            case .idle:
                return .available
            case .syncing:
                return .syncing
            case .synced(let date):
                return .synced(date)
            case .failed(let message):
                return .failed(message)
            }
        }
    }

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
    private(set) var accountState: CloudSyncAccountState = .checking
    private(set) var eventState: CloudSyncEventState = .idle
    private(set) var importRevision = 0

    var state: CloudSyncState {
        CloudSyncState.resolve(account: accountState, event: eventState)
    }

    @ObservationIgnored private let containerIdentifier: String
    @ObservationIgnored private var cloudContainer: CKContainer?
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var eventObserverTask: Task<Void, Never>?
    @ObservationIgnored private var accountObserverTask: Task<Void, Never>?
    @ObservationIgnored private var importDebounceTask: Task<Void, Never>?
    @ObservationIgnored private let importDebounceDuration: Duration
    @ObservationIgnored private var hasStarted = false

    init(
        containerIdentifier: String = WeekyiiPersistence.cloudKitContainerIdentifier,
        notificationCenter: NotificationCenter = .default,
        importDebounceDuration: Duration = .seconds(1)
    ) {
        self.containerIdentifier = containerIdentifier
        self.notificationCenter = notificationCenter
        self.importDebounceDuration = importDebounceDuration
    }

    nonisolated static func shouldStart(isRunningTests: Bool, isUITesting: Bool) -> Bool {
        !isRunningTests && !isUITesting
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        cloudContainer = CKContainer(identifier: containerIdentifier)
        eventObserverTask = Task { @MainActor [weak self, notificationCenter] in
            for await notification in notificationCenter.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            ) {
                guard let self else { return }
                consume(notification)
            }
        }
        accountObserverTask = Task { @MainActor [weak self, notificationCenter] in
            for await _ in notificationCenter.notifications(named: .CKAccountChanged) {
                guard let self else { return }
                await refreshAccountStatus()
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
                accountState = .available
            case .noAccount:
                accountState = .unavailable(.noAccount)
            case .restricted:
                accountState = .unavailable(.restricted)
            case .temporarilyUnavailable:
                accountState = .unavailable(.temporarilyUnavailable)
            case .couldNotDetermine:
                accountState = .unavailable(.unknown)
            @unknown default:
                accountState = .unavailable(.unknown)
            }
        } catch {
            accountState = .failed(error.localizedDescription)
        }
    }

    private func consume(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else {
            return
        }

        guard event.endDate != nil else {
            eventState = .syncing
            return
        }

        if event.succeeded {
            eventState = .synced(event.endDate ?? Date())
            if event.type == .import {
                scheduleImportedChanges()
            }
        } else {
            eventState = .failed(
                event.error?.localizedDescription
                    ?? String(
                        localized: "settings.icloud.status.unknown_error",
                        defaultValue: "未知错误"
                    )
            )
        }
    }

    func scheduleImportedChanges() {
        importDebounceTask?.cancel()
        importDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: importDebounceDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            importRevision &+= 1
        }
    }

    deinit {
        eventObserverTask?.cancel()
        accountObserverTask?.cancel()
        importDebounceTask?.cancel()
    }
}
