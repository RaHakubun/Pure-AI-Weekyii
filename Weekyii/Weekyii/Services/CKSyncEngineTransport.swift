import CloudKit
import Foundation

/// Production implementation of the domain transport. CKSyncEngine is configured
/// with automatic scheduling disabled; callers own every fetch/send trigger.
actor CKSyncEngineTransport: CloudSyncTransport, CloudSyncCancellableTransport, CKSyncEngineDelegate {
    nonisolated static let automaticSchedulingEnabled = false
    private let database: CKDatabase
    private let accountRecordName: String
    private let metadataStore: CloudSyncMetadataStore
    private let inbox: CloudSyncDurableInbox
    private let infrastructure: CloudKitInfrastructureManager
    private let zoneID = CKRecordZone.ID(
        zoneName: CloudRecordCodec.customZoneName,
        ownerName: CKCurrentUserDefaultName
    )

    private var engineStateData: Data?
    private var engine: CKSyncEngine?
    private var rebuildingLegacySnapshot = false
    private var fetchFailure: CloudSyncFailure?
    private var sendResults: [String: CloudSyncRecordResult] = [:]
    private var outgoingRecords: [String: CloudSyncRecord] = [:]
    private var outgoingDeletes: [String: SyncEntityKey] = [:]
    private var activeAssetFiles: CloudKitOutgoingAssetFiles?

    init(
        container: CKContainer = .default(),
        accountRecordName: String,
        metadataStore: CloudSyncMetadataStore = CloudSyncMetadataStore(),
        infrastructureClient: (any CloudKitInfrastructureClient)? = nil
    ) {
        self.database = container.privateCloudDatabase
        self.accountRecordName = accountRecordName
        self.metadataStore = metadataStore
        self.inbox = CloudSyncDurableInbox(store: metadataStore, accountRecordName: accountRecordName)
        self.infrastructure = CloudKitInfrastructureManager(
            client: infrastructureClient ?? CloudKitPrivateDatabaseClient(database: container.privateCloudDatabase)
        )
    }

    static func forCurrentAccount(
        container: CKContainer = .default(),
        metadataStore: CloudSyncMetadataStore = CloudSyncMetadataStore()
    ) async throws -> CKSyncEngineTransport {
        let user = try await container.userRecordID()
        return CKSyncEngineTransport(
            container: container,
            accountRecordName: user.recordName,
            metadataStore: metadataStore
        )
    }

    var databaseScope: CloudSyncDatabaseScope { .privateDatabase }

    nonisolated static func makeEngineConfiguration(
        database: CKDatabase,
        stateSerialization: CKSyncEngine.State.Serialization?,
        delegate: any CKSyncEngineDelegate
    ) -> CKSyncEngine.Configuration {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateSerialization,
            delegate: delegate
        )
        configuration.automaticallySync = Self.automaticSchedulingEnabled
        configuration.subscriptionID = CloudKitInfrastructureManager.subscriptionID
        return configuration
    }

    func ensureInfrastructure() async throws -> CloudSyncRemoteInfrastructure {
        do {
            let remote = try await infrastructure.ensure()
            try await ensureEngine()
            try metadataStore.update(forAccountRecordName: accountRecordName) { $0.zoneInitialized = true }
            return remote
        } catch {
            throw CloudSyncTransportError.cloudFailure(CloudKitFailureMapper.map(error, recordNames: recordNameIndex()))
        }
    }

    func inspectRemoteZone() async throws -> CloudSyncZoneInspection {
        do {
            // Inspection is a read-only staging operation. In particular, it
            // must not mix freshly observed target records into stale account
            // metadata before the user has chosen a resolution.
            return try await infrastructure.inspect()
        } catch {
            throw CloudSyncTransportError.cloudFailure(CloudKitFailureMapper.map(error, recordNames: recordNameIndex()))
        }
    }

    func resetCustomZone() async throws {
        await engine?.cancelOperations()
        engine = nil
        do {
            try await infrastructure.resetWeekyiiZone()
            try metadataStore.update(forAccountRecordName: accountRecordName) { state in
                state.entityBaselines.removeAll()
                state.recordNameToEntityKey = [:]
                state.syncEngineState = nil
                state.remoteChangeToken = nil
                state.pendingRemoteChanges = []
                state.changeSequence = 0
                state.needsFullRemoteSnapshot = false
                state.zoneInitialized = false
                state.lastFailure = nil
                state.lastFailureCategory = nil
                state.lastFailureReason = nil
                state.automaticRetrySuppressed = false
            }
            engineStateData = nil
            rebuildingLegacySnapshot = false
        } catch {
            throw CloudSyncTransportError.cloudFailure(CloudKitFailureMapper.map(error, recordNames: recordNameIndex()))
        }
    }

    func fetchChanges(since token: Data?) async throws -> CloudSyncChangeBatch {
        do {
            _ = try await ensureInfrastructure()
            fetchFailure = nil
            try await engine!.fetchChanges(.init(scope: .zoneIDs([zoneID])))
            if let fetchFailure { throw CloudSyncTransportError.cloudFailure(fetchFailure) }
            if rebuildingLegacySnapshot {
                let inspection = try await infrastructure.inspect()
                try inbox.appendAuthoritativeSnapshot(inspection.records)
            }
            try persistStagedEngineState()
            // The old D2 cursor referred to a process-local array. A migrated
            // account must replay from the newly durable inbox instead.
            let batch = try inbox.batch(since: rebuildingLegacySnapshot ? nil : token)
            rebuildingLegacySnapshot = false
            return batch
        } catch let error as CloudSyncTransportError {
            throw error
        } catch {
            throw CloudSyncTransportError.cloudFailure(CloudKitFailureMapper.map(error, recordNames: recordNameIndex()))
        }
    }

    func upsert(_ records: [CloudSyncRecord]) async -> [CloudSyncRecordResult] {
        await send(records: records, deleting: [])
    }

    func delete(_ keys: [SyncEntityKey]) async -> [CloudSyncRecordResult] {
        await send(records: [], deleting: keys)
    }

    func restoreTransportState(_ state: Data?) async {
        // The persisted account state is authoritative. The caller may have
        // loaded its copy before a newer CKSyncEngine state was committed.
        _ = state
        engineStateData = try? metadataStore.load(forAccountRecordName: accountRecordName)?.syncEngineState
        await engine?.cancelOperations()
        engine = nil
    }

    func persistedTransportState() async -> Data? {
        return try? metadataStore.load(forAccountRecordName: accountRecordName)?.syncEngineState
    }

    func cancelOperations() async {
        await engine?.cancelOperations()
        await activeAssetFiles?.cleanup()
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            do {
                engineStateData = try JSONEncoder().encode(update.stateSerialization)
            } catch {
                fetchFailure = .other("Could not encode CloudKit sync state")
            }
        case .fetchedRecordZoneChanges(let fetched):
            do {
                var upserts: [CloudSyncRecord] = []
                for modification in fetched.modifications where modification.record.recordID.zoneID == zoneID {
                    upserts.append(try await CloudKitRecordAdapter.decode(modification.record))
                }
                let deletedNames = fetched.deletions.filter {
                    $0.recordID.zoneID == zoneID && $0.recordType == CloudRecordCodec.recordTypeName
                }
                try inbox.append(upserts: upserts, deletedRecordNames: deletedNames.map { $0.recordID.recordName })
            } catch {
                fetchFailure = error is CloudKitRecordAdapterError
                    ? .invalidArguments
                    : CloudKitFailureMapper.map(error, recordNames: recordNameIndex())
            }
        case .sentRecordZoneChanges(let sent):
            let knownMetadata = try? metadataStore.load(forAccountRecordName: accountRecordName)
            var remembered: [CloudSyncRecord] = []
            var conflictRecords: [CloudSyncRecord] = []
            for record in sent.savedRecords where record.recordID.zoneID == zoneID {
                do {
                    let decoded = try await CloudKitRecordAdapter.decode(record)
                    remembered.append(decoded)
                    sendResults[decoded.recordName] = CloudSyncRecordResult(
                        entityKey: decoded.entityKey,
                        outcome: .upserted,
                        serverMetadata: decoded.serverMetadata,
                        recordName: decoded.recordName
                    )
                } catch {
                    if let key = outgoingRecords[record.recordID.recordName]?.entityKey {
                        sendResults[record.recordID.recordName] = CloudSyncRecordResult(
                            entityKey: key,
                            outcome: .failed(.invalidArguments),
                            recordName: record.recordID.recordName
                        )
                    }
                }
            }
            for failed in sent.failedRecordSaves where failed.record.recordID.zoneID == zoneID {
                let name = failed.record.recordID.recordName
                guard let key = outgoingRecords[name]?.entityKey ?? knownMetadata?.entityKey(forRecordName: name) else { continue }
                var latestServerMetadata: Data?
                if (failed.error as NSError).code == CKError.serverRecordChanged.rawValue,
                   let serverRecord = (failed.error as NSError).userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord,
                   serverRecord.recordID.zoneID == zoneID {
                    do {
                        let decoded = try await CloudKitRecordAdapter.decode(serverRecord)
                        latestServerMetadata = decoded.serverMetadata
                        conflictRecords.append(decoded)
                    } catch {
                        fetchFailure = .invalidArguments
                    }
                }
                sendResults[name] = CloudSyncRecordResult(
                    entityKey: key,
                    outcome: .failed(CloudKitFailureMapper.map(failed.error, recordNames: recordNameIndex())) ,
                    serverMetadata: latestServerMetadata,
                    recordName: name
                )
            }
            for id in sent.deletedRecordIDs where id.zoneID == zoneID {
                guard let key = outgoingDeletes[id.recordName] else { continue }
                sendResults[id.recordName] = CloudSyncRecordResult(entityKey: key, outcome: .deleted, recordName: id.recordName)
            }
            for (id, error) in sent.failedRecordDeletes where id.zoneID == zoneID {
                guard let key = outgoingDeletes[id.recordName] else { continue }
                sendResults[id.recordName] = CloudSyncRecordResult(
                    entityKey: key,
                    outcome: .failed(CloudKitFailureMapper.map(error, recordNames: recordNameIndex())),
                    recordName: id.recordName
                )
            }
            do {
                try metadataStore.update(forAccountRecordName: accountRecordName) { metadata in
                    for record in remembered {
                        metadata.remember(record.entityKey, recordName: record.recordName, serverMetadata: record.serverMetadata)
                    }
                    for record in conflictRecords {
                        metadata.remember(record.entityKey, recordName: record.recordName, serverMetadata: record.serverMetadata)
                        metadata.enqueue(.upsert(record))
                    }
                    // A successful server delete does not clear the baseline here.
                    // Reconciliation owns that change and commits it with its ACK.
                }
            } catch {
                fetchFailure = .other("Could not persist CloudKit sent changes")
            }
        case .accountChange:
            // The coordinator observes account state and increments its generation;
            // this transport never follows an account into a different user namespace.
            break
        case .fetchedDatabaseChanges, .sentDatabaseChanges, .willFetchChanges,
             .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .didFetchChanges,
             .willSendChanges, .didSendChanges:
            break
        @unknown default:
            break
        }
    }

    func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        .init(scope: .zoneIDs([zoneID]))
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { change in
            guard context.options.scope.contains(change) else { return false }
            switch change {
            case .saveRecord(let id), .deleteRecord(let id): return id.zoneID == zoneID
            @unknown default: return false
            }
        }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] id in
            await self?.recordForSending(id)
        }
    }

    // MARK: Internal operations

    private func send(records: [CloudSyncRecord], deleting keys: [SyncEntityKey]) async -> [CloudSyncRecordResult] {
        let keyByName = Dictionary(uniqueKeysWithValues: (records.map { ($0.recordName, $0.entityKey) }
            + keys.map { (CKRecordNameCodec.recordName(for: $0), $0) }))
        do {
            guard !records.isEmpty || !keys.isEmpty else { return [] }
            _ = try await ensureInfrastructure()
            fetchFailure = nil
            let assets = try CloudKitOutgoingAssetFiles()
            activeAssetFiles = assets
            outgoingRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.recordName, $0) })
            outgoingDeletes = Dictionary(uniqueKeysWithValues: keys.map { (CKRecordNameCodec.recordName(for: $0), $0) })
            let saves = records.map { CKRecord.ID(recordName: $0.recordName, zoneID: zoneID) }
            let deletes = keys.map { CKRecord.ID(recordName: CKRecordNameCodec.recordName(for: $0), zoneID: zoneID) }
            let pending = saves.map(CKSyncEngine.PendingRecordZoneChange.saveRecord)
                + deletes.map(CKSyncEngine.PendingRecordZoneChange.deleteRecord)
            engine!.state.add(pendingRecordZoneChanges: pending)
            for name in keyByName.keys { sendResults.removeValue(forKey: name) }
            let currentEngine = engine!
            try await withTaskCancellationHandler {
                try await currentEngine.sendChanges(.init(scope: .zoneIDs([zoneID])))
            } onCancel: {
                Task { await currentEngine.cancelOperations() }
            }
            if let fetchFailure { throw CloudSyncTransportError.cloudFailure(fetchFailure) }
            try persistStagedEngineState()
            await assets.cleanup()
            activeAssetFiles = nil
            let completedNames = Set(sendResults.keys)
            return keyByName.map { name, key in
                sendResults[name] ?? CloudSyncRecordResult(
                    entityKey: key,
                    outcome: completedNames.contains(name) ? .deleted : .failed(.transportNotReady),
                    recordName: name
                )
            }.sorted { $0.entityKey < $1.entityKey }
        } catch {
            await activeAssetFiles?.cleanup()
            activeAssetFiles = nil
            let failure: CloudSyncFailure
            if case CloudSyncTransportError.cloudFailure(let mapped) = error { failure = mapped }
            else { failure = CloudKitFailureMapper.map(error, recordNames: recordNameIndex()) }
            return keyByName.map { name, key in
                CloudSyncRecordResult(entityKey: key, outcome: .failed(failure), recordName: name)
            }.sorted { $0.entityKey < $1.entityKey }
        }
    }

    private func recordForSending(_ id: CKRecord.ID) async -> CKRecord? {
        guard id.zoneID == zoneID,
              let value = outgoingRecords[id.recordName],
              let activeAssetFiles
        else { return nil }
        return try? await CloudKitRecordAdapter.makeCKRecord(from: value, zoneID: zoneID, assetFiles: activeAssetFiles)
    }

    private func ensureEngine() async throws {
        guard engine == nil else { return }
        let prepared = try inbox.prepare()
        rebuildingLegacySnapshot = prepared.needsAuthoritativeSnapshot
        engineStateData = prepared.metadata.syncEngineState
        let serialized = engineStateData
        let stateSerialization = serialized.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let config = Self.makeEngineConfiguration(database: database, stateSerialization: stateSerialization, delegate: self)
        engine = CKSyncEngine(config)
    }

    private func persistStagedEngineState() throws {
        if let engineStateData { try inbox.persistEngineState(engineStateData) }
    }

    private func recordNameIndex() -> [String: SyncEntityKey] {
        (try? metadataStore.load(forAccountRecordName: accountRecordName))?.recordNameToEntityKey ?? [:]
    }
}
