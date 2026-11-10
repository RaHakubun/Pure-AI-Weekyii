import XCTest
import UIKit
@testable import Weekyii

@MainActor
final class CloudRemoteNotificationRouterTests: XCTestCase {
    func test_malformedNotificationCompletesNoDataWithoutTriggeringSync() async {
        let probe = SyncProbe()
        let router = makeRouter(handler: { await probe.run() })
        var results: [UIBackgroundFetchResult] = []

        router.receive(["malformed": true], completion: { results.append($0) })

        XCTAssertEqual(results, [.noData])
        XCTAssertEqual(probe.invocationCount, 0)
    }

    func testProductionCloudKitParserRejectsMalformedDictionary() {
        let probe = SyncProbe()
        let router = CloudRemoteNotificationRouter()
        router.attach(sync: { await probe.run() })
        var results: [UIBackgroundFetchResult] = []

        router.receive(["aps": ["content-available": 1]], completion: { results.append($0) })

        XCTAssertEqual(results, [.noData])
        XCTAssertEqual(probe.invocationCount, 0)
    }

    func test_nonRecordZoneAndWrongSubscriptionOrZoneCompleteNoDataWithoutTriggeringSync() async {
        let probe = SyncProbe()
        let router = makeRouter(handler: { await probe.run() })
        var results: [UIBackgroundFetchResult] = []

        router.receive(payload(type: "query"), completion: { results.append($0) })
        router.receive(payload(subscriptionID: "another-subscription"), completion: { results.append($0) })
        router.receive(payload(zoneName: "AnotherZone"), completion: { results.append($0) })

        XCTAssertEqual(results, [.noData, .noData, .noData])
        XCTAssertEqual(probe.invocationCount, 0)
    }

    func test_exactRecordZonePushTriggersOneCycleAndMapsNewData() async {
        let probe = SyncProbe()
        let router = makeRouter(handler: { await probe.run() })
        var results: [UIBackgroundFetchResult] = []

        router.receive(payload(), completion: { results.append($0) })
        await probe.waitForInvocationCount(1)
        await probe.completeNext(.newData)
        await settleTasks()

        XCTAssertEqual(probe.invocationCount, 1)
        XCTAssertEqual(results, [.newData])
    }

    func test_idleBurstCoalescesIntoOneCycle() async {
        let probe = SyncProbe()
        let router = makeRouter(handler: { await probe.run() })
        var results: [UIBackgroundFetchResult] = []

        router.receive(payload(), completion: { results.append($0) })
        router.receive(payload(), completion: { results.append($0) })
        router.receive(payload(), completion: { results.append($0) })
        await probe.waitForInvocationCount(1)
        await probe.completeNext(.noData)
        await settleTasks()

        XCTAssertEqual(probe.invocationCount, 1)
        XCTAssertEqual(results, [.noData, .noData, .noData])
    }

    func test_pushesDuringActiveCycleCauseAtMostOneFollowUp() async {
        let probe = SyncProbe()
        let router = makeRouter(handler: { await probe.run() })
        var results: [UIBackgroundFetchResult] = []

        router.receive(payload(), completion: { results.append($0) })
        await probe.waitForInvocationCount(1)
        router.receive(payload(), completion: { results.append($0) })
        router.receive(payload(), completion: { results.append($0) })
        await probe.completeNext(.newData)
        await probe.waitForInvocationCount(2)

        router.receive(payload(), completion: { results.append($0) })
        router.receive(payload(), completion: { results.append($0) })
        await probe.completeNext(.noData)
        await settleTasks()

        XCTAssertEqual(probe.invocationCount, 2)
        XCTAssertEqual(results, [.newData, .noData, .noData, .noData, .noData])
    }

    func test_stableFailureCompletesQueuedPushesFailedWithoutFollowUp() async {
        let probe = SyncProbe()
        let router = makeRouter(handler: { await probe.run() })
        var results: [UIBackgroundFetchResult] = []

        router.receive(payload(), completion: { results.append($0) })
        await probe.waitForInvocationCount(1)
        router.receive(payload(), completion: { results.append($0) })
        await probe.completeNext(.failed)
        await settleTasks()

        XCTAssertEqual(probe.invocationCount, 1)
        XCTAssertEqual(results, [.failed, .failed])
    }

    func test_suppressedCycleMapsToNoDataAndDropsQueuedFollowUp() async {
        let probe = SyncProbe()
        let router = makeRouter(handler: { await probe.run() })
        var results: [UIBackgroundFetchResult] = []

        router.receive(payload(), completion: { results.append($0) })
        await probe.waitForInvocationCount(1)
        router.receive(payload(), completion: { results.append($0) })
        await probe.completeNext(.suppressed)
        await settleTasks()

        XCTAssertEqual(probe.invocationCount, 1)
        XCTAssertEqual(results, [.noData, .noData])
    }

    func test_pushBeforeAttachmentCompletesPromptlyAndDeliversSignalAfterAttach() async {
        let probe = SyncProbe()
        let router = makeRouter()
        var results: [UIBackgroundFetchResult] = []

        router.receive(payload(), completion: { results.append($0) })

        XCTAssertTrue(router.hasPendingNotification)
        XCTAssertEqual(results, [.noData])
        XCTAssertEqual(probe.invocationCount, 0)
        router.attach(sync: { await probe.run() })
        await probe.waitForInvocationCount(1)
        await probe.completeNext(.noData)
        await settleTasks()

        XCTAssertFalse(router.hasPendingNotification)
        XCTAssertEqual(probe.invocationCount, 1)
        XCTAssertEqual(results, [.noData])
    }

