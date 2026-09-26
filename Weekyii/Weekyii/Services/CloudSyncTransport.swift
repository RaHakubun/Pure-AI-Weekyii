import Foundation

nonisolated enum CloudSyncDatabaseScope: String, Codable, Hashable, Sendable {
    case privateDatabase
}

nonisolated struct CloudSyncRemoteInfrastructure: Hashable, Sendable {
    let zoneName: String
    let databaseScope: CloudSyncDatabaseScope
}

nonisolated enum CloudSyncChange: Hashable, Sendable, Codable {
    case upsert(CloudSyncRecord)
    case delete(SyncEntityKey)

    private enum CodingKeys: String, CodingKey { case upsert, delete }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let record = try values.decodeIfPresent(CloudSyncRecord.self, forKey: .upsert) {
            self = .upsert(record)
        } else {
            self = .delete(try values.decode(SyncEntityKey.self, forKey: .delete))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .upsert(let record): try values.encode(record, forKey: .upsert)
        case .delete(let key): try values.encode(key, forKey: .delete)
        }
    }
}

nonisolated struct CloudSyncChangeBatch: Hashable, Sendable {
    let changes: [CloudSyncChange]
    let nextToken: Data
}

nonisolated struct CloudSyncZoneInspection: Hashable, Sendable {
    let exists: Bool
    let records: [CloudSyncRecord]
}

nonisolated enum CloudSyncRecordOperation: String, Hashable, Sendable {
    case upsert
    case delete
}

nonisolated enum CloudSyncFailureCategory: String, Codable, Hashable, Sendable {
    case transient
    case terminal
    case conflict
    case partialFailure
}

nonisolated struct CloudSyncRecordFailure: Hashable, Sendable {
    let entityKey: SyncEntityKey
    let failure: CloudSyncFailure
}

nonisolated enum CloudSyncFailure: Hashable, Sendable {
    case networkUnavailable
    case networkFailure
    case serviceUnavailable(retryAfter: TimeInterval?)
    case requestRateLimited(retryAfter: TimeInterval?)
    case zoneBusy(retryAfter: TimeInterval?)
    case quotaExceeded
    case notAuthenticated
    case permissionFailure
    case invalidArguments
    case badContainer
    case accountActionRequired
    case entitlementActionRequired
    case transportNotReady
    case serverRecordChanged
    case partialFailure([CloudSyncRecordFailure])
    case other(String)
}

nonisolated enum CloudSyncRecordOutcome: Hashable, Sendable {
    case upserted
    case deleted
    case failed(CloudSyncFailure)
}

nonisolated struct CloudSyncRecordResult: Hashable, Sendable {
    let entityKey: SyncEntityKey
    let outcome: CloudSyncRecordOutcome
    let serverMetadata: Data?
    let recordName: String?

    init(
        entityKey: SyncEntityKey,
        outcome: CloudSyncRecordOutcome,
        serverMetadata: Data? = nil,
        recordName: String? = nil
    ) {
        self.entityKey = entityKey
        self.outcome = outcome
        self.serverMetadata = serverMetadata
        self.recordName = recordName
    }
}

nonisolated enum CloudSyncTransportError: Error, Equatable {
    case transportNotReady
    case invalidChangeToken
    case accountChanged
    case cloudFailure(CloudSyncFailure)
}

/// Domain-only surface consumed by a future reconciliation layer.
protocol CloudSyncTransport: Sendable {
    var databaseScope: CloudSyncDatabaseScope { get async }
    func ensureInfrastructure() async throws -> CloudSyncRemoteInfrastructure
    /// Reads only Weekyii's custom zone and never creates it.
    func inspectRemoteZone() async throws -> CloudSyncZoneInspection
    /// Deletes only Weekyii's custom zone and clears its account-scoped engine state.
    func resetCustomZone() async throws
    func fetchChanges(since token: Data?) async throws -> CloudSyncChangeBatch
    func upsert(_ records: [CloudSyncRecord]) async -> [CloudSyncRecordResult]
    func delete(_ keys: [SyncEntityKey]) async -> [CloudSyncRecordResult]
    func restoreTransportState(_ state: Data?) async
    func persistedTransportState() async -> Data?
}

