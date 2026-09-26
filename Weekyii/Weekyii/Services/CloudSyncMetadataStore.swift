import Foundation
import CryptoKit
import Darwin

nonisolated struct CloudSyncPendingChange: Codable, Hashable, Sendable {
    let sequence: UInt64
    let change: CloudSyncChange
}

nonisolated enum CloudSyncLatchedFailureReason: String, Codable, Hashable, Sendable {
    case network
    case temporaryService
    case quota
    case authentication
    case permission
    case configuration
    case entitlement
    case other
}

nonisolated struct CloudSyncEntityBaseline: Codable, Hashable, Sendable {
    var lastSyncedHash: String
    var serverMetadata: Data?
    /// Physical CloudKit identity needed to interpret a later deletion event.
    /// Optional so metadata files written by D1 continue to decode unchanged.
    var recordName: String?

    init(lastSyncedHash: String, serverMetadata: Data? = nil, recordName: String? = nil) {
        self.lastSyncedHash = lastSyncedHash
        self.serverMetadata = serverMetadata
        self.recordName = recordName
    }
}

nonisolated struct CloudSyncMetadata: Codable, Hashable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var accountHash: String
    var syncEngineState: Data?
    var entityBaselines: [SyncEntityKey: CloudSyncEntityBaseline]
    var serverMetadata: Data?
    var lastSuccessfulSync: Date?
    var lastAttempt: Date?
    var lastFailure: String?
    var lastFailureCategory: CloudSyncFailureCategory?
    var lastFailureReason: CloudSyncLatchedFailureReason?
    var automaticRetrySuppressed: Bool
    var zoneInitialized: Bool
    /// Durable reverse index for CloudKit deletion events, which carry only a
    /// physical record name and no deleted record payload.
    var recordNameToEntityKey: [String: SyncEntityKey]?
    /// Application-level cursor into transport-delivered changes. Kept separate
    /// from CKSyncEngine serialization so reconciliation can commit it per cycle.
    var remoteChangeToken: Data?
    /// Nil denotes metadata written before durable delivery was introduced.
    /// The CK transport then discards its old engine cursor and performs a full fetch.
    var pendingRemoteChanges: [CloudSyncPendingChange]?
    var changeSequence: UInt64?
    /// A pre-inbox engine cursor may have consumed a delete that a full CK fetch
    /// cannot replay. Persist this flag until a current zone snapshot is journaled.
    var needsFullRemoteSnapshot: Bool?

    init(accountHash: String) {
        formatVersion = Self.currentFormatVersion
        self.accountHash = accountHash
        syncEngineState = nil
        entityBaselines = [:]
        serverMetadata = nil
        lastSuccessfulSync = nil
        lastAttempt = nil
        lastFailure = nil
        lastFailureCategory = nil
        lastFailureReason = nil
        automaticRetrySuppressed = false
        zoneInitialized = false
        recordNameToEntityKey = [:]
        remoteChangeToken = nil
        pendingRemoteChanges = []
        changeSequence = 0
        needsFullRemoteSnapshot = false
    }

    mutating func remember(_ key: SyncEntityKey, recordName: String, serverMetadata: Data? = nil) {
        var index = recordNameToEntityKey ?? [:]
        index[recordName] = key
        recordNameToEntityKey = index
        if var baseline = entityBaselines[key] {
            if let serverMetadata { baseline.serverMetadata = serverMetadata }
            baseline.recordName = recordName
            entityBaselines[key] = baseline
        }
    }

    func entityKey(forRecordName recordName: String) -> SyncEntityKey? {
        recordNameToEntityKey?[recordName]
            ?? entityBaselines.first(where: { $0.value.recordName == recordName })?.key
    }

    mutating func forget(_ key: SyncEntityKey) {
        entityBaselines.removeValue(forKey: key)
        recordNameToEntityKey = recordNameToEntityKey?.filter { $0.value != key }
    }

    mutating func enqueue(_ change: CloudSyncChange) {
        let next = (changeSequence ?? 0) &+ 1
        changeSequence = next
        pendingRemoteChanges = (pendingRemoteChanges ?? []) + [CloudSyncPendingChange(sequence: next, change: change)]
    }

    mutating func acknowledgeChanges(through sequence: UInt64, token: Data) {
        remoteChangeToken = token
        pendingRemoteChanges?.removeAll { $0.sequence <= sequence }
    }
}

nonisolated enum CloudSyncMetadataStoreError: Error, Equatable {
    case corruptedMetadata
    case accountHashMismatch
    case unsupportedFormatVersion
}

