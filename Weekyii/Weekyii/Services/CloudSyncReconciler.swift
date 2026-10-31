import Foundation

struct CloudSyncEntityFailure: Hashable, Sendable {
    let entityKey: SyncEntityKey
    let failure: CloudSyncFailure
}

struct CloudSyncReconciliationReport: Hashable, Sendable {
    let fetchedRemoteCount: Int
    let localUpserts: Int
    let remoteAppliedUpserts: Int
    let localDeletionsSent: Int
    let remoteDeletionsApplied: Int
    let conflicts: Int
    let semanticHabitDuplicateGroups: Int
    let perRecordFailures: [CloudSyncEntityFailure]
    let pendingChanges: Int
    let successTimestamp: Date?
    /// Remote records this build cannot read. They are skipped (never applied,
    /// overwritten or deleted) and do not count as failures.
    var quarantinedRecords: Int = 0

    var succeeded: Bool { perRecordFailures.isEmpty }
}

enum CloudSyncReconciliationError: LocalizedError, Equatable {
    case invalidLocalSnapshot(String)
    case invalidRemoteRecord(SyncEntityKey)
    case invalidPlannedSnapshot([String])
    case sessionInvalidated
    case accountChanged
    case cloudFailure(CloudSyncFailure)
    case transport(String)
    case metadata(String)

    var errorDescription: String? {
        switch self {
        case .invalidLocalSnapshot(let detail): "本地数据暂时无法安全同步：\(detail)"
        case .invalidRemoteRecord(let key): "iCloud 记录校验失败：\(key)"
        case .invalidPlannedSnapshot(let details): "同步计划引用关系不完整：\(details.joined(separator: "；"))"
        case .sessionInvalidated: "同步会话已变化，已丢弃过期结果。"
        case .accountChanged: "iCloud 账户已变化，已停止处理旧账户的同步请求。"
        case .cloudFailure(let failure): "iCloud 同步失败：\(failure)"
        case .transport(let detail): "iCloud 同步失败：\(detail)"
        case .metadata(let detail): "同步状态保存失败：\(detail)"
        }
    }
}

private struct CloudSyncEntityPlan {
    var desired: [SyncEntityKey: CloudSyncEntity]
    var remoteUpserts: [SyncEntityKey: CloudSyncEntity]
    var remoteDeletes: Set<SyncEntityKey>
    var remoteRecords: [SyncEntityKey: CloudSyncRecord]
    var remoteDeleted: Set<SyncEntityKey>
    var conflicts: Int
    var clearBaselines: Set<SyncEntityKey>
}

/// Per-entity three-way reconciliation. Snapshot/store work remains MainActor
/// isolated; network awaits never hold or freeze the ModelContext.
@MainActor
final class CloudSyncReconciler {
    private let localStore: any CloudSyncLocalStore
    private let transport: any CloudSyncTransport
    private let metadataStore: CloudSyncMetadataStore
    private let accountRecordName: String
    private let now: () -> Date

    init(
        localStore: any CloudSyncLocalStore,
        transport: any CloudSyncTransport,
        metadataStore: CloudSyncMetadataStore = CloudSyncMetadataStore(),
        accountRecordName: String,
        now: @escaping () -> Date = Date.init
    ) {
        self.localStore = localStore
        self.transport = transport
        self.metadataStore = metadataStore
        self.accountRecordName = accountRecordName
        self.now = now
    }