/// Deterministic offline transport used as the executable D1 contract.
actor InMemoryCloudSyncTransport: CloudSyncTransport {
    private struct LoggedChange: Sendable {
        let sequence: UInt64
        let change: CloudSyncChange
    }

    private struct InjectedFailureKey: Hashable, Sendable {
        let entityKey: SyncEntityKey
        let operation: CloudSyncRecordOperation
    }

    private var records: [SyncEntityKey: CloudSyncRecord] = [:]
    private var changeLog: [LoggedChange] = []
    private var sequence: UInt64 = 0
    private var initialized = false
    private var transportState: Data?
    private var fetchCallCountValue = 0
    private var upsertCallCountValue = 0
    private var injectedFailures: [InjectedFailureKey: [CloudSyncFailure]] = [:]

    init(seedRecords: [CloudSyncRecord] = []) {
        var seededRecords: [SyncEntityKey: CloudSyncRecord] = [:]
        var seededChanges: [LoggedChange] = []
        var seedSequence: UInt64 = 0
        for record in seedRecords.sorted(by: { $0.entityKey < $1.entityKey }) {
            seededRecords[record.entityKey] = record
            seedSequence &+= 1
            seededChanges.append(LoggedChange(sequence: seedSequence, change: .upsert(record)))
        }
        records = seededRecords
        changeLog = seededChanges
        sequence = seedSequence
    }

    var databaseScope: CloudSyncDatabaseScope { .privateDatabase }

    func ensureInfrastructure() async throws -> CloudSyncRemoteInfrastructure {
        initialized = true
        return CloudSyncRemoteInfrastructure(
            zoneName: CloudRecordCodec.customZoneName,
            databaseScope: .privateDatabase
        )
    }

    func inspectRemoteZone() async throws -> CloudSyncZoneInspection {
        CloudSyncZoneInspection(exists: initialized, records: remoteRecords())
    }

    func resetCustomZone() async throws {
        records.removeAll()
        changeLog.removeAll()
        sequence = 0
        initialized = false
        transportState = nil
    }

    func fetchChanges(since token: Data?) async throws -> CloudSyncChangeBatch {
        fetchCallCountValue += 1
        guard initialized else { throw CloudSyncTransportError.transportNotReady }
        let afterSequence = try token.map(decodeToken) ?? 0
        guard afterSequence <= sequence else { throw CloudSyncTransportError.invalidChangeToken }
        let changes = changeLog.filter { $0.sequence > afterSequence }.map(\.change)
        return CloudSyncChangeBatch(changes: changes, nextToken: encodeToken(sequence))
    }

    func upsert(_ incoming: [CloudSyncRecord]) async -> [CloudSyncRecordResult] {
        upsertCallCountValue += 1
        return incoming.map { record in
            guard initialized else {
                return CloudSyncRecordResult(entityKey: record.entityKey, outcome: .failed(.transportNotReady))
            }
            if let failure = takeFailure(for: record.entityKey, operation: .upsert) {
                return CloudSyncRecordResult(entityKey: record.entityKey, outcome: .failed(failure))
            }
            records[record.entityKey] = record
            append(.upsert(record))
            return CloudSyncRecordResult(entityKey: record.entityKey, outcome: .upserted)
        }
    }

    func delete(_ keys: [SyncEntityKey]) async -> [CloudSyncRecordResult] {
        keys.map { key in
            guard initialized else {
                return CloudSyncRecordResult(entityKey: key, outcome: .failed(.transportNotReady))
            }
            if let failure = takeFailure(for: key, operation: .delete) {
                return CloudSyncRecordResult(entityKey: key, outcome: .failed(failure))
            }
            records.removeValue(forKey: key)
            append(.delete(key))
            return CloudSyncRecordResult(entityKey: key, outcome: .deleted)
        }
    }

    func injectFailure(
        _ failure: CloudSyncFailure,
        for key: SyncEntityKey,
        operation: CloudSyncRecordOperation
    ) {
        let failureKey = InjectedFailureKey(entityKey: key, operation: operation)
        injectedFailures[failureKey, default: []].append(failure)
    }

    func remoteRecords() -> [CloudSyncRecord] {
        records.values.sorted { $0.entityKey < $1.entityKey }
    }

    func fetchCallCount() -> Int { fetchCallCountValue }
    func upsertCallCount() -> Int { upsertCallCountValue }

    func restoreTransportState(_ state: Data?) async {
        transportState = state
    }

    func persistedTransportState() async -> Data? { transportState }

    private func append(_ change: CloudSyncChange) {
        sequence &+= 1
        changeLog.append(LoggedChange(sequence: sequence, change: change))
    }

    private func takeFailure(for key: SyncEntityKey, operation: CloudSyncRecordOperation) -> CloudSyncFailure? {
        let failureKey = InjectedFailureKey(entityKey: key, operation: operation)
        guard var queued = injectedFailures[failureKey], !queued.isEmpty else { return nil }
        let next = queued.removeFirst()
        injectedFailures[failureKey] = queued.isEmpty ? nil : queued
        return next
    }

    private func encodeToken(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }

    private func decodeToken(_ token: Data) throws -> UInt64 {
        guard token.count == MemoryLayout<UInt64>.size else {
            throw CloudSyncTransportError.invalidChangeToken
        }
        return token.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: UInt64.self).bigEndian
        }
    }
}
