import CloudKit
import Foundation
import Observation

enum CloudSyncAccountResolution: Equatable, Sendable {
    case available(recordName: String)
    case noAccount
    case restricted
    case temporarilyUnavailable
    case failed(String)
}

enum CloudSyncCoordinatorAccountState: Equatable, Sendable {
    case unchecked
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case failed
}

enum CloudSyncInitialEnableDecision: Equatable, Sendable {
    case remoteEmpty
    case remoteNonempty
}

enum CloudSyncInitialEnableChoice: Equatable, Sendable {
    case uploadLocal
    case useLocal
    case useCloud
    case merge
    case cancel
}

nonisolated enum CloudAccountResolutionChoice: String, Codable, Equatable, Sendable {
    case useLocal
    case useCloud
    case merge
    case disable
}

nonisolated enum CloudAccountResolutionJournalStage: String, Codable, Equatable, Sendable {
    case decisionPending
    case decisionPendingAfterMutation
    case choiceSelected
    case localMutationAuthorized
    case localMutationApplied
    case targetCloudMutationBegun
    case readyToCommit
}

nonisolated struct CloudAccountResolutionJournal: Codable, Equatable, Sendable {
    let previousAccountHash: String?
    var targetAccountHash: String
    var choice: CloudAccountResolutionChoice?
    var stage: CloudAccountResolutionJournalStage
}

enum CloudAccountResolutionFailure: String, Codable, Error, Equatable, Sendable {
    case accountUnavailable
    case invalidCloudData
    case localDataUnavailable
    case recoveryPointFailed
    case cloudOperationFailed
    case accountChanged
    case targetAccountRequired
    case journalUnavailable

    var localizationKey: String {
        switch self {
        case .accountUnavailable: "cloud.accountSwitch.error.accountUnavailable"
        case .invalidCloudData: "cloud.accountSwitch.error.invalidCloudData"
        case .localDataUnavailable: "cloud.accountSwitch.error.localDataUnavailable"
        case .recoveryPointFailed: "cloud.accountSwitch.error.recoveryPointFailed"
        case .cloudOperationFailed: "cloud.accountSwitch.error.cloudOperationFailed"
        case .accountChanged: "cloud.accountSwitch.error.accountChanged"
        case .targetAccountRequired: "cloud.accountSwitch.error.targetAccountRequired"
        case .journalUnavailable: "cloud.accountSwitch.error.journalUnavailable"
        }
    }
}

enum CloudAccountResolutionProgress: Equatable, Sendable {
    case inspecting
    case ready
    case resolving(CloudAccountResolutionChoice)
    case failed(CloudAccountResolutionFailure)
}

/// Hash-only information suitable for the resolution UI. Raw Apple account
/// record names remain transient coordinator inputs and never leave this type.
struct CloudAccountResolutionContext: Equatable, Sendable {
    let previousAccountHash: String?
    let targetAccountHash: String
    let localEntityCount: Int
    let targetCloudEntityCount: Int?
    let targetCloudIsEmpty: Bool?
    let targetAccountAvailable: Bool
    var progress: CloudAccountResolutionProgress
}

enum CloudSyncTrigger: Equatable, Sendable {
    case initialEnable
    case appLaunch
    case sceneActive
    case remoteNotification
    case networkRecovered
    case manual
    case entitlementRestored
}

enum CloudSyncStatus: Equatable, Sendable {
    case disabled
    case locked(CloudSyncEntitlementState)
    case checkingAccount
    case ready
    case syncing
    case synced(Date)
    case offline
    case quotaExceeded
    case accountUnavailable
    case initialEnableDecisionRequired(CloudSyncInitialEnableDecision)
    case accountDecisionRequired
    case pausedAfterFailure

    var diagnosticDescription: String {
        switch self {
        case .disabled: "disabled"
        case .locked: "locked"
        case .checkingAccount: "checking-account"
        case .ready: "ready"
        case .syncing: "syncing"
        case .synced: "synced"
        case .offline: "offline"
        case .quotaExceeded: "quota-exceeded"
        case .accountUnavailable: "account-unavailable"
        case .initialEnableDecisionRequired(.remoteEmpty): "initial-decision-remote-empty"
        case .initialEnableDecisionRequired(.remoteNonempty): "initial-decision-remote-nonempty"
        case .accountDecisionRequired: "account-decision-required"
        case .pausedAfterFailure: "paused-after-failure"
        }
    }
}

protocol CloudSyncAccountProviding: Sendable {
    func resolveAccount() async -> CloudSyncAccountResolution
}

protocol CloudSyncTransportFactory: Sendable {
    func makeTransport(accountRecordName: String) async throws -> any CloudSyncTransport
}

protocol CloudSyncCancellableTransport: Sendable {
    func cancelOperations() async
}

private protocol CloudAccountResolutionInvalidationReporting: Sendable {
    func accountChangedDuringOperation() async -> Bool
}

/// Adds an identity and session check around every operation performed while
/// resolving a changed Apple account. The underlying transport is still scoped
/// to the intended account name; this wrapper prevents later steps from running
/// after a switch or an explicit sync disable.
private actor CloudAccountBoundTransport: CloudSyncTransport, CloudSyncCancellableTransport, CloudAccountResolutionInvalidationReporting {
    private let base: any CloudSyncTransport
    private let accountProvider: any CloudSyncAccountProviding
    private let targetAccountHash: String
    private let isSessionCurrent: @MainActor @Sendable () -> Bool
    private var invalidated = false

    init(
        base: any CloudSyncTransport,
        accountProvider: any CloudSyncAccountProviding,
        targetAccountHash: String,
        isSessionCurrent: @escaping @MainActor @Sendable () -> Bool
    ) {
        self.base = base
        self.accountProvider = accountProvider
        self.targetAccountHash = targetAccountHash
        self.isSessionCurrent = isSessionCurrent
    }

    var databaseScope: CloudSyncDatabaseScope { get async { await base.databaseScope } }

    func ensureInfrastructure() async throws -> CloudSyncRemoteInfrastructure {
        try await checkAccount()
        let value = try await base.ensureInfrastructure()
        try await checkAccount()
        return value
    }

    func inspectRemoteZone() async throws -> CloudSyncZoneInspection {
        try await checkAccount()
        let value = try await base.inspectRemoteZone()
        try await checkAccount()
        return value
    }

    func resetCustomZone() async throws {
        try await checkAccount()
        try await base.resetCustomZone()
        try await checkAccount()
    }

    func fetchChanges(since token: Data?) async throws -> CloudSyncChangeBatch {
        try await checkAccount()
        let value = try await base.fetchChanges(since: token)
        try await checkAccount()
        return value
    }

    func upsert(_ records: [CloudSyncRecord]) async -> [CloudSyncRecordResult] {
        do { try await checkAccount() }
        catch { return records.map { .init(entityKey: $0.entityKey, outcome: .failed(.notAuthenticated), recordName: $0.recordName) } }
        let results = await base.upsert(records)
        do { try await checkAccount() }
        catch { return records.map { .init(entityKey: $0.entityKey, outcome: .failed(.notAuthenticated), recordName: $0.recordName) } }
        return results
    }

    func delete(_ keys: [SyncEntityKey]) async -> [CloudSyncRecordResult] {
        do { try await checkAccount() }
        catch { return keys.map { .init(entityKey: $0, outcome: .failed(.notAuthenticated)) } }
        let results = await base.delete(keys)
        do { try await checkAccount() }
        catch { return keys.map { .init(entityKey: $0, outcome: .failed(.notAuthenticated)) } }
        return results
    }

    func restoreTransportState(_ state: Data?) async { await base.restoreTransportState(state) }
    func persistedTransportState() async -> Data? { await base.persistedTransportState() }

    func cancelOperations() async {
        await (base as? any CloudSyncCancellableTransport)?.cancelOperations()
    }

    func accountChangedDuringOperation() async -> Bool { invalidated }

    private func checkAccount() async throws {
        guard await isSessionCurrent() else {
            invalidated = true
            throw CloudSyncTransportError.accountChanged
        }
        guard case .available(let recordName) = await accountProvider.resolveAccount(),
              (try? CloudSyncMetadataStore.accountHash(for: recordName)) == targetAccountHash,
              await isSessionCurrent() else {
            invalidated = true
            throw CloudSyncTransportError.accountChanged
        }
    }
}

