import Foundation
import XCTest
@testable import Weekyii

@MainActor
final class CloudSyncCoordinatorTests: XCTestCase {
    func test_syncOffDoesNotQueryAccountOrTransportAndLocalStoreRemainsEditable() async throws {
        let task = makeTask(title: "before")
        let harness = try await makeHarness(local: [.task(task)])

        await harness.coordinator.handle(.appLaunch)

        let accountQueries = await harness.accountProvider.queryCount()
        let factoryCalls = await harness.transportFactory.makeCount()
        XCTAssertEqual(accountQueries, 0)
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertEqual(harness.coordinator.status, .disabled)
        XCTAssertFalse(harness.coordinator.diagnosticsSnapshot.manualSyncAllowed)
        let pushOutcome = await harness.coordinator.handleRemoteNotification()
        let accountQueriesAfterPush = await harness.accountProvider.queryCount()
        let transportsAfterPush = await harness.transportFactory.makeCount()
        XCTAssertEqual(pushOutcome, .suppressed)
        XCTAssertEqual(accountQueriesAfterPush, 0)
        XCTAssertEqual(transportsAfterPush, 0)

        harness.localStore.snapshot = makeSnapshot([.task(makeTask(id: task.id, title: "still editable"))])
        await harness.accountProvider.setResolution(.available(recordName: "account-B"))
        await harness.coordinator.handle(.appLaunch)
        let queriesWhileOff = await harness.accountProvider.queryCount()
        let transportsWhileOff = await harness.transportFactory.makeCount()
        XCTAssertEqual(queriesWhileOff, 0, "account changes remain invisible while sync is off")
        XCTAssertEqual(transportsWhileOff, 0)
        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "still editable")
    }

    func test_openAccessEnablePersistsIntentAndWaitsForEmptyCloudConfirmation() async throws {
        let local = CloudSyncEntity.task(makeTask(title: "local"))
        let harness = try await makeHarness(local: [local])

        await harness.coordinator.setRequested(true)

        XCTAssertTrue(harness.settings.cloudSyncRequested)
        XCTAssertEqual(harness.coordinator.status, .initialEnableDecisionRequired(.remoteEmpty))
        XCTAssertFalse(harness.coordinator.diagnosticsSnapshot.manualSyncAllowed)
        let remoteRecords = await harness.memoryTransport.remoteRecords()
        XCTAssertTrue(remoteRecords.isEmpty, "opening access must not silently upload the first dataset")
        XCTAssertNil(try harness.metadataStore.loadActiveAccountHash(), "account binding waits for an explicit initial-data choice")
    }

    func test_diagnosticsRestoresPersistedFailureAsLocalizedSafeReason() async throws {
        let harness = try await makeHarness(local: [], requested: true)
        try await harness.establishBaseline([])
        var metadata = try XCTUnwrap(try harness.metadataStore.load(forAccountRecordName: harness.accountRecordName))
        metadata.lastFailure = "server error: iCloud.user-record-private-12345"
        metadata.lastFailureCategory = .terminal
        metadata.lastFailureReason = .permission
        metadata.automaticRetrySuppressed = true
        try harness.metadataStore.save(metadata, forAccountRecordName: harness.accountRecordName)

        await harness.coordinator.handle(.appLaunch)

        let diagnostics = harness.coordinator.diagnosticsSnapshot
        XCTAssertEqual(diagnostics.lastFailure, CloudSyncFailurePresentation(reason: .permission))
        XCTAssertTrue(diagnostics.automaticRetrySuppressed)
        XCTAssertEqual(diagnostics.lastSuccessfulSync, Date(timeIntervalSince1970: 100))
        XCTAssertFalse(diagnostics.lastFailure?.localizedDescription.contains("iCloud.user-record-private-12345") ?? true)
        XCTAssertEqual(harness.coordinator.status, .pausedAfterFailure)
    }

    func test_diagnosticsBannerMappingKeepsNormalStatesQuietAndPrioritizesResolution() {
        XCTAssertNil(CloudSyncDiagnosticsSnapshot.bannerKind(for: .disabled, requested: false, requiresAccountResolution: false))
        XCTAssertNil(CloudSyncDiagnosticsSnapshot.bannerKind(for: .ready, requested: true, requiresAccountResolution: false))
        XCTAssertNil(CloudSyncDiagnosticsSnapshot.bannerKind(for: .synced(Date()), requested: true, requiresAccountResolution: false))
        XCTAssertEqual(CloudSyncDiagnosticsSnapshot.bannerKind(for: .syncing, requested: true, requiresAccountResolution: false), .syncing)
        XCTAssertEqual(CloudSyncDiagnosticsSnapshot.bannerKind(for: .offline, requested: true, requiresAccountResolution: false), .offline)
        XCTAssertEqual(CloudSyncDiagnosticsSnapshot.bannerKind(for: .quotaExceeded, requested: true, requiresAccountResolution: false), .quotaExceeded)
        XCTAssertEqual(CloudSyncDiagnosticsSnapshot.bannerKind(for: .accountUnavailable, requested: true, requiresAccountResolution: false), .accountUnavailable)
        XCTAssertEqual(CloudSyncDiagnosticsSnapshot.bannerKind(for: .locked(.notPurchased), requested: true, requiresAccountResolution: false), .locked)
        XCTAssertEqual(CloudSyncDiagnosticsSnapshot.bannerKind(for: .pausedAfterFailure, requested: true, requiresAccountResolution: false), .paused)
        XCTAssertEqual(CloudSyncDiagnosticsSnapshot.bannerKind(for: .quotaExceeded, requested: true, requiresAccountResolution: true), .accountDecision)
        XCTAssertEqual(CloudSyncDiagnosticsSnapshot.bannerKind(for: .initialEnableDecisionRequired(.remoteEmpty), requested: true, requiresAccountResolution: false), nil)
    }

    func test_diagnosticsManualSyncRequiresSafeRequestedSession() {
        func allowed(
            requested: Bool = true,
            hasLocalStore: Bool = true,
            entitlement: CloudSyncEntitlementState = .entitled,
            status: CloudSyncStatus = .ready,
            cycle: Bool = false,
            accountDecision: Bool = false,
            initialDecision: Bool = false,
            resolving: Bool = false,
            journalUnavailable: Bool = false
        ) -> Bool {
            CloudSyncDiagnosticsSnapshot.manualSyncAllowed(
                requested: requested,
                hasLocalStore: hasLocalStore,
                entitlement: entitlement,
                status: status,
                syncCycleInProgress: cycle,
                accountResolutionRequired: accountDecision,
                initialEnableDecisionRequired: initialDecision,
                resolutionInProgress: resolving,
                resolutionJournalUnavailable: journalUnavailable
            )
        }

        XCTAssertTrue(allowed())
        XCTAssertTrue(allowed(status: .offline))
        XCTAssertTrue(allowed(status: .quotaExceeded))
        XCTAssertTrue(allowed(status: .pausedAfterFailure))
        XCTAssertFalse(allowed(requested: false))
        XCTAssertFalse(allowed(hasLocalStore: false))
        XCTAssertFalse(allowed(entitlement: .expired))
        XCTAssertFalse(allowed(status: .syncing, cycle: true))
        XCTAssertFalse(allowed(status: .checkingAccount))
        XCTAssertFalse(allowed(accountDecision: true))
        XCTAssertFalse(allowed(initialDecision: true))
        XCTAssertFalse(allowed(resolving: true))
        XCTAssertFalse(allowed(journalUnavailable: true))
    }

    func test_diagnosticsAccountAndFailurePresentationNeverContainsRawAccountIdentifier() {
        let rawAccountIdentifier = "iCloud.user-record-private-12345"
        let account = CloudSyncAccountPresentationState(coordinatorState: .available)
        let failure = CloudSyncFailurePresentation(reason: .permission)

        XCTAssertEqual(account.localizedDescription, String(localized: "cloud.sync.account.available"))
        XCTAssertEqual(failure.localizedDescription, String(localized: "cloud.sync.failure.permission"))
        XCTAssertFalse(account.localizedDescription.contains(rawAccountIdentifier))
        XCTAssertFalse(failure.localizedDescription.contains(rawAccountIdentifier))
    }

    func test_remoteNotificationFetchesRemoteChangesAndReportsNewData() async throws {
        let base = CloudSyncEntity.task(makeTask(title: "baseline"))
        let baseID = try taskID(from: base)
        let harness = try await makeHarness(
            local: [base],
            remote: [try CloudRecordCodec.encode(base)],
            requested: true
        )
        try await harness.establishBaseline([base])
        let remoteUpdate = CloudSyncEntity.task(makeTask(id: baseID, title: "remote change"))
        _ = await harness.memoryTransport.upsert([try CloudRecordCodec.encode(remoteUpdate)])

        let outcome = await harness.coordinator.handleRemoteNotification()

        XCTAssertEqual(outcome, .newData)
        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "remote change")
    }

    func test_remoteNotificationDoesNotResumeAnIncompleteAccountResolutionJournal() async throws {
        let harness = try await makeHarness(local: [], requested: true)
        let previousHash = try CloudSyncMetadataStore.accountHash(for: harness.accountRecordName)
        let targetHash = try CloudSyncMetadataStore.accountHash(for: "account-B")
        try harness.metadataStore.saveAccountResolutionJournal(
            CloudAccountResolutionJournal(
                previousAccountHash: previousHash,
                targetAccountHash: targetHash,
                choice: nil,
                stage: .decisionPending
            )
        )
        let queriesBefore = await harness.accountProvider.queryCount()
        let factoryCallsBefore = await harness.transportFactory.makeCount()

        let outcome = await harness.coordinator.handleRemoteNotification()

        XCTAssertEqual(outcome, .suppressed)
        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        let queriesAfter = await harness.accountProvider.queryCount()
        let factoryCallsAfter = await harness.transportFactory.makeCount()
        XCTAssertEqual(queriesAfter, queriesBefore)
        XCTAssertEqual(factoryCallsAfter, factoryCallsBefore)
    }

    func test_remoteNotificationDoesNotBypassAnAccountSwitchDecision() async throws {
        let base = CloudSyncEntity.task(makeTask(title: "existing"))
        let harness = try await makeHarness(
            local: [base],
            remote: [try CloudRecordCodec.encode(base)],
            requested: true
        )
        try await harness.establishBaseline([base])
        await harness.accountProvider.setResolution(.available(recordName: "account-B"))
        await harness.coordinator.handle(.appLaunch)
        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        let queriesBefore = await harness.accountProvider.queryCount()
        let factoryCallsBefore = await harness.transportFactory.makeCount()

        let outcome = await harness.coordinator.handleRemoteNotification()

        XCTAssertEqual(outcome, .suppressed)
        let queriesAfter = await harness.accountProvider.queryCount()
        let factoryCallsAfter = await harness.transportFactory.makeCount()
        XCTAssertEqual(queriesAfter, queriesBefore)
        XCTAssertEqual(factoryCallsAfter, factoryCallsBefore)
    }

    func test_injectedEntitlementProviderIsIndependentAndDeniedEnableDoesNotPersist() async throws {
        let entitlement = FakeCloudSyncEntitlementProvider(.notPurchased)
        let harness = try await makeHarness(local: [], entitlementProvider: entitlement)

        await harness.coordinator.setRequested(true)

        XCTAssertFalse(harness.settings.cloudSyncRequested)
        XCTAssertEqual(harness.coordinator.status, .locked(.notPurchased))
        let entitlementQueries = await entitlement.queryCount()
        let accountQueries = await harness.accountProvider.queryCount()
        XCTAssertEqual(entitlementQueries, 1)
        XCTAssertEqual(accountQueries, 0)
    }

    func test_disablingSyncPersistsFalseAndStopsTheCurrentSession() async throws {
        let task = CloudSyncEntity.task(makeTask(title: "local"))
        let harness = try await makeHarness(local: [task])
        await harness.coordinator.setRequested(true)
        XCTAssertTrue(harness.settings.cloudSyncRequested)

        await harness.coordinator.setRequested(false)

        XCTAssertFalse(harness.settings.cloudSyncRequested)
        XCTAssertEqual(harness.coordinator.status, .disabled)
        XCTAssertNil(try harness.metadataStore.loadActiveAccountHash(), "cancelling the first-data decision must not bind an account")
        let remoteRecords = await harness.memoryTransport.remoteRecords()
        XCTAssertTrue(remoteRecords.isEmpty)
    }

    func test_noAccountPausesCloudWithoutBlockingLocalEdits() async throws {
        let harness = try await makeHarness(
            local: [.task(makeTask(title: "local"))],
            account: .noAccount
        )

        await harness.coordinator.setRequested(true)

        XCTAssertTrue(harness.settings.cloudSyncRequested)
        XCTAssertEqual(harness.coordinator.status, .accountUnavailable)
        harness.localStore.snapshot = makeSnapshot([.task(makeTask(title: "local edit while offline"))])
        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "local edit while offline")
        let factoryCalls = await harness.transportFactory.makeCount()
        XCTAssertEqual(factoryCalls, 0)
    }

    func test_initialRemoteEmptyUploadCreatesBaselineOnlyAfterConfirmation() async throws {
        let task = CloudSyncEntity.task(makeTask(title: "upload after confirmation"))
        let harness = try await makeHarness(local: [task])
        await harness.coordinator.setRequested(true)

        await harness.coordinator.resolveInitialEnable(.uploadLocal)

        let records = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(records.map(\.entityKey), [task.key])
        XCTAssertEqual(harness.coordinator.status, .synced(harness.coordinator.lastSuccessfulSync ?? .distantPast))
        let metadata = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: harness.accountRecordName))
        XCTAssertNotNil(metadata.entityBaselines[task.key])
        XCTAssertTrue(harness.settings.cloudSyncRequested)
    }

    func test_remoteInsertDuringEmptyPromptRequiresNewNonemptyDecisionWithoutUploading() async throws {
        let local = CloudSyncEntity.task(makeTask(title: "local"))
        let base = InMemoryCloudSyncTransport()
        let gate = CoordinatorAsyncGate()
        let gated = GatedCoordinatorTransport(base: base, gate: gate)
        let harness = try await makeHarness(local: [local], customTransport: gated, memoryTransport: base)
        await harness.coordinator.setRequested(true)
        XCTAssertEqual(harness.coordinator.status, .initialEnableDecisionRequired(.remoteEmpty))

        await gated.suspendNextInspection()
        let resolving = Task { await harness.coordinator.resolveInitialEnable(.uploadLocal) }
        await gate.waitUntilEntered()
        let otherDevice = try CloudRecordCodec.encode(.task(makeTask(title: "other device")))
        _ = await base.upsert([otherDevice])
        await gate.release()
        await resolving.value

        XCTAssertEqual(harness.coordinator.status, .initialEnableDecisionRequired(.remoteNonempty))
        let remoteAfterPrompt = await base.remoteRecords()
        XCTAssertEqual(remoteAfterPrompt.map(\.entityKey), [otherDevice.entityKey])
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local"])
        XCTAssertNil(try harness.metadataStore.loadActiveAccountHash())
    }

    func test_useCloudReadsCurrentRemoteRecordAfterPromptChanges() async throws {
        let id = UUID()
        let original = try CloudRecordCodec.encode(.task(makeTask(id: id, title: "cloud before prompt")))
        let updated = try CloudRecordCodec.encode(.task(makeTask(id: id, title: "cloud after prompt")))
        let harness = try await makeHarness(local: [.task(makeTask(title: "local"))], remote: [original])
        await harness.coordinator.setRequested(true)
        _ = await harness.memoryTransport.upsert([updated])

        await harness.coordinator.resolveInitialEnable(.useCloud)

        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["cloud after prompt"])
        XCTAssertEqual(try harness.metadataStore.load(forAccountRecordName: harness.accountRecordName)?.entityBaselines[updated.entityKey]?.lastSyncedHash, updated.payloadHash)
    }

    func test_mergeReadsCurrentRemoteSnapshotAfterPromptChanges() async throws {
        let local = CloudSyncEntity.task(makeTask(title: "local"))
        let id = UUID()
        let original = try CloudRecordCodec.encode(.task(makeTask(id: id, title: "old remote")))
        let updated = try CloudRecordCodec.encode(.task(makeTask(id: id, title: "new remote")))
        let newlyInserted = try CloudRecordCodec.encode(.task(makeTask(title: "new device record")))
        let harness = try await makeHarness(local: [local], remote: [original])
        await harness.coordinator.setRequested(true)
        _ = await harness.memoryTransport.upsert([updated, newlyInserted])

        await harness.coordinator.resolveInitialEnable(.merge)

        XCTAssertEqual(Set(harness.localStore.snapshot.tasks.map(\.title)), Set(["local", "new remote", "new device record"]))
        let mergedRemote = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(Set(try mergedRemote.map { try taskTitle(from: $0) }), Set(["local", "new remote", "new device record"]))
    }

    func test_sessionInvalidatedDuringRemoteReinspectionDoesNotMutateEitherSide() async throws {
        let local = CloudSyncEntity.task(makeTask(title: "local"))
        let base = InMemoryCloudSyncTransport()
        let gate = CoordinatorAsyncGate()
        let gated = GatedCoordinatorTransport(base: base, gate: gate)
        let harness = try await makeHarness(local: [local], customTransport: gated, memoryTransport: base)
        await harness.coordinator.setRequested(true)
        await gated.suspendNextInspection()
        let resolving = Task { await harness.coordinator.resolveInitialEnable(.uploadLocal) }
        await gate.waitUntilEntered()
        await harness.coordinator.setRequested(false)
        await gate.release()
        await resolving.value

        XCTAssertEqual(harness.coordinator.status, .disabled)
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local"])
        let remoteAfterDisable = await base.remoteRecords()
        XCTAssertTrue(remoteAfterDisable.isEmpty)
        XCTAssertNil(try harness.metadataStore.loadActiveAccountHash())
    }

    func test_accountChangesDuringRemoteReinspectionPauseBeforeAnyMutation() async throws {
        let local = CloudSyncEntity.task(makeTask(title: "local"))
        let base = InMemoryCloudSyncTransport()
        let gate = CoordinatorAsyncGate()
        let gated = GatedCoordinatorTransport(base: base, gate: gate)
        let harness = try await makeHarness(local: [local], customTransport: gated, memoryTransport: base)
        await harness.coordinator.setRequested(true)
        await gated.suspendNextInspection()
        let resolving = Task { await harness.coordinator.resolveInitialEnable(.uploadLocal) }
        await gate.waitUntilEntered()
        await harness.accountProvider.setResolution(.available(recordName: "account-B"))
        await gate.release()
        await resolving.value

        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local"])
        let remote = await base.remoteRecords()
        XCTAssertTrue(remote.isEmpty)
        XCTAssertNil(try harness.metadataStore.loadActiveAccountHash())
    }

    func test_initialRemoteNonemptyCancelLeavesLocalAndRemoteUntouchedAndTurnsPreferenceOff() async throws {
        let local = CloudSyncEntity.task(makeTask(title: "local"))
        let remote = try CloudRecordCodec.encode(.task(makeTask(title: "remote")))
        let harness = try await makeHarness(local: [local], remote: [remote])
        await harness.coordinator.setRequested(true)
        XCTAssertEqual(harness.coordinator.status, .initialEnableDecisionRequired(.remoteNonempty))

        await harness.coordinator.resolveInitialEnable(.cancel)

        let records = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(records, [remote])
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local"])
        XCTAssertFalse(harness.settings.cloudSyncRequested)
        XCTAssertEqual(harness.coordinator.status, .disabled)
    }

    func test_useLocalReplacesOnlyWeekyiiZoneAndUploadsLocalSnapshot() async throws {
        let local = CloudSyncEntity.task(makeTask(title: "local winner"))
        let remote = try CloudRecordCodec.encode(.task(makeTask(title: "old cloud")))
        let harness = try await makeHarness(local: [local], remote: [remote])
        await harness.coordinator.setRequested(true)

        await harness.coordinator.resolveInitialEnable(.useLocal)

        let records = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(records.map(\.entityKey), [local.key])
        XCTAssertEqual(try CloudRecordCodec.decode(try XCTUnwrap(records.first)), local)
        XCTAssertTrue(harness.settings.cloudSyncRequested)
        XCTAssertEqual(harness.coordinator.status, .synced(harness.coordinator.lastSuccessfulSync ?? .distantPast))
    }

    func test_useCloudCreatesRecoveryPointBeforeReplacingBusinessSnapshot() async throws {
        let local = CloudSyncEntity.task(makeTask(title: "local before"))
        let remote = try CloudRecordCodec.encode(.task(makeTask(title: "cloud source")))
        let events = RecoveryEventRecorder()
        let harness = try await makeHarness(local: [local], remote: [remote], recoveryRecorder: events)
        await harness.coordinator.setRequested(true)

        await harness.coordinator.resolveInitialEnable(.useCloud)

        let recoveryObserved = await events.observedLocalTitles()
        XCTAssertEqual(recoveryObserved, ["local before"], "recovery must finish before destructive local apply")
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["cloud source"])
        XCTAssertTrue(harness.settings.cloudSyncRequested)
        let metadata = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: harness.accountRecordName))
        XCTAssertNotNil(metadata.entityBaselines[remote.entityKey])
    }

    func test_mergeUsesLocalFirstUnionThenReplacesCloudZoneWithMergedSnapshot() async throws {
        let sharedID = UUID()
        let local = CloudSyncEntity.task(makeTask(id: sharedID, title: "local winner"))
        let remoteShared = try CloudRecordCodec.encode(.task(makeTask(id: sharedID, title: "remote conflict")))
        let remoteOnly = try CloudRecordCodec.encode(.task(makeTask(title: "remote only")))
        let harness = try await makeHarness(local: [local], remote: [remoteShared, remoteOnly])
        await harness.coordinator.setRequested(true)

        await harness.coordinator.resolveInitialEnable(.merge)

        XCTAssertEqual(Set(harness.localStore.snapshot.tasks.map(\.title)), Set(["local winner", "remote only"]))
        let records = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(Set(try records.map { try taskTitle(from: $0) }), Set(["local winner", "remote only"]))
        XCTAssertTrue(harness.settings.cloudSyncRequested)
        let metadata = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: harness.accountRecordName))
        XCTAssertEqual(metadata.entityBaselines.count, 2)
    }

    func test_establishedAppLaunchSyncsAndSceneActiveIsThrottled() async throws {
        let base = CloudSyncEntity.task(makeTask(title: "base"))
        let baseID = try taskID(from: base)
        let harness = try await makeHarness(local: [base], remote: [try CloudRecordCodec.encode(base)], requested: true)
        try await harness.establishBaseline([base])
        let updatedRemote = CloudSyncEntity.task(makeTask(id: baseID, title: "remote update"))
        _ = await harness.transport.upsert([try CloudRecordCodec.encode(updatedRemote)])

        await harness.coordinator.handle(.appLaunch)
        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "remote update")
        await harness.coordinator.handle(.sceneActive)
        let queriesAfterFirstScene = await harness.accountProvider.queryCount()
        await harness.coordinator.handle(.sceneActive)
        let queriesAfterSecondScene = await harness.accountProvider.queryCount()

        XCTAssertEqual(queriesAfterSecondScene, queriesAfterFirstScene, "scene-active triggers inside the throttle window must not recheck Cloud")
    }

    func test_transientFailureRetriesWithinBoundedBudget() async throws {
        let task = CloudSyncEntity.task(makeTask(title: "transient"))
        let retryDelays = RetryDelayRecorder()
        let harness = try await makeHarness(local: [task], retryDelay: { delay in await retryDelays.append(delay) })
        await harness.memoryTransport.injectFailure(.networkFailure, for: task.key, operation: .upsert)
        await harness.coordinator.setRequested(true)

        await harness.coordinator.resolveInitialEnable(.uploadLocal)

        let delays = await retryDelays.values()
        XCTAssertEqual(delays, [1])
        let remote = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(remote.map(\.entityKey), [task.key])
        XCTAssertTrue(harness.coordinator.automaticRetrySuppressed == false)
    }

    func test_lastStableFailureRemainsVisibleWhileManualSyncIsInFlight() async throws {
        let base = CloudSyncEntity.task(makeTask(title: "base"))
        let transport = InMemoryCloudSyncTransport(seedRecords: [try CloudRecordCodec.encode(base)])
        _ = try await transport.ensureInfrastructure()
        let gate = CoordinatorAsyncGate()
        let gatedTransport = GatedCoordinatorTransport(base: transport, gate: gate)
        let harness = try await makeHarness(
            local: [base],
            requested: true,
            customTransport: gatedTransport,
            memoryTransport: transport
        )
        try await harness.establishBaseline([base])

        let edited = CloudSyncEntity.task(
            makeTask(id: try taskID(from: base), title: "local edit")
        )
        harness.localStore.snapshot = makeSnapshot([edited])
        await transport.injectFailure(.permissionFailure, for: edited.key, operation: .upsert)
        await harness.coordinator.handle(.manual)

        XCTAssertEqual(
            harness.coordinator.diagnosticsSnapshot.lastFailure,
            CloudSyncFailurePresentation(reason: .permission)
        )
        XCTAssertTrue(harness.coordinator.automaticRetrySuppressed)

        await gatedTransport.suspendNextFetch()
        let running = Task { await harness.coordinator.handle(.manual) }
        await gate.waitUntilEntered()

        let inFlightDiagnostics = harness.coordinator.diagnosticsSnapshot
        XCTAssertEqual(inFlightDiagnostics.status, .syncing)
        XCTAssertEqual(inFlightDiagnostics.lastFailure, CloudSyncFailurePresentation(reason: .permission))
        XCTAssertFalse(inFlightDiagnostics.manualSyncAllowed)
        XCTAssertEqual(inFlightDiagnostics.lastSuccessfulSync, Date(timeIntervalSince1970: 100))

        await gate.release()
        await running.value

        XCTAssertNil(harness.coordinator.diagnosticsSnapshot.lastFailure)
        if case .synced = harness.coordinator.status {
            // Stable success is published only after the gated fetch/reconcile returns.
        } else {
            XCTFail("completed manual reconciliation must publish its stable success")
        }
    }

    func test_remoteApplyRefreshesAppEvenWhenSiblingUploadFails() async throws {
        let base = CloudSyncEntity.task(makeTask(title: "base"))
        let baseID = try taskID(from: base)
        let localOnly = CloudSyncEntity.task(makeTask(title: "local-only"))
        let harness = try await makeHarness(
            local: [base, localOnly],
            remote: [try CloudRecordCodec.encode(base)],
            requested: true
        )
        try await harness.establishBaseline([base])
        let remoteUpdate = CloudSyncEntity.task(makeTask(id: baseID, title: "remote update"))
        _ = await harness.memoryTransport.upsert([try CloudRecordCodec.encode(remoteUpdate)])
        await harness.memoryTransport.injectFailure(.quotaExceeded, for: localOnly.key, operation: .upsert)
        var appRevisionCallbacks = 0
        harness.coordinator.attach(localStore: harness.localStore) { appRevisionCallbacks += 1 }

        await harness.coordinator.handle(.appLaunch)

        XCTAssertEqual(harness.localStore.snapshot.tasks.first(where: { $0.id == baseID })?.title, "remote update")
        XCTAssertEqual(appRevisionCallbacks, 1)
        XCTAssertEqual(harness.coordinator.status, .quotaExceeded)
    }

    func test_terminalQuotaFailureLatchesSceneRetryButManualTriggerClearsIt() async throws {
        let task = CloudSyncEntity.task(makeTask(title: "quota"))
        let harness = try await makeHarness(local: [task])
        await harness.memoryTransport.injectFailure(.quotaExceeded, for: task.key, operation: .upsert)
        await harness.coordinator.setRequested(true)
        try harness.metadataStore.update(forAccountRecordName: harness.accountRecordName) { $0.syncEngineState = Data([0xA1]) }
        await harness.coordinator.resolveInitialEnable(.uploadLocal)
        XCTAssertTrue(harness.coordinator.automaticRetrySuppressed)
        XCTAssertEqual(try harness.metadataStore.load(forAccountRecordName: harness.accountRecordName)?.syncEngineState, Data([0xA1]))

        let attemptsBeforeScene = await harness.memoryTransport.fetchCallCount()
        await harness.coordinator.handle(.sceneActive)
        let attemptsAfterScene = await harness.memoryTransport.fetchCallCount()
        XCTAssertEqual(attemptsAfterScene, attemptsBeforeScene)
        await harness.coordinator.handle(.networkRecovered)
        let attemptsAfterNetwork = await harness.memoryTransport.fetchCallCount()
        XCTAssertEqual(attemptsAfterNetwork, attemptsBeforeScene, "quota must not be unlocked by network recovery")

        let pushOutcome = await harness.coordinator.handleRemoteNotification()
        XCTAssertEqual(pushOutcome, .suppressed)
        let attemptsAfterPush = await harness.memoryTransport.fetchCallCount()
        XCTAssertEqual(attemptsAfterPush, attemptsBeforeScene, "remote push must not clear the quota latch")

        await harness.coordinator.handle(.manual)
        let remote = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(remote.map(\.entityKey), [task.key])
        XCTAssertFalse(harness.coordinator.automaticRetrySuppressed)
    }

    func test_explicitDisableThenReenableClearsPersistedQuotaLatchAndSyncs() async throws {
        let base = CloudSyncEntity.task(makeTask(title: "baseline"))
        let edited = CloudSyncEntity.task(makeTask(id: try taskID(from: base), title: "edit after quota"))
        let harness = try await makeHarness(local: [base], remote: [try CloudRecordCodec.encode(base)], requested: true)
        try await harness.establishBaseline([base])
        harness.localStore.snapshot = makeSnapshot([edited])
        await harness.memoryTransport.injectFailure(.quotaExceeded, for: edited.key, operation: .upsert)

        let beforeFailure = await harness.memoryTransport.fetchCallCount()
        await harness.coordinator.handle(.manual)
        XCTAssertTrue(harness.coordinator.automaticRetrySuppressed)
        let latched = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: harness.accountRecordName))
        XCTAssertTrue(latched.automaticRetrySuppressed)
        XCTAssertEqual(latched.lastFailureReason, .quota)
        let afterFailure = await harness.memoryTransport.fetchCallCount()
        XCTAssertEqual(afterFailure, beforeFailure + 1)

        await harness.coordinator.setRequested(false)
        XCTAssertEqual(harness.coordinator.status, .disabled)
        XCTAssertFalse(harness.settings.cloudSyncRequested)

        let beforeReenable = await harness.memoryTransport.fetchCallCount()
        let upsertsBeforeReenable = await harness.memoryTransport.upsertCallCount()
        await harness.coordinator.setRequested(true)

        let accountQueries = await harness.accountProvider.queryCount()
        let fetchesAfterReenable = await harness.memoryTransport.fetchCallCount()
        let upsertsAfterReenable = await harness.memoryTransport.upsertCallCount()
        XCTAssertGreaterThan(accountQueries, 0)
        XCTAssertGreaterThan(fetchesAfterReenable, beforeReenable)
        XCTAssertGreaterThan(upsertsAfterReenable, upsertsBeforeReenable)
        XCTAssertFalse(harness.coordinator.automaticRetrySuppressed)
        XCTAssertEqual(harness.coordinator.status, .synced(harness.coordinator.lastSuccessfulSync ?? .distantPast))
        let recovered = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: harness.accountRecordName))
        XCTAssertFalse(recovered.automaticRetrySuppressed)
        XCTAssertNil(recovered.lastFailureReason)
    }

    func test_permissionLatchIgnoresNetworkRecovery() async throws {
        let task = CloudSyncEntity.task(makeTask(title: "permission"))
        let harness = try await makeHarness(local: [task])
        await harness.memoryTransport.injectFailure(.permissionFailure, for: task.key, operation: .upsert)
        await harness.coordinator.setRequested(true)
        await harness.coordinator.resolveInitialEnable(.uploadLocal)
        let before = await harness.memoryTransport.fetchCallCount()

        await harness.coordinator.handle(.networkRecovered)

        XCTAssertTrue(harness.coordinator.automaticRetrySuppressed)
        let after = await harness.memoryTransport.fetchCallCount()
        XCTAssertEqual(after, before)
    }

    func test_exhaustedNetworkLatchSuppressesSceneActiveThenAllowsOneRecoveryCycle() async throws {
        let task = CloudSyncEntity.task(makeTask(title: "network"))
        let harness = try await makeHarness(local: [task])
        for _ in 0..<3 {
            await harness.memoryTransport.injectFailure(.networkFailure, for: task.key, operation: .upsert)
        }
        await harness.coordinator.setRequested(true)
        await harness.coordinator.resolveInitialEnable(.uploadLocal)
        XCTAssertTrue(harness.coordinator.automaticRetrySuppressed)
        let before = await harness.memoryTransport.fetchCallCount()

        await harness.coordinator.handle(.sceneActive)
        let afterScene = await harness.memoryTransport.fetchCallCount()
        XCTAssertEqual(afterScene, before)
        await harness.coordinator.handle(.networkRecovered)
        let afterRecovery = await harness.memoryTransport.fetchCallCount()
        XCTAssertEqual(afterRecovery, before + 1)
        XCTAssertFalse(harness.coordinator.automaticRetrySuppressed)
    }

    func test_quotaLatchRestoresStableStatusAfterCoordinatorRecreation() async throws {
        let task = CloudSyncEntity.task(makeTask(title: "quota relaunch"))
        let harness = try await makeHarness(local: [task])
        await harness.memoryTransport.injectFailure(.quotaExceeded, for: task.key, operation: .upsert)
        await harness.coordinator.setRequested(true)
        await harness.coordinator.resolveInitialEnable(.uploadLocal)
        let before = await harness.memoryTransport.fetchCallCount()
        let newFactory = FakeCloudSyncTransportFactory(transport: harness.memoryTransport)
        let relaunched = CloudSyncCoordinator(
            settings: harness.settings,
            localStore: harness.localStore,
            accountProvider: harness.accountProvider,
            entitlementProvider: OpenAccessCloudSyncEntitlementProvider(),
            transportFactory: newFactory,
            metadataStore: harness.metadataStore
        )

        await relaunched.handle(.appLaunch)
        XCTAssertEqual(relaunched.status, .quotaExceeded)
        await relaunched.handle(.networkRecovered)
        XCTAssertEqual(relaunched.status, .quotaExceeded)
        let factoryCalls = await newFactory.makeCount()
        let after = await harness.memoryTransport.fetchCallCount()
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertEqual(after, before)
    }

    func test_disablingSyncDiscardsSuspendedFetchBeforeApplyOrSuccess() async throws {
        let base = CloudSyncEntity.task(makeTask(title: "base"))
        let transport = InMemoryCloudSyncTransport(seedRecords: [try CloudRecordCodec.encode(base)])
        _ = try await transport.ensureInfrastructure()
        let gate = CoordinatorAsyncGate()
        let gatedTransport = GatedCoordinatorTransport(base: transport, gate: gate)
        let harness = try await makeHarness(local: [base], requested: true, customTransport: gatedTransport, memoryTransport: transport)
        try await harness.establishBaseline([base])
        let remoteUpdate = CloudSyncEntity.task(makeTask(id: try taskID(from: base), title: "stale cloud update"))
        _ = await transport.upsert([try CloudRecordCodec.encode(remoteUpdate)])
        await gatedTransport.suspendNextFetch()

        let running = Task { await harness.coordinator.handle(.manual) }
        await gate.waitUntilEntered()
        await harness.coordinator.setRequested(false)
        await gate.release()
        await running.value

        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "base")
        XCTAssertEqual(harness.coordinator.status, .disabled)
        XCTAssertNil(harness.coordinator.lastSuccessfulSync)
    }

    func test_accountSwitchDuringSyncPausesWithoutCreatingTransportForNewAccount() async throws {
        let base = CloudSyncEntity.task(makeTask(title: "base"))
        let transport = InMemoryCloudSyncTransport(seedRecords: [try CloudRecordCodec.encode(base)])
        _ = try await transport.ensureInfrastructure()
        let gate = CoordinatorAsyncGate()
        let gatedTransport = GatedCoordinatorTransport(base: transport, gate: gate)
        let harness = try await makeHarness(local: [base], requested: true, customTransport: gatedTransport, memoryTransport: transport)
        try await harness.establishBaseline([base])
        await gatedTransport.suspendNextFetch()

        let running = Task { await harness.coordinator.handle(.manual) }
        await gate.waitUntilEntered()
        await harness.accountProvider.setResolution(.available(recordName: "account-B"))
        await harness.coordinator.handle(.sceneActive)
        await gate.release()
        await running.value

        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        let factoryCalls = await harness.transportFactory.makeCount()
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "base")

        let nextFactory = FakeCloudSyncTransportFactory(transport: InMemoryCloudSyncTransport())
        let nextCoordinator = CloudSyncCoordinator(
            settings: harness.settings,
            localStore: harness.localStore,
            accountProvider: FakeCloudSyncAccountProvider(.available(recordName: "account-B")),
            entitlementProvider: OpenAccessCloudSyncEntitlementProvider(),
            transportFactory: nextFactory,
            metadataStore: harness.metadataStore
        )
        await nextCoordinator.handle(.appLaunch)
        XCTAssertEqual(nextCoordinator.status, .accountDecisionRequired)
        let nextFactoryCalls = await nextFactory.makeCount()
        XCTAssertEqual(nextFactoryCalls, 0, "a relaunch must not bind the new account without Phase G resolution")
        let activeAccountHash = try XCTUnwrap(harness.metadataStore.loadActiveAccountHash())
        XCTAssertEqual(activeAccountHash.count, 64)
        XCTAssertFalse(activeAccountHash.contains("account-A"))
    }

    func test_existingTargetMetadataWithoutActiveCommitMarkerStillRequiresAccountResolution() async throws {
        let local = CloudSyncEntity.task(makeTask(title: "local remains authoritative"))
        let targetRecord = try CloudRecordCodec.encode(.task(makeTask(title: "target cloud")))
        let harness = try await makeHarness(local: [local], requested: true)
        let targetHash = try CloudSyncMetadataStore.accountHash(for: "account-B")
        var staleTargetMetadata = CloudSyncMetadata(accountHash: targetHash)
        staleTargetMetadata.lastSuccessfulSync = Date(timeIntervalSince1970: 100)
        staleTargetMetadata.zoneInitialized = true
        staleTargetMetadata.entityBaselines[targetRecord.entityKey] = CloudSyncEntityBaseline(
            lastSyncedHash: targetRecord.payloadHash,
            recordName: targetRecord.recordName
        )
        try harness.metadataStore.save(staleTargetMetadata, forAccountRecordName: "account-B")
        let targetTransport = await installTransport(harness, account: "account-B", records: [targetRecord])
        let nextCoordinator = CloudSyncCoordinator(
            settings: harness.settings,
            localStore: harness.localStore,
            accountProvider: harness.accountProvider,
            entitlementProvider: OpenAccessCloudSyncEntitlementProvider(),
            transportFactory: harness.transportFactory,
            metadataStore: harness.metadataStore
        )
        await harness.accountProvider.setResolution(.available(recordName: "account-B"))

        await nextCoordinator.handle(.appLaunch)

        XCTAssertEqual(nextCoordinator.status, .accountDecisionRequired)
        XCTAssertNil(try harness.metadataStore.loadActiveAccountHash())
        let targetTransportCreations = await harness.transportFactory.makeCount(forAccountRecordName: "account-B")
        XCTAssertEqual(targetTransportCreations, 0, "orphaned target metadata cannot establish an account binding")
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local remains authoritative"])
        let targetRecordsAfterLaunch = await targetTransport.remoteRecords()
        XCTAssertEqual(targetRecordsAfterLaunch, [targetRecord])
    }

    func test_accountResolutionJournalPersistsOnlyHashesAndCanBeCleared() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeekyiiResolutionJournalTest-\(UUID().uuidString)")
        let store = CloudSyncMetadataStore(rootURL: root)
        let previousHash = try CloudSyncMetadataStore.accountHash(for: "account-A")
        let targetHash = try CloudSyncMetadataStore.accountHash(for: "account-B")
        let journal = CloudAccountResolutionJournal(
            previousAccountHash: previousHash,
            targetAccountHash: targetHash,
            choice: .merge,
            stage: .localMutationApplied
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try store.saveAccountResolutionJournal(journal)

        let journalURL = store.accountResolutionJournalFileURL
        let contents = try String(contentsOf: journalURL, encoding: .utf8)
        XCTAssertEqual(try store.loadAccountResolutionJournal(), journal)
        XCTAssertEqual(journalURL.lastPathComponent, "account-resolution.json")
        XCTAssertFalse(journalURL.path.contains("account-A"))
        XCTAssertFalse(journalURL.path.contains("account-B"))
        XCTAssertFalse(contents.contains("account-A"))
        XCTAssertFalse(contents.contains("account-B"))

        var readyJournal = journal
        readyJournal.stage = .readyToCommit
        try store.saveAccountResolutionJournal(readyJournal)
        XCTAssertEqual(try store.loadAccountResolutionJournal(), readyJournal)
        try store.clearAccountResolutionJournal()
        XCTAssertNil(try store.loadAccountResolutionJournal())
    }

    func test_accountResolutionWaitsForOldTransportCancellationAndRequiresChoiceBeforeTargetMutation() async throws {
        let local = CloudSyncEntity.task(makeTask(title: "device data"))
        let oldRemote = try CloudRecordCodec.encode(.task(makeTask(title: "old account data")))
        let targetRemote = try CloudRecordCodec.encode(.task(makeTask(title: "new account data")))
        let oldTask = try taskSnapshot(from: oldRemote)
        let oldTransport = InMemoryCloudSyncTransport(seedRecords: [oldRemote])
        let cancellationGate = CoordinatorAsyncGate()
        let oldGatedTransport = GatedCoordinatorTransport(base: oldTransport, gate: CoordinatorAsyncGate(), cancellationGate: cancellationGate)
        let harness = try await makeHarness(
            local: [.task(oldTask)],
            remote: [oldRemote],
            requested: true,
            customTransport: oldGatedTransport,
            memoryTransport: oldTransport
        )
        try await harness.establishBaseline([.task(oldTask)])
        let targetAccountHash = try CloudSyncMetadataStore.accountHash(for: "account-B")
        try harness.metadataStore.saveActiveAccountHash(CloudSyncMetadataStore.accountHash(for: harness.accountRecordName))
        await harness.coordinator.handle(.appLaunch)
        harness.localStore.snapshot = makeSnapshot([local])
        let targetTransport = InMemoryCloudSyncTransport(seedRecords: [targetRemote])
        _ = try await targetTransport.ensureInfrastructure()
        await harness.transportFactory.setTransport(targetTransport, forAccountRecordName: "account-B")
        await harness.accountProvider.setResolution(.available(recordName: "account-B"))
        await oldGatedTransport.suspendNextCancellation()

        let switching = Task { await harness.coordinator.handle(.manual) }
        await cancellationGate.waitUntilEntered()

        XCTAssertEqual(harness.coordinator.status, .checkingAccount)
        let targetFactoryCallsBeforeBarrier = await harness.transportFactory.makeCount(forAccountRecordName: "account-B")
        let targetRecordsBeforeChoice = await targetTransport.remoteRecords()
        XCTAssertEqual(targetFactoryCallsBeforeBarrier, 0)
        XCTAssertEqual(targetRecordsBeforeChoice, [targetRemote])
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["device data"])

        await cancellationGate.release()
        await switching.value

        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        let stagedContext = await harness.coordinator.prepareAccountResolutionContext()
        XCTAssertEqual(stagedContext?.targetAccountHash, targetAccountHash)
        XCTAssertEqual(stagedContext?.targetCloudEntityCount, 1)
        let targetRecordsAfterStaging = await targetTransport.remoteRecords()
        XCTAssertEqual(targetRecordsAfterStaging, [targetRemote], "staging must not mutate the target zone")

        await harness.coordinator.resolveAccountSwitch(.useLocal)

        let targetRecordsAfterChoice = await targetTransport.remoteRecords()
        XCTAssertEqual(try targetRecordsAfterChoice.map(taskTitle(from:)), ["device data"])
        let oldRecordsAfterChoice = await oldTransport.remoteRecords()
        XCTAssertEqual(oldRecordsAfterChoice, [oldRemote], "resolving B must leave A unchanged")
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), targetAccountHash)
        XCTAssertEqual(harness.coordinator.status, .synced(harness.coordinator.lastSuccessfulSync ?? .distantPast))
    }

    func test_relaunchRequiresResolutionEvenWhenTargetHasOldMetadata() async throws {
        let task = makeTask(title: "local")
        let remoteA = try CloudRecordCodec.encode(.task(task))
        let harness = try await makeHarness(local: [.task(task)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(task)])

        var oldTargetMetadata = CloudSyncMetadata(
            accountHash: try CloudSyncMetadataStore.accountHash(for: "account-B")
        )
        oldTargetMetadata.lastSuccessfulSync = Date(timeIntervalSince1970: 99)
        oldTargetMetadata.zoneInitialized = true
        oldTargetMetadata.syncEngineState = Data([0xBA, 0xD0])
        try harness.metadataStore.save(oldTargetMetadata, forAccountRecordName: "account-B")

        let relaunchFactory = FakeCloudSyncTransportFactory(transport: InMemoryCloudSyncTransport())
        let relaunched = CloudSyncCoordinator(
            settings: harness.settings,
            localStore: harness.localStore,
            accountProvider: FakeCloudSyncAccountProvider(.available(recordName: "account-B")),
            entitlementProvider: OpenAccessCloudSyncEntitlementProvider(),
            transportFactory: relaunchFactory,
            metadataStore: harness.metadataStore
        )

        await relaunched.handle(.appLaunch)

        XCTAssertEqual(relaunched.status, .accountDecisionRequired)
        XCTAssertNil(relaunched.accountResolutionContext)
        let targetTransportsOnRelaunch = await relaunchFactory.makeCount(forAccountRecordName: "account-B")
        XCTAssertEqual(targetTransportsOnRelaunch, 0)
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-A"))
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local"])
    }

    func test_useCloudReinspectsTargetAndRebuildsOnlyTargetMetadataAfterRecovery() async throws {
        let localTask = makeTask(title: "local before")
        let remoteA = try CloudRecordCodec.encode(.task(localTask))
        let recovery = RecoveryEventRecorder()
        let harness = try await makeHarness(local: [.task(localTask)], remote: [remoteA], requested: true, recoveryRecorder: recovery)
        try await connectAccountA(harness, entities: [.task(localTask)])

        let targetID = UUID()
        let staged = try CloudRecordCodec.encode(.task(makeTask(id: targetID, title: "cloud staged")))
        let fresh = try CloudRecordCodec.encode(.task(makeTask(id: targetID, title: "cloud fresh")))
        let targetOnly = try CloudRecordCodec.encode(.task(makeTask(title: "second fresh cloud record")))
        let targetTransport = await installTransport(harness, account: "account-B", records: [staged])
        var staleMetadata = CloudSyncMetadata(accountHash: try CloudSyncMetadataStore.accountHash(for: "account-B"))
        staleMetadata.lastSuccessfulSync = Date(timeIntervalSince1970: 5)
        staleMetadata.zoneInitialized = true
        staleMetadata.syncEngineState = Data([0xA1, 0xB2])
        staleMetadata.remoteChangeToken = Data([0xC3])
        staleMetadata.pendingRemoteChanges = [CloudSyncPendingChange(sequence: 9, change: .upsert(staged))]
        staleMetadata.changeSequence = 9
        staleMetadata.needsFullRemoteSnapshot = true
        staleMetadata.remember(staged.entityKey, recordName: staged.recordName)
        try harness.metadataStore.save(staleMetadata, forAccountRecordName: "account-B")
        let context = await beginAccountSwitch(harness, to: "account-B")
        XCTAssertEqual(context?.targetCloudEntityCount, 1)
        _ = await targetTransport.upsert([fresh, targetOnly])
        await harness.coordinator.resolveAccountSwitch(.useCloud)

        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title).sorted(), ["cloud fresh", "second fresh cloud record"])
        let recoveredLocal = await recovery.observedLocalTitles()
        XCTAssertEqual(recoveredLocal, ["local before"], "the recovery point must precede local replacement")
        let targetRecords = await targetTransport.remoteRecords()
        XCTAssertEqual(Set(try targetRecords.map(taskTitle(from:))), Set(["cloud fresh", "second fresh cloud record"]))
        let oldRecordsAfterUseCloud = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(oldRecordsAfterUseCloud, [remoteA], "the old account zone must remain unchanged")
        let rebuilt = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: "account-B"))
        XCTAssertNil(rebuilt.syncEngineState)
        XCTAssertNil(rebuilt.remoteChangeToken)
        XCTAssertEqual(rebuilt.pendingRemoteChanges, [])
        XCTAssertEqual(rebuilt.changeSequence, 0)
        XCTAssertFalse(rebuilt.needsFullRemoteSnapshot ?? true)
        XCTAssertEqual(Set(rebuilt.entityBaselines.keys), Set(targetRecords.map(\.entityKey)))
        XCTAssertEqual(Set(rebuilt.recordNameToEntityKey?.values.map { $0 } ?? []), Set(targetRecords.map(\.entityKey)))
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-B"))
        XCTAssertNil(try harness.metadataStore.loadAccountResolutionJournal(), "the journal clears after the target binding commits")
    }

    func test_recoveryFailureDuringUseCloudPreservesLocalAndLeavesTargetAndBindingUntouched() async throws {
        let localTask = makeTask(title: "local safe")
        let remoteA = try CloudRecordCodec.encode(.task(localTask))
        let recovery = RecoveryEventRecorder(failing: true)
        let harness = try await makeHarness(local: [.task(localTask)], remote: [remoteA], requested: true, recoveryRecorder: recovery)
        try await connectAccountA(harness, entities: [.task(localTask)])
        let target = try CloudRecordCodec.encode(.task(makeTask(title: "cloud must not apply")))
        let targetTransport = await installTransport(harness, account: "account-B", records: [target])
        _ = await beginAccountSwitch(harness, to: "account-B")
        await harness.coordinator.resolveAccountSwitch(.useCloud)

        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local safe"])
        let targetRecordsAfterFailure = await targetTransport.remoteRecords()
        XCTAssertEqual(targetRecordsAfterFailure, [target])
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-A"))
        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        XCTAssertEqual(harness.coordinator.accountResolutionContext?.progress, .failed(.recoveryPointFailed))
    }

    func test_mergeUsesLocalConflictAndUnionsBothDatasetsWithoutChangingOldAccount() async throws {
        let aTask = makeTask(title: "A baseline")
        let remoteA = try CloudRecordCodec.encode(.task(aTask))
        let harness = try await makeHarness(local: [.task(aTask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(aTask)])

        let sharedID = UUID()
        let localConflict = makeTask(id: sharedID, title: "local conflict wins")
        let localOnly = makeTask(title: "local-only")
        harness.localStore.snapshot = makeSnapshot([.task(localConflict), .task(localOnly)])
        let remoteConflict = try CloudRecordCodec.encode(.task(makeTask(id: sharedID, title: "remote conflict loses")))
        let remoteOnly = try CloudRecordCodec.encode(.task(makeTask(title: "remote-only")))
        let targetTransport = await installTransport(harness, account: "account-B", records: [remoteConflict, remoteOnly])

        _ = await beginAccountSwitch(harness, to: "account-B")
        await harness.coordinator.resolveAccountSwitch(.merge)

        XCTAssertEqual(Set(harness.localStore.snapshot.tasks.map(\.title)), Set(["local conflict wins", "local-only", "remote-only"]))
        let targetRecords = await targetTransport.remoteRecords()
        XCTAssertEqual(Set(try targetRecords.map(taskTitle(from:))), Set(["local conflict wins", "local-only", "remote-only"]))
        let oldRecordsAfterMerge = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(oldRecordsAfterMerge, [remoteA])
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-B"))
        let targetMetadata = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: "account-B"))
        XCTAssertEqual(Set(targetMetadata.entityBaselines.keys), Set(targetRecords.map(\.entityKey)))
        XCTAssertNil(try harness.metadataStore.loadAccountResolutionJournal(), "the journal clears only after B is committed")
    }

    func test_mergeUploadFailureAfterLocalApplyPersistsJournalAndRelaunchUnderAStaysPaused() async throws {
        let sharedID = UUID()
        let accountATask = makeTask(id: sharedID, title: "A original")
        let remoteA = try CloudRecordCodec.encode(.task(accountATask))
        let harness = try await makeHarness(local: [.task(accountATask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(accountATask)])

        let localConflict = makeTask(id: sharedID, title: "local wins")
        let localOnly = makeTask(title: "local only")
        harness.localStore.snapshot = makeSnapshot([.task(localConflict), .task(localOnly)])
        let remoteConflict = try CloudRecordCodec.encode(.task(makeTask(id: sharedID, title: "B conflict")))
        let remoteOnly = try CloudRecordCodec.encode(.task(makeTask(title: "B only")))
        let targetTransport = await installTransport(harness, account: "account-B", records: [remoteConflict, remoteOnly])
        await targetTransport.injectFailure(.quotaExceeded, for: remoteOnly.entityKey, operation: .upsert)
        _ = await beginAccountSwitch(harness, to: "account-B")

        await harness.coordinator.resolveAccountSwitch(.merge)

        let activeHash = try CloudSyncMetadataStore.accountHash(for: "account-A")
        let targetHash = try CloudSyncMetadataStore.accountHash(for: "account-B")
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), activeHash)
        XCTAssertEqual(Set(harness.localStore.snapshot.tasks.map(\.title)), Set(["local wins", "local only", "B only"]))
        let recordsAAfterMergeFailure = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(recordsAAfterMergeFailure, [remoteA])
        let journal = try XCTUnwrap(harness.metadataStore.loadAccountResolutionJournal())
        XCTAssertEqual(journal.previousAccountHash, activeHash)
        XCTAssertEqual(journal.targetAccountHash, targetHash)
        XCTAssertEqual(journal.choice, .merge)
        XCTAssertEqual(journal.stage, .targetCloudMutationBegun)

        await harness.accountProvider.setResolution(.available(recordName: "account-A"))
        let relaunchedFactory = FakeCloudSyncTransportFactory(transport: harness.memoryTransport)
        await relaunchedFactory.setTransport(targetTransport, forAccountRecordName: "account-B")
        let relaunched = CloudSyncCoordinator(
            settings: harness.settings,
            localStore: harness.localStore,
            accountProvider: harness.accountProvider,
            entitlementProvider: OpenAccessCloudSyncEntitlementProvider(),
            transportFactory: relaunchedFactory,
            metadataStore: harness.metadataStore
        )

        await relaunched.handle(.appLaunch)

        XCTAssertEqual(relaunched.status, .accountDecisionRequired)
        XCTAssertEqual(relaunched.accountResolutionContext?.targetAccountAvailable, false)
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), activeHash)
        let accountATransportCreations = await relaunchedFactory.makeCount(forAccountRecordName: "account-A")
        XCTAssertEqual(accountATransportCreations, 0)
        let recordsAAfterRelaunch = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(try recordsAAfterRelaunch.map(taskTitle(from:)), ["A original"])
        XCTAssertEqual(try harness.metadataStore.loadAccountResolutionJournal(), journal)

        await harness.accountProvider.setResolution(.available(recordName: "account-B"))
        await relaunched.handle(.sceneActive)
        XCTAssertEqual(relaunched.status, .accountDecisionRequired)
        XCTAssertEqual(relaunched.accountResolutionContext?.targetAccountAvailable, true)
        let targetCreationsBeforePresentation = await relaunchedFactory.makeCount(forAccountRecordName: "account-B")
        XCTAssertEqual(targetCreationsBeforePresentation, 0, "account discovery must not inspect or mutate the target until the decision UI requests staging")

        let refreshedContext = await relaunched.prepareAccountResolutionContext()
        XCTAssertEqual(refreshedContext?.progress, .ready)
        XCTAssertEqual(refreshedContext?.targetAccountAvailable, true)
    }

    func test_mergeCrashJournalAfterLocalMutationBlocksOldAccountOnRelaunch() async throws {
        let accountATask = makeTask(title: "A data")
        let remoteA = try CloudRecordCodec.encode(.task(accountATask))
        let harness = try await makeHarness(local: [.task(accountATask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(accountATask)])
        let mergedLocal = makeTask(title: "merged with B only")
        harness.localStore.snapshot = makeSnapshot([.task(accountATask), .task(mergedLocal)])
        let journal = CloudAccountResolutionJournal(
            previousAccountHash: try CloudSyncMetadataStore.accountHash(for: "account-A"),
            targetAccountHash: try CloudSyncMetadataStore.accountHash(for: "account-B"),
            choice: .merge,
            stage: .localMutationApplied
        )
        try harness.metadataStore.saveAccountResolutionJournal(journal)
        let relaunchedFactory = FakeCloudSyncTransportFactory(transport: harness.memoryTransport)
        let relaunched = CloudSyncCoordinator(
            settings: harness.settings,
            localStore: harness.localStore,
            accountProvider: FakeCloudSyncAccountProvider(.available(recordName: "account-A")),
            entitlementProvider: OpenAccessCloudSyncEntitlementProvider(),
            transportFactory: relaunchedFactory,
            metadataStore: harness.metadataStore
        )

        await relaunched.handle(.appLaunch)

        XCTAssertEqual(relaunched.status, .accountDecisionRequired)
        let accountATransportCreations = await relaunchedFactory.makeCount(forAccountRecordName: "account-A")
        XCTAssertEqual(accountATransportCreations, 0)
        XCTAssertEqual(Set(harness.localStore.snapshot.tasks.map(\.title)), Set(["A data", "merged with B only"]))
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-A"))
        XCTAssertEqual(try harness.metadataStore.loadAccountResolutionJournal(), journal)
    }

    func test_useCloudCrashAfterLocalApplyBlocksOldAccountOnRelaunch() async throws {
        let accountATask = makeTask(title: "A data")
        let remoteA = try CloudRecordCodec.encode(.task(accountATask))
        let harness = try await makeHarness(local: [.task(accountATask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(accountATask)])
        let cloudTask = makeTask(title: "B authoritative")
        try harness.localStore.apply(makeSnapshot([.task(cloudTask)]))
        let journal = CloudAccountResolutionJournal(
            previousAccountHash: try CloudSyncMetadataStore.accountHash(for: "account-A"),
            targetAccountHash: try CloudSyncMetadataStore.accountHash(for: "account-B"),
            choice: .useCloud,
            stage: .localMutationApplied
        )
        try harness.metadataStore.saveAccountResolutionJournal(journal)
        let relaunchedFactory = FakeCloudSyncTransportFactory(transport: harness.memoryTransport)
        let relaunched = CloudSyncCoordinator(
            settings: harness.settings,
            localStore: harness.localStore,
            accountProvider: FakeCloudSyncAccountProvider(.available(recordName: "account-A")),
            entitlementProvider: OpenAccessCloudSyncEntitlementProvider(),
            transportFactory: relaunchedFactory,
            metadataStore: harness.metadataStore
        )

        await relaunched.handle(.appLaunch)

        XCTAssertEqual(relaunched.status, .accountDecisionRequired)
        let accountATransportCreations = await relaunchedFactory.makeCount(forAccountRecordName: "account-A")
        XCTAssertEqual(accountATransportCreations, 0)
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["B authoritative"])
        let recordsAAfterRelaunch = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(recordsAAfterRelaunch, [remoteA])
        XCTAssertEqual(try harness.metadataStore.loadAccountResolutionJournal(), journal)
    }

    func test_finalAccountCheckRetargetsBeforeCommittingUseCloud() async throws {
        let localTask = makeTask(title: "A local")
        let remoteA = try CloudRecordCodec.encode(.task(localTask))
        let harness = try await makeHarness(local: [.task(localTask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(localTask)])
        let remoteB = try CloudRecordCodec.encode(.task(makeTask(title: "B cloud")))
        let targetB = await installTransport(harness, account: "account-B", records: [remoteB])
        let targetC = await installTransport(harness, account: "account-C", records: [])
        _ = await beginAccountSwitch(harness, to: "account-B")
        await harness.accountProvider.switchResolution(afterAdditionalQueries: 6, to: .available(recordName: "account-C"))

        await harness.coordinator.resolveAccountSwitch(.useCloud)

        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["B cloud"])
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-A"))
        let recordsB = await targetB.remoteRecords()
        let recordsC = await targetC.remoteRecords()
        XCTAssertEqual(recordsB, [remoteB])
        XCTAssertEqual(recordsC, [])
        let targetCCreations = await harness.transportFactory.makeCount(forAccountRecordName: "account-C")
        XCTAssertEqual(targetCCreations, 0)
        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        let journal = try XCTUnwrap(harness.metadataStore.loadAccountResolutionJournal())
        XCTAssertEqual(journal.targetAccountHash, try CloudSyncMetadataStore.accountHash(for: "account-C"))
        XCTAssertEqual(journal.stage, .decisionPendingAfterMutation)
    }

    func test_disableAccountResolutionKeepsBothCloudZonesAndStopsAllFurtherQueries() async throws {
        let localTask = makeTask(title: "keep local")
        let remoteA = try CloudRecordCodec.encode(.task(localTask))
        let harness = try await makeHarness(local: [.task(localTask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(localTask)])
        let remoteB = try CloudRecordCodec.encode(.task(makeTask(title: "B remains")))
        let targetTransport = await installTransport(harness, account: "account-B", records: [remoteB])
        _ = await beginAccountSwitch(harness, to: "account-B")
        let localBeforeDisable = harness.localStore.snapshot
        let oldBeforeDisable = await harness.memoryTransport.remoteRecords()
        let targetBeforeDisable = await targetTransport.remoteRecords()

        await harness.coordinator.resolveAccountSwitch(.disable)

        let queriesAfterDisable = await harness.accountProvider.queryCount()
        let factoryCallsAfterDisable = await harness.transportFactory.makeCount()
        await harness.coordinator.handle(.sceneActive)
        let oldRecordsAfterDisable = await harness.memoryTransport.remoteRecords()
        let targetRecordsAfterDisable = await targetTransport.remoteRecords()
        let queriesAfterSceneActive = await harness.accountProvider.queryCount()
        let factoryCallsAfterSceneActive = await harness.transportFactory.makeCount()
        XCTAssertFalse(harness.settings.cloudSyncRequested)
        XCTAssertEqual(harness.coordinator.status, .disabled)
        XCTAssertEqual(harness.localStore.snapshot, localBeforeDisable)
        XCTAssertEqual(oldRecordsAfterDisable, oldBeforeDisable)
        XCTAssertEqual(targetRecordsAfterDisable, targetBeforeDisable)
        XCTAssertEqual(queriesAfterSceneActive, queriesAfterDisable)
        XCTAssertEqual(factoryCallsAfterSceneActive, factoryCallsAfterDisable)
    }

    func test_targetChangingToAnotherAccountBeforeChoiceCannotMutateEitherNewTarget() async throws {
        let localTask = makeTask(title: "local unchanged")
        let remoteA = try CloudRecordCodec.encode(.task(localTask))
        let harness = try await makeHarness(local: [.task(localTask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(localTask)])
        let remoteB = try CloudRecordCodec.encode(.task(makeTask(title: "B data")))
        let remoteC = try CloudRecordCodec.encode(.task(makeTask(title: "C data")))
        let targetB = await installTransport(harness, account: "account-B", records: [remoteB])
        let targetC = await installTransport(harness, account: "account-C", records: [remoteC])
        _ = await beginAccountSwitch(harness, to: "account-B")
        await harness.accountProvider.setResolution(.available(recordName: "account-C"))

        await harness.coordinator.resolveAccountSwitch(.useCloud)

        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local unchanged"])
        let targetBRecords = await targetB.remoteRecords()
        let targetCRecords = await targetC.remoteRecords()
        let targetCFactoryCalls = await harness.transportFactory.makeCount(forAccountRecordName: "account-C")
        XCTAssertEqual(targetBRecords, [remoteB])
        XCTAssertEqual(targetCRecords, [remoteC])
        XCTAssertEqual(targetCFactoryCalls, 0)
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-A"))
        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        XCTAssertEqual(harness.coordinator.accountResolutionContext, nil)
    }

    func test_accountChangingToCDuringBResolutionStopsBeforeApplyingB() async throws {
        let localTask = makeTask(title: "local stays safe")
        let remoteA = try CloudRecordCodec.encode(.task(localTask))
        let harness = try await makeHarness(local: [.task(localTask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(localTask)])
        let remoteB = try CloudRecordCodec.encode(.task(makeTask(title: "B data")))
        let remoteC = try CloudRecordCodec.encode(.task(makeTask(title: "C data")))
        let baseB = InMemoryCloudSyncTransport(seedRecords: [remoteB])
        _ = try await baseB.ensureInfrastructure()
        let inspectionGate = CoordinatorAsyncGate()
        let gatedB = GatedCoordinatorTransport(base: baseB, gate: inspectionGate)
        await harness.transportFactory.setTransport(gatedB, forAccountRecordName: "account-B")
        let targetC = await installTransport(harness, account: "account-C", records: [remoteC])
        _ = await beginAccountSwitch(harness, to: "account-B")
        await gatedB.suspendNextInspection()

        let resolving = Task { await harness.coordinator.resolveAccountSwitch(.useCloud) }
        await inspectionGate.waitUntilEntered()
        await harness.accountProvider.setResolution(.available(recordName: "account-C"))
        await inspectionGate.release()
        await resolving.value

        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local stays safe"])
        let recordsB = await baseB.remoteRecords()
        let recordsC = await targetC.remoteRecords()
        let createsForC = await harness.transportFactory.makeCount(forAccountRecordName: "account-C")
        XCTAssertEqual(recordsB, [remoteB])
        XCTAssertEqual(recordsC, [remoteC])
        XCTAssertEqual(createsForC, 0)
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-A"))
        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        XCTAssertNil(harness.coordinator.accountResolutionContext)
    }

    func test_useLocalFailureKeepsBindingAndCanBeRetriedWithoutDuplicateIdentity() async throws {
        let localTask = makeTask(title: "local authoritative")
        let remoteA = try CloudRecordCodec.encode(.task(localTask))
        let harness = try await makeHarness(local: [.task(localTask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(localTask)])
        let oldB = try CloudRecordCodec.encode(.task(makeTask(title: "old B data")))
        let targetTransport = await installTransport(harness, account: "account-B", records: [oldB])
        await targetTransport.injectFailure(.quotaExceeded, for: SyncEntityKey(kind: .task, id: localTask.id), operation: .upsert)
        _ = await beginAccountSwitch(harness, to: "account-B")

        await harness.coordinator.resolveAccountSwitch(.useLocal)

        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-A"))
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local authoritative"])
        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        XCTAssertEqual(harness.coordinator.accountResolutionContext?.progress, .failed(.cloudOperationFailed))

        await harness.coordinator.resolveAccountSwitch(.useLocal)

        let records = await targetTransport.remoteRecords()
        XCTAssertEqual(try records.map(taskTitle(from:)), ["local authoritative"])
        XCTAssertEqual(Set(records.map(\.entityKey)).count, records.count)
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-B"))
    }

    func test_useLocalRebuildsOnlyTargetAccountMetadataBeforeUploading() async throws {
        let localTask = makeTask(title: "device authority")
        let remoteA = try CloudRecordCodec.encode(.task(localTask))
        let harness = try await makeHarness(local: [.task(localTask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(localTask)])
        let oldB = try CloudRecordCodec.encode(.task(makeTask(title: "stale B record")))
        let targetTransport = await installTransport(harness, account: "account-B", records: [oldB])
        let staleBHash = try CloudSyncMetadataStore.accountHash(for: "account-B")
        var staleMetadata = CloudSyncMetadata(accountHash: staleBHash)
        staleMetadata.syncEngineState = Data([0x44])
        staleMetadata.remoteChangeToken = Data([0x55])
        staleMetadata.serverMetadata = Data([0x66])
        staleMetadata.recordNameToEntityKey = [oldB.recordName: oldB.entityKey]
        staleMetadata.pendingRemoteChanges = [CloudSyncPendingChange(sequence: 19, change: .delete(oldB.entityKey))]
        staleMetadata.changeSequence = 19
        staleMetadata.needsFullRemoteSnapshot = true
        staleMetadata.zoneInitialized = true
        staleMetadata.lastSuccessfulSync = Date(timeIntervalSince1970: 100)
        try harness.metadataStore.save(staleMetadata, forAccountRecordName: "account-B")

        _ = await beginAccountSwitch(harness, to: "account-B")
        await harness.coordinator.resolveAccountSwitch(.useLocal)

        let resolvedB = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: "account-B"))
        let recordsB = await targetTransport.remoteRecords()
        XCTAssertEqual(try recordsB.map(taskTitle(from:)), ["device authority"])
        XCTAssertNil(resolvedB.syncEngineState)
        XCTAssertNil(resolvedB.serverMetadata)
        XCTAssertNotEqual(resolvedB.remoteChangeToken, Data([0x55]))
        XCTAssertEqual(Set(resolvedB.recordNameToEntityKey?.values.map { $0 } ?? []), [SyncEntityKey(kind: .task, id: localTask.id)])
        XCTAssertFalse(resolvedB.pendingRemoteChanges?.contains(where: { $0.change == .delete(oldB.entityKey) }) ?? false)
        XCTAssertFalse(resolvedB.needsFullRemoteSnapshot ?? true)
        let recordsA = await harness.memoryTransport.remoteRecords()
        XCTAssertEqual(recordsA, [remoteA], "resolving B must preserve A's zone")
    }

    func test_switchingBackToPreviousAccountRequiresChoiceAndRebuildsItsStaleMetadata() async throws {
        let taskA = makeTask(title: "A current cloud")
        let remoteA = try CloudRecordCodec.encode(.task(taskA))
        let harness = try await makeHarness(local: [.task(taskA)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(taskA)])
        var staleA = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: "account-A"))
        staleA.syncEngineState = Data([0x44])
        staleA.remoteChangeToken = Data([0x55])
        staleA.pendingRemoteChanges = [CloudSyncPendingChange(sequence: 17, change: .upsert(remoteA))]
        staleA.changeSequence = 17
        staleA.needsFullRemoteSnapshot = true
        try harness.metadataStore.save(staleA, forAccountRecordName: "account-A")

        let targetBRecord = try CloudRecordCodec.encode(.task(makeTask(title: "B cloud")))
        let targetB = await installTransport(harness, account: "account-B", records: [targetBRecord])
        _ = await beginAccountSwitch(harness, to: "account-B")
        await harness.coordinator.resolveAccountSwitch(.useLocal)
        let activeBHash = try CloudSyncMetadataStore.accountHash(for: "account-B")
        let resolvedBRecords = await targetB.remoteRecords()
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), activeBHash)
        harness.localStore.snapshot = makeSnapshot([.task(makeTask(title: "local after B"))])

        await harness.accountProvider.setResolution(.available(recordName: "account-A"))
        await harness.coordinator.handle(.manual)

        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), activeBHash)
        let countBeforeChoice = await harness.transportFactory.makeCount(forAccountRecordName: "account-A")
        XCTAssertEqual(countBeforeChoice, 1, "the existing A transport must not be resumed automatically")
        _ = await harness.coordinator.prepareAccountResolutionContext()
        await harness.coordinator.resolveAccountSwitch(.useCloud)

        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["A current cloud"])
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-A"))
        let rebuiltA = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: "account-A"))
        XCTAssertNil(rebuiltA.syncEngineState)
        XCTAssertNil(rebuiltA.remoteChangeToken)
        XCTAssertEqual(rebuiltA.pendingRemoteChanges, [])
        XCTAssertFalse(rebuiltA.needsFullRemoteSnapshot ?? true)
        let targetBRecordsAfterSwitchback = await targetB.remoteRecords()
        XCTAssertEqual(targetBRecordsAfterSwitchback, resolvedBRecords)
    }

    func test_malformedTargetSnapshotStaysPendingAndDoesNotTouchLocalData() async throws {
        let localTask = makeTask(title: "local safe")
        let remoteA = try CloudRecordCodec.encode(.task(localTask))
        let harness = try await makeHarness(local: [.task(localTask)], remote: [remoteA], requested: true)
        try await connectAccountA(harness, entities: [.task(localTask)])
        let malformed = CloudSyncRecord(
            zoneName: CloudRecordCodec.customZoneName,
            recordType: CloudRecordCodec.recordTypeName,
            recordName: "malformed-target-record",
            kind: .task,
            businessId: UUID().uuidString,
            payloadVersion: CloudRecordCodec.payloadVersion(for: .task),
            payload: Data([0xFF]),
            payloadHash: "not-a-valid-hash",
            blob: nil
        )
        let targetTransport = await installTransport(harness, account: "account-B", records: [malformed])
        await harness.accountProvider.setResolution(.available(recordName: "account-B"))
        await harness.coordinator.handle(.manual)

        let context = await harness.coordinator.prepareAccountResolutionContext()

        XCTAssertEqual(context?.progress, .failed(.invalidCloudData))
        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["local safe"])
        let targetRecords = await targetTransport.remoteRecords()
        XCTAssertEqual(targetRecords, [malformed])
        XCTAssertEqual(try harness.metadataStore.loadActiveAccountHash(), try CloudSyncMetadataStore.accountHash(for: "account-A"))
    }

    func test_resolutionContextAndDiagnosticsNeverExposeRawAccountRecordNames() async throws {
        let task = makeTask(title: "private task")
        let record = try CloudRecordCodec.encode(.task(task))
        let harness = try await makeHarness(local: [.task(task)], remote: [record], requested: true)
        try await connectAccountA(harness, entities: [.task(task)])
        let targetRecordName = "apple-user-record-name-secret"
        let target = try CloudRecordCodec.encode(.task(makeTask(title: "target")))
        _ = await installTransport(harness, account: targetRecordName, records: [target])

        let context = await beginAccountSwitch(harness, to: targetRecordName)
        let targetHash = try CloudSyncMetadataStore.accountHash(for: targetRecordName)
        XCTAssertEqual(context?.targetAccountHash, targetHash)
        XCTAssertFalse(context?.targetAccountHash.contains(targetRecordName) ?? true)
        XCTAssertFalse(harness.coordinator.diagnosticsDescription.contains(targetRecordName))
        let metadataURL = try harness.metadataStore.metadataFileURL(forAccountRecordName: targetRecordName)
        XCTAssertFalse(metadataURL.path.contains(targetRecordName))

        let beforeDefer = harness.coordinator.accountResolutionContext
        harness.coordinator.deferAccountResolutionPresentation()
        XCTAssertEqual(harness.coordinator.accountResolutionContext, beforeDefer)
        XCTAssertEqual(harness.coordinator.status, .accountDecisionRequired)
        let reopenedContext = await harness.coordinator.prepareAccountResolutionContext()
        XCTAssertNotNil(reopenedContext)
    }

    private struct Harness {
        let coordinator: CloudSyncCoordinator
        let settings: UserSettings
        let localStore: MemoryCoordinatorLocalStore
        let transport: any CloudSyncTransport
        let memoryTransport: InMemoryCloudSyncTransport
        let transportFactory: FakeCloudSyncTransportFactory
        let accountProvider: FakeCloudSyncAccountProvider
        let metadataStore: CloudSyncMetadataStore
        let accountRecordName: String

        @MainActor func establishBaseline(_ entities: [CloudSyncEntity]) async throws {
            let batch = try await transport.fetchChanges(since: nil)
            var metadata = CloudSyncMetadata(accountHash: try CloudSyncMetadataStore.accountHash(for: accountRecordName))
            metadata.lastSuccessfulSync = Date(timeIntervalSince1970: 100)
            metadata.remoteChangeToken = batch.nextToken
            metadata.zoneInitialized = true
            for entity in entities {
                let record = try CloudRecordCodec.encode(entity)
                metadata.entityBaselines[entity.key] = CloudSyncEntityBaseline(lastSyncedHash: record.payloadHash, recordName: record.recordName)
                metadata.remember(entity.key, recordName: record.recordName)
            }
            try metadataStore.save(metadata, forAccountRecordName: accountRecordName)
            try metadataStore.saveActiveAccountHash(CloudSyncMetadataStore.accountHash(for: accountRecordName))
        }
    }

    private func makeHarness(
        local: [CloudSyncEntity],
        remote: [CloudSyncRecord] = [],
        account: CloudSyncAccountResolution = .available(recordName: "account-A"),
        requested: Bool = false,
        customTransport: (any CloudSyncTransport)? = nil,
        memoryTransport suppliedMemoryTransport: InMemoryCloudSyncTransport? = nil,
        retryDelay: @escaping @Sendable (TimeInterval) async -> Void = { _ in },
        recoveryRecorder: RecoveryEventRecorder? = nil,
        entitlementProvider: (any CloudSyncEntitlementProviding)? = nil
    ) async throws -> Harness {
        let suiteName = "WeekyiiCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = UserSettings(defaults: defaults)
        settings.setCloudSyncRequested(requested)
        let memoryTransport = suppliedMemoryTransport ?? InMemoryCloudSyncTransport(seedRecords: remote)
        let transport: any CloudSyncTransport = customTransport ?? memoryTransport
        _ = try await transport.ensureInfrastructure()
        let factory = FakeCloudSyncTransportFactory(transport: transport)
        let accountProvider = FakeCloudSyncAccountProvider(account)
        let store = MemoryCoordinatorLocalStore(snapshot: makeSnapshot(local))
        let accountRecordName = "account-A"
        let metadataRoot = FileManager.default.temporaryDirectory.appendingPathComponent("WeekyiiSyncCoordinatorTest-\(UUID().uuidString)")
        let metadataStore = CloudSyncMetadataStore(rootURL: metadataRoot)
        let coordinator = CloudSyncCoordinator(
            settings: settings,
            localStore: store,
            accountProvider: accountProvider,
            entitlementProvider: entitlementProvider ?? OpenAccessCloudSyncEntitlementProvider(),
            transportFactory: factory,
            metadataStore: metadataStore,
            now: { Date(timeIntervalSince1970: 10_000) },
            retryDelay: retryDelay,
            recoveryPoint: { _ in
                try await recoveryRecorder?.append(localTitles: store.snapshot.tasks.map(\.title))
            }
        )
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: metadataRoot)
        }
        return Harness(coordinator: coordinator, settings: settings, localStore: store, transport: transport, memoryTransport: memoryTransport, transportFactory: factory, accountProvider: accountProvider, metadataStore: metadataStore, accountRecordName: accountRecordName)
    }

    private func connectAccountA(_ harness: Harness, entities: [CloudSyncEntity]) async throws {
        try await harness.establishBaseline(entities)
        let hash = try CloudSyncMetadataStore.accountHash(for: harness.accountRecordName)
        try harness.metadataStore.saveActiveAccountHash(hash)
        await harness.coordinator.handle(.appLaunch)
    }

    private func installTransport(
        _ harness: Harness,
        account: String,
        records: [CloudSyncRecord]
    ) async -> InMemoryCloudSyncTransport {
        let transport = InMemoryCloudSyncTransport(seedRecords: records)
        _ = try? await transport.ensureInfrastructure()
        await harness.transportFactory.setTransport(transport, forAccountRecordName: account)
        return transport
    }

    private func beginAccountSwitch(
        _ harness: Harness,
        to account: String
    ) async -> CloudAccountResolutionContext? {
        await harness.accountProvider.setResolution(.available(recordName: account))
        await harness.coordinator.handle(.manual)
        return await harness.coordinator.prepareAccountResolutionContext()
    }

    private func makeSnapshot(_ entities: [CloudSyncEntity]) -> WeekyiiBusinessSnapshot {
        var tasks: [TaskSnapshot] = []
        var attachments: [AttachmentSnapshot] = []
        var weeks: [WeekSnapshot] = []
        var days: [DaySnapshot] = []
        var projects: [ProjectSnapshot] = []
        var habits: [HabitSnapshot] = []
        var suspendedTasks: [SuspendedTaskSnapshot] = []
        var mindStamps: [MindStampSnapshot] = []
        var taskTypes: [TaskTypeSnapshot] = []
        var habitDayRecords: [HabitDayRecordSnapshot] = []
        for entity in entities {
            switch entity {
            case .task(let value): tasks.append(value)
            case .attachment(let value): attachments.append(value)
            case .week(let value): weeks.append(value)
            case .day(let value): days.append(value)
            case .project(let value): projects.append(value)
            case .habit(let value): habits.append(value)
            case .suspendedTask(let value): suspendedTasks.append(value)
            case .mindStamp(let value): mindStamps.append(value)
            case .taskType(let value): taskTypes.append(value)
            case .habitDayRecord(let value): habitDayRecords.append(value)
            }
        }
        return WeekyiiBusinessSnapshot(weeks: weeks, days: days, tasks: tasks, suspendedTasks: suspendedTasks, attachments: attachments, projects: projects, mindStamps: mindStamps, taskTypes: taskTypes, habits: habits, habitDayRecords: habitDayRecords)
    }

    private func makeTask(id: UUID = UUID(), title: String) -> TaskSnapshot {
        TaskSnapshot(id: id, dayId: nil, projectId: nil, habitId: nil, title: title, taskDescription: "", taskType: .regular, taskTypeIdRaw: "regular", order: 0, zone: .draft, startedAt: nil, endedAt: nil, completedOrder: 0, steps: [], attachmentIds: [])
    }

    private func taskID(from entity: CloudSyncEntity) throws -> UUID {
        guard case .task(let task) = entity else { throw CloudRecordCodecError.entityKeyMismatch }
        return task.id
    }

    private func taskTitle(from record: CloudSyncRecord) throws -> String {
        guard case .task(let task) = try CloudRecordCodec.decode(record) else { throw CloudRecordCodecError.entityKeyMismatch }
        return task.title
    }

    private func taskSnapshot(from record: CloudSyncRecord) throws -> TaskSnapshot {
        guard case .task(let task) = try CloudRecordCodec.decode(record) else { throw CloudRecordCodecError.entityKeyMismatch }
        return task
    }
}

