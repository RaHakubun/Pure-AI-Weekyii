import Foundation
import CryptoKit

/// A normalised, single-aggregate value that can be represented by one Cloud record.
enum CloudSyncEntity: Hashable {
    case week(WeekSnapshot)
    case day(DaySnapshot)
    case task(TaskSnapshot)
    case suspendedTask(SuspendedTaskSnapshot)
    case attachment(AttachmentSnapshot)
    case project(ProjectSnapshot)
    case mindStamp(MindStampSnapshot)
    case taskType(TaskTypeSnapshot)
    case habit(HabitSnapshot)
    case habitDayRecord(HabitDayRecordSnapshot)

    var kind: SyncEntityKind {
        switch self {
        case .week: .week
        case .day: .day
        case .task: .task
        case .suspendedTask: .suspendedTask
        case .attachment: .attachment
        case .project: .project
        case .mindStamp: .mindStamp
        case .taskType: .taskType
        case .habit: .habit
        case .habitDayRecord: .habitDayRecord
        }
    }

    var key: SyncEntityKey {
        switch self {
        case .week(let value): value.entityKey
        case .day(let value): value.entityKey
        case .task(let value): value.entityKey
        case .suspendedTask(let value): value.entityKey
        case .attachment(let value): value.entityKey
        case .project(let value): value.entityKey
        case .mindStamp(let value): value.entityKey
        case .taskType(let value): value.entityKey
        case .habit(let value): value.entityKey
        case .habitDayRecord(let value): value.entityKey
        }
    }
}

