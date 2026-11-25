import XCTest
@testable import Weekyii

@MainActor
final class CloudSyncNetworkMonitorTests: XCTestCase {
    func test_initiallySatisfiedPathDoesNotTriggerRecovery() async {
        let source = FakeCloudSyncNetworkPathStateSource()
        let recovery = expectation(description: "initial satisfied path is ignored")
        recovery.isInverted = true
        let monitor = CloudSyncNetworkRecoveryMonitor(pathStateSource: source) {
            recovery.fulfill()
        }

        monitor.start()
        source.send(.satisfied)
        await fulfillment(of: [recovery], timeout: 0.05)
    }

    func test_emitsOnceForEachUnsatisfiedToSatisfiedTransition() async {
        let source = FakeCloudSyncNetworkPathStateSource()
        let recoveredTwice = expectation(description: "both recovery transitions delivered")
        recoveredTwice.expectedFulfillmentCount = 2
        let monitor = CloudSyncNetworkRecoveryMonitor(pathStateSource: source) {
            recoveredTwice.fulfill()
        }

        monitor.start()
        source.send(.unsatisfied)
        source.send(.satisfied)
        source.send(.satisfied)
        source.send(.unsatisfied)
        source.send(.satisfied)

        await fulfillment(of: [recoveredTwice], timeout: 1)
    }

    func test_initialRequiresConnectionToSatisfiedEmitsRecovery() async {
        let source = FakeCloudSyncNetworkPathStateSource()
        let recovery = expectation(description: "path becomes satisfied")
        let monitor = CloudSyncNetworkRecoveryMonitor(pathStateSource: source) {
            recovery.fulfill()
        }

        monitor.start()
        source.send(.requiresConnection)
        source.send(.satisfied)
        await fulfillment(of: [recovery], timeout: 1)
    }

    func test_unavailableStatusTransitionsCoalesceIntoOneRecoveryEach() async {
        let source = FakeCloudSyncNetworkPathStateSource()
        let recoveries = expectation(description: "two unavailable to available transitions")
        recoveries.expectedFulfillmentCount = 2
        let monitor = CloudSyncNetworkRecoveryMonitor(pathStateSource: source) {
            recoveries.fulfill()
        }

        monitor.start()
        source.send(.unsatisfied)
        source.send(.requiresConnection)
        source.send(.unsatisfied)
        source.send(.satisfied)
        source.send(.satisfied)
        source.send(.requiresConnection)
        source.send(.satisfied)

        await fulfillment(of: [recoveries], timeout: 1)
    }

    func test_startIsIdempotentAndStopIgnoresLaterPathChanges() async {
        let source = FakeCloudSyncNetworkPathStateSource()
        let unexpectedRecovery = expectation(description: "stopped monitor ignores path changes")
        unexpectedRecovery.isInverted = true
        let monitor = CloudSyncNetworkRecoveryMonitor(pathStateSource: source) {
            unexpectedRecovery.fulfill()
        }

        monitor.start()
        monitor.start()
        XCTAssertEqual(source.startCount, 1)

        monitor.stop()
        source.send(.unsatisfied)
        source.send(.satisfied)
        await fulfillment(of: [unexpectedRecovery], timeout: 0.05)

        XCTAssertEqual(source.cancelCount, 1)
    }
}

@MainActor
private final class FakeCloudSyncNetworkPathStateSource: CloudSyncNetworkPathStateSource {
    private var handler: (@Sendable (CloudSyncNetworkPathStatus) -> Void)?
    private(set) var startCount = 0
    private(set) var cancelCount = 0

    func start(_ handler: @escaping @Sendable (CloudSyncNetworkPathStatus) -> Void) {
        startCount += 1
        self.handler = handler
    }

    func cancel() {
        cancelCount += 1
        handler = nil
    }

    func send(_ status: CloudSyncNetworkPathStatus) {
        handler?(status)
    }
}