    func reconcile(isSessionCurrent: @MainActor () -> Bool = { true }) async throws -> CloudSyncReconciliationReport {
        let accountHash = try CloudSyncMetadataStore.accountHash(for: accountRecordName)
        var metadata: CloudSyncMetadata
        do {
            metadata = try metadataStore.load(forAccountRecordName: accountRecordName)
                ?? CloudSyncMetadata(accountHash: accountHash)
        } catch {
            throw CloudSyncReconciliationError.metadata("本机同步状态不可读取（\(error)）")
        }

        let beforeNetwork: WeekyiiBusinessSnapshot
        do { beforeNetwork = try localStore.currentSnapshot() }
        catch { throw CloudSyncReconciliationError.invalidLocalSnapshot(error.localizedDescription) }
        let beforeNetworkEntities = try Self.entityMap(beforeNetwork)
        let beforeNetworkHashes = try Self.hashes(beforeNetworkEntities)

        let batch: CloudSyncChangeBatch
        do { batch = try await transport.fetchChanges(since: metadata.remoteChangeToken) }
        catch { throw Self.reconciliationError(for: error) }
        guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }

        let afterNetwork: WeekyiiBusinessSnapshot
        do { afterNetwork = try localStore.currentSnapshot() }
        catch { throw CloudSyncReconciliationError.invalidLocalSnapshot(error.localizedDescription) }
        let currentEntities = try Self.entityMap(afterNetwork)
        let currentHashes = try Self.hashes(currentEntities)
        let concurrentlyEdited = Set(beforeNetworkHashes.keys).union(currentHashes.keys).filter {
            beforeNetworkHashes[$0] != currentHashes[$0]
        }

        var remoteRecords: [SyncEntityKey: CloudSyncRecord] = [:]
        var remoteDeleted: Set<SyncEntityKey> = []
        // Records the transport already set aside plus any that fail to decode
        // here. One unreadable record must never fail the whole cycle (that used
        // to latch sync permanently); it is skipped in both directions instead.
        var newlyQuarantined: [String: String] = [:]
        for change in batch.changes {
            switch change {
            case .upsert(let record):
                let entity: CloudSyncEntity
                do { entity = try CloudRecordCodec.decode(record) }
                catch {
                    newlyQuarantined[record.recordName] = "reconciler decode failed"
                    remoteRecords.removeValue(forKey: record.entityKey)
                    continue
                }
                remoteRecords[entity.key] = record
                remoteDeleted.remove(entity.key)
            case .delete(let key):
                remoteRecords.removeValue(forKey: key)
                remoteDeleted.insert(key)
            }
        }

        let quarantinedKeys: Set<SyncEntityKey> = {
            var probe = metadata
            for (name, reason) in newlyQuarantined { probe.quarantine(recordName: name, reason: reason) }
            let keys = Set(currentEntities.keys).union(metadata.entityBaselines.keys).union(remoteRecords.keys).union(remoteDeleted)
            return keys.filter { probe.isQuarantined($0) }
        }()
        for key in quarantinedKeys {
            remoteRecords.removeValue(forKey: key)
            remoteDeleted.remove(key)
        }

        var plan = try Self.makePlan(
            local: currentEntities,
            localHashes: currentHashes,
            baselines: metadata.entityBaselines,
            remoteRecords: remoteRecords,
            remoteDeleted: remoteDeleted,
            concurrentlyEdited: Set(concurrentlyEdited)
        )

        // Rebase on the latest whole local graph once, immediately before apply.
        // (An earlier version re-read the whole store, attachments included, once
        // per remote-winning entity; the single comparison below already catches
        // every edit that landed after planning, so that loop was pure cost.)
        var safeRemoteUpserts = plan.remoteUpserts
        var safeRemoteDeletes = plan.remoteDeletes
        // An unrelated edit made during fetch is carried through the apply too.
        let latestEntitiesForApply: [SyncEntityKey: CloudSyncEntity]
        let beforeApply: WeekyiiBusinessSnapshot
        do { beforeApply = try localStore.currentSnapshot() }
        catch { throw CloudSyncReconciliationError.invalidLocalSnapshot(error.localizedDescription) }
        guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
        latestEntitiesForApply = try Self.entityMap(beforeApply)
        let beforeApplyHashes = try Self.hashes(latestEntitiesForApply)
        for key in Set(safeRemoteUpserts.keys).union(safeRemoteDeletes) where beforeApplyHashes[key] != currentHashes[key] {
            safeRemoteUpserts.removeValue(forKey: key)
            safeRemoteDeletes.remove(key)
            plan.conflicts += 1
        }
        plan.desired = latestEntitiesForApply
        for (key, entity) in safeRemoteUpserts { plan.desired[key] = entity }
        for key in safeRemoteDeletes { plan.desired.removeValue(forKey: key) }
        plan.remoteUpserts = safeRemoteUpserts
        plan.remoteDeletes = safeRemoteDeletes

