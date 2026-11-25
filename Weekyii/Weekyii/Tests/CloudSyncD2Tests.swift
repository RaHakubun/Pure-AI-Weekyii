import CloudKit
import Foundation
import XCTest
@testable import Weekyii

@MainActor
final class CloudKitRecordAdapterTests: XCTestCase {
    func test_cloudRecordConversionCarriesOpaqueSystemMetadataAndDerivesIdentityFromPayload() async throws {
        let entity = makeTask(title: "adapter round trip")
        let domainRecord = try CloudRecordCodec.encode(.task(entity))
        let assetOwner = try CloudKitOutgoingAssetFiles()
        defer { Task { await assetOwner.cleanup() } }
        let zoneID = CKRecordZone.ID(zoneName: CloudRecordCodec.customZoneName, ownerName: CKCurrentUserDefaultName)

        let cloudRecord = try await CloudKitRecordAdapter.makeCKRecord(
            from: domainRecord,
            zoneID: zoneID,
            assetFiles: assetOwner
        )
        let decoded = try CloudKitRecordAdapter.decode(cloudRecord)
        let restored = try XCTUnwrap(decoded.serverMetadata).withCloudKitSystemMetadata()

        XCTAssertEqual(decoded.entityKey, entity.entityKey)
        XCTAssertEqual(decoded.recordName, CKRecordNameCodec.recordName(for: entity.entityKey))
        XCTAssertEqual(decoded.payload, domainRecord.payload)
        XCTAssertEqual(restored.recordID, cloudRecord.recordID)
        XCTAssertEqual(restored.recordType, CloudRecordCodec.recordTypeName)
    }

    func test_adapterRejectsRecordNameThatDoesNotMatchPayloadIdentity() async throws {
        let entity = makeTask()
        let value = try CloudRecordCodec.encode(.task(entity))
        let zoneID = CKRecordZone.ID(zoneName: CloudRecordCodec.customZoneName, ownerName: CKCurrentUserDefaultName)
        let record = CKRecord(recordType: CloudRecordCodec.recordTypeName,
                              recordID: CKRecord.ID(recordName: "wy1_wrong", zoneID: zoneID))
        record["kind"] = SyncEntityKind.task.rawValue as CKRecordValue
        record["payloadVersion"] = NSNumber(value: value.payloadVersion)
        record["payload"] = value.payload as CKRecordValue
        record["payloadHash"] = value.payloadHash as CKRecordValue

        XCTAssertThrowsError(try CloudKitRecordAdapter.decode(record)) {
            XCTAssertEqual($0 as? CloudKitRecordAdapterError, .recordNameMismatch)
        }
    }