@MainActor
private final class MemoryCoordinatorLocalStore: CloudSyncLocalStore {
    var snapshot: WeekyiiBusinessSnapshot
    private(set) var applyCount = 0

    init(snapshot: WeekyiiBusinessSnapshot) { self.snapshot = snapshot }
    func currentSnapshot() throws -> WeekyiiBusinessSnapshot { snapshot }
    func apply(_ snapshot: WeekyiiBusinessSnapshot) throws { self.snapshot = snapshot; applyCount += 1 }
}

private actor FakeCloudSyncAccountProvider: CloudSyncAccountProviding {
    private var resolution: CloudSyncAccountResolution
    private var queries = 0
    private var scheduledSwitch: (query: Int, resolution: CloudSyncAccountResolution)?

    init(_ resolution: CloudSyncAccountResolution) { self.resolution = resolution }
    func resolveAccount() async -> CloudSyncAccountResolution {
        queries += 1
        if let scheduledSwitch, queries >= scheduledSwitch.query {
            resolution = scheduledSwitch.resolution
            self.scheduledSwitch = nil
        }
        return resolution
    }
    func setResolution(_ resolution: CloudSyncAccountResolution) { self.resolution = resolution }
    func switchResolution(afterAdditionalQueries count: Int, to resolution: CloudSyncAccountResolution) {
        scheduledSwitch = (queries + max(1, count), resolution)
    }
    func queryCount() -> Int { queries }
}

