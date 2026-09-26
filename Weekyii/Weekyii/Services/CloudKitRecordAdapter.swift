import CloudKit
import Foundation

nonisolated enum CloudKitRecordAdapterError: Error, Equatable {
    case wrongZone
    case wrongRecordType
    case malformedField(String)
    case malformedSystemMetadata
    case recordNameMismatch
    case malformedPayloadIdentity
    case missingAssetFile
}

/// CloudKit's opaque system fields travel through the domain as `Data`; no
/// `CKRecord` escapes this file's transport boundary.
nonisolated enum CloudKitSystemMetadata {
    static func encode(_ record: CKRecord) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    static func decode(_ data: Data) throws -> CKRecord {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        guard let record = CKRecord(coder: unarchiver) else {
            throw CloudKitRecordAdapterError.malformedSystemMetadata
        }
        return record
    }
}

/// Owns only outgoing files created by this process. Incoming CKAsset URLs are
/// CloudKit-owned and are deliberately never passed to this owner.
nonisolated actor CloudKitOutgoingAssetFiles {
    private let directory: URL
    private let fileManager: FileManager
    private var ownedFiles: Set<URL> = []

    init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let parent = directory ?? fileManager.temporaryDirectory
        self.directory = parent.appendingPathComponent("WeekyiiCloudAssets-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func makeAssetFile(for blob: CloudSyncBinaryBlob) throws -> URL {
        let url = directory.appendingPathComponent("\(UUID().uuidString).asset", isDirectory: false)
        try blob.data.write(to: url, options: [.atomic])
        ownedFiles.insert(url)
        return url
    }

    func cleanup() {
        for url in ownedFiles { try? fileManager.removeItem(at: url) }
        ownedFiles.removeAll()
        try? fileManager.removeItem(at: directory)
    }

    func ownedFileURLs() -> Set<URL> { ownedFiles }

    deinit {
        // Explicit call sites clean up before returning. This is a final safety
        // net for an abandoned transport or cancellation during teardown.
        try? fileManager.removeItem(at: directory)
    }
}

@MainActor enum CloudKitRecordAdapter {
    private enum Field {
        static let kind = "kind"
        static let payloadVersion = "payloadVersion"
        static let payload = "payload"
        static let payloadHash = "payloadHash"
        static let blob = "blob"
        static let blobRole = "blobRole"
        static let blobFileName = "blobFileName"
        static let blobContentType = "blobContentType"
    }

    static func makeCKRecord(
        from value: CloudSyncRecord,
        zoneID: CKRecordZone.ID,
        assetFiles: CloudKitOutgoingAssetFiles
    ) async throws -> CKRecord {
        guard value.zoneName == CloudRecordCodec.customZoneName else { throw CloudKitRecordAdapterError.wrongZone }
        guard value.recordType == CloudRecordCodec.recordTypeName else { throw CloudKitRecordAdapterError.wrongRecordType }

        let id = CKRecord.ID(recordName: value.recordName, zoneID: zoneID)
        let record: CKRecord
        if let metadata = value.serverMetadata {
            let existing = try CloudKitSystemMetadata.decode(metadata)
            guard existing.recordID == id,
                  existing.recordType == CloudRecordCodec.recordTypeName
            else { throw CloudKitRecordAdapterError.recordNameMismatch }
            record = existing
        } else {
            record = CKRecord(recordType: CloudRecordCodec.recordTypeName, recordID: id)
        }

        record[Field.kind] = value.kind.rawValue as CKRecordValue
        record[Field.payloadVersion] = NSNumber(value: value.payloadVersion)
        record[Field.payload] = value.payload as CKRecordValue
        record[Field.payloadHash] = value.payloadHash as CKRecordValue
        record[Field.blob] = nil
        record[Field.blobRole] = nil
        record[Field.blobFileName] = nil
        record[Field.blobContentType] = nil
        if let blob = value.blob {
            let url = try await assetFiles.makeAssetFile(for: blob)
            record[Field.blob] = CKAsset(fileURL: url)
            record[Field.blobRole] = blob.role.rawValue as CKRecordValue
            if let name = blob.suggestedFileName { record[Field.blobFileName] = name as CKRecordValue }
            if let contentType = blob.contentType { record[Field.blobContentType] = contentType as CKRecordValue }
        }
        return record
    }