    func test_outgoingAssetFilesAreOwnedAndRemovedOnCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeekyiiD2AssetTest-\(UUID().uuidString)")
        let files = try CloudKitOutgoingAssetFiles(directory: root)
        let blob = CloudSyncBinaryBlob(role: .attachment, data: Data([1, 2, 3]), sha256: "digest", suggestedFileName: "x", contentType: "application/octet-stream")
        let url = try await files.makeAssetFile(for: blob)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        await files.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: root.path))?.isEmpty ?? true)
        try? FileManager.default.removeItem(at: root)
    }

    func test_cloudKitErrorMappingPreservesRetryAndPerRecordFailureIdentity() {
        let key = SyncEntityKey(kind: .task, businessId: UUID().uuidString)
        let id = CKRecord.ID(recordName: CKRecordNameCodec.recordName(for: key), zoneID: CKRecordZone.ID(zoneName: CloudRecordCodec.customZoneName, ownerName: CKCurrentUserDefaultName))
        let itemError = NSError(domain: CKErrorDomain, code: CKError.quotaExceeded.rawValue)
        let partial = NSError(
            domain: CKErrorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [id: itemError]]
        )

        XCTAssertEqual(CloudKitFailureMapper.map(NSError(domain: CKErrorDomain, code: CKError.networkUnavailable.rawValue)), .networkUnavailable)
        XCTAssertEqual(CloudKitFailureMapper.map(NSError(domain: CKErrorDomain, code: CKError.serviceUnavailable.rawValue, userInfo: [CKErrorRetryAfterKey: 17])), .serviceUnavailable(retryAfter: 17))
        XCTAssertEqual(CloudKitFailureMapper.map(partial, recordNames: [id.recordName: key]), .partialFailure([CloudSyncRecordFailure(entityKey: key, failure: .quotaExceeded)]))
    }

    func test_recordNameDeleteMappingSurvivesMetadataReloadAndOldD1ShapeStillDecodes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeekyiiD2MetadataTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudSyncMetadataStore(rootURL: root)
        let account = "opaque-account-record-name"
        let key = SyncEntityKey(kind: .task, businessId: UUID().uuidString)
        let recordName = CKRecordNameCodec.recordName(for: key)
        var metadata = CloudSyncMetadata(accountHash: try CloudSyncMetadataStore.accountHash(for: account))
        metadata.remember(key, recordName: recordName, serverMetadata: Data([7, 8]))
        try store.save(metadata, forAccountRecordName: account)

        let restored = try XCTUnwrap(store.load(forAccountRecordName: account))
        XCTAssertEqual(restored.entityKey(forRecordName: recordName), key)
        XCTAssertEqual(restored.recordNameToEntityKey?[recordName], key)

        let fileURL = try store.metadataFileURL(forAccountRecordName: account)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        object.removeValue(forKey: "recordNameToEntityKey")
        try JSONSerialization.data(withJSONObject: object).write(to: fileURL)
        XCTAssertEqual(try store.load(forAccountRecordName: account)?.entityKey(forRecordName: recordName), nil)
    }

    func test_infrastructureEnsureIsIdempotentAndResetOnlyDeletesWeekyiiZone() async throws {
        let client = FakeCloudKitInfrastructureClient()
        let manager = CloudKitInfrastructureManager(client: client)
        _ = try await manager.ensure()
        _ = try await manager.ensure()
        let counts = await client.operationCounts()
        XCTAssertEqual(counts.zoneCreates, 1)
        XCTAssertEqual(counts.subscriptionCreates, 1)
        try await manager.resetWeekyiiZone()
        let resetCounts = await client.operationCounts()
        XCTAssertEqual(resetCounts.zoneDeletes, 1)
    }

    func test_productionEnginePolicyDisablesAutomaticScheduling() {
        XCTAssertFalse(CKSyncEngineTransport.automaticSchedulingEnabled)
        XCTAssertEqual(CloudKitInfrastructureManager.subscriptionID, "WeekyiiSyncZoneV1-subscription-v1")
    }

    func test_durableInboxReplaysFetchedChangeAfterEngineStateCommitAndRecreation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeekyiiInboxCrash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let account = "crash-account"
        let record = try CloudRecordCodec.encode(.task(makeTask(title: "survives crash")))
        let first = CloudSyncDurableInbox(store: CloudSyncMetadataStore(rootURL: root), accountRecordName: account)
        try first.append(upserts: [record], deletedRecordNames: [])
        try first.persistEngineState(Data([0xCA, 0xFE]))

        let restarted = CloudSyncDurableInbox(store: CloudSyncMetadataStore(rootURL: root), accountRecordName: account)
        let replay = try restarted.batch(since: nil)
        XCTAssertEqual(replay.changes, [.upsert(record)])
        XCTAssertEqual(try CloudSyncMetadataStore(rootURL: root).load(forAccountRecordName: account)?.syncEngineState, Data([0xCA, 0xFE]))
    }

    func test_ackPrunesDeliveredChangesAndMonotonicCursorSurvivesRecreation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeekyiiInboxAck-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let account = "ack-account"
        let store = CloudSyncMetadataStore(rootURL: root)
        let first = CloudSyncDurableInbox(store: store, accountRecordName: account)
        let earlier = try CloudRecordCodec.encode(.task(makeTask(title: "earlier")))
        try first.append(upserts: [earlier], deletedRecordNames: [])
        let batch = try first.batch(since: nil)
        try store.update(forAccountRecordName: account) { metadata in
            metadata.entityBaselines[earlier.entityKey] = CloudSyncEntityBaseline(lastSyncedHash: earlier.payloadHash)
            metadata.acknowledgeChanges(
                through: try CloudSyncDurableInbox.decodeToken(batch.nextToken),
                token: batch.nextToken
            )
        }

        let restarted = CloudSyncDurableInbox(store: CloudSyncMetadataStore(rootURL: root), accountRecordName: account)
        let restoredCursor = try XCTUnwrap(store.load(forAccountRecordName: account)?.remoteChangeToken)
        XCTAssertEqual(restoredCursor, batch.nextToken)
        XCTAssertTrue(try restarted.batch(since: restoredCursor).changes.isEmpty)
        XCTAssertTrue(try restarted.batch(since: nil).changes.isEmpty, "acknowledged business changes are pruned")
        let later = try CloudRecordCodec.encode(.task(makeTask(title: "later")))
        try restarted.append(upserts: [later], deletedRecordNames: [])
        let afterRestart = try CloudSyncDurableInbox(store: CloudSyncMetadataStore(rootURL: root), accountRecordName: account)
            .batch(since: restoredCursor)
        XCTAssertEqual(afterRestart.changes, [.upsert(later)])
        XCTAssertEqual(try CloudSyncDurableInbox.decodeToken(afterRestart.nextToken), 2)
    }

    func test_payloadlessRemoteDeleteRemainsInInboxAcrossRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeekyiiInboxDelete-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let account = "delete-account"
        let store = CloudSyncMetadataStore(rootURL: root)
        let key = SyncEntityKey(kind: .task, businessId: UUID().uuidString)
        let name = CKRecordNameCodec.recordName(for: key)
        try store.update(forAccountRecordName: account) { $0.remember(key, recordName: name) }
        let first = CloudSyncDurableInbox(store: store, accountRecordName: account)
        try first.append(upserts: [], deletedRecordNames: [name, "unknown-record"])
        try first.persistEngineState(Data([0xDD]))

        let restarted = CloudSyncDurableInbox(store: CloudSyncMetadataStore(rootURL: root), accountRecordName: account)
        XCTAssertEqual(try restarted.batch(since: nil).changes, [.delete(key)])
        XCTAssertEqual(try store.load(forAccountRecordName: account)?.syncEngineState, Data([0xDD]))
    }

    func test_preInboxMetadataForcesFullRefetchInsteadOfTrustingProcessLocalToken() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeekyiiInboxUpgrade-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let account = "legacy-delivery-account"
        let store = CloudSyncMetadataStore(rootURL: root)
        var legacy = CloudSyncMetadata(accountHash: try CloudSyncMetadataStore.accountHash(for: account))
        legacy.pendingRemoteChanges = nil
        legacy.changeSequence = nil
        legacy.remoteChangeToken = CloudSyncDurableInbox.encodeToken(5)
        legacy.syncEngineState = Data([1, 2, 3])
        let deletedKey = SyncEntityKey(kind: .task, businessId: UUID().uuidString)
        legacy.entityBaselines[deletedKey] = CloudSyncEntityBaseline(lastSyncedHash: "old-hash")
        try store.save(legacy, forAccountRecordName: account)

        let inbox = CloudSyncDurableInbox(store: store, accountRecordName: account)
        let prepared = try inbox.prepare()
        XCTAssertTrue(prepared.needsAuthoritativeSnapshot)
        XCTAssertNil(prepared.metadata.remoteChangeToken)
        XCTAssertNil(prepared.metadata.syncEngineState)
        XCTAssertEqual(prepared.metadata.changeSequence, 0)
        let afterCrashBeforeSnapshot = try CloudSyncDurableInbox(
            store: CloudSyncMetadataStore(rootURL: root), accountRecordName: account
        ).prepare()
        XCTAssertTrue(afterCrashBeforeSnapshot.needsAuthoritativeSnapshot)

        try inbox.appendAuthoritativeSnapshot([])
        XCTAssertEqual(try inbox.batch(since: nil).changes, [.delete(deletedKey)])
        XCTAssertEqual(try store.load(forAccountRecordName: account)?.needsFullRemoteSnapshot, false)
    }

    private func makeTask(title: String = "task") -> TaskSnapshot {
        TaskSnapshot(id: UUID(), dayId: "2026-09-25", projectId: nil, habitId: nil, title: title, taskDescription: "", taskType: .regular, taskTypeIdRaw: "regular", order: 0, zone: .draft, startedAt: nil, endedAt: nil, completedOrder: 0, steps: [], attachmentIds: [])
    }
}

private extension Data {
    func withCloudKitSystemMetadata() throws -> CKRecord {
        try CloudKitSystemMetadata.decode(self)
    }
}

private actor FakeCloudKitInfrastructureClient: CloudKitInfrastructureClient {
    private var zone = false
    private var subscription = false
    private var zoneCreates = 0
    private var subscriptionCreates = 0
    private var zoneDeletes = 0

    func zoneExists() async throws -> Bool { zone }
    func createZone() async throws { zoneCreates += 1; zone = true }
    func subscriptionExists(id: String) async throws -> Bool { subscription }
    func createZoneSubscription(id: String) async throws { subscriptionCreates += 1; subscription = true }
    func deleteWeekyiiZone() async throws { zoneDeletes += 1; zone = false; subscription = false }
    func recordsInWeekyiiZone() async throws -> [CKRecord] { [] }

    func operationCounts() -> (zoneCreates: Int, subscriptionCreates: Int, zoneDeletes: Int) {
        (zoneCreates, subscriptionCreates, zoneDeletes)
    }
}
