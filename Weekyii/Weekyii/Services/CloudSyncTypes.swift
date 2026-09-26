import Foundation

enum CloudSyncEntitlementState: Equatable, Sendable {
    case checking
    case entitled
    case notPurchased
    case expired
    case notConfigured
    case verificationFailed(String)
}

enum CloudSyncAccountPresentationState: Equatable, Sendable {
    case unchecked
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unableToCheck

    init(coordinatorState: CloudSyncCoordinatorAccountState) {
        switch coordinatorState {
        case .unchecked: self = .unchecked
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        case .failed: self = .unableToCheck
        }
    }

    var localizedDescription: String {
        switch self {
        case .unchecked: String(localized: "cloud.sync.account.unchecked")
        case .available: String(localized: "cloud.sync.account.available")
        case .noAccount: String(localized: "cloud.sync.account.no_account")
        case .restricted: String(localized: "cloud.sync.account.restricted")
        case .temporarilyUnavailable: String(localized: "cloud.sync.account.temporarily_unavailable")
        case .unableToCheck: String(localized: "cloud.sync.account.unable_to_check")
        }
    }
}

enum CloudSyncFailurePresentation: Equatable, Sendable {
    case network
    case temporaryService
    case quota
    case authentication
    case permission
    case configuration
    case entitlement
    case other

    init(reason: CloudSyncLatchedFailureReason) {
        switch reason {
        case .network: self = .network
        case .temporaryService: self = .temporaryService
        case .quota: self = .quota
        case .authentication: self = .authentication
        case .permission: self = .permission
        case .configuration: self = .configuration
        case .entitlement: self = .entitlement
        case .other: self = .other
        }
    }

    var localizedDescription: String {
        switch self {
        case .network: String(localized: "cloud.sync.failure.network")
        case .temporaryService: String(localized: "cloud.sync.failure.temporary_service")
        case .quota: String(localized: "cloud.sync.failure.quota")
        case .authentication: String(localized: "cloud.sync.failure.authentication")
        case .permission: String(localized: "cloud.sync.failure.permission")
        case .configuration: String(localized: "cloud.sync.failure.configuration")
        case .entitlement: String(localized: "cloud.sync.failure.entitlement")
        case .other: String(localized: "cloud.sync.failure.other")
        }
    }
}

enum CloudSyncBannerKind: Equatable, Sendable {
    case accountDecision
    case quotaExceeded
    case paused
    case offline
    case accountUnavailable
    case locked
    case syncing
}

enum CloudSyncRemoteTriggerResult: Equatable, Sendable {
    case suppressed
    case noData
    case newData
    case failed
}

struct CloudSyncDiagnosticsSnapshot: Equatable, Sendable {
    let status: CloudSyncStatus
    let requested: Bool
    let entitlement: CloudSyncEntitlementState
    let account: CloudSyncAccountPresentationState
    let lastSuccessfulSync: Date?
    let lastFailure: CloudSyncFailurePresentation?
    let automaticRetrySuppressed: Bool
    let manualSyncAllowed: Bool
    let accountResolutionRequired: Bool

    static func bannerKind(
        for status: CloudSyncStatus,
        requested: Bool,
        requiresAccountResolution: Bool
    ) -> CloudSyncBannerKind? {
        guard requested else { return nil }
        if requiresAccountResolution { return .accountDecision }
        return switch status {
        case .quotaExceeded: .quotaExceeded
        case .pausedAfterFailure: .paused
        case .offline: .offline
        case .accountUnavailable: .accountUnavailable
        case .locked: .locked
        case .syncing: .syncing
        default: nil
        }
    }

    static func manualSyncAllowed(
        requested: Bool,
        hasLocalStore: Bool,
        entitlement: CloudSyncEntitlementState,
        status: CloudSyncStatus,
        syncCycleInProgress: Bool,
        accountResolutionRequired: Bool,
        initialEnableDecisionRequired: Bool,
        resolutionInProgress: Bool,
        resolutionJournalUnavailable: Bool
    ) -> Bool {
        guard requested,
              hasLocalStore,
              entitlement == .entitled,
              !syncCycleInProgress,
              !accountResolutionRequired,
              !initialEnableDecisionRequired,
              !resolutionInProgress,
              !resolutionJournalUnavailable else { return false }
        switch status {
        case .disabled, .locked, .checkingAccount, .syncing, .initialEnableDecisionRequired, .accountDecisionRequired:
            return false
        case .ready, .synced, .offline, .quotaExceeded, .accountUnavailable, .pausedAfterFailure:
            return true
        }
    }
}