        var duplicateGroups = 0
        Self.convergeHabitDayDuplicates(
            entities: &plan.desired,
            localEntities: currentEntities,
            knownRemoteKeys: Set(metadata.entityBaselines.keys).union(remoteRecords.keys),
            deleteKeys: &plan.remoteDeletes,
            upsertKeys: &plan.remoteUpserts,
            groupCount: &duplicateGroups
        )

        Self.convergeHabitTaskDuplicates(
            entities: &plan.desired,
            localEntities: currentEntities,
            knownRemoteKeys: Set(metadata.entityBaselines.keys).union(remoteRecords.keys),
            deleteKeys: &plan.remoteDeletes,
            groupCount: &duplicateGroups
        )

        let desiredSnapshot = Self.snapshot(from: plan.desired)
        let diagnostics = WeekyiiSnapshotRepository.validate(desiredSnapshot)
        guard diagnostics.isEmpty else {
            throw CloudSyncReconciliationError.invalidPlannedSnapshot(diagnostics.map(\.description))
        }

        guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
        if beforeApply != desiredSnapshot {
            do { try localStore.apply(desiredSnapshot) }
            catch { throw CloudSyncReconciliationError.invalidLocalSnapshot(error.localizedDescription) }
        }

        guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
        let finalEntities = try Self.entityMap(desiredSnapshot)
        let finalHashes = try Self.hashes(finalEntities)
        let effectiveRemoteHashes = Self.effectiveRemoteHashes(
            keys: Set(finalEntities.keys).union(metadata.entityBaselines.keys).union(remoteRecords.keys).union(remoteDeleted),
            baselines: metadata.entityBaselines,
            remoteRecords: remoteRecords,
            remoteDeleted: remoteDeleted
        )

        var upsertsToSend: [CloudSyncRecord] = []
        var deletesToSend: [SyncEntityKey] = []
        let candidateKeys = Set(finalEntities.keys).union(metadata.entityBaselines.keys).union(remoteRecords.keys).union(remoteDeleted)
        for key in candidateKeys.sorted() where !quarantinedKeys.contains(key) {
            if let entity = finalEntities[key], finalHashes[key] != effectiveRemoteHashes[key] {
                var record = try CloudRecordCodec.encode(entity)
                record = Self.applyingServerMetadata(
                    metadata.entityBaselines[key]?.serverMetadata ?? remoteRecords[key]?.serverMetadata,
                    to: record
                )
                upsertsToSend.append(record)
            } else if finalEntities[key] == nil, effectiveRemoteHashes[key] != nil {
                deletesToSend.append(key)
            }
        }