actor CKCloudSyncAccountProvider: CloudSyncAccountProviding {
    private let configuredContainer: CKContainer?

    init(container: CKContainer? = nil) {
        self.configuredContainer = container
    }

    func resolveAccount() async -> CloudSyncAccountResolution {
        let container = configuredContainer ?? CKContainer.default()
        do {
            switch try await container.accountStatus() {
            case .available:
                do {
                    let user = try await container.userRecordID()
                    return .available(recordName: user.recordName)
                } catch {
                    return .failed("无法读取 iCloud 账户状态")
                }
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine:
                return .temporarilyUnavailable
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            @unknown default:
                return .temporarilyUnavailable
            }
        } catch {
            return .failed("无法确认 iCloud 账户状态")
        }
    }
}

@MainActor
final class CKSyncEngineTransportFactory: CloudSyncTransportFactory {
    private let configuredContainer: CKContainer?
    private let metadataStore: CloudSyncMetadataStore

    init(container: CKContainer? = nil, metadataStore: CloudSyncMetadataStore = CloudSyncMetadataStore()) {
        self.configuredContainer = container
        self.metadataStore = metadataStore
    }

    func makeTransport(accountRecordName: String) async throws -> any CloudSyncTransport {
        let container = configuredContainer ?? CKContainer.default()
        return CKSyncEngineTransport(
            container: container,
            accountRecordName: accountRecordName,
            metadataStore: metadataStore
        )
    }
}

/// Owns explicit CloudKit sync decisions. The local store is attached only after
/// SwiftData has opened the canonical local store; no coordinator path changes
/// that store or gates local writes.
@Observable
@MainActor
final class CloudSyncCoordinator {
    private(set) var status: CloudSyncStatus = .disabled
    private(set) var accountState: CloudSyncCoordinatorAccountState = .unchecked
    private(set) var entitlementState: CloudSyncEntitlementState = .entitled
    private(set) var lastSuccessfulSync: Date?
    private(set) var lastFailurePresentation: CloudSyncFailurePresentation?
    private(set) var automaticRetrySuppressed = false
    private(set) var accountResolutionContext: CloudAccountResolutionContext?
    private(set) var accountResolutionPresentationRequest = 0

    private let settings: UserSettings
    private let accountProvider: any CloudSyncAccountProviding
    private let entitlementProvider: any CloudSyncEntitlementProviding
    private let transportFactory: any CloudSyncTransportFactory
    private let metadataStore: CloudSyncMetadataStore
    private let retryPolicy: CloudSyncRetryPolicy
    private let now: () -> Date
    private let retryDelay: @Sendable (TimeInterval) async -> Void
    private let recoveryPoint: @MainActor @Sendable (URL) async throws -> Void

    private var localStore: (any CloudSyncLocalStore)?
    private var transport: (any CloudSyncTransport)?
    private var currentAccountRecordName: String?
    private var requiresAccountDecision = false
    private var latchedFailureReason: CloudSyncLatchedFailureReason?
    private var sessionGeneration = 0
    private var userIntentGeneration = 0
    private var cycleInProgress = false
    private var lastSceneActiveCheck: Date?
    private var pendingInitialDecision: CloudSyncInitialEnableDecision?
    private var pendingInitialChoice: CloudSyncInitialEnableChoice?
    private var pendingAccountResolutionRecordName: String?
    private var pendingAccountResolutionTransport: (any CloudSyncTransport)?
    private var accountResolutionInProgress = false
    private var accountResolutionCancellationComplete = true
    private var completedSyncCycleCount: UInt64 = 0
    private var failureLatchCount: UInt64 = 0
    private var lastCompletedSyncCycleResult: CloudSyncRemoteTriggerResult = .noData
    private(set) var accountResolutionJournalUnavailable = false
    private var businessDataChanged: @MainActor () -> Void = {}

    var diagnosticsDescription: String {
        "status=\(status.diagnosticDescription),account=\(accountState),requested=\(settings.cloudSyncRequested),retrySuppressed=\(automaticRetrySuppressed)"
    }

    var diagnosticsSnapshot: CloudSyncDiagnosticsSnapshot {
        let accountDecisionRequired = requiresAccountDecision || status == .accountDecisionRequired
        let initialDecisionRequired: Bool
        if case .initialEnableDecisionRequired = status { initialDecisionRequired = true }
        else { initialDecisionRequired = false }
        let canManuallySync = CloudSyncDiagnosticsSnapshot.manualSyncAllowed(
            requested: settings.cloudSyncRequested,
            hasLocalStore: localStore != nil,
            entitlement: entitlementState,
            status: status,
            syncCycleInProgress: cycleInProgress,
            accountResolutionRequired: accountDecisionRequired,
            initialEnableDecisionRequired: initialDecisionRequired,
            resolutionInProgress: accountResolutionInProgress || !accountResolutionCancellationComplete,
            resolutionJournalUnavailable: accountResolutionJournalUnavailable
        )
        return CloudSyncDiagnosticsSnapshot(
            status: status,
            requested: settings.cloudSyncRequested,
            entitlement: entitlementState,
            account: CloudSyncAccountPresentationState(coordinatorState: accountState),
            lastSuccessfulSync: lastSuccessfulSync,
            lastFailure: lastFailurePresentation,
            automaticRetrySuppressed: automaticRetrySuppressed,
            manualSyncAllowed: canManuallySync,
            accountResolutionRequired: accountDecisionRequired
        )
    }

    init(
        settings: UserSettings,
        localStore: (any CloudSyncLocalStore)? = nil,
        accountProvider: (any CloudSyncAccountProviding)? = nil,
        entitlementProvider: (any CloudSyncEntitlementProviding)? = nil,
        transportFactory: (any CloudSyncTransportFactory)? = nil,
        metadataStore: CloudSyncMetadataStore = CloudSyncMetadataStore(),
        retryPolicy: CloudSyncRetryPolicy? = nil,
        now: @escaping () -> Date = Date.init,
        retryDelay: @escaping @Sendable (TimeInterval) async -> Void = { delay in
            try? await Task.sleep(for: .seconds(delay))
        },
        recoveryPoint: @escaping @MainActor @Sendable (URL) async throws -> Void = { storeURL in
            guard try BackupRecoveryService.createSnapshot(storeURL: storeURL, reason: "icloud-use-cloud") != nil else {
                throw CloudSyncReconciliationError.metadata("无法创建本地恢复点，因此没有替换本地数据。")
            }
        }
    ) {
        self.settings = settings
        self.localStore = localStore
        self.accountProvider = accountProvider ?? CKCloudSyncAccountProvider()
        self.entitlementProvider = entitlementProvider ?? OpenAccessCloudSyncEntitlementProvider()
        self.transportFactory = transportFactory ?? CKSyncEngineTransportFactory()
        self.metadataStore = metadataStore
        self.retryPolicy = retryPolicy ?? CloudSyncRetryPolicy()
        self.now = now
        self.retryDelay = retryDelay
        self.recoveryPoint = recoveryPoint
    }

    func attach(
        localStore: any CloudSyncLocalStore,
        onBusinessDataChanged: @escaping @MainActor () -> Void = {}
    ) {
        if let existing = self.localStore, existing === localStore {
            businessDataChanged = onBusinessDataChanged
            return
        }
        sessionGeneration &+= 1
        self.localStore = localStore
        businessDataChanged = onBusinessDataChanged
        if settings.cloudSyncRequested {
            status = .ready
        }
    }

    func setRequested(_ requested: Bool) async {
        userIntentGeneration &+= 1
        let intentGeneration = userIntentGeneration
        guard requested else {
            settings.setCloudSyncRequested(false)
            invalidateSession(status: .disabled)
            accountState = .unchecked
            requiresAccountDecision = false
            currentAccountRecordName = nil
            return
        }

        let entitlement = await entitlementProvider.currentState()
        guard userIntentGeneration == intentGeneration else { return }
        entitlementState = entitlement
        guard entitlement == .entitled else {
            status = .locked(entitlement)
            return
        }

        settings.setCloudSyncRequested(true)
        sessionGeneration &+= 1
        clearPendingDecision()
        requiresAccountDecision = false
        automaticRetrySuppressed = false
        latchedFailureReason = nil
        status = .checkingAccount
        await clearPersistentRetryLatchIfPossible()
        await handle(.initialEnable)
    }

    func syncNow() async {
        guard diagnosticsSnapshot.manualSyncAllowed else { return }
        await handle(.manual)
    }

    func handleRemoteNotification() async -> CloudSyncRemoteTriggerResult {
        guard settings.cloudSyncRequested,
              localStore != nil,
              !cycleInProgress,
              !automaticRetrySuppressed,
              entitlementState == .entitled,
              !diagnosticsSnapshot.accountResolutionRequired else { return .suppressed }
        if case .initialEnableDecisionRequired = status { return .suppressed }

        let cycleCount = completedSyncCycleCount
        let failureCount = failureLatchCount
        await handle(.remoteNotification)
        if completedSyncCycleCount != cycleCount { return lastCompletedSyncCycleResult }
        if failureLatchCount != failureCount { return .failed }
        return .suppressed
    }