private actor FakeCloudSyncEntitlementProvider: CloudSyncEntitlementProviding {
    private let state: CloudSyncEntitlementState
    private var queries = 0

    init(_ state: CloudSyncEntitlementState) { self.state = state }
    func currentState() async -> CloudSyncEntitlementState { queries += 1; return state }
    func queryCount() -> Int { queries }
}

private actor FakeCloudSyncTransportFactory: CloudSyncTransportFactory {
    private let fallbackTransport: any CloudSyncTransport
    private var accountTransports: [String: any CloudSyncTransport] = [:]
    private var calls = 0
    private var callsByAccount: [String: Int] = [:]

    init(transport: any CloudSyncTransport) { fallbackTransport = transport }
    func makeTransport(accountRecordName: String) async throws -> any CloudSyncTransport {
        calls += 1
        callsByAccount[accountRecordName, default: 0] += 1
        return accountTransports[accountRecordName] ?? fallbackTransport
    }
    func setTransport(_ transport: any CloudSyncTransport, forAccountRecordName accountRecordName: String) {
        accountTransports[accountRecordName] = transport
    }
    func makeCount() -> Int { calls }
    func makeCount(forAccountRecordName accountRecordName: String) -> Int { callsByAccount[accountRecordName, default: 0] }
}

private actor RecoveryEventRecorder {
    private var values: [[String]] = []
    private let failing: Bool
    init(failing: Bool = false) { self.failing = failing }
    func append(localTitles: [String]) throws {
        values.append(localTitles)
        if failing { throw RecoveryPointTestFailure.failed }
    }
    func observedLocalTitles() -> [String] { values.first ?? [] }
}