    func test_multiplePushesBeforeAttachmentCompleteEachCallbackAndCoalesceOneSignal() async {
        let probe = SyncProbe()
        let router = makeRouter()
        var completionCounts = [0, 0, 0]
        var results: [UIBackgroundFetchResult] = []

        for index in completionCounts.indices {
            router.receive(payload(), completion: { result in
                completionCounts[index] += 1
                results.append(result)
            })
        }

        XCTAssertTrue(router.hasPendingNotification)
        XCTAssertEqual(completionCounts, [1, 1, 1])
        XCTAssertEqual(results, [.noData, .noData, .noData])
        XCTAssertEqual(probe.invocationCount, 0)

        router.attach(sync: { await probe.run() })
        await probe.waitForInvocationCount(1)
        await probe.completeNext(.noData)
        await settleTasks()

        XCTAssertFalse(router.hasPendingNotification)
        XCTAssertEqual(probe.invocationCount, 1)
        XCTAssertEqual(completionCounts, [1, 1, 1])
        XCTAssertEqual(results, [.noData, .noData, .noData])
    }

    func test_pushBeforeAttachmentCompletesEvenIfCoordinatorNeverAttaches() {
        let router = makeRouter()
        var completionCount = 0
        var result: UIBackgroundFetchResult?

        router.receive(payload(), completion: {
            completionCount += 1
            result = $0
        })

        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(result, .noData)
        XCTAssertTrue(router.hasPendingNotification)
    }

    func test_detachBeforeAttachmentDiscardsPendingSignalWithoutDuplicateCompletion() {
        let router = makeRouter()
        var completionCount = 0
        var result: UIBackgroundFetchResult?

        router.receive(payload(), completion: {
            completionCount += 1
            result = $0
        })
        router.detach()

        XCTAssertFalse(router.hasPendingNotification)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(result, .noData)
    }

    func testInitialPendingBitRunsOnceWhenCoordinatorAttaches() async {
        let probe = SyncProbe()
        let router = CloudRemoteNotificationRouter(
            pendingNotificationBeforeAttachment: true,
            envelopeParser: Self.parseEnvelope
        )

        XCTAssertTrue(router.hasPendingNotification)
        router.attach(sync: { await probe.run() })
        await probe.waitForInvocationCount(1)
        await probe.completeNext(.noData)
        await settleTasks()

        XCTAssertFalse(router.hasPendingNotification)
        XCTAssertEqual(probe.invocationCount, 1)
    }

    func testDetachBeforeScheduledDeliveryDiscardsPushAndCompletesOnce() async {
        let probe = SyncProbe()
        let router = makeRouter(handler: { await probe.run() })
        var results: [UIBackgroundFetchResult] = []

        router.receive(payload(), completion: { results.append($0) })
        router.detach()
        await settleTasks()

        XCTAssertEqual(probe.invocationCount, 0)
        XCTAssertEqual(results, [.noData])
    }

    func testDetachDuringActiveCycleDiscardsFollowUpAndIgnoresLateCompletion() async {
        let probe = SyncProbe()
        let router = makeRouter(handler: { await probe.run() })
        var results: [UIBackgroundFetchResult] = []

        router.receive(payload(), completion: { results.append($0) })
        await probe.waitForInvocationCount(1)
        router.receive(payload(), completion: { results.append($0) })
        router.detach()
        XCTAssertEqual(results, [.noData, .noData])

        await probe.completeNext(.newData)
        await settleTasks()

        XCTAssertEqual(probe.invocationCount, 1)
        XCTAssertEqual(results, [.noData, .noData])
    }

    private func makeRouter(
        handler: CloudRemoteNotificationRouter.SyncHandler? = nil
    ) -> CloudRemoteNotificationRouter {
        let router = CloudRemoteNotificationRouter(envelopeParser: Self.parseEnvelope)
        if let handler { router.attach(sync: handler) }
        return router
    }

    private static func parseEnvelope(_ payload: [AnyHashable: Any]) -> CloudRemoteNotificationEnvelope? {
        guard payload["parseable"] as? Bool == true else { return nil }
        let type: CloudRemoteNotificationEnvelope.NotificationType
        switch payload["type"] as? String {
        case "recordZone": type = .recordZone
        case "query": type = .query
        case "database": type = .database
        case "readNotification": type = .readNotification
        default: type = .unknown
        }
        return CloudRemoteNotificationEnvelope(
            notificationType: type,
            subscriptionID: payload["subscriptionID"] as? String,
            zoneName: payload["zoneName"] as? String
        )
    }

    private func payload(
        type: String = "recordZone",
        subscriptionID: String = CloudKitInfrastructureManager.subscriptionID,
        zoneName: String = CloudRecordCodec.customZoneName
    ) -> [AnyHashable: Any] {
        [
            "parseable": true,
            "type": type,
            "subscriptionID": subscriptionID,
            "zoneName": zoneName
        ]
    }

    private func settleTasks() async {
        for _ in 0..<5 { await Task.yield() }
    }
}

@MainActor
private final class SyncProbe {
    private(set) var invocationCount = 0
    private var continuation: CheckedContinuation<CloudRemoteNotificationSyncOutcome, Never>?
    private var invocationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func run() async -> CloudRemoteNotificationSyncOutcome {
        await withCheckedContinuation { continuation in
            invocationCount += 1
            self.continuation = continuation
            resumeSatisfiedWaiters()
        }
    }

    func waitForInvocationCount(_ expected: Int) async {
        guard invocationCount < expected else { return }
        await withCheckedContinuation { invocationWaiters.append((expected, $0)) }
    }

    func completeNext(_ outcome: CloudRemoteNotificationSyncOutcome) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: outcome)
    }

    private func resumeSatisfiedWaiters() {
        let satisfied = invocationWaiters.filter { invocationCount >= $0.0 }
        invocationWaiters.removeAll { invocationCount >= $0.0 }
        for (_, continuation) in satisfied { continuation.resume() }
    }
}