    static func decode(_ record: CKRecord) throws -> CloudSyncRecord {
        guard record.recordID.zoneID.zoneName == CloudRecordCodec.customZoneName else {
            throw CloudKitRecordAdapterError.wrongZone
        }
        guard record.recordType == CloudRecordCodec.recordTypeName else {
            throw CloudKitRecordAdapterError.wrongRecordType
        }
        guard let rawKind = record[Field.kind] as? String,
              let kind = SyncEntityKind(rawValue: rawKind),
              let payloadVersion = (record[Field.payloadVersion] as? NSNumber)?.intValue,
              let payload = record[Field.payload] as? Data,
              let payloadHash = record[Field.payloadHash] as? String
        else { throw CloudKitRecordAdapterError.malformedField("entity") }

        let key: SyncEntityKey
        do {
            key = try CloudRecordCodec.entityKey(kind: kind, payload: payload)
        } catch {
            throw CloudKitRecordAdapterError.malformedPayloadIdentity
        }
        guard CKRecordNameCodec.recordName(for: key) == record.recordID.recordName else {
            throw CloudKitRecordAdapterError.recordNameMismatch
        }

        let blob: CloudSyncBinaryBlob?
        if let asset = record[Field.blob] as? CKAsset {
            guard let url = asset.fileURL else { throw CloudKitRecordAdapterError.missingAssetFile }
            // CloudKit owns this URL; only read it. Do not unlink or move it.
            let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard let rawRole = record[Field.blobRole] as? String,
                  let role = CloudSyncBlobRole(rawValue: rawRole),
                  let digest = WeekyiiSnapshotCodec.blobHash(bytes)
            else { throw CloudKitRecordAdapterError.malformedField("blob") }
            blob = CloudSyncBinaryBlob(
                role: role,
                data: bytes,
                sha256: digest,
                suggestedFileName: record[Field.blobFileName] as? String,
                contentType: record[Field.blobContentType] as? String
            )
        } else {
            blob = nil
        }

        let value = CloudSyncRecord(
            zoneName: record.recordID.zoneID.zoneName,
            recordType: record.recordType,
            recordName: record.recordID.recordName,
            kind: kind,
            businessId: key.businessId,
            payloadVersion: payloadVersion,
            payload: payload,
            payloadHash: payloadHash,
            blob: blob,
            serverMetadata: try CloudKitSystemMetadata.encode(record)
        )
        do {
            _ = try CloudRecordCodec.decode(value)
        } catch CloudRecordCodecError.recordNameMismatch {
            throw CloudKitRecordAdapterError.recordNameMismatch
        } catch {
            throw CloudKitRecordAdapterError.malformedField("payload")
        }
        return value
    }
}

nonisolated enum CloudKitFailureMapper {
    static func map(_ error: Error, recordNames: [String: SyncEntityKey] = [:]) -> CloudSyncFailure {
        let nsError = error as NSError
        guard nsError.domain == CKErrorDomain, let code = CKError.Code(rawValue: nsError.code) else {
            return .other("CloudKit request failed")
        }
        let retryAfter = (nsError.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue
        switch code {
        case .networkUnavailable: return .networkUnavailable
        case .networkFailure: return .networkFailure
        case .serviceUnavailable: return .serviceUnavailable(retryAfter: retryAfter)
        case .requestRateLimited: return .requestRateLimited(retryAfter: retryAfter)
        case .zoneBusy: return .zoneBusy(retryAfter: retryAfter)
        case .quotaExceeded: return .quotaExceeded
        case .notAuthenticated: return .notAuthenticated
        case .permissionFailure: return .permissionFailure
        case .invalidArguments: return .invalidArguments
        case .badContainer, .badDatabase, .missingEntitlement: return .badContainer
        case .serverRecordChanged: return .serverRecordChanged
        case .partialFailure:
            let perItem = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] ?? [:]
            let failures = perItem.compactMap { recordID, itemError -> CloudSyncRecordFailure? in
                guard recordID.zoneID.zoneName == CloudRecordCodec.customZoneName,
                      let key = recordNames[recordID.recordName]
                else { return nil }
                return CloudSyncRecordFailure(entityKey: key, failure: map(itemError, recordNames: recordNames))
            }.sorted { $0.entityKey < $1.entityKey }
            return .partialFailure(failures)
        default: return .other("CloudKit request failed (\(code.rawValue))")
        }
    }
}
