import Foundation

struct CloudSyncRecordFailureClassification: Hashable, Sendable {
    let entityKey: SyncEntityKey
    let category: CloudSyncFailureCategory
}

struct CloudSyncFailureClassification: Hashable, Sendable {
    let category: CloudSyncFailureCategory
    let perRecord: [CloudSyncRecordFailureClassification]
}

enum CloudSyncRetryDecision: Hashable, Sendable {
    case retry(after: TimeInterval)
    case stop(category: CloudSyncFailureCategory)
}

struct CloudSyncRecordRetryDecision: Hashable, Sendable {
    let entityKey: SyncEntityKey
    let decision: CloudSyncRetryDecision
}

/// Pure, bounded retry decisions. It never sleeps or chooses conflict winners.
struct CloudSyncRetryPolicy: Sendable {
    let maximumRetries: Int
    let maximumDelay: TimeInterval

    init(maximumRetries: Int = 2, maximumDelay: TimeInterval = 30) {
        self.maximumRetries = max(0, maximumRetries)
        self.maximumDelay = max(0, maximumDelay)
    }

    func classify(_ failure: CloudSyncFailure) -> CloudSyncFailureClassification {
        switch failure {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            CloudSyncFailureClassification(category: .transient, perRecord: [])
        case .quotaExceeded, .notAuthenticated, .permissionFailure, .invalidArguments, .badContainer,
             .accountActionRequired, .entitlementActionRequired, .transportNotReady:
            CloudSyncFailureClassification(category: .terminal, perRecord: [])
        case .serverRecordChanged:
            CloudSyncFailureClassification(category: .conflict, perRecord: [])
        case .partialFailure(let failures):
            CloudSyncFailureClassification(
                category: .partialFailure,
                perRecord: failures.map {
                    CloudSyncRecordFailureClassification(
                        entityKey: $0.entityKey,
                        category: classify($0.failure).category
                    )
                }
            )
        case .other:
            CloudSyncFailureClassification(category: .terminal, perRecord: [])
        }
    }

    func retryDecision(for failure: CloudSyncFailure, retryNumber: Int) -> CloudSyncRetryDecision {
        let category = classify(failure).category
        guard category == .transient else { return .stop(category: category) }
        guard retryNumber > 0, retryNumber <= maximumRetries else { return .stop(category: category) }

        if let serverDelay = serverRetryAfter(in: failure) {
            return .retry(after: min(max(0, serverDelay), maximumDelay))
        }

        let fallback: TimeInterval
        switch retryNumber {
        case 1: fallback = 1
        case 2: fallback = 4
        default: fallback = min(4 * pow(2, Double(retryNumber - 2)), maximumDelay)
        }
        return .retry(after: min(fallback, maximumDelay))
    }

    func perRecordRetryDecisions(
        for failure: CloudSyncFailure,
        retryNumber: Int
    ) -> [CloudSyncRecordRetryDecision]? {
        guard case .partialFailure(let failures) = failure else { return nil }
        return failures.map {
            CloudSyncRecordRetryDecision(
                entityKey: $0.entityKey,
                decision: retryDecision(for: $0.failure, retryNumber: retryNumber)
            )
        }
    }

    private func serverRetryAfter(in failure: CloudSyncFailure) -> TimeInterval? {
        switch failure {
        case .serviceUnavailable(let delay), .requestRateLimited(let delay), .zoneBusy(let delay): delay
        default: nil
        }
    }
}