        var resultsByKey: [SyncEntityKey: CloudSyncRecordResult] = [:]
        if !upsertsToSend.isEmpty {
            guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
            for result in await transport.upsert(upsertsToSend) { resultsByKey[result.entityKey] = result }
            guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
        }
        if !deletesToSend.isEmpty {
            guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
            for result in await transport.delete(deletesToSend) { resultsByKey[result.entityKey] = result }
            guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
        }
        guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }

        // A serverRecordChanged is a local-first conflict, not a transport retry.
        // Read the latest server version and perform at most one metadata-based resend.
        var serverConflictKeys: Set<SyncEntityKey> = []
        // Inbox position covered by each successful resend. Everything queued up
        // to there for that key is superseded by the version just written.
        var resendCoverage: [SyncEntityKey: UInt64] = [:]
        for (key, result) in resultsByKey.sorted(by: { $0.key < $1.key }) {
            guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
            guard case .failed(.serverRecordChanged) = result.outcome,
                  let entity = finalEntities[key]
            else { continue }
            serverConflictKeys.insert(key)
            do {
                let latestServer = try await transport.fetchChanges(since: batch.nextToken)
                guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
                let latestChange = latestServer.changes.last(where: { change in
                    switch change {
                    case .upsert(let value): return value.entityKey == key
                    case .delete(let deleted): return deleted == key
                    }
                })
                var resend = try CloudRecordCodec.encode(entity)
                switch latestChange {
                case .upsert(let remote)?:
                    resend = Self.applyingServerMetadata(remote.serverMetadata, to: resend)
                case .delete(_)?, .none:
                    // The server no longer has this record (deleted on another
                    // device, CloudKit `unknownItem`). The local edit wins: send it
                    // as a brand-new record without stale system fields.
                    resend = Self.applyingServerMetadata(nil, to: resend)
                }
                let retryResults = await transport.upsert([resend])
                guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
                if let retry = retryResults.first {
                    resultsByKey[key] = retry
                    if Self.isUpsertSuccess(retry),
                       let covered = try? CloudSyncDurableInbox.decodeToken(latestServer.nextToken) {
                        resendCoverage[key] = covered
                    }
                }
            } catch let error as CloudSyncReconciliationError {
                throw error
            } catch {
                resultsByKey[key] = CloudSyncRecordResult(entityKey: key, outcome: .failed(.other("Conflict refresh failed")))
            }
        }

        var failures: [CloudSyncEntityFailure] = []
        for (key, result) in resultsByKey {
            if case .failed(let failure) = result.outcome {
                failures.append(CloudSyncEntityFailure(entityKey: key, failure: failure))
            }
        }
        failures.sort { $0.entityKey < $1.entityKey }
        let failedKeys = Set(failures.map(\.entityKey))

        // Compute only the baseline delta. The transport may have advanced its
        // engine state and reverse index during the network awaits above, so the
        // final commit must apply this delta to the latest account metadata.
        var baselineUpdates: [SyncEntityKey: CloudSyncEntityBaseline] = [:]
        var baselineDeletes: Set<SyncEntityKey> = []
        // Quarantined keys keep their old baseline, so a local edit made while the
        // server copy was unreadable is still seen as an edit once it is readable.
        for key in candidateKeys.sorted() where !failedKeys.contains(key) && !quarantinedKeys.contains(key) {
            if finalEntities[key] != nil, let hash = finalHashes[key] {
                let sendResult = resultsByKey[key]
                let remoteRecord = remoteRecords[key]
                let serverMetadata: Data? = {
                    if case .upserted? = sendResult?.outcome { return sendResult?.serverMetadata }
                    return remoteRecord?.serverMetadata ?? metadata.entityBaselines[key]?.serverMetadata
                }()
                let recordName = sendResult?.recordName
                    ?? remoteRecord?.recordName
                    ?? metadata.entityBaselines[key]?.recordName
                    ?? CKRecordNameCodec.recordName(for: key)
                if sendResult == nil || Self.isUpsertSuccess(sendResult) || effectiveRemoteHashes[key] == hash {
                    baselineUpdates[key] = CloudSyncEntityBaseline(
                        lastSyncedHash: hash,
                        serverMetadata: serverMetadata,
                        recordName: recordName
                    )
                }
            } else if Self.isDeleteSuccessOrUnneeded(resultsByKey[key], remoteHash: effectiveRemoteHashes[key]) {
                baselineDeletes.insert(key)
            }
        }

        let completeSuccess = failures.isEmpty
        let acknowledgedSequence = try CloudSyncDurableInbox.decodeToken(batch.nextToken)
        guard isSessionCurrent() else { throw CloudSyncReconciliationError.sessionInvalidated }
        let committed: CloudSyncMetadata
        do {
            committed = try metadataStore.update(forAccountRecordName: accountRecordName) { latest in
                for key in baselineDeletes { latest.forget(key) }
                for (key, baseline) in baselineUpdates {
                    var updated = baseline
                    if updated.serverMetadata == nil {
                        updated.serverMetadata = latest.entityBaselines[key]?.serverMetadata
                    }
                    latest.entityBaselines[key] = updated
                    if let name = updated.recordName {
                        latest.remember(key, recordName: name, serverMetadata: updated.serverMetadata)
                    }
                }
                latest.zoneInitialized = true
                // Per-key acknowledgement, even after a partial failure: entries for
                // keys whose baseline was just committed are settled and must not
                // replay over the local winner. Failed keys keep their entries.
                let settled = Set(baselineUpdates.keys).union(baselineDeletes)
                latest.discardPendingChanges(for: settled, through: acknowledgedSequence)
                for (key, sequence) in resendCoverage where settled.contains(key) {
                    latest.discardPendingChanges(for: [key], through: sequence)
                }
                for (name, reason) in newlyQuarantined { latest.quarantine(recordName: name, reason: reason) }
                if completeSuccess { latest.acknowledgeChanges(through: acknowledgedSequence, token: batch.nextToken) }
                latest.lastAttempt = now()
                if completeSuccess {
                    latest.lastSuccessfulSync = latest.lastAttempt
                    latest.lastFailure = nil
                    latest.lastFailureCategory = nil
                    latest.lastFailureReason = nil
                    latest.automaticRetrySuppressed = false
                } else {
                    latest.lastFailure = "部分同步失败（\(failures.count) 项）"
                    latest.lastFailureCategory = .partialFailure
                }
            }
        }
        catch { throw CloudSyncReconciliationError.metadata(error.localizedDescription) }

        return CloudSyncReconciliationReport(
            fetchedRemoteCount: batch.changes.count,
            localUpserts: resultsByKey.values.filter { Self.isUpsertSuccess($0) }.count,
            remoteAppliedUpserts: plan.remoteUpserts.count,
            localDeletionsSent: resultsByKey.values.filter { if case .deleted = $0.outcome { return true }; return false }.count,
            remoteDeletionsApplied: plan.remoteDeletes.count,
            conflicts: plan.conflicts + serverConflictKeys.count,
            semanticHabitDuplicateGroups: duplicateGroups,
            perRecordFailures: failures,
            pendingChanges: failures.count,
            successTimestamp: completeSuccess ? committed.lastSuccessfulSync : nil,
            quarantinedRecords: committed.quarantinedRecordCount
        )
    }

    // MARK: Planning

    private static func makePlan(
        local: [SyncEntityKey: CloudSyncEntity],
        localHashes: [SyncEntityKey: String],
        baselines: [SyncEntityKey: CloudSyncEntityBaseline],
        remoteRecords: [SyncEntityKey: CloudSyncRecord],
        remoteDeleted: Set<SyncEntityKey>,
        concurrentlyEdited: Set<SyncEntityKey>
    ) throws -> CloudSyncEntityPlan {
        var plan = CloudSyncEntityPlan(
            desired: local,
            remoteUpserts: [:],
            remoteDeletes: [],
            remoteRecords: remoteRecords,
            remoteDeleted: remoteDeleted,
            conflicts: 0,
            clearBaselines: []
        )
        let allKeys = Set(local.keys).union(baselines.keys).union(remoteRecords.keys).union(remoteDeleted)
        for key in allKeys.sorted() {
            let localEntity = local[key]
            let localHash = localHashes[key]
            let baseline = baselines[key]?.lastSyncedHash
            let remoteRecord = remoteRecords[key]
            let remoteWasDeleted = remoteDeleted.contains(key)

            guard let baseline else {
                if let remoteRecord {
                    let remoteEntity: CloudSyncEntity
                    do { remoteEntity = try CloudRecordCodec.decode(remoteRecord) }
                    catch { throw CloudSyncReconciliationError.invalidRemoteRecord(key) }
                    if local[key] != nil, localHash != remoteRecord.payloadHash {
                        plan.conflicts += 1
                    } else if local[key] == nil {
                        plan.remoteUpserts[key] = remoteEntity
                        plan.desired[key] = remoteEntity
                    }
                } else if remoteWasDeleted {
                    if localEntity != nil {
                        plan.conflicts += 1
                    } else {
                        plan.clearBaselines.insert(key)
                    }
                } else if localEntity != nil {
                    // New local entity; desired already contains the local winner.
                }
                continue
            }

            let localChanged = localHash != baseline
            let remoteChanged: Bool
            if let remoteRecord { remoteChanged = remoteRecord.payloadHash != baseline }
            else { remoteChanged = remoteWasDeleted }

            guard remoteChanged else {
                if !localChanged { continue }
                if localEntity == nil { plan.remoteDeletes.insert(key) }
                continue
            }

            if !localChanged && !concurrentlyEdited.contains(key) {
                if let remoteRecord {
                    let entity: CloudSyncEntity
                    do { entity = try CloudRecordCodec.decode(remoteRecord) }
                    catch { throw CloudSyncReconciliationError.invalidRemoteRecord(key) }
                    plan.remoteUpserts[key] = entity
                    plan.desired[key] = entity
                } else {
                    plan.remoteDeletes.insert(key)
                    plan.desired.removeValue(forKey: key)
                }
            } else {
                plan.conflicts += 1
                if let localEntity {
                    plan.desired[key] = localEntity
                } else if remoteRecord != nil {
                    plan.remoteDeletes.insert(key)
                    plan.desired.removeValue(forKey: key)
                } else {
                    plan.clearBaselines.insert(key)
                    plan.desired.removeValue(forKey: key)
                }
            }
        }
        return plan
    }

    private static func effectiveRemoteHashes(
        keys: Set<SyncEntityKey>,
        baselines: [SyncEntityKey: CloudSyncEntityBaseline],
        remoteRecords: [SyncEntityKey: CloudSyncRecord],
        remoteDeleted: Set<SyncEntityKey>
    ) -> [SyncEntityKey: String] {
        var result: [SyncEntityKey: String] = [:]
        for key in keys {
            if remoteDeleted.contains(key) { continue }
            if let record = remoteRecords[key] { result[key] = record.payloadHash }
            else if let baseline = baselines[key] { result[key] = baseline.lastSyncedHash }
        }
        return result
    }

    private static func convergeHabitDayDuplicates(
        entities: inout [SyncEntityKey: CloudSyncEntity],
        localEntities: [SyncEntityKey: CloudSyncEntity],
        knownRemoteKeys: Set<SyncEntityKey>,
        deleteKeys: inout Set<SyncEntityKey>,
        upsertKeys: inout [SyncEntityKey: CloudSyncEntity],
        groupCount: inout Int
    ) {
        let records = entities.values.compactMap { entity -> HabitDayRecordSnapshot? in
            if case .habitDayRecord(let value) = entity, value.habitId != nil { return value }
            return nil
        }
        let groups = Dictionary(grouping: records, by: { "\($0.habitId!.uuidString)|\($0.dayId)" })
        for group in groups.values where group.count > 1 {
            groupCount += 1
            let localRecords = group.filter { localEntities[$0.entityKey] != nil }
            let survivor = (localRecords.isEmpty ? group : localRecords)
                .sorted { $0.id.uuidString < $1.id.uuidString }[0]
            let strongest = group.map(\.statusRaw).sorted { lhs, rhs in
                if statusRank(lhs) != statusRank(rhs) { return statusRank(lhs) < statusRank(rhs) }
                return lhs < rhs
            }.last ?? survivor.statusRaw
            let completedRecords = group.filter { $0.statusRaw == HabitDayRecordStatus.completed.rawValue }
            let completedAt = completedRecords.compactMap(\.completedAt).min()
                ?? (strongest == HabitDayRecordStatus.completed.rawValue ? completedRecords.map(\.createdAt).min() : nil)
            let merged = HabitDayRecordSnapshot(
                id: survivor.id,
                habitId: survivor.habitId,
                dayId: survivor.dayId,
                statusRaw: strongest,
                createdAt: survivor.createdAt,
                completedAt: completedAt
            )
            entities[survivor.entityKey] = .habitDayRecord(merged)
            if knownRemoteKeys.contains(survivor.entityKey) { upsertKeys[survivor.entityKey] = .habitDayRecord(merged) }
            for loser in group where loser.id != survivor.id {
                entities.removeValue(forKey: loser.entityKey)
                if knownRemoteKeys.contains(loser.entityKey) { deleteKeys.insert(loser.entityKey) }
            }
        }
    }

    /// Two devices that materialised the same habit on the same day before task
    /// ids became deterministic each hold their own copy. Keep one: the most
    /// advanced (completed > focus > frozen > draft), then the deterministic id,
    /// then a local one, then the lowest id. Only untouched duplicates (still in
    /// the draft zone, no attachments) are removed, so no user work is dropped.
    private static func convergeHabitTaskDuplicates(
        entities: inout [SyncEntityKey: CloudSyncEntity],
        localEntities: [SyncEntityKey: CloudSyncEntity],
        knownRemoteKeys: Set<SyncEntityKey>,
        deleteKeys: inout Set<SyncEntityKey>,
        groupCount: inout Int
    ) {
        let tasks = entities.values.compactMap { entity -> TaskSnapshot? in
            if case .task(let value) = entity, value.habitId != nil, value.dayId != nil { return value }
            return nil
        }
        let groups = Dictionary(grouping: tasks, by: { "\($0.habitId!.uuidString)|\($0.dayId!)" })
        for group in groups.values where group.count > 1 {
            func rank(_ task: TaskSnapshot) -> (Int, Int, Int, String) {
                let zone: Int
                switch task.zone {
                case .complete: zone = 3
                case .focus: zone = 2
                case .frozen: zone = 1
                case .draft: zone = 0
                }
                let deterministic = task.id == HabitDeterministicID.task(habitId: task.habitId!, dayId: task.dayId!) ? 1 : 0
                let local = localEntities[task.entityKey] != nil ? 1 : 0
                return (zone, deterministic, local, task.id.uuidString)
            }
            let survivor = group.max { lhs, rhs in
                let l = rank(lhs), r = rank(rhs)
                if l.0 != r.0 { return l.0 < r.0 }
                if l.1 != r.1 { return l.1 < r.1 }
                if l.2 != r.2 { return l.2 < r.2 }
                return l.3 > r.3
            }!
            var removed = false
            for loser in group where loser.id != survivor.id && loser.zone == .draft && loser.attachmentIds.isEmpty {
                entities.removeValue(forKey: loser.entityKey)
                // Counted even when local-only, so the UI refreshes; the upload
                // of the deletion is derived from the final graph as usual.
                deleteKeys.insert(loser.entityKey)
                removed = true
            }
            if removed { groupCount += 1 }
        }
    }

    private static func statusRank(_ raw: String) -> Int {
        switch HabitDayRecordStatus(rawValue: raw) {
        case .completed: 3
        case .missed: 2
        case .pending: 1
        case .none: 0
        }
    }

    // MARK: Snapshot conversion / hashing

    private static func entityMap(_ snapshot: WeekyiiBusinessSnapshot) throws -> [SyncEntityKey: CloudSyncEntity] {
        var result: [SyncEntityKey: CloudSyncEntity] = [:]
        for entity in entities(in: snapshot) { result[entity.key] = entity }
        guard result.count == snapshot.entityKeys().count else {
            throw CloudSyncReconciliationError.invalidLocalSnapshot("存在重复业务 ID")
        }
        return result
    }

    private static func entities(in snapshot: WeekyiiBusinessSnapshot) -> [CloudSyncEntity] {
        snapshot.weeks.map(CloudSyncEntity.week)
            + snapshot.days.map(CloudSyncEntity.day)
            + snapshot.tasks.map(CloudSyncEntity.task)
            + snapshot.suspendedTasks.map(CloudSyncEntity.suspendedTask)
            + snapshot.attachments.map(CloudSyncEntity.attachment)
            + snapshot.projects.map(CloudSyncEntity.project)
            + snapshot.mindStamps.map(CloudSyncEntity.mindStamp)
            + snapshot.taskTypes.map(CloudSyncEntity.taskType)
            + snapshot.habits.map(CloudSyncEntity.habit)
            + snapshot.habitDayRecords.map(CloudSyncEntity.habitDayRecord)
    }

    private static func hashes(_ entities: [SyncEntityKey: CloudSyncEntity]) throws -> [SyncEntityKey: String] {
        try entities.mapValues { try CloudRecordCodec.encode($0).payloadHash }
    }

    static func snapshot(from entities: [SyncEntityKey: CloudSyncEntity]) -> WeekyiiBusinessSnapshot {
        var weeks: [WeekSnapshot] = []; var days: [DaySnapshot] = []; var tasks: [TaskSnapshot] = []
        var suspended: [SuspendedTaskSnapshot] = []; var attachments: [AttachmentSnapshot] = []
        var projects: [ProjectSnapshot] = []; var stamps: [MindStampSnapshot] = []; var types: [TaskTypeSnapshot] = []
        var habits: [HabitSnapshot] = []; var records: [HabitDayRecordSnapshot] = []
        for entity in entities.values {
            switch entity {
            case .week(let value): weeks.append(value)
            case .day(let value): days.append(value)
            case .task(let value): tasks.append(value)
            case .suspendedTask(let value): suspended.append(value)
            case .attachment(let value): attachments.append(value)
            case .project(let value): projects.append(value)
            case .mindStamp(let value): stamps.append(value)
            case .taskType(let value): types.append(value)
            case .habit(let value): habits.append(value)
            case .habitDayRecord(let value): records.append(value)
            }
        }
        return WeekyiiBusinessSnapshot(weeks: weeks, days: days, tasks: tasks, suspendedTasks: suspended, attachments: attachments, projects: projects, mindStamps: stamps, taskTypes: types, habits: habits, habitDayRecords: records)
    }

    private static func applyingServerMetadata(_ metadata: Data?, to value: CloudSyncRecord) -> CloudSyncRecord {
        CloudSyncRecord(
            zoneName: value.zoneName, recordType: value.recordType, recordName: value.recordName,
            kind: value.kind, businessId: value.businessId, payloadVersion: value.payloadVersion,
            payload: value.payload, payloadHash: value.payloadHash, blob: value.blob,
            serverMetadata: metadata
        )
    }

    private static func isUpsertSuccess(_ result: CloudSyncRecordResult?) -> Bool {
        guard let result else { return false }
        if case .upserted = result.outcome { return true }
        return false
    }

    private static func isDeleteSuccessOrUnneeded(_ result: CloudSyncRecordResult?, remoteHash: String?) -> Bool {
        if remoteHash == nil { return result == nil || (result.map { if case .deleted = $0.outcome { return true }; return false } ?? false) }
        guard let result else { return false }
        if case .deleted = result.outcome { return true }
        return false
    }

    private static func reconciliationError(for error: Error) -> CloudSyncReconciliationError {
        if case CloudSyncTransportError.accountChanged = error {
            return .accountChanged
        }
        if case CloudSyncTransportError.cloudFailure(let failure) = error {
            return .cloudFailure(failure)
        }
        return .transport(error.localizedDescription)
    }
}