    func handle(_ trigger: CloudSyncTrigger) async {
        let triggerGeneration = sessionGeneration
        guard settings.cloudSyncRequested else {
            status = .disabled
            return
        }
        guard localStore != nil else {
            status = .ready
            return
        }

        if trigger == .remoteNotification {
            if requiresAccountDecision || status == .accountDecisionRequired {
                status = .accountDecisionRequired
                return
            }
            do {
                if try metadataStore.loadAccountResolutionJournal() != nil {
                    requiresAccountDecision = true
                    status = .accountDecisionRequired
                    return
                }
            } catch {
                await blockForUnavailableAccountResolutionJournal()
                return
            }
        }

        let unresolvedJournalDecision = requiresAccountDecision && pendingAccountResolutionRecordName == nil
        if trigger == .sceneActive, !unresolvedJournalDecision {
            let activeSyncMustCheckAccount = cycleInProgress
            if !activeSyncMustCheckAccount,
               let lastSceneActiveCheck,
               now().timeIntervalSince(lastSceneActiveCheck) < 30 {
                return
            }
            lastSceneActiveCheck = now()
        }

        if requiresAccountDecision {
            if pendingAccountResolutionRecordName == nil {
                do {
                    if let journal = try metadataStore.loadAccountResolutionJournal() {
                        await resumeIncompleteAccountResolution(journal)
                        return
                    }
                } catch {
                    await blockForUnavailableAccountResolutionJournal()
                    return
                }
            }
            status = .accountDecisionRequired
            return
        }

        do {
            if let journal = try metadataStore.loadAccountResolutionJournal() {
                await resumeIncompleteAccountResolution(journal)
                return
            }
        } catch {
            await blockForUnavailableAccountResolutionJournal()
            return
        }

        if cycleInProgress {
            if trigger == .sceneActive { await detectAccountChangeDuringActiveCycle() }
            return
        }

        if automaticRetrySuppressed {
            guard Self.mayClearLatch(trigger: trigger, reason: latchedFailureReason) else { return }
            automaticRetrySuppressed = false
            latchedFailureReason = nil
            await clearPersistentRetryLatchIfPossible()
        }

        let entitlement = await entitlementProvider.currentState()
        guard isCurrent(triggerGeneration) else { return }
        entitlementState = entitlement
        guard entitlement == .entitled else {
            invalidateSession(status: .locked(entitlement))
            return
        }

        status = .checkingAccount
        let operationGeneration = sessionGeneration
        let resolution = await accountProvider.resolveAccount()
        guard isCurrent(operationGeneration) else { return }
        switch resolution {
        case .available(let recordName):
            accountState = .available
            if let currentAccountRecordName, currentAccountRecordName != recordName {
                await pauseForAccountDecision(targetRecordName: recordName)
                return
            }
            currentAccountRecordName = recordName
            await runForAvailableAccount(recordName: recordName, trigger: trigger, generation: operationGeneration)
        case .noAccount:
            accountState = .noAccount
            status = .accountUnavailable
        case .restricted:
            accountState = .restricted
            status = .accountUnavailable
        case .temporarilyUnavailable:
            accountState = .temporarilyUnavailable
            status = .accountUnavailable
        case .failed:
            accountState = .failed
            status = .accountUnavailable
        }
    }

    func resolveInitialEnable(_ choice: CloudSyncInitialEnableChoice) async {
        guard pendingInitialDecision != nil,
              let localStore,
              let accountRecordName = currentAccountRecordName,
              let transport,
              settings.cloudSyncRequested else { return }
        let generation = sessionGeneration

        if choice == .cancel {
            settings.setCloudSyncRequested(false)
            invalidateSession(status: .disabled)
            clearPendingDecision()
            accountState = .unchecked
            return
        }

        let entitlement = await entitlementProvider.currentState()
        guard isCurrent(generation) else { return }
        entitlementState = entitlement
        guard entitlement == .entitled else {
            invalidateSession(status: .locked(entitlement))
            return
        }

        pendingInitialChoice = choice
        cycleInProgress = true
        status = .syncing
        defer { cycleInProgress = false }
        do {
            let accountHash = try CloudSyncMetadataStore.accountHash(for: accountRecordName)
            if let previousAccountHash = try metadataStore.loadActiveAccountHash(), previousAccountHash != accountHash {
                await pauseForAccountDecision(targetRecordName: accountRecordName)
                return
            }
            let resolution = await accountProvider.resolveAccount()
            guard isCurrent(generation) else { return }
            guard case .available(let confirmedRecordName) = resolution else {
                invalidateSession(status: .accountUnavailable)
                return
            }
            guard confirmedRecordName == accountRecordName else {
                await pauseForAccountDecision(targetRecordName: confirmedRecordName)
                return
            }

            // The prompt may have been open while another device changed the
            // zone. Inspect again before accepting a source-of-truth decision.
            let currentRecords: [CloudSyncRecord]
            if choice == .useLocal {
                currentRecords = [] // explicit local authority does not inspect before reset
            } else {
                if choice == .useCloud {
                    try await recoveryPoint(WeekyiiPersistence.persistentStoreURL())
                    guard isCurrent(generation) else { return }
                }
                let inspection = try await transport.inspectRemoteZone()
                guard isCurrent(generation) else { return }
                currentRecords = inspection.records
                if pendingInitialDecision == .remoteEmpty && choice == .uploadLocal && !currentRecords.isEmpty {
                    pendingInitialDecision = .remoteNonempty
                    pendingInitialChoice = nil
                    status = .initialEnableDecisionRequired(.remoteNonempty)
                    return
                }
                if pendingInitialDecision == .remoteNonempty && currentRecords.isEmpty {
                    pendingInitialDecision = .remoteEmpty
                    pendingInitialChoice = nil
                    status = .initialEnableDecisionRequired(.remoteEmpty)
                    return
                }
            }

            if choice != .useLocal {
                let latestResolution = await accountProvider.resolveAccount()
                guard isCurrent(generation) else { return }
                guard case .available(let latestRecordName) = latestResolution else {
                    invalidateSession(status: .accountUnavailable)
                    return
                }
                guard latestRecordName == accountRecordName else {
                    await pauseForAccountDecision(targetRecordName: latestRecordName)
                    return
                }
            }
            guard isCurrent(generation) else { return }
            switch (pendingInitialDecision, choice) {
            case (.remoteEmpty?, .uploadLocal):
                _ = try await transport.ensureInfrastructure()
                guard isCurrent(generation) else { return }
            case (.remoteNonempty?, .useLocal):
                guard isCurrent(generation) else { return }
                try await transport.resetCustomZone()
                guard isCurrent(generation) else { return }
                _ = try await transport.ensureInfrastructure()
                guard isCurrent(generation) else { return }
            case (.remoteNonempty?, .useCloud):
                let remoteSnapshot = try Self.businessSnapshot(from: currentRecords)
                let diagnostics = WeekyiiSnapshotRepository.validate(remoteSnapshot)
                guard diagnostics.isEmpty else {
                    throw CloudSyncReconciliationError.invalidPlannedSnapshot(diagnostics.map(\.description))
                }
                let previous = try localStore.currentSnapshot()
                try localStore.apply(remoteSnapshot)
                guard isCurrent(generation) else { return }
                try establishBaseline(remoteRecords: currentRecords, accountRecordName: accountRecordName)
                try metadataStore.saveActiveAccountHash(accountHash)
                currentAccountRecordName = accountRecordName
                if previous != remoteSnapshot { businessDataChanged() }
                clearPendingDecision()
                return
            case (.remoteNonempty?, .merge):
                let remoteSnapshot = try Self.businessSnapshot(from: currentRecords)
                let localSnapshot = try localStore.currentSnapshot()
                let merge = try WeekyiiSnapshotMergeService.mergePreferringLocal(local: localSnapshot, remote: remoteSnapshot)
                guard merge.report.diagnostics.isEmpty else {
                    throw CloudSyncReconciliationError.invalidPlannedSnapshot(merge.report.diagnostics.map(\.description))
                }
                guard isCurrent(generation) else { return }
                if localSnapshot != merge.snapshot { try localStore.apply(merge.snapshot); businessDataChanged() }
                guard isCurrent(generation) else { return }
                try await transport.resetCustomZone()
                guard isCurrent(generation) else { return }
                _ = try await transport.ensureInfrastructure()
                guard isCurrent(generation) else { return }
            default:
                return
            }

            guard isCurrent(generation) else { return }
            // The first-data decision is already explicit at this point and
            // the chosen source has been safely prepared. Retain its account
            // binding across transient upload failure so a retry restores the
            // failure latch instead of treating this same account as orphaned.
            // Account-switch resolution uses a separate path and commits only
            // after its full reset/apply/reconcile sequence succeeds.
            try metadataStore.saveActiveAccountHash(accountHash)
            currentAccountRecordName = accountRecordName
            let didSync = await reconcileWithRetries(transport: transport, accountRecordName: accountRecordName, generation: generation)
            if didSync, isCurrent(generation) {
                try metadataStore.saveActiveAccountHash(accountHash)
                currentAccountRecordName = accountRecordName
            }
        } catch {
            guard isCurrent(generation) else { return }
            await handleFailure(error, accountRecordName: accountRecordName)
        }
    }

