import Foundation
import Network

nonisolated enum CloudSyncNetworkPathStatus: Equatable, Sendable {
    case satisfied
    case unsatisfied
    case requiresConnection
}

@MainActor
protocol CloudSyncNetworkPathStateSource: AnyObject {
    func start(_ handler: @escaping @Sendable (CloudSyncNetworkPathStatus) -> Void)
    func cancel()
}

@MainActor
final class NWPathCloudSyncNetworkPathStateSource: CloudSyncNetworkPathStateSource {
    private var monitor: NWPathMonitor?

    func start(_ handler: @escaping @Sendable (CloudSyncNetworkPathStatus) -> Void) {
        guard monitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let status: CloudSyncNetworkPathStatus
            switch path.status {
            case .satisfied:
                status = .satisfied
            case .unsatisfied:
                status = .unsatisfied
            case .requiresConnection:
                status = .requiresConnection
            @unknown default:
                status = .requiresConnection
            }
            handler(status)
        }
        monitor.start(queue: DispatchQueue(label: "com.weekyii.cloud-sync-network-path"))
        self.monitor = monitor
    }

    func cancel() {
        monitor?.cancel()
        monitor = nil
    }
}

@MainActor
final class CloudSyncNetworkRecoveryMonitor {
    private let pathStateSource: any CloudSyncNetworkPathStateSource
    private let onNetworkRecovered: @MainActor @Sendable () async -> Void
    private let transitionTracker = CloudSyncNetworkTransitionTracker()
    private(set) var isStarted = false
    private(set) var isStopped = false

    init(
        pathStateSource: any CloudSyncNetworkPathStateSource,
        onNetworkRecovered: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.pathStateSource = pathStateSource
        self.onNetworkRecovered = onNetworkRecovered
    }

    convenience init(
        onNetworkRecovered: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.init(
            pathStateSource: NWPathCloudSyncNetworkPathStateSource(),
            onNetworkRecovered: onNetworkRecovered
        )
    }

    func start() {
        guard !isStarted, !isStopped else { return }
        isStarted = true

        let tracker = transitionTracker
        pathStateSource.start { [weak self, tracker] status in
            guard tracker.consume(status) else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                await self.onNetworkRecovered()
            }
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        transitionTracker.stop()
        pathStateSource.cancel()
    }
}

/// Serializes path transitions from Network.framework's callback queue before they
/// hop to the main actor, so quick successive updates cannot be reordered.
nonisolated private final class CloudSyncNetworkTransitionTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var lastAvailability: Bool?
    private var isStopped = false

    func consume(_ status: CloudSyncNetworkPathStatus) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isStopped else { return false }
        let wasAvailable = lastAvailability
        let isAvailable = status == .satisfied
        lastAvailability = isAvailable
        return wasAvailable == false && isAvailable
    }

    func stop() {
        lock.lock()
        isStopped = true
        lock.unlock()
    }
}