/// Versioned Cloud identity derived only from the logical `(kind, businessId)` key.
nonisolated enum CKRecordNameCodec {
    static func recordName(for key: SyncEntityKey) -> String {
        let kind = Data(key.kind.rawValue.utf8)
        let businessId = Data(key.businessId.utf8)
        var input = Data("Weekyii.CloudRecordName.V1".utf8)
        appendLength(kind.count, to: &input)
        input.append(kind)
        appendLength(businessId.count, to: &input)
        input.append(businessId)
        let digest = SHA256.hash(data: input)
        return "wy1_" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func appendLength(_ count: Int, to data: inout Data) {
        var value = UInt32(count).bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}

nonisolated enum CloudSyncBlobRole: String, Codable, Hashable, Sendable {
    case attachment
    case mindStampImage
}

/// Binary bytes are transport material; structural JSON contains only their digest and length.
nonisolated struct CloudSyncBinaryBlob: Codable, Hashable, Sendable {
    let role: CloudSyncBlobRole
    let data: Data
    let sha256: String
    let suggestedFileName: String?
    let contentType: String?
}

nonisolated struct CloudSyncRecord: Codable, Hashable, Sendable {
    let zoneName: String
    let recordType: String
    let recordName: String
    let kind: SyncEntityKind
    let businessId: String
    let payloadVersion: Int
    let payload: Data
    let payloadHash: String
    let blob: CloudSyncBinaryBlob?
    /// Opaque transport metadata (CloudKit system fields/change tag). It is never
    /// interpreted by the snapshot or persistence layers.
    let serverMetadata: Data?

    init(
        zoneName: String,
        recordType: String,
        recordName: String,
        kind: SyncEntityKind,
        businessId: String,
        payloadVersion: Int,
        payload: Data,
        payloadHash: String,
        blob: CloudSyncBinaryBlob?,
        serverMetadata: Data? = nil
    ) {
        self.zoneName = zoneName
        self.recordType = recordType
        self.recordName = recordName
        self.kind = kind
        self.businessId = businessId
        self.payloadVersion = payloadVersion
        self.payload = payload
        self.payloadHash = payloadHash
        self.blob = blob
        self.serverMetadata = serverMetadata
    }

    var entityKey: SyncEntityKey { SyncEntityKey(kind: kind, businessId: businessId) }
}

enum CloudRecordCodecError: Error, Equatable {
    case wrongZone
    case wrongRecordType
    case recordNameMismatch
    case entityKeyMismatch
    case unsupportedPayloadVersion
    case payloadHashMismatch
    case malformedBlob
    case malformedPayloadIdentity
}

/// Cloud wire protocol versioning is per aggregate, independent of SwiftData schema versions.
enum CloudRecordCodec {
    nonisolated static let customZoneName = "WeekyiiSyncZoneV1"
    nonisolated static let recordTypeName = "WYEntityV1"

    nonisolated static func payloadVersion(for kind: SyncEntityKind) -> Int {
        switch kind {
        case .week: 1
        case .day: 1
        case .task: 1
        case .suspendedTask: 1
        case .attachment: 1
        case .project: 1
        case .mindStamp: 1
        case .taskType: 1
        case .habit: 1
        case .habitDayRecord: 1
        }
    }

    static func encode(_ entity: CloudSyncEntity) throws -> CloudSyncRecord {
        let payload: Data
        let payloadHash: String
        let blob: CloudSyncBinaryBlob?
        switch entity {
        case .week(let value):
            payload = try WeekyiiSnapshotCodec.canonicalJSON(value)
            payloadHash = try WeekyiiSnapshotCodec.entityHash(value)
            blob = nil
        case .day(let value):
            payload = try WeekyiiSnapshotCodec.canonicalJSON(value)
            payloadHash = try WeekyiiSnapshotCodec.entityHash(value)
            blob = nil
        case .task(let value):
            payload = try WeekyiiSnapshotCodec.canonicalJSON(value)
            payloadHash = try WeekyiiSnapshotCodec.entityHash(value)
            blob = nil
        case .suspendedTask(let value):
            payload = try WeekyiiSnapshotCodec.canonicalJSON(value)
            payloadHash = try WeekyiiSnapshotCodec.entityHash(value)
            blob = nil
        case .attachment(let value):
            let wire = AttachmentPayload(value)
            payload = try WeekyiiSnapshotCodec.canonicalJSON(wire)
            payloadHash = try WeekyiiSnapshotCodec.entityHash(value)
            blob = try value.data.map {
                CloudSyncBinaryBlob(
                    role: .attachment,
                    data: $0,
                    sha256: try Self.blobDigest($0),
                    suggestedFileName: value.fileName,
                    contentType: value.fileType
                )
            }
        case .project(let value):
            payload = try WeekyiiSnapshotCodec.canonicalJSON(value)
            payloadHash = try WeekyiiSnapshotCodec.entityHash(value)
            blob = nil
        case .mindStamp(let value):
            let wire = MindStampPayload(value)
            payload = try WeekyiiSnapshotCodec.canonicalJSON(wire)
            payloadHash = try WeekyiiSnapshotCodec.entityHash(value)
            blob = try value.imageBlob.map {
                CloudSyncBinaryBlob(
                    role: .mindStampImage,
                    data: $0,
                    sha256: try Self.blobDigest($0),
                    suggestedFileName: nil,
                    contentType: "application/octet-stream"
                )
            }
        case .taskType(let value):
            payload = try WeekyiiSnapshotCodec.canonicalJSON(value)
            payloadHash = try WeekyiiSnapshotCodec.entityHash(value)
            blob = nil
        case .habit(let value):
            payload = try WeekyiiSnapshotCodec.canonicalJSON(value)
            payloadHash = try WeekyiiSnapshotCodec.entityHash(value)
            blob = nil
        case .habitDayRecord(let value):
            payload = try WeekyiiSnapshotCodec.canonicalJSON(value)
            payloadHash = try WeekyiiSnapshotCodec.entityHash(value)
            blob = nil
        }

        return CloudSyncRecord(
            zoneName: customZoneName,
            recordType: recordTypeName,
            recordName: CKRecordNameCodec.recordName(for: entity.key),
            kind: entity.kind,
            businessId: entity.key.businessId,
            payloadVersion: payloadVersion(for: entity.kind),
            payload: payload,
            payloadHash: payloadHash,
            blob: blob
        )
    }

    static func decode(_ record: CloudSyncRecord) throws -> CloudSyncEntity {
        guard record.zoneName == customZoneName else { throw CloudRecordCodecError.wrongZone }
        guard record.recordType == recordTypeName else { throw CloudRecordCodecError.wrongRecordType }
        guard record.recordName == CKRecordNameCodec.recordName(for: record.entityKey) else {
            throw CloudRecordCodecError.recordNameMismatch
        }
        guard record.payloadVersion == payloadVersion(for: record.kind) else {
            throw CloudRecordCodecError.unsupportedPayloadVersion
        }

        let entity: CloudSyncEntity
        switch record.kind {
        case .week: entity = .week(try decodePayload(WeekSnapshot.self, from: record.payload))
        case .day: entity = .day(try decodePayload(DaySnapshot.self, from: record.payload))
        case .task: entity = .task(try decodePayload(TaskSnapshot.self, from: record.payload))
        case .suspendedTask: entity = .suspendedTask(try decodePayload(SuspendedTaskSnapshot.self, from: record.payload))
        case .attachment:
            let wire = try decodePayload(AttachmentPayload.self, from: record.payload)
            let data = try decodeBlob(record.blob, role: .attachment, expectedHash: wire.blobSHA256, expectedCount: wire.byteCount)
            entity = .attachment(wire.snapshot(data: data))
        case .project: entity = .project(try decodePayload(ProjectSnapshot.self, from: record.payload))
        case .mindStamp:
            let wire = try decodePayload(MindStampPayload.self, from: record.payload)
            let data = try decodeBlob(record.blob, role: .mindStampImage, expectedHash: wire.imageBlobSHA256, expectedCount: wire.imageByteCount)
            entity = .mindStamp(wire.snapshot(imageBlob: data))
        case .taskType: entity = .taskType(try decodePayload(TaskTypeSnapshot.self, from: record.payload))
        case .habit: entity = .habit(try decodePayload(HabitSnapshot.self, from: record.payload))
        case .habitDayRecord: entity = .habitDayRecord(try decodePayload(HabitDayRecordSnapshot.self, from: record.payload))
        }

        guard entity.key == record.entityKey else { throw CloudRecordCodecError.entityKeyMismatch }
        guard try Self.hash(of: entity) == record.payloadHash else { throw CloudRecordCodecError.payloadHashMismatch }
        return entity
    }

    /// Derives identity from the payload itself. The CloudKit `kind` field only
    /// selects the versioned payload decoder; `businessId` is never trusted.
    static func entityKey(kind: SyncEntityKind, payload: Data) throws -> SyncEntityKey {
        do {
            switch kind {
            case .week:
                return try decodePayload(WeekSnapshot.self, from: payload).entityKey
            case .day:
                return try decodePayload(DaySnapshot.self, from: payload).entityKey
            case .task:
                return try decodePayload(TaskSnapshot.self, from: payload).entityKey
            case .suspendedTask:
                return try decodePayload(SuspendedTaskSnapshot.self, from: payload).entityKey
            case .attachment:
                return SyncEntityKey(kind: .attachment, id: try decodePayload(AttachmentPayload.self, from: payload).id)
            case .project:
                return try decodePayload(ProjectSnapshot.self, from: payload).entityKey
            case .mindStamp:
                return SyncEntityKey(kind: .mindStamp, id: try decodePayload(MindStampPayload.self, from: payload).id)
            case .taskType:
                return try decodePayload(TaskTypeSnapshot.self, from: payload).entityKey
            case .habit:
                return try decodePayload(HabitSnapshot.self, from: payload).entityKey
            case .habitDayRecord:
                return try decodePayload(HabitDayRecordSnapshot.self, from: payload).entityKey
            }
        } catch {
            throw CloudRecordCodecError.malformedPayloadIdentity
        }
    }

    private static func decodePayload<T: Decodable>(_ type: T.Type, from payload: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: payload)
    }

    private static func hash(of entity: CloudSyncEntity) throws -> String {
        switch entity {
        case .week(let value): try WeekyiiSnapshotCodec.entityHash(value)
        case .day(let value): try WeekyiiSnapshotCodec.entityHash(value)
        case .task(let value): try WeekyiiSnapshotCodec.entityHash(value)
        case .suspendedTask(let value): try WeekyiiSnapshotCodec.entityHash(value)
        case .attachment(let value): try WeekyiiSnapshotCodec.entityHash(value)
        case .project(let value): try WeekyiiSnapshotCodec.entityHash(value)
        case .mindStamp(let value): try WeekyiiSnapshotCodec.entityHash(value)
        case .taskType(let value): try WeekyiiSnapshotCodec.entityHash(value)
        case .habit(let value): try WeekyiiSnapshotCodec.entityHash(value)
        case .habitDayRecord(let value): try WeekyiiSnapshotCodec.entityHash(value)
        }
    }

    private static func blobDigest(_ bytes: Data) throws -> String {
        guard let hash = WeekyiiSnapshotCodec.blobHash(bytes) else { throw CloudRecordCodecError.malformedBlob }
        return hash
    }

    private static func decodeBlob(
        _ blob: CloudSyncBinaryBlob?,
        role: CloudSyncBlobRole,
        expectedHash: String?,
        expectedCount: Int
    ) throws -> Data? {
        guard let expectedHash else {
            guard expectedCount == 0, blob == nil else { throw CloudRecordCodecError.malformedBlob }
            return nil
        }
        guard let blob,
              blob.role == role,
              blob.sha256 == expectedHash,
              blob.data.count == expectedCount,
              try blobDigest(blob.data) == expectedHash
        else { throw CloudRecordCodecError.malformedBlob }
        return blob.data
    }

    private struct AttachmentPayload: Codable {
        let id: UUID
        let owner: AttachmentOwner
        let fileName: String
        let fileType: String
        let createdAt: Date
        let byteCount: Int
        let blobSHA256: String?

        init(_ value: AttachmentSnapshot) {
            id = value.id
            owner = value.owner
            fileName = value.fileName
            fileType = value.fileType
            createdAt = value.createdAt
            byteCount = value.data?.count ?? 0
            blobSHA256 = WeekyiiSnapshotCodec.blobHash(value.data)
        }

        func snapshot(data: Data?) -> AttachmentSnapshot {
            AttachmentSnapshot(id: id, owner: owner, data: data, fileName: fileName, fileType: fileType, createdAt: createdAt)
        }
    }

    private struct MindStampPayload: Codable {
        let id: UUID
        let text: String
        let createdAt: Date
        let imageByteCount: Int
        let imageBlobSHA256: String?

        init(_ value: MindStampSnapshot) {
            id = value.id
            text = value.text
            createdAt = value.createdAt
            imageByteCount = value.imageBlob?.count ?? 0
            imageBlobSHA256 = WeekyiiSnapshotCodec.blobHash(value.imageBlob)
        }

        func snapshot(imageBlob: Data?) -> MindStampSnapshot {
            MindStampSnapshot(id: id, text: text, imageBlob: imageBlob, createdAt: createdAt)
        }
    }
}