    /// Inspects only the current target account's Weekyii zone. This operation
    /// never creates infrastructure or applies cloud data to the business store.
    @discardableResult
    func prepareAccountResolutionContext() async -> CloudAccountResolutionContext? {
        guard settings.cloudSyncRequested,
              requiresAccountDecision,
              accountResolutionCancellationComplete else { return nil }
        guard !accountResolutionJournalUnavailable else { return accountResolutionContext }
        let targetRecordName = pendingAccountResolutionRecordName
        let journal: CloudAccountResolutionJournal?
        do {
            journal = try metadataStore.loadAccountResolutionJournal()
        } catch {
            await blockForUnavailableAccountResolutionJournal()
            return accountResolutionContext
        }
        if targetRecordName == nil {
            guard let journal else { return accountResolutionContext }
            let localCount = (try? localStore?.currentSnapshot().entityKeys().count) ?? 0
            accountResolutionContext = CloudAccountResolutionContext(
                previousAccountHash: journal.previousAccountHash,
                targetAccountHash: journal.targetAccountHash,
                localEntityCount: localCount,
                targetCloudEntityCount: nil,
                targetCloudIsEmpty: nil,
                targetAccountAvailable: false,
                progress: .failed(.targetAccountRequired)
            )
            return accountResolutionContext
        }
        guard let targetRecordName else { return accountResolutionContext }
        if let context = accountResolutionContext,
           context.progress == .ready,
           context.targetAccountAvailable,
           pendingAccountResolutionTransport != nil {
            return context
        }

        let generation = sessionGeneration
        let targetHash: String
        let previousHash: String?
        do {
            targetHash = try CloudSyncMetadataStore.accountHash(for: targetRecordName)
            if let journal {
                previousHash = journal.previousAccountHash
            } else {
                previousHash = try metadataStore.loadActiveAccountHash()
            }
        } catch {
            markAccountResolutionFailed(.cloudOperationFailed)
            return accountResolutionContext
        }

        let localSnapshot: WeekyiiBusinessSnapshot
        do {
            guard let localStore else { throw CloudAccountResolutionFailure.localDataUnavailable }
            localSnapshot = try localStore.currentSnapshot()
            let diagnostics = WeekyiiSnapshotRepository.validate(localSnapshot)
            guard diagnostics.isEmpty else { throw CloudAccountResolutionFailure.localDataUnavailable }
        } catch {
            accountResolutionContext = CloudAccountResolutionContext(
                previousAccountHash: previousHash,
                targetAccountHash: targetHash,
                localEntityCount: 0,
                targetCloudEntityCount: nil,
                targetCloudIsEmpty: nil,
                targetAccountAvailable: true,
                progress: .failed(.localDataUnavailable)
            )
            return accountResolutionContext
        }

        accountResolutionContext = CloudAccountResolutionContext(
            previousAccountHash: previousHash,
            targetAccountHash: targetHash,
            localEntityCount: localSnapshot.entityKeys().count,
            targetCloudEntityCount: nil,
            targetCloudIsEmpty: nil,
            targetAccountAvailable: true,
            progress: .inspecting
        )

        guard await verifyResolutionTarget(targetRecordName, generation: generation) else {
            return accountResolutionContext
        }

        do {
            let targetTransport: any CloudSyncTransport
            if let pendingAccountResolutionTransport {
                targetTransport = pendingAccountResolutionTransport
            } else {
                targetTransport = try await transportFactory.makeTransport(accountRecordName: targetRecordName)
            }
            guard isAccountResolutionCurrent(generation, targetRecordName: targetRecordName) else { return accountResolutionContext }
            guard await verifyResolutionTarget(targetRecordName, generation: generation) else { return accountResolutionContext }
            let inspection = try await targetTransport.inspectRemoteZone()
            guard isAccountResolutionCurrent(generation, targetRecordName: targetRecordName) else { return accountResolutionContext }
            guard await verifyResolutionTarget(targetRecordName, generation: generation) else { return accountResolutionContext }
            _ = try Self.businessSnapshot(from: inspection.records)

            pendingAccountResolutionTransport = targetTransport
            accountResolutionContext = CloudAccountResolutionContext(
                previousAccountHash: previousHash,
                targetAccountHash: targetHash,
                localEntityCount: localSnapshot.entityKeys().count,
                targetCloudEntityCount: inspection.records.count,
                targetCloudIsEmpty: inspection.records.isEmpty,
                targetAccountAvailable: true,
                progress: .ready
            )
        } catch let failure as CloudAccountResolutionFailure {
            markAccountResolutionFailed(failure)
        } catch let error as CloudSyncTransportError where error == .accountChanged {
            await retargetResolutionToCurrentAccount(generation: generation)
        } catch {
            let failure: CloudAccountResolutionFailure
            if error is CloudRecordCodecError || error is CloudSyncReconciliationError {
                failure = .invalidCloudData
            } else {
                failure = .cloudOperationFailed
            }
            markAccountResolutionFailed(failure)
        }
        return accountResolutionContext
    }