/// Atomic, device-local transport state. The account key on disk is one-way hashed.
nonisolated struct CloudSyncMetadataStore: Sendable {
    private let rootURL: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.rootURL = applicationSupport
                .appendingPathComponent("Weekyii", isDirectory: true)
                .appendingPathComponent("CloudSyncState", isDirectory: true)
        }
    }

    static func accountHash(for accountRecordName: String) throws -> String {
        guard !accountRecordName.isEmpty else { throw CloudSyncMetadataStoreError.accountHashMismatch }
        let digest = SHA256.hash(data: Data(accountRecordName.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func metadataFileURL(forAccountRecordName accountRecordName: String) throws -> URL {
        let hashedAccount = try Self.accountHash(for: accountRecordName)
        return rootURL.appendingPathComponent(hashedAccount, isDirectory: true)
            .appendingPathComponent("metadata.json", isDirectory: false)
    }

    /// Device-local pointer to the previously active CloudKit account. It stores
    /// only a one-way account hash so a changed account can be paused after relaunch.
    func loadActiveAccountHash() throws -> String? {
        let url = rootURL.appendingPathComponent("active-account.sha256", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let value = String(data: try Data(contentsOf: url), encoding: .utf8),
              value.count == 64,
              value.allSatisfy({ $0.isHexDigit }) else {
            throw CloudSyncMetadataStoreError.corruptedMetadata
        }
        return value
    }

    func saveActiveAccountHash(_ hash: String) throws {
        guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else {
            throw CloudSyncMetadataStoreError.accountHashMismatch
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data(hash.utf8).write(
            to: rootURL.appendingPathComponent("active-account.sha256", isDirectory: false),
            options: [.atomic]
        )
    }

    var accountResolutionJournalFileURL: URL {
        rootURL.appendingPathComponent("account-resolution.json", isDirectory: false)
    }

    func loadAccountResolutionJournal() throws -> CloudAccountResolutionJournal? {
        let url = accountResolutionJournalFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let journal = try JSONDecoder().decode(CloudAccountResolutionJournal.self, from: Data(contentsOf: url))
            guard Self.isAccountHash(journal.targetAccountHash),
                  journal.previousAccountHash.map(Self.isAccountHash) ?? true else {
                throw CloudSyncMetadataStoreError.accountHashMismatch
            }
            return journal
        } catch let error as CloudSyncMetadataStoreError {
            throw error
        } catch {
            throw CloudSyncMetadataStoreError.corruptedMetadata
        }
    }

    func saveAccountResolutionJournal(_ journal: CloudAccountResolutionJournal) throws {
        guard Self.isAccountHash(journal.targetAccountHash),
              journal.previousAccountHash.map(Self.isAccountHash) ?? true else {
            throw CloudSyncMetadataStoreError.accountHashMismatch
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(journal).write(to: accountResolutionJournalFileURL, options: [.atomic])
    }

    func clearAccountResolutionJournal() throws {
        let url = accountResolutionJournalFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func isAccountHash(_ hash: String) -> Bool {
        hash.count == 64 && hash.allSatisfy(\.isHexDigit)
    }

    func load(forAccountRecordName accountRecordName: String) throws -> CloudSyncMetadata? {
        let fileURL = try metadataFileURL(forAccountRecordName: accountRecordName)
        return try load(at: fileURL, accountRecordName: accountRecordName)
    }

    private func load(at fileURL: URL, accountRecordName: String) throws -> CloudSyncMetadata? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let decoded: CloudSyncMetadata
        do {
            let data = try Data(contentsOf: fileURL)
            decoded = try Self.decoder().decode(CloudSyncMetadata.self, from: data)
        } catch {
            throw CloudSyncMetadataStoreError.corruptedMetadata
        }

        guard decoded.accountHash == (try Self.accountHash(for: accountRecordName)) else {
            throw CloudSyncMetadataStoreError.accountHashMismatch
        }
        guard decoded.formatVersion == CloudSyncMetadata.currentFormatVersion else {
            throw CloudSyncMetadataStoreError.unsupportedFormatVersion
        }
        return decoded
    }

    func save(_ metadata: CloudSyncMetadata, forAccountRecordName accountRecordName: String) throws {
        let fileURL = try metadataFileURL(forAccountRecordName: accountRecordName)
        try withAccountLock(at: fileURL) {
            try saveUnlocked(metadata, at: fileURL, accountRecordName: accountRecordName)
        }
    }

    /// All production writers use this account-scoped transaction. The closure
    /// sees the latest disk value, so a network await cannot cause a stale
    /// whole-object write to erase engine state, inbox entries or latch changes.
    @discardableResult
    func update(
        forAccountRecordName accountRecordName: String,
        _ body: (inout CloudSyncMetadata) throws -> Void
    ) throws -> CloudSyncMetadata {
        let fileURL = try metadataFileURL(forAccountRecordName: accountRecordName)
        return try withAccountLock(at: fileURL) {
            var current = try load(at: fileURL, accountRecordName: accountRecordName)
                ?? CloudSyncMetadata(accountHash: Self.accountHash(for: accountRecordName))
            try body(&current)
            try saveUnlocked(current, at: fileURL, accountRecordName: accountRecordName)
            return current
        }
    }

    /// Replaces only one account's local synchronization state. Used when fresh
    /// cloud data becomes authoritative so stale baselines, engine cursors,
    /// reverse indexes, and inbox entries cannot leak into the new session.
    func resetSynchronizationState(forAccountRecordName accountRecordName: String) throws {
        let hash = try Self.accountHash(for: accountRecordName)
        try update(forAccountRecordName: accountRecordName) { metadata in
            metadata = CloudSyncMetadata(accountHash: hash)
        }
    }

    private func saveUnlocked(
        _ metadata: CloudSyncMetadata,
        at fileURL: URL,
        accountRecordName: String
    ) throws {
        let expectedHash = try Self.accountHash(for: accountRecordName)
        guard metadata.accountHash == expectedHash else {
            throw CloudSyncMetadataStoreError.accountHashMismatch
        }
        guard metadata.formatVersion == CloudSyncMetadata.currentFormatVersion else {
            throw CloudSyncMetadataStoreError.unsupportedFormatVersion
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder().encode(metadata)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func withAccountLock<T>(at fileURL: URL, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let accountDirectory = fileURL.deletingLastPathComponent()
        let lockURL = rootURL.appendingPathComponent(accountDirectory.lastPathComponent + ".metadata.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { _ = flock(descriptor, LOCK_UN); _ = close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        return try body()
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

/// A durable, account-scoped inbox between CKSyncEngine and reconciliation.
/// CloudKit's engine cursor is committed only after fetched events are in this
/// inbox. Reconciliation advances its own cursor and prunes the inbox atomically
/// with the corresponding entity baselines.
nonisolated struct CloudSyncDurableInbox: Sendable {
    let store: CloudSyncMetadataStore
    let accountRecordName: String

    /// Existing pre-inbox state cannot prove that delivered changes survived.
    /// Rebuild it by restarting CKSyncEngine from a nil state and refetching.
    func prepare() throws -> (metadata: CloudSyncMetadata, needsAuthoritativeSnapshot: Bool) {
        let metadata = try store.update(forAccountRecordName: accountRecordName) { current in
            if current.pendingRemoteChanges == nil || current.changeSequence == nil {
                current.syncEngineState = nil
                current.remoteChangeToken = nil
                current.pendingRemoteChanges = []
                current.changeSequence = 0
                current.needsFullRemoteSnapshot = true
            }
        }
        return (metadata, metadata.needsFullRemoteSnapshot == true)
    }

    func append(upserts: [CloudSyncRecord], deletedRecordNames: [String]) throws {
        try store.update(forAccountRecordName: accountRecordName) { metadata in
            for record in upserts {
                metadata.remember(record.entityKey, recordName: record.recordName, serverMetadata: record.serverMetadata)
                metadata.enqueue(.upsert(record))
            }
            for recordName in deletedRecordNames {
                guard let key = metadata.entityKey(forRecordName: recordName) else { continue }
                metadata.enqueue(.delete(key))
            }
        }
    }

    /// One-time repair when upgrading metadata written by the old process-local
    /// delivery scheme. Comparing a complete zone snapshot with old baselines
    /// recovers deletes that a fresh CKSyncEngine cursor cannot deliver.
    func appendAuthoritativeSnapshot(_ records: [CloudSyncRecord]) throws {
        try store.update(forAccountRecordName: accountRecordName) { metadata in
            guard metadata.needsFullRemoteSnapshot == true else { return }
            let remoteKeys = Set(records.map(\.entityKey))
            for record in records {
                metadata.remember(record.entityKey, recordName: record.recordName, serverMetadata: record.serverMetadata)
                metadata.enqueue(.upsert(record))
            }
            for key in metadata.entityBaselines.keys.sorted() where !remoteKeys.contains(key) {
                metadata.enqueue(.delete(key))
            }
            metadata.needsFullRemoteSnapshot = false
        }
    }

    func batch(since token: Data?) throws -> CloudSyncChangeBatch {
        let after = try token.map(Self.decodeToken) ?? 0
        let metadata = try store.load(forAccountRecordName: accountRecordName)
        let sequence = metadata?.changeSequence ?? 0
        guard after <= sequence else { throw CloudSyncTransportError.invalidChangeToken }
        let changes = metadata?.pendingRemoteChanges?.filter { $0.sequence > after }.map(\.change) ?? []
        return CloudSyncChangeBatch(changes: changes, nextToken: Self.encodeToken(sequence))
    }

    func persistEngineState(_ state: Data) throws {
        try store.update(forAccountRecordName: accountRecordName) { $0.syncEngineState = state }
    }

    static func encodeToken(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }

    static func decodeToken(_ token: Data) throws -> UInt64 {
        guard token.count == MemoryLayout<UInt64>.size else {
            throw CloudSyncTransportError.invalidChangeToken
        }
        return token.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
    }
}
