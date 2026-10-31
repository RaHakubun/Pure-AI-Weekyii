import CloudKit
import Foundation

nonisolated protocol CloudKitInfrastructureClient: Sendable {
    func zoneExists() async throws -> Bool
    func createZone() async throws
    func subscriptionExists(id: String) async throws -> Bool
    func createZoneSubscription(id: String) async throws
    func deleteWeekyiiZone() async throws
    func recordsInWeekyiiZone() async throws -> [CKRecord]
}

/// The manager only knows Weekyii's fixed zone and subscription. It has no API
/// that accepts an arbitrary zone name, which keeps destructive work narrowly scoped.
nonisolated actor CloudKitInfrastructureManager {
    static let subscriptionID = "WeekyiiSyncZoneV1-subscription-v1"
    private let client: any CloudKitInfrastructureClient

    init(client: any CloudKitInfrastructureClient) {
        self.client = client
    }

    func ensure() async throws -> CloudSyncRemoteInfrastructure {
        if try await !client.zoneExists() {
            do {
                try await client.createZone()
            } catch {
                // Another Weekyii process/device may have created the same fixed
                // zone between the existence read and save. Accept only if it now exists.
                guard try await client.zoneExists() else { throw error }
            }
        }
        if try await !client.subscriptionExists(id: Self.subscriptionID) {
            do {
                try await client.createZoneSubscription(id: Self.subscriptionID)
            } catch {
                guard try await client.subscriptionExists(id: Self.subscriptionID) else { throw error }
            }
        }
        return CloudSyncRemoteInfrastructure(
            zoneName: CloudRecordCodec.customZoneName,
            databaseScope: .privateDatabase
        )
    }

    func inspect() async throws -> CloudSyncZoneInspection {
        guard try await client.zoneExists() else {
            return CloudSyncZoneInspection(exists: false, records: [])
        }
        let cloudRecords = try await client.recordsInWeekyiiZone()
        var records: [CloudSyncRecord] = []
        var undecodable: [String] = []
        records.reserveCapacity(cloudRecords.count)
        for record in cloudRecords {
            // A record written by a newer build is counted, not fatal: the
            // first-enable and account-switch decisions must stay reachable.
            do {
                records.append(try await CloudKitRecordAdapter.decode(record))
            } catch {
                undecodable.append(record.recordID.recordName)
            }
        }
        return CloudSyncZoneInspection(exists: true, records: records, undecodableRecordNames: undecodable.sorted())
    }

    func resetWeekyiiZone() async throws {
        if try await client.zoneExists() { try await client.deleteWeekyiiZone() }
    }
}

nonisolated final class CloudKitPrivateDatabaseClient: CloudKitInfrastructureClient, @unchecked Sendable {
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID

    init(database: CKDatabase) {
        self.database = database
        self.zoneID = CKRecordZone.ID(zoneName: CloudRecordCodec.customZoneName, ownerName: CKCurrentUserDefaultName)
    }

    func zoneExists() async throws -> Bool {
        let result = try await database.recordZones(for: [zoneID])
        guard let outcome = result[zoneID] else { return false }
        switch outcome {
        case .success: return true
        case .failure(let error):
            let code = (error as NSError).code
            if code == CKError.unknownItem.rawValue || code == CKError.zoneNotFound.rawValue { return false }
            throw error
        }
    }

    func createZone() async throws {
        let result = try await database.modifyRecordZones(
            saving: [CKRecordZone(zoneID: zoneID)],
            deleting: []
        )
        guard let saveResult = result.saveResults[zoneID] else {
            throw CloudSyncTransportError.transportNotReady
        }
        _ = try saveResult.get()
    }

    func subscriptionExists(id: String) async throws -> Bool {
        let result = try await database.subscriptions(for: [id])
        guard let outcome = result[id] else { return false }
        switch outcome {
        case .success: return true
        case .failure(let error):
            if (error as NSError).code == CKError.unknownItem.rawValue { return false }
            throw error
        }
    }

    func createZoneSubscription(id: String) async throws {
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        let result = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        guard let saveResult = result.saveResults[id] else {
            throw CloudSyncTransportError.transportNotReady
        }
        _ = try saveResult.get()
    }

    func deleteWeekyiiZone() async throws {
        let result = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
        guard let deleteResult = result.deleteResults[zoneID] else {
            throw CloudSyncTransportError.transportNotReady
        }
        try deleteResult.get()
    }

    /// Enumerates the zone with a zone-changes fetch from a nil token rather than
    /// a `CKQuery`. A query needs a queryable `recordName` index deployed in the
    /// production schema; a zone-changes fetch needs no index at all, so first
    /// enable and account switch cannot fail on a missing index.
    func recordsInWeekyiiZone() async throws -> [CKRecord] {
        var token: CKServerChangeToken?
        var byID: [CKRecord.ID: CKRecord] = [:]
        var moreComing = true
        while moreComing {
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            for (id, result) in page.modificationResultsByID {
                byID[id] = try result.get().record
            }
            for deletion in page.deletions { byID.removeValue(forKey: deletion.recordID) }
            token = page.changeToken
            moreComing = page.moreComing
        }
        return byID.values
            .filter { $0.recordType == CloudRecordCodec.recordTypeName }
            .sorted { $0.recordID.recordName < $1.recordID.recordName }
    }
}