    /// Applies an explicit choice to the newly signed-in account. Staging is
    /// advisory only; cloud data is re-read before every choice that consumes it.
    func resolveAccountSwitch(_ choice: CloudAccountResolutionChoice) async {
        if choice == .disable {
            await setRequested(false)
            return
        }
        guard settings.cloudSyncRequested,
              requiresAccountDecision,
              let targetRecordName = pendingAccountResolutionRecordName else { return }
        if accountResolutionContext?.progress != .ready || pendingAccountResolutionTransport == nil {
            guard await prepareAccountResolutionContext()?.progress == .ready else { return }
        }
        guard let context = accountResolutionContext,
              let targetTransport = pendingAccountResolutionTransport,
              let localStore else { return }

        let generation = sessionGeneration
        guard await verifyResolutionTarget(targetRecordName, generation: generation) else { return }
        do {
            try persistAccountResolutionJournal(
                targetRecordName: targetRecordName,
                context: context,
                choice: choice,
                stage: .choiceSelected
            )
        } catch {
            markAccountResolutionFailed(.journalUnavailable)
            return
        }
        accountResolutionInProgress = true
        accountResolutionContext?.progress = .resolving(choice)
        defer { accountResolutionInProgress = false }

        let boundTransport = CloudAccountBoundTransport(
            base: targetTransport,
            accountProvider: accountProvider,
            targetAccountHash: context.targetAccountHash,
            isSessionCurrent: { [weak self] in
                guard let self else { return false }
                return self.isAccountResolutionCurrent(generation, targetRecordName: targetRecordName)
            }
        )

        do {
            switch choice {
            case .disable:
                return
            case .useLocal:
                let localBeforeReset = try localStore.currentSnapshot()
                guard WeekyiiSnapshotRepository.validate(localBeforeReset).isEmpty else {
                    markAccountResolutionFailed(.localDataUnavailable)
                    return
                }
                try persistAccountResolutionJournal(
                    targetRecordName: targetRecordName,
                    context: context,
                    choice: choice,
                    stage: .targetCloudMutationBegun
                )
                try await boundTransport.resetCustomZone()
                try metadataStore.resetSynchronizationState(forAccountRecordName: targetRecordName)
                _ = try await boundTransport.ensureInfrastructure()
                let succeeded = await reconcileWithRetries(
                    transport: boundTransport,
                    accountRecordName: targetRecordName,
                    generation: generation
                )
                guard isAccountResolutionCurrent(generation, targetRecordName: targetRecordName) else { return }
                if await boundTransport.accountChangedDuringOperation() {
                    await retargetResolutionToCurrentAccount(generation: generation)
                    return
                }
                guard succeeded else {
                    markAccountResolutionFailed(.cloudOperationFailed)
                    return
                }
                let finalLocal = try localStore.currentSnapshot()
                let finalRemote = try await boundTransport.inspectRemoteZone()
                let finalRemoteSnapshot = try Self.businessSnapshot(from: finalRemote.records)
                guard finalLocal == finalRemoteSnapshot else {
                    markAccountResolutionFailed(.cloudOperationFailed)
                    return
                }
                try establishBaseline(remoteRecords: finalRemote.records, accountRecordName: targetRecordName)
                try persistAccountResolutionJournal(
                    targetRecordName: targetRecordName,
                    context: context,
                    choice: choice,
                    stage: .readyToCommit
                )
                guard await commitAccountResolution(targetRecordName: targetRecordName, accountHash: context.targetAccountHash, transport: targetTransport) else { return }

            case .useCloud:
                let inspection = try await boundTransport.inspectRemoteZone()
                let remoteSnapshot = try Self.businessSnapshot(from: inspection.records)
                guard await verifyResolutionTarget(targetRecordName, generation: generation) else { return }
                do {
                    try await recoveryPoint(WeekyiiPersistence.persistentStoreURL())
                } catch {
                    markAccountResolutionFailed(.recoveryPointFailed)
                    return
                }
                guard await verifyResolutionTarget(targetRecordName, generation: generation) else { return }
                let previousLocal = try localStore.currentSnapshot()
                try persistAccountResolutionJournal(
                    targetRecordName: targetRecordName,
                    context: context,
                    choice: choice,
                    stage: .localMutationAuthorized
                )
                try localStore.apply(remoteSnapshot)
                try persistAccountResolutionJournal(
                    targetRecordName: targetRecordName,
                    context: context,
                    choice: choice,
                    stage: .localMutationApplied
                )
                try metadataStore.resetSynchronizationState(forAccountRecordName: targetRecordName)
                try establishBaseline(remoteRecords: inspection.records, accountRecordName: targetRecordName)
                if previousLocal != remoteSnapshot { businessDataChanged() }
                try persistAccountResolutionJournal(
                    targetRecordName: targetRecordName,
                    context: context,
                    choice: choice,
                    stage: .readyToCommit
                )
                guard await commitAccountResolution(targetRecordName: targetRecordName, accountHash: context.targetAccountHash, transport: targetTransport) else { return }

            case .merge:
                let inspection = try await boundTransport.inspectRemoteZone()
                let remoteSnapshot = try Self.businessSnapshot(from: inspection.records)
                let localSnapshot = try localStore.currentSnapshot()
                let merge = try WeekyiiSnapshotMergeService.mergePreferringLocal(local: localSnapshot, remote: remoteSnapshot)
                guard merge.report.diagnostics.isEmpty else {
                    markAccountResolutionFailed(.invalidCloudData)
                    return
                }
                guard await verifyResolutionTarget(targetRecordName, generation: generation) else { return }
                do {
                    try await recoveryPoint(WeekyiiPersistence.persistentStoreURL())
                } catch {
                    markAccountResolutionFailed(.recoveryPointFailed)
                    return
                }
                guard await verifyResolutionTarget(targetRecordName, generation: generation) else { return }
                if localSnapshot != merge.snapshot {
                    try persistAccountResolutionJournal(
                        targetRecordName: targetRecordName,
                        context: context,
                        choice: choice,
                        stage: .localMutationAuthorized
                    )
                    try localStore.apply(merge.snapshot)
                    try persistAccountResolutionJournal(
                        targetRecordName: targetRecordName,
                        context: context,
                        choice: choice,
                        stage: .localMutationApplied
                    )
                    businessDataChanged()
                }
                try persistAccountResolutionJournal(
                    targetRecordName: targetRecordName,
                    context: context,
                    choice: choice,
                    stage: .targetCloudMutationBegun
                )
                try await boundTransport.resetCustomZone()
                try metadataStore.resetSynchronizationState(forAccountRecordName: targetRecordName)
                _ = try await boundTransport.ensureInfrastructure()
                let succeeded = await reconcileWithRetries(
                    transport: boundTransport,
                    accountRecordName: targetRecordName,
                    generation: generation
                )
                guard isAccountResolutionCurrent(generation, targetRecordName: targetRecordName) else { return }
                if await boundTransport.accountChangedDuringOperation() {
                    await retargetResolutionToCurrentAccount(generation: generation)
                    return
                }
                guard succeeded else {
                    markAccountResolutionFailed(.cloudOperationFailed)
                    return
                }
                let finalLocal = try localStore.currentSnapshot()
                let finalRemote = try await boundTransport.inspectRemoteZone()
                let finalRemoteSnapshot = try Self.businessSnapshot(from: finalRemote.records)
                guard finalLocal == finalRemoteSnapshot else {
                    markAccountResolutionFailed(.cloudOperationFailed)
                    return
                }
                try establishBaseline(remoteRecords: finalRemote.records, accountRecordName: targetRecordName)
                try persistAccountResolutionJournal(
                    targetRecordName: targetRecordName,
                    context: context,
                    choice: choice,
                    stage: .readyToCommit
                )
                guard await commitAccountResolution(targetRecordName: targetRecordName, accountHash: context.targetAccountHash, transport: targetTransport) else { return }
            }
        } catch let failure as CloudAccountResolutionFailure {
            markAccountResolutionFailed(failure)
        } catch let error as CloudSyncTransportError where error == .accountChanged {
            await retargetResolutionToCurrentAccount(generation: generation)
        } catch let error as CloudSyncReconciliationError {
            if case .accountChanged = error {
                await retargetResolutionToCurrentAccount(generation: generation)
            } else {
                markAccountResolutionFailed(Self.isSnapshotFailure(error) ? .invalidCloudData : .cloudOperationFailed)
            }
        } catch {
            markAccountResolutionFailed(.cloudOperationFailed)
        }
    }

    /// Deferring presentation changes no sync or data state. ContentView can
    /// reopen the decision while the coordinator remains paused.
    func deferAccountResolutionPresentation() { }

    func requestAccountResolutionPresentation() {
        guard requiresAccountDecision || status == .accountDecisionRequired else { return }
        accountResolutionPresentationRequest &+= 1
    }

    private func runForAvailableAccount(
        recordName: String,
        trigger: CloudSyncTrigger,
        generation: Int
    ) async {
        guard let localStore else { status = .ready; return }
        cycleInProgress = true
        defer { cycleInProgress = false }
        do {
            let accountHash = try CloudSyncMetadataStore.accountHash(for: recordName)
            let activeAccountHash = try metadataStore.loadActiveAccountHash()
            if let activeAccountHash, activeAccountHash != accountHash {
                await pauseForAccountDecision(targetRecordName: recordName)
                return
            }

            let metadata = try metadataStore.load(forAccountRecordName: recordName)
            // A metadata directory can outlive the active-account commit marker
            // (for example after an interrupted resolution or restored backup).
            // Its baseline is not authority to resume this account automatically.
            if activeAccountHash == nil,
               metadata?.zoneInitialized == true || metadata?.lastSuccessfulSync != nil {
                await pauseForAccountDecision(targetRecordName: recordName)
                return
            }
            lastSuccessfulSync = metadata?.lastSuccessfulSync
            automaticRetrySuppressed = metadata?.automaticRetrySuppressed ?? false
            latchedFailureReason = metadata?.lastFailureReason
            lastFailurePresentation = metadata?.lastFailureReason.map { CloudSyncFailurePresentation(reason: $0) }
                ?? ((metadata?.lastFailure?.isEmpty == false) ? CloudSyncFailurePresentation(reason: .other) : nil)
            if metadata?.lastSuccessfulSync != nil, metadata?.zoneInitialized == true {
                try metadataStore.saveActiveAccountHash(accountHash)
            }
            if automaticRetrySuppressed {
                guard Self.mayClearLatch(trigger: trigger, reason: latchedFailureReason) else {
                status = Self.statusForLatchedFailure(latchedFailureReason)
                    return
                }
                automaticRetrySuppressed = false
                latchedFailureReason = nil
                await clearPersistentRetryLatchIfPossible()
            }
            let transport: any CloudSyncTransport
            if let existing = self.transport {
                transport = existing
            } else {
                transport = try await transportFactory.makeTransport(accountRecordName: recordName)
                guard isCurrent(generation) else { return }
                self.transport = transport
            }
            await transport.restoreTransportState(metadata?.syncEngineState)
            guard isCurrent(generation) else { return }

            if let pendingInitialChoice {
                await resolveInitialEnable(pendingInitialChoice)
                return
            }

            if metadata?.lastSuccessfulSync == nil || metadata?.zoneInitialized != true {
                let inspection = try await transport.inspectRemoteZone()
                guard isCurrent(generation) else { return }
                let decision: CloudSyncInitialEnableDecision = inspection.records.isEmpty ? .remoteEmpty : .remoteNonempty
                pendingInitialDecision = decision
                status = .initialEnableDecisionRequired(decision)
                return
            }

            _ = localStore
            _ = try await transport.ensureInfrastructure()
            guard isCurrent(generation) else { return }
            _ = await reconcileWithRetries(transport: transport, accountRecordName: recordName, generation: generation)
        } catch {
            guard isCurrent(generation) else { return }
            await handleFailure(error, accountRecordName: recordName)
        }
    }

