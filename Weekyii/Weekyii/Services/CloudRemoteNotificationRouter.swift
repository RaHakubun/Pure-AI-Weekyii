import CloudKit
import Foundation
import UIKit

nonisolated struct CloudRemoteNotificationEnvelope: Equatable, Sendable {
    nonisolated enum NotificationType: Equatable, Sendable {
        case recordZone
        case query
        case database
        case readNotification
        case unknown
    }

    let notificationType: NotificationType
    let subscriptionID: String?
    let zoneName: String?
}

nonisolated enum CloudRemoteNotificationSyncOutcome: Equatable, Sendable {
    case noData
    case newData
    /// The trigger did not run a fetch, usually because sync is disabled or
    /// coordinator state currently blocks remote-notification work.
    case suppressed
    /// Treat a failed cycle as stable for this push burst: queued pushes complete
    /// as failed without immediately retrying the same failing sync operation.
    case failed

    var backgroundFetchResult: UIBackgroundFetchResult {
        switch self {
        case .noData: .noData
        case .newData: .newData
        case .suppressed: .noData
        case .failed: .failed
        }
    }
}

/// Filters Weekyii's silent zone pushes and coalesces their sync triggers.
/// It deliberately has no account or Cloud transport dependencies.
nonisolated final class CloudRemoteNotificationRouter {
    typealias EnvelopeParser = @MainActor ([AnyHashable: Any]) -> CloudRemoteNotificationEnvelope?
    typealias SyncHandler = @MainActor () async -> CloudRemoteNotificationSyncOutcome
    typealias Completion = @MainActor (UIBackgroundFetchResult) -> Void

    private enum CycleKind {
        case initial
        case followUp
    }

    private enum CyclePhase {
        case scheduled
        case running
    }

    private struct ActiveCycle {
        let id: UInt64
        let kind: CycleKind
        var phase: CyclePhase
        var completions: [CompletionOnce]
    }

    @MainActor private let expectedSubscriptionID: String
    @MainActor private let expectedZoneName: String
    @MainActor private let envelopeParser: EnvelopeParser

    @MainActor private var syncHandler: SyncHandler?
    @MainActor private var pendingBeforeAttachment: Bool
    @MainActor private var activeCycle: ActiveCycle?
    @MainActor private var followUpCompletions: [CompletionOnce] = []
    @MainActor private var cycleTask: Task<Void, Never>?
    @MainActor private var attachmentGeneration: UInt64 = 0
    @MainActor private var nextCycleID: UInt64 = 0

    /// True while an accepted push is waiting for the coordinator to attach.
    @MainActor
    var hasPendingNotification: Bool {
        pendingBeforeAttachment
    }

    @MainActor
    init(
        pendingNotificationBeforeAttachment: Bool = false,
        expectedSubscriptionID: String = CloudKitInfrastructureManager.subscriptionID,
        expectedZoneName: String = CloudRecordCodec.customZoneName,
        envelopeParser: EnvelopeParser? = nil
    ) {
        self.pendingBeforeAttachment = pendingNotificationBeforeAttachment
        self.expectedSubscriptionID = expectedSubscriptionID
        self.expectedZoneName = expectedZoneName
        self.envelopeParser = envelopeParser ?? Self.parseCloudKitNotification
    }

    /// Attaches the coordinator's remote-notification sync entry point. Repeated
    /// attachment is idempotent; detach first to replace the current handler.
    @MainActor
    func attach(sync handler: @escaping SyncHandler) {
        guard syncHandler == nil else { return }
        syncHandler = handler
        guard pendingBeforeAttachment else { return }

        pendingBeforeAttachment = false
        scheduleCycle(kind: .initial, completions: [])
    }

    /// Discards undelivered notifications, completes outstanding callbacks once
    /// with `.noData`, and prevents a cancelled cycle from scheduling a follow-up.
    @MainActor
    func detach() {
        attachmentGeneration &+= 1
        syncHandler = nil
        cycleTask?.cancel()
        cycleTask = nil
        pendingBeforeAttachment = false

        let outstanding = (activeCycle?.completions ?? [])
            + followUpCompletions
        followUpCompletions.removeAll(keepingCapacity: false)
        activeCycle = nil

        complete(outstanding, with: .noData)
    }

    /// Parses and filters one application delegate push. Invalid or unrelated
    /// payloads complete immediately with `.noData` and never reach the handler.
    @MainActor
    func receive(
        _ remoteNotification: [AnyHashable: Any],
        completion: @escaping Completion
    ) {
        let completionOnce = CompletionOnce(completion)
        guard let envelope = envelopeParser(remoteNotification), isRelevant(envelope) else {
            completionOnce.call(.noData)
            return
        }

        guard syncHandler != nil else {
            pendingBeforeAttachment = true
            completionOnce.call(.noData)
            return
        }

        guard var cycle = activeCycle else {
            scheduleCycle(kind: .initial, completions: [completionOnce])
            return
        }

        switch (cycle.kind, cycle.phase) {
        case (.initial, .scheduled), (.followUp, .scheduled), (.followUp, .running):
            cycle.completions.append(completionOnce)
            activeCycle = cycle
        case (.initial, .running):
            followUpCompletions.append(completionOnce)
        }
    }

    @MainActor
    private func isRelevant(_ envelope: CloudRemoteNotificationEnvelope) -> Bool {
        envelope.notificationType == .recordZone
            && envelope.subscriptionID == expectedSubscriptionID
            && envelope.zoneName == expectedZoneName
    }

    @MainActor
    private func scheduleCycle(kind: CycleKind, completions: [CompletionOnce]) {
        guard let syncHandler else {
            pendingBeforeAttachment = true
            complete(completions, with: .noData)
            return
        }

        nextCycleID &+= 1
        let cycleID = nextCycleID
        let generation = attachmentGeneration
        activeCycle = ActiveCycle(id: cycleID, kind: kind, phase: .scheduled, completions: completions)

        cycleTask = Task { @MainActor [weak self] in
            // Defer one actor turn so synchronous notifications in an idle burst
            // share the same cycle instead of observing an already-running task.
            await Task.yield()
            guard !Task.isCancelled,
                  let self,
                  self.attachmentGeneration == generation,
                  self.syncHandler != nil,
                  self.activeCycle?.id == cycleID else { return }

            self.activeCycle?.phase = .running
            let outcome = await syncHandler()

            guard !Task.isCancelled,
                  self.attachmentGeneration == generation,
                  self.activeCycle?.id == cycleID else { return }
            self.finishCycle(id: cycleID, outcome: outcome)
        }
    }

    @MainActor
    private func finishCycle(id cycleID: UInt64, outcome: CloudRemoteNotificationSyncOutcome) {
        guard let cycle = activeCycle, cycle.id == cycleID else { return }
        activeCycle = nil
        cycleTask = nil

        if cycle.kind == .initial, !followUpCompletions.isEmpty {
            let queued = followUpCompletions
            followUpCompletions.removeAll(keepingCapacity: false)
            if outcome == .failed {
                complete(cycle.completions, with: outcome.backgroundFetchResult)
                complete(queued, with: .failed)
                return
            }
            if outcome == .suppressed {
                complete(cycle.completions, with: .noData)
                complete(queued, with: .noData)
                return
            }

            // Establish the one permitted follow-up before invoking user
            // completion closures; detach from a callback can then discard it.
            scheduleCycle(kind: .followUp, completions: queued)
        }

        complete(cycle.completions, with: outcome.backgroundFetchResult)
    }

    @MainActor
    private func complete(_ completions: [CompletionOnce], with result: UIBackgroundFetchResult) {
        for completion in completions { completion.call(result) }
    }

    @MainActor
    private static func parseCloudKitNotification(
        _ remoteNotification: [AnyHashable: Any]
    ) -> CloudRemoteNotificationEnvelope? {
        // CKNotification's Objective-C parser assumes the CloudKit payload
        // envelope is present; reject arbitrary APS dictionaries first.
        guard remoteNotification["ck"] is [AnyHashable: Any] else { return nil }
        guard let notification = CKNotification(fromRemoteNotificationDictionary: remoteNotification) else {
            return nil
        }

        let type: CloudRemoteNotificationEnvelope.NotificationType
        let zoneName: String?
        switch notification.notificationType {
        case .recordZone:
            guard let zoneNotification = notification as? CKRecordZoneNotification else { return nil }
            type = .recordZone
            zoneName = zoneNotification.recordZoneID?.zoneName
        case .query:
            type = .query
            zoneName = nil
        case .database:
            type = .database
            zoneName = nil
        case .readNotification:
            type = .readNotification
            zoneName = nil
        @unknown default:
            type = .unknown
            zoneName = nil
        }

        return CloudRemoteNotificationEnvelope(
            notificationType: type,
            subscriptionID: notification.subscriptionID,
            zoneName: zoneName
        )
    }
}

nonisolated private final class CompletionOnce {
    private var hasCompleted = false
    private let completion: CloudRemoteNotificationRouter.Completion

    @MainActor
    init(_ completion: @escaping CloudRemoteNotificationRouter.Completion) {
        self.completion = completion
    }

    @MainActor
    func call(_ result: UIBackgroundFetchResult) {
        guard !hasCompleted else { return }
        hasCompleted = true
        completion(result)
    }
}