private enum RecoveryPointTestFailure: Error { case failed }

private actor RetryDelayRecorder {
    private var delays: [TimeInterval] = []
    func append(_ delay: TimeInterval) { delays.append(delay) }
    func values() -> [TimeInterval] { delays }
}

private actor CoordinatorAsyncGate {
    private var entered = false
    private var operationContinuation: CheckedContinuation<Void, Never>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            operationContinuation = continuation
            entered = true
            enteredContinuation?.resume()
            enteredContinuation = nil
        }
    }
    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }
    func release() { operationContinuation?.resume(); operationContinuation = nil }
}

private actor GatedCoordinatorTransport: CloudSyncTransport, CloudSyncCancellableTransport {
    private let base: InMemoryCloudSyncTransport
    private let gate: CoordinatorAsyncGate
    private let cancellationGate: CoordinatorAsyncGate?
    private var armed = false
    private var inspectionArmed = false
    private var cancellationArmed = false
    init(base: InMemoryCloudSyncTransport, gate: CoordinatorAsyncGate, cancellationGate: CoordinatorAsyncGate? = nil) {
        self.base = base
        self.gate = gate
        self.cancellationGate = cancellationGate
    }
    var databaseScope: CloudSyncDatabaseScope { get async { await base.databaseScope } }
    func ensureInfrastructure() async throws -> CloudSyncRemoteInfrastructure { try await base.ensureInfrastructure() }
    func inspectRemoteZone() async throws -> CloudSyncZoneInspection {
        if inspectionArmed { inspectionArmed = false; await gate.wait() }
        return try await base.inspectRemoteZone()
    }
    func resetCustomZone() async throws { try await base.resetCustomZone() }
    func suspendNextFetch() { armed = true }
    func suspendNextInspection() { inspectionArmed = true }
    func suspendNextCancellation() { cancellationArmed = true }
    func cancelOperations() async {
        if cancellationArmed, let cancellationGate {
            cancellationArmed = false
            await cancellationGate.wait()
        }
    }
    func fetchChanges(since token: Data?) async throws -> CloudSyncChangeBatch {
        if armed { armed = false; await gate.wait() }
        return try await base.fetchChanges(since: token)
    }
    func upsert(_ records: [CloudSyncRecord]) async -> [CloudSyncRecordResult] { await base.upsert(records) }
    func delete(_ keys: [SyncEntityKey]) async -> [CloudSyncRecordResult] { await base.delete(keys) }
    func restoreTransportState(_ state: Data?) async { await base.restoreTransportState(state) }
    func persistedTransportState() async -> Data? { await base.persistedTransportState() }
}