    private func reconcileWithRetries(
        transport: any CloudSyncTransport,
        accountRecordName: String,
        generation: Int
    ) async -> Bool {
        guard let localStore, isCurrent(generation) else { return false }
        cycleInProgress = true
        status = .syncing
        var cycleResult: CloudSyncRemoteTriggerResult = .noData
        defer {
            cycleInProgress = false
            completedSyncCycleCount &+= 1
            lastCompletedSyncCycleResult = cycleResult
        }

        let reconciler = CloudSyncReconciler(
            localStore: localStore,
            transport: transport,
            metadataStore: metadataStore,
            accountRecordName: accountRecordName,
            now: now
        )
        var retryNumber = 0
        while isCurrent(generation) {
            let snapshotBeforeAttempt = try? localStore.currentSnapshot()
            do {
                let report = try await reconciler.reconcile { [weak self] in
                    guard let self else { return false }
                    return self.isCurrent(generation)
                }
                guard isCurrent(generation) else { return false }
                if report.remoteAppliedUpserts > 0 || report.remoteDeletionsApplied > 0 {
                    businessDataChanged()
                }
                if report.perRecordFailures.isEmpty {
                    let date = report.successTimestamp ?? now()
                    cycleResult = report.remoteAppliedUpserts > 0 || report.remoteDeletionsApplied > 0 ? .newData : .noData
                    lastSuccessfulSync = date
                    lastFailurePresentation = nil
                    automaticRetrySuppressed = false
                    latchedFailureReason = nil
                    status = .synced(date)
                    if pendingInitialChoice != nil { clearPendingDecision() }
                    return true
                }

                let failures = report.perRecordFailures.map(\.failure)
                guard let retryFailure = failures.first.flatMap(retryFailureCandidate),
                      failures.allSatisfy({ retryFailureCandidate($0) != nil }),
                      retryNumber < retryPolicy.maximumRetries else {
                    await latchFailure(failures.first ?? .other("同步部分失败"), accountRecordName: accountRecordName)
                    cycleResult = .failed
                    return false
                }
                retryNumber += 1
                let delay: TimeInterval
                if case .retry(let seconds) = retryPolicy.retryDecision(for: retryFailure, retryNumber: retryNumber) {
                    delay = seconds
                } else {
                    await latchFailure(retryFailure, accountRecordName: accountRecordName)
                    cycleResult = .failed
                    return false
                }
                await retryDelay(delay)
            } catch {
                guard isCurrent(generation) else { return false }
                if let snapshotBeforeAttempt,
                   let snapshotAfterAttempt = try? localStore.currentSnapshot(),
                   snapshotBeforeAttempt != snapshotAfterAttempt {
                    businessDataChanged()
                }
                if case CloudSyncReconciliationError.sessionInvalidated = error { return false }
                if case CloudSyncReconciliationError.accountChanged = error { return false }
                let failure = Self.failure(from: error)
                guard let retryFailure = retryFailureCandidate(failure),
                      retryNumber < retryPolicy.maximumRetries else {
                    await latchFailure(failure, accountRecordName: accountRecordName)
                    cycleResult = .failed
                    return false
                }
                retryNumber += 1
                let delay: TimeInterval
                if case .retry(let seconds) = retryPolicy.retryDecision(for: retryFailure, retryNumber: retryNumber) {
                    delay = seconds
                } else {
                    await latchFailure(retryFailure, accountRecordName: accountRecordName)
                    cycleResult = .failed
                    return false
                }
                await retryDelay(delay)
            }
        }
        return false
    }

    private func detectAccountChangeDuringActiveCycle() async {
        guard let currentAccountRecordName, settings.cloudSyncRequested else { return }
        let generation = sessionGeneration
        let entitlement = await entitlementProvider.currentState()
        guard isCurrent(generation) else { return }
        entitlementState = entitlement
        guard entitlement == .entitled else {
            invalidateSession(status: .locked(entitlement))
            return
        }
        let resolution = await accountProvider.resolveAccount()
        guard isCurrent(generation) else { return }
        switch resolution {
        case .available(let newName) where newName != currentAccountRecordName:
            await pauseForAccountDecision(targetRecordName: newName)
        case .available:
            accountState = .available
        case .noAccount:
            accountState = .noAccount
            invalidateSession(status: .accountUnavailable)
        case .restricted:
            accountState = .restricted
            invalidateSession(status: .accountUnavailable)
        case .temporarilyUnavailable:
            accountState = .temporarilyUnavailable
            invalidateSession(status: .accountUnavailable)
        case .failed:
            accountState = .failed
            invalidateSession(status: .accountUnavailable)
        }
    }

    private func pauseForAccountDecision(targetRecordName: String) async {
        guard settings.cloudSyncRequested else { return }
        do {
            let targetHash = try CloudSyncMetadataStore.accountHash(for: targetRecordName)
            let existingJournal = try metadataStore.loadAccountResolutionJournal()
            if existingJournal?.targetAccountHash != targetHash {
                let previousAccountHash: String?
                if let existingJournal {
                    previousAccountHash = existingJournal.previousAccountHash
                } else {
                    previousAccountHash = try metadataStore.loadActiveAccountHash()
                }
                let priorMutationMayHaveOccurred = existingJournal.map {
                    switch $0.stage {
                    case .localMutationAuthorized, .localMutationApplied, .targetCloudMutationBegun, .readyToCommit, .decisionPendingAfterMutation:
                        true
                    case .decisionPending, .choiceSelected:
                        false
                    }
                } ?? false
                let journal = CloudAccountResolutionJournal(
                    previousAccountHash: previousAccountHash,
                    targetAccountHash: targetHash,
                    choice: nil,
                    stage: priorMutationMayHaveOccurred ? .decisionPendingAfterMutation : .decisionPending
                )
                try metadataStore.saveAccountResolutionJournal(journal)
            }
            accountResolutionJournalUnavailable = false
        } catch {
            accountResolutionJournalUnavailable = true
        }
        if requiresAccountDecision,
           pendingAccountResolutionRecordName == targetRecordName {
            if accountResolutionJournalUnavailable {
                status = .accountDecisionRequired
                markAccountResolutionFailed(.journalUnavailable)
            }
            return
        }
        sessionGeneration &+= 1
        let decisionGeneration = sessionGeneration
        requiresAccountDecision = true
        accountResolutionCancellationComplete = false
        accountResolutionContext = nil
        accountResolutionInProgress = false
        pendingAccountResolutionRecordName = targetRecordName
        let oldTransport = transport
        let oldTargetTransport = pendingAccountResolutionTransport
        transport = nil
        pendingAccountResolutionTransport = nil
        await (oldTransport as? any CloudSyncCancellableTransport)?.cancelOperations()
        await (oldTargetTransport as? any CloudSyncCancellableTransport)?.cancelOperations()
        guard sessionGeneration == decisionGeneration, settings.cloudSyncRequested else { return }
        accountResolutionCancellationComplete = true
        status = .accountDecisionRequired
        automaticRetrySuppressed = true
        if accountResolutionJournalUnavailable {
            accountResolutionContext = nil
        }
    }

    private func resumeIncompleteAccountResolution(_ journal: CloudAccountResolutionJournal) async {
        sessionGeneration &+= 1
        let generation = sessionGeneration
        requiresAccountDecision = true
        accountResolutionCancellationComplete = false
        accountResolutionJournalUnavailable = false
        pendingAccountResolutionRecordName = nil
        accountResolutionContext = nil
        let oldTargetTransport = pendingAccountResolutionTransport
        pendingAccountResolutionTransport = nil
        accountResolutionInProgress = false
        let oldTransport = transport
        transport = nil
        pendingAccountResolutionTransport = nil
        await (oldTransport as? any CloudSyncCancellableTransport)?.cancelOperations()
        await (oldTargetTransport as? any CloudSyncCancellableTransport)?.cancelOperations()
        guard generation == sessionGeneration, settings.cloudSyncRequested else { return }
        accountResolutionCancellationComplete = true
        status = .accountDecisionRequired
        automaticRetrySuppressed = true

        switch await accountProvider.resolveAccount() {
        case .available(let recordName):
            accountState = .available
            do {
                let signedInHash = try CloudSyncMetadataStore.accountHash(for: recordName)
                if signedInHash == journal.targetAccountHash {
                    pendingAccountResolutionRecordName = recordName
                    setAvailableResolutionContext(for: journal)
                } else if signedInHash == journal.previousAccountHash {
                    setUnavailableResolutionContext(for: journal, failure: .targetAccountRequired)
                } else {
                    let hadLocalMutation = Self.journalMayHaveChangedLocalData(journal.stage)
                    let retargeted = CloudAccountResolutionJournal(
                        previousAccountHash: journal.previousAccountHash,
                        targetAccountHash: signedInHash,
                        choice: nil,
                        stage: hadLocalMutation ? .decisionPendingAfterMutation : .decisionPending
                    )
                    try metadataStore.saveAccountResolutionJournal(retargeted)
                    pendingAccountResolutionRecordName = recordName
                    setAvailableResolutionContext(for: retargeted)
                }
            } catch {
                await blockForUnavailableAccountResolutionJournal()
            }
        case .noAccount:
            accountState = .noAccount
            setUnavailableResolutionContext(for: journal, failure: .accountUnavailable)
        case .restricted:
            accountState = .restricted
            setUnavailableResolutionContext(for: journal, failure: .accountUnavailable)
        case .temporarilyUnavailable:
            accountState = .temporarilyUnavailable
            setUnavailableResolutionContext(for: journal, failure: .accountUnavailable)
        case .failed:
            accountState = .failed
            setUnavailableResolutionContext(for: journal, failure: .accountUnavailable)
        }
    }

    private func setUnavailableResolutionContext(
        for journal: CloudAccountResolutionJournal,
        failure: CloudAccountResolutionFailure
    ) {
        let localCount = (try? localStore?.currentSnapshot().entityKeys().count) ?? 0
        accountResolutionContext = CloudAccountResolutionContext(
            previousAccountHash: journal.previousAccountHash,
            targetAccountHash: journal.targetAccountHash,
            localEntityCount: localCount,
            targetCloudEntityCount: nil,
            targetCloudIsEmpty: nil,
            targetAccountAvailable: false,
            progress: .failed(failure)
        )
        status = .accountDecisionRequired
    }

    private func setAvailableResolutionContext(for journal: CloudAccountResolutionJournal) {
        let localCount = (try? localStore?.currentSnapshot().entityKeys().count) ?? 0
        accountResolutionContext = CloudAccountResolutionContext(
            previousAccountHash: journal.previousAccountHash,
            targetAccountHash: journal.targetAccountHash,
            localEntityCount: localCount,
            targetCloudEntityCount: nil,
            targetCloudIsEmpty: nil,
            targetAccountAvailable: true,
            progress: .inspecting
        )
        status = .accountDecisionRequired
    }

    private func blockForUnavailableAccountResolutionJournal() async {
        accountResolutionJournalUnavailable = true
        sessionGeneration &+= 1
        let generation = sessionGeneration
        requiresAccountDecision = true
        accountResolutionCancellationComplete = false
        pendingAccountResolutionRecordName = nil
        let oldTargetTransport = pendingAccountResolutionTransport
        pendingAccountResolutionTransport = nil
        accountResolutionContext = nil
        let oldTransport = transport
        transport = nil
        await (oldTransport as? any CloudSyncCancellableTransport)?.cancelOperations()
        await (oldTargetTransport as? any CloudSyncCancellableTransport)?.cancelOperations()
        guard generation == sessionGeneration else { return }
        accountResolutionCancellationComplete = true
        status = .accountDecisionRequired
        automaticRetrySuppressed = true
    }

    private func persistAccountResolutionJournal(
        targetRecordName: String,
        context: CloudAccountResolutionContext,
        choice: CloudAccountResolutionChoice,
        stage: CloudAccountResolutionJournalStage
    ) throws {
        let targetHash = try CloudSyncMetadataStore.accountHash(for: targetRecordName)
        guard targetHash == context.targetAccountHash else { throw CloudAccountResolutionFailure.accountChanged }
        let existing = try metadataStore.loadAccountResolutionJournal()
        if let existing, existing.targetAccountHash != targetHash {
            throw CloudAccountResolutionFailure.accountChanged
        }
        let previousAccountHash: String?
        if let existing {
            previousAccountHash = existing.previousAccountHash
        } else {
            previousAccountHash = context.previousAccountHash
        }
        let journal = CloudAccountResolutionJournal(
            previousAccountHash: previousAccountHash,
            targetAccountHash: targetHash,
            choice: choice,
            stage: stage
        )
        do {
            try metadataStore.saveAccountResolutionJournal(journal)
            accountResolutionJournalUnavailable = false
        } catch {
            throw CloudAccountResolutionFailure.journalUnavailable
        }
    }

    private static func journalMayHaveChangedLocalData(_ stage: CloudAccountResolutionJournalStage) -> Bool {
        switch stage {
        case .localMutationAuthorized, .localMutationApplied, .targetCloudMutationBegun, .readyToCommit, .decisionPendingAfterMutation:
            true
        case .decisionPending, .choiceSelected:
            false
        }
    }

    private func isAccountResolutionCurrent(_ generation: Int, targetRecordName: String) -> Bool {
        settings.cloudSyncRequested
            && requiresAccountDecision
            && accountResolutionCancellationComplete
            && sessionGeneration == generation
            && pendingAccountResolutionRecordName == targetRecordName
    }

    private func verifyResolutionTarget(_ targetRecordName: String, generation: Int) async -> Bool {
        guard isAccountResolutionCurrent(generation, targetRecordName: targetRecordName) else { return false }
        let resolution = await accountProvider.resolveAccount()
        guard sessionGeneration == generation, settings.cloudSyncRequested, requiresAccountDecision else { return false }
        switch resolution {
        case .available(let currentRecordName):
            guard currentRecordName == targetRecordName else {
                await pauseForAccountDecision(targetRecordName: currentRecordName)
                return false
            }
            return true
        case .noAccount:
            accountState = .noAccount
        case .restricted:
            accountState = .restricted
        case .temporarilyUnavailable:
            accountState = .temporarilyUnavailable
        case .failed:
            accountState = .failed
        }
        markAccountResolutionFailed(.accountUnavailable)
        return false
    }

    private func retargetResolutionToCurrentAccount(generation: Int) async {
        guard sessionGeneration == generation, settings.cloudSyncRequested, requiresAccountDecision else { return }
        let resolution = await accountProvider.resolveAccount()
        guard sessionGeneration == generation, settings.cloudSyncRequested, requiresAccountDecision else { return }
        switch resolution {
        case .available(let currentRecordName):
            if currentRecordName != pendingAccountResolutionRecordName {
                await pauseForAccountDecision(targetRecordName: currentRecordName)
            } else {
                markAccountResolutionFailed(.accountChanged)
            }
        case .noAccount:
            accountState = .noAccount
            markAccountResolutionFailed(.accountUnavailable)
        case .restricted:
            accountState = .restricted
            markAccountResolutionFailed(.accountUnavailable)
        case .temporarilyUnavailable:
            accountState = .temporarilyUnavailable
            markAccountResolutionFailed(.accountUnavailable)
        case .failed:
            accountState = .failed
            markAccountResolutionFailed(.accountUnavailable)
        }
    }

    private func markAccountResolutionFailed(_ failure: CloudAccountResolutionFailure) {
        guard var context = accountResolutionContext else {
            status = .accountDecisionRequired
            automaticRetrySuppressed = true
            return
        }
        context.progress = .failed(failure)
        accountResolutionContext = context
        status = .accountDecisionRequired
        automaticRetrySuppressed = true
    }

    private func commitAccountResolution(
        targetRecordName: String,
        accountHash: String,
        transport: any CloudSyncTransport
    ) async -> Bool {
        guard isAccountResolutionCurrent(sessionGeneration, targetRecordName: targetRecordName) else {
            return false
        }
        do {
            let journal = try metadataStore.loadAccountResolutionJournal()
            guard let journal,
                  journal.targetAccountHash == accountHash,
                  journal.stage == .readyToCommit else {
                markAccountResolutionFailed(.journalUnavailable)
                return false
            }
        } catch {
            markAccountResolutionFailed(.journalUnavailable)
            return false
        }

        let finalResolution = await accountProvider.resolveAccount()
        guard isAccountResolutionCurrent(sessionGeneration, targetRecordName: targetRecordName) else { return false }
        switch finalResolution {
        case .available(let latestRecordName):
            guard latestRecordName == targetRecordName else {
                await pauseForAccountDecision(targetRecordName: latestRecordName)
                return false
            }
        case .noAccount:
            accountState = .noAccount
            markAccountResolutionFailed(.accountUnavailable)
            return false
        case .restricted:
            accountState = .restricted
            markAccountResolutionFailed(.accountUnavailable)
            return false
        case .temporarilyUnavailable:
            accountState = .temporarilyUnavailable
            markAccountResolutionFailed(.accountUnavailable)
            return false
        case .failed:
            accountState = .failed
            markAccountResolutionFailed(.accountUnavailable)
            return false
        }

        do {
            try metadataStore.saveActiveAccountHash(accountHash)
        } catch {
            markAccountResolutionFailed(.cloudOperationFailed)
            return false
        }
        do {
            try metadataStore.clearAccountResolutionJournal()
        } catch {
            markAccountResolutionFailed(.journalUnavailable)
            return false
        }
        currentAccountRecordName = targetRecordName
        self.transport = transport
        pendingAccountResolutionRecordName = nil
        pendingAccountResolutionTransport = nil
        accountResolutionContext = nil
        requiresAccountDecision = false
        accountResolutionCancellationComplete = true
        automaticRetrySuppressed = false
        accountState = .available
        status = .synced(lastSuccessfulSync ?? now())
        return true
    }

    private static func isSnapshotFailure(_ error: CloudSyncReconciliationError) -> Bool {
        switch error {
        case .invalidRemoteRecord, .invalidPlannedSnapshot: true
        default: false
        }
    }

    private func handleFailure(_ error: Error, accountRecordName: String) async {
        await latchFailure(Self.failure(from: error), accountRecordName: accountRecordName)
    }

    private func latchFailure(_ failure: CloudSyncFailure, accountRecordName: String) async {
        failureLatchCount &+= 1
        automaticRetrySuppressed = true
        latchedFailureReason = Self.reason(for: failure)
        lastFailurePresentation = CloudSyncFailurePresentation(reason: latchedFailureReason ?? .other)
        do {
            try metadataStore.update(forAccountRecordName: accountRecordName) { metadata in
                metadata.automaticRetrySuppressed = true
                metadata.lastFailure = lastFailurePresentation?.localizedDescription
                metadata.lastFailureCategory = retryPolicy.classify(failure).category
                metadata.lastFailureReason = Self.reason(for: failure)
            }
        } catch {
            // The in-memory latch still prevents a scene-active retry storm when
            // device-local metadata itself cannot be written.
        }
        switch failure {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            status = .offline
        case .quotaExceeded:
            status = .quotaExceeded
        case .notAuthenticated:
            status = .accountUnavailable
        default:
            status = .pausedAfterFailure
        }
    }

    private func retryFailureCandidate(_ failure: CloudSyncFailure) -> CloudSyncFailure? {
        switch failure {
        case .partialFailure(let failures):
            guard !failures.isEmpty,
                  failures.allSatisfy({ retryFailureCandidate($0.failure) != nil }) else { return nil }
            return retryFailureCandidate(failures[0].failure)
        default:
            return retryPolicy.classify(failure).category == .transient ? failure : nil
        }
    }

    private func clearPersistentRetryLatchIfPossible() async {
        guard let recordName = currentAccountRecordName else { return }
        do {
            try metadataStore.update(forAccountRecordName: recordName) { metadata in
                metadata.automaticRetrySuppressed = false
            }
        } catch { }
    }

    private func establishBaseline(remoteRecords: [CloudSyncRecord], accountRecordName: String) throws {
        let metadata = try metadataStore.update(forAccountRecordName: accountRecordName) { metadata in
            metadata.zoneInitialized = true
            metadata.lastAttempt = now()
            metadata.lastSuccessfulSync = metadata.lastAttempt
            metadata.lastFailure = nil
            metadata.lastFailureCategory = nil
            metadata.lastFailureReason = nil
            metadata.automaticRetrySuppressed = false
            metadata.entityBaselines.removeAll()
            for record in remoteRecords {
                metadata.entityBaselines[record.entityKey] = CloudSyncEntityBaseline(
                    lastSyncedHash: record.payloadHash,
                    serverMetadata: record.serverMetadata,
                    recordName: record.recordName
                )
                metadata.remember(record.entityKey, recordName: record.recordName, serverMetadata: record.serverMetadata)
            }
        }
        lastSuccessfulSync = metadata.lastSuccessfulSync
        lastFailurePresentation = nil
        automaticRetrySuppressed = false
        latchedFailureReason = nil
        status = .synced(metadata.lastSuccessfulSync ?? now())
    }

    private func invalidateSession(status newStatus: CloudSyncStatus, cancelTransport: Bool = true) {
        sessionGeneration &+= 1
        clearPendingDecision()
        let oldResolutionTransport = pendingAccountResolutionTransport
        pendingAccountResolutionTransport = nil
        pendingAccountResolutionRecordName = nil
        accountResolutionContext = nil
        accountResolutionInProgress = false
        accountResolutionCancellationComplete = true
        cycleInProgress = false
        let oldTransport = transport
        if cancelTransport {
            Task {
                await (oldTransport as? any CloudSyncCancellableTransport)?.cancelOperations()
                await (oldResolutionTransport as? any CloudSyncCancellableTransport)?.cancelOperations()
            }
        }
        transport = nil
        lastSuccessfulSync = nil
        automaticRetrySuppressed = false
        latchedFailureReason = nil
        status = newStatus
    }

    private func clearPendingDecision() {
        pendingInitialDecision = nil
        pendingInitialChoice = nil
    }

    private func isCurrent(_ generation: Int) -> Bool {
        sessionGeneration == generation && settings.cloudSyncRequested
    }

    private static func failure(from error: Error) -> CloudSyncFailure {
        if let error = error as? CloudSyncTransportError {
            if case .cloudFailure(let failure) = error { return failure }
        }
        if let error = error as? CloudSyncReconciliationError {
            switch error {
            case .cloudFailure(let failure): return failure
            case .transport(let detail): return .other(detail)
            default: return .other(error.localizedDescription)
            }
        }
        return .other(error.localizedDescription)
    }

    private static func reason(for failure: CloudSyncFailure) -> CloudSyncLatchedFailureReason {
        switch failure {
        case .networkUnavailable, .networkFailure: return .network
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return .temporaryService
        case .quotaExceeded: return .quota
        case .notAuthenticated, .accountActionRequired: return .authentication
        case .permissionFailure: return .permission
        case .badContainer, .invalidArguments: return .configuration
        case .entitlementActionRequired: return .entitlement
        case .partialFailure(let failures):
            let reasons = failures.map { reason(for: $0.failure) }
            if reasons.contains(.quota) { return .quota }
            if !reasons.isEmpty && reasons.allSatisfy({ $0 == .network }) { return .network }
            return .other
        case .transportNotReady, .serverRecordChanged, .other: return .other
        }
    }

    private static func mayClearLatch(
        trigger: CloudSyncTrigger,
        reason: CloudSyncLatchedFailureReason?
    ) -> Bool {
        switch trigger {
        case .manual: true
        case .networkRecovered: reason == .network
        case .entitlementRestored: reason == .entitlement
        case .initialEnable: true
        case .appLaunch, .sceneActive, .remoteNotification: false
        }
    }

    private static func statusForLatchedFailure(_ reason: CloudSyncLatchedFailureReason?) -> CloudSyncStatus {
        switch reason {
        case .network, .temporaryService: .offline
        case .quota: .quotaExceeded
        case .authentication: .accountUnavailable
        default: .pausedAfterFailure
        }
    }

    private static func businessSnapshot(from records: [CloudSyncRecord]) throws -> WeekyiiBusinessSnapshot {
        var entities: [SyncEntityKey: CloudSyncEntity] = [:]
        for record in records {
            let entity = try CloudRecordCodec.decode(record)
            guard entities.updateValue(entity, forKey: entity.key) == nil else {
                throw CloudSyncReconciliationError.invalidRemoteRecord(entity.key)
            }
        }
        let snapshot = CloudSyncReconciler.snapshot(from: entities)
        let diagnostics = WeekyiiSnapshotRepository.validate(snapshot)
        guard diagnostics.isEmpty else {
            throw CloudSyncReconciliationError.invalidPlannedSnapshot(diagnostics.map(\.description))
        }
        return snapshot
    }
}
