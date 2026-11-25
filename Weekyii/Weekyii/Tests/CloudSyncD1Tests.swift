import XCTest
import CryptoKit
@testable import Weekyii

@MainActor
final class CloudRecordCodecTests: XCTestCase {
    func test_recordNamesAreStableSafeVersionedAndDistinctForEveryEntityKind() {
        let keys = SyncEntityKind.allCases.map {
            SyncEntityKey(kind: $0, businessId: "same:business/id-🪁")
        } + [
            SyncEntityKey(kind: .taskType, businessId: "中文 task type:with/slash % punctuation!?"),
            SyncEntityKey(kind: .taskType, businessId: String(repeating: "长", count: 2_048))
        ]
        let names = keys.map(CKRecordNameCodec.recordName(for:))

        XCTAssertEqual(Set(names).count, names.count)
        for (key, name) in zip(keys, names) {
            XCTAssertEqual(CKRecordNameCodec.recordName(for: key), name)
            XCTAssertLessThanOrEqual(name.utf8.count, 255)
            XCTAssertNotNil(name.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression))
            XCTAssertNotEqual(name, key.description)
        }
    }

    func test_recordIdentityDependsOnlyOnTheEntityKey() throws {
        let first = makeTask(title: "Draft A")
        let edited = makeTask(id: first.id, title: "改过的标题 / punctuation: !")

        let firstRecord = try CloudRecordCodec.encode(.task(first))
        let editedRecord = try CloudRecordCodec.encode(.task(edited))

        XCTAssertEqual(first.entityKey, edited.entityKey)
        XCTAssertEqual(firstRecord.recordName, editedRecord.recordName)
        XCTAssertNotEqual(firstRecord.payloadHash, editedRecord.payloadHash)
    }

    func test_eachEntityFamilyRoundTripsAsOneVersionedCloudRecord() throws {
        let entities = makeEntities()

        XCTAssertEqual(Set(entities.map(\.kind)), Set(SyncEntityKind.allCases))
        for entity in entities {
            let record = try CloudRecordCodec.encode(entity)

            XCTAssertEqual(record.recordType, CloudRecordCodec.recordTypeName)
            XCTAssertEqual(record.zoneName, CloudRecordCodec.customZoneName)
            XCTAssertEqual(record.kind, entity.kind)
            XCTAssertEqual(record.businessId, entity.key.businessId)
            XCTAssertEqual(record.payloadVersion, CloudRecordCodec.payloadVersion(for: entity.kind))
            XCTAssertEqual(record.payloadVersion, 1)
            XCTAssertEqual(record.recordName, CKRecordNameCodec.recordName(for: entity.key))
            XCTAssertEqual(try CloudRecordCodec.decode(record), entity)
        }
    }

    func test_taskStepsStayEmbeddedAndAttachmentBytesStayOutsideTaskPayloadAndHash() throws {
        let attachmentID = UUID()
        let task = makeTask(attachmentIds: [attachmentID])
        let before = try CloudRecordCodec.encode(.task(task))
        let changedAttachment = AttachmentSnapshot(
            id: attachmentID,
            owner: .task(task.id),
            data: Data([0xFA, 0xCE, 0x01, 0x02]),
            fileName: "résumé/计划.pdf",
            fileType: "application/pdf",
            createdAt: date(3)
        )
        let attachmentRecord = try CloudRecordCodec.encode(.attachment(changedAttachment))
        let after = try CloudRecordCodec.encode(.task(task))
        let taskPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: before.payload) as? [String: Any])

        XCTAssertEqual(taskPayload["attachmentIds"] as? [String], [attachmentID.uuidString])
        XCTAssertEqual((taskPayload["steps"] as? [[String: Any]])?.count, task.steps.count)
        XCTAssertNil(taskPayload["attachments"])
        XCTAssertNil(taskPayload["data"])
        XCTAssertNil(before.blob)
        XCTAssertEqual(before.payloadHash, after.payloadHash)
        XCTAssertEqual(attachmentRecord.blob?.data, changedAttachment.data)
        XCTAssertFalse(String(decoding: before.payload, as: UTF8.self).contains(changedAttachment.data!.base64EncodedString()))
    }

    func test_attachmentPayloadAndHashContainMetadataAndBlobDigestButNotBlobBytes() throws {
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03])
        let attachment = AttachmentSnapshot(
            id: UUID(), owner: .task(UUID()), data: bytes,
            fileName: "附件/报告 📎.pdf", fileType: "application/pdf", createdAt: date(4)
        )
        let record = try CloudRecordCodec.encode(.attachment(attachment))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: record.payload) as? [String: Any])

        XCTAssertEqual(record.blob?.role, .attachment)
        XCTAssertEqual(record.blob?.data, bytes)
        XCTAssertEqual(record.blob?.sha256, WeekyiiSnapshotCodec.blobHash(bytes))
        XCTAssertEqual(record.blob?.suggestedFileName, attachment.fileName)
        XCTAssertEqual(record.blob?.contentType, attachment.fileType)
        XCTAssertEqual(record.payloadHash, try WeekyiiSnapshotCodec.entityHash(attachment))
        XCTAssertEqual(fields["blobSHA256"] as? String, WeekyiiSnapshotCodec.blobHash(bytes))
        XCTAssertEqual(fields["byteCount"] as? Int, bytes.count)
        XCTAssertNil(fields["data"])
        XCTAssertFalse(String(decoding: record.payload, as: UTF8.self).contains(bytes.base64EncodedString()))
    }

    func test_mindStampImageUsesBlobDescriptorAndImageAwareHash() throws {
        let bytes = Data([0x10, 0x20, 0x30, 0x40, 0x50])
        let stamp = MindStampSnapshot(id: UUID(), text: "记录图像 🗻", imageBlob: bytes, createdAt: date(5))
        let record = try CloudRecordCodec.encode(.mindStamp(stamp))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: record.payload) as? [String: Any])

        XCTAssertEqual(record.blob?.role, .mindStampImage)
        XCTAssertEqual(record.blob?.data, bytes)
        XCTAssertEqual(record.blob?.sha256, WeekyiiSnapshotCodec.blobHash(bytes))
        XCTAssertEqual(record.payloadHash, try WeekyiiSnapshotCodec.entityHash(stamp))
        XCTAssertNil(fields["imageBlob"])
        XCTAssertNil(fields["data"])
        XCTAssertFalse(String(decoding: record.payload, as: UTF8.self).contains(bytes.base64EncodedString()))

        let changed = MindStampSnapshot(id: stamp.id, text: stamp.text, imageBlob: Data([0x10, 0x20, 0x30, 0x40, 0x51]), createdAt: stamp.createdAt)
        XCTAssertNotEqual(try CloudRecordCodec.encode(.mindStamp(changed)).payloadHash, record.payloadHash)
    }

    func test_habitPayloadOmitsLegacyWatermarkAndDeviceLocalState() throws {
        let records = try makeEntities().map(CloudRecordCodec.encode)
        let payloads = records.map { String(decoding: $0.payload, as: UTF8.self) }
        let combined = payloads.joined(separator: "\n")

        XCTAssertFalse(combined.contains("generatedThroughDayId"))
        XCTAssertFalse(combined.contains("cloudSyncRequested"))
        XCTAssertFalse(combined.contains("premiumThemeUnlocked"))
        XCTAssertFalse(combined.contains("notificationPreferences"))
        XCTAssertFalse(combined.contains("AppState"))
        XCTAssertFalse(String(reflecting: CloudSyncEntity.self).contains("UserSettings"))
        XCTAssertFalse(String(reflecting: CloudSyncEntity.self).contains("AppState"))
    }

    func test_codecRejectsUnsupportedVersionAndTamperedContentHash() throws {
        let record = try CloudRecordCodec.encode(.task(makeTask()))
        let unsupported = CloudSyncRecord(
            zoneName: record.zoneName,
            recordType: record.recordType,
            recordName: record.recordName,
            kind: record.kind,
            businessId: record.businessId,
            payloadVersion: record.payloadVersion + 1,
            payload: record.payload,
            payloadHash: record.payloadHash,
            blob: record.blob
        )
        let tampered = CloudSyncRecord(
            zoneName: record.zoneName,
            recordType: record.recordType,
            recordName: record.recordName,
            kind: record.kind,
            businessId: record.businessId,
            payloadVersion: record.payloadVersion,
            payload: record.payload,
            payloadHash: String(repeating: "0", count: 64),
            blob: record.blob
        )

        XCTAssertThrowsError(try CloudRecordCodec.decode(unsupported)) { error in
            guard case CloudRecordCodecError.unsupportedPayloadVersion = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(try CloudRecordCodec.decode(tampered)) { error in
            XCTAssertEqual(error as? CloudRecordCodecError, .payloadHashMismatch)
        }
    }

    private func makeEntities() -> [CloudSyncEntity] {
        let taskID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let suspendedID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let attachmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
        let habitID = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
        let entities: [CloudSyncEntity] = [
            .week(WeekSnapshot(weekId: "2026-W07", startDate: date(0), endDate: date(6), status: .pending, completedTasksCount: 0, expiredTasksCount: 0, totalStartedDays: 0)),
            .day(DaySnapshot(dayId: "2026-02-08", weekId: "2026-W07", date: date(1), dayOfWeek: "Sun", status: .draft, killTimeHour: 20, killTimeMinute: 0, followsDefaultKillTime: true, initiatedAt: nil, closedAt: nil, executionModeRaw: ExecutionMode.strict.rawValue, isDraftZoneUnlocked: false, expiredCount: 0)),
            .task(makeTask(id: taskID, attachmentIds: [attachmentID], projectId: projectID, habitId: habitID)),
            .suspendedTask(SuspendedTaskSnapshot(id: suspendedID, title: "悬而未决", taskDescription: "desc", taskType: .ddl, taskTypeIdRaw: "ddl", createdAt: date(2), decisionDeadline: date(9), preferredCountdownDays: 7, snoozeCount: 1, statusRaw: "active", steps: [StepSnapshot(title: "跟进", isCompleted: false, sortOrder: 0, createdAt: date(2))], attachmentIds: [])),
            .attachment(AttachmentSnapshot(id: attachmentID, owner: .task(taskID), data: Data([0x01, 0x02]), fileName: "附件.pdf", fileType: "application/pdf", createdAt: date(3))),
            .project(ProjectSnapshot(id: projectID, name: "项目", projectDescription: "desc", color: "#123456", icon: "folder", status: .active, startDate: date(0), endDate: date(30), createdAt: date(0), tileSizeRaw: "medium", tileOrder: 0)),
            .mindStamp(MindStampSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!, text: "记住", imageBlob: Data([0x03]), createdAt: date(4))),
            .taskType(TaskTypeSnapshot(idRaw: "自定义 类型:with/slash 🪁", name: "自定义", iconName: "pencil", colorHex: "#654321", baseKindRaw: "regular", sortOrder: 0, isBuiltIn: false, isArchived: false)),
            .habit(HabitSnapshot(id: habitID, name: "习惯", iconName: "repeat", colorHex: "#00AA00", categoryRaw: "health", scheduleKindRaw: "weekly", scheduleWeekdaysRaw: 31, scheduleMonthDaysRaw: 0, startDayId: "2026-02-08", isActive: true, createdAt: date(0), sortOrder: 0)),
            .habitDayRecord(HabitDayRecordSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000107")!, habitId: habitID, dayId: "2026-02-08", statusRaw: "completed", createdAt: date(1), completedAt: date(2)))
        ]
        return entities
    }

    private func makeTask(
        id: UUID = UUID(),
        title: String = "任务",
        attachmentIds: [UUID] = [],
        projectId: UUID? = nil,
        habitId: UUID? = nil
    ) -> TaskSnapshot {
        TaskSnapshot(id: id, dayId: "2026-02-08", projectId: projectId, habitId: habitId, title: title, taskDescription: "desc", taskType: .regular, taskTypeIdRaw: "regular", order: 1, zone: .draft, startedAt: nil, endedAt: nil, completedOrder: 0, steps: [StepSnapshot(title: "第一步", isCompleted: false, sortOrder: 0, createdAt: date(1))], attachmentIds: attachmentIds)
    }

    private func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_770_000_000 + Double(day * 86_400))
    }
}

@MainActor
final class CloudSyncTransportTests: XCTestCase {
    func test_fakeTransportSeedsFetchesUpsertsDeletesAndPersistsState() async throws {
        let original = try CloudRecordCodec.encode(.task(makeTask(title: "remote")))
        let next = try CloudRecordCodec.encode(.project(makeProject()))
        let transport = InMemoryCloudSyncTransport(seedRecords: [original])

        let transportScope = await transport.databaseScope
        XCTAssertEqual(transportScope, .privateDatabase)
        let firstInfrastructure = try await transport.ensureInfrastructure()
        let secondInfrastructure = try await transport.ensureInfrastructure()
        XCTAssertEqual(firstInfrastructure, secondInfrastructure)
        XCTAssertEqual(firstInfrastructure.zoneName, CloudRecordCodec.customZoneName)
        XCTAssertEqual(firstInfrastructure.databaseScope, .privateDatabase)

        let seeded = try await transport.fetchChanges(since: nil)
        XCTAssertEqual(seeded.changes, [.upsert(original)])
        let upsertResults = await transport.upsert([next])
        XCTAssertEqual(upsertResults, [CloudSyncRecordResult(entityKey: next.entityKey, outcome: .upserted)])
        let afterUpsert = try await transport.fetchChanges(since: seeded.nextToken)
        XCTAssertEqual(afterUpsert.changes, [.upsert(next)])

        let deleteResults = await transport.delete([original.entityKey])
        XCTAssertEqual(deleteResults, [CloudSyncRecordResult(entityKey: original.entityKey, outcome: .deleted)])
        let afterDelete = try await transport.fetchChanges(since: afterUpsert.nextToken)
        XCTAssertEqual(afterDelete.changes, [.delete(original.entityKey)])
        let finalRecords = await transport.remoteRecords()
        XCTAssertEqual(finalRecords, [next])

        let engineState = Data([0x01, 0x02, 0x03])
        await transport.restoreTransportState(engineState)
        let restoredState = await transport.persistedTransportState()
        XCTAssertEqual(restoredState, engineState)
    }

    func test_fakeTransportReturnsIndependentPerRecordFailures() async throws {
        let successful = try CloudRecordCodec.encode(.task(makeTask(title: "ok")))
        let transient = try CloudRecordCodec.encode(.task(makeTask(title: "retry")))
        let terminal = try CloudRecordCodec.encode(.project(makeProject()))
        let transport = InMemoryCloudSyncTransport()
        _ = try await transport.ensureInfrastructure()
        await transport.injectFailure(.networkUnavailable, for: transient.entityKey, operation: .upsert)
        await transport.injectFailure(.quotaExceeded, for: terminal.entityKey, operation: .upsert)

        let results = await transport.upsert([successful, transient, terminal])

        XCTAssertEqual(results.map(\.entityKey), [successful.entityKey, transient.entityKey, terminal.entityKey])
        XCTAssertEqual(results[0].outcome, .upserted)
        XCTAssertEqual(results[1].outcome, .failed(.networkUnavailable))
        XCTAssertEqual(results[2].outcome, .failed(.quotaExceeded))
        let recordsAfterPartialFailure = await transport.remoteRecords()
        XCTAssertEqual(recordsAfterPartialFailure, [successful])
    }

    private func makeTask(title: String) -> TaskSnapshot {
        TaskSnapshot(id: UUID(), dayId: nil, projectId: nil, habitId: nil, title: title, taskDescription: "", taskType: .regular, taskTypeIdRaw: "regular", order: 1, zone: .draft, startedAt: nil, endedAt: nil, completedOrder: 0, steps: [], attachmentIds: [])
    }

    private func makeProject() -> ProjectSnapshot {
        ProjectSnapshot(id: UUID(), name: "project", projectDescription: "", color: "#123456", icon: "folder", status: .active, startDate: Date(timeIntervalSince1970: 1_700_000_000), endDate: Date(timeIntervalSince1970: 1_700_086_400), createdAt: Date(timeIntervalSince1970: 1_700_000_000), tileSizeRaw: "medium", tileOrder: 0)
    }
}

@MainActor
final class CloudSyncMetadataStoreTests: XCTestCase {
    func test_metadataRoundTripsUnderHashedAccountDirectoryWithoutRawIdentity() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudSyncMetadataStore(rootURL: root)
        let accountID = "_defaultUserRecordID/私有账号:🛰️"
        let accountHash = try CloudSyncMetadataStore.accountHash(for: accountID)
        let key = SyncEntityKey(kind: .taskType, businessId: "custom type:/🔥")
        var metadata = CloudSyncMetadata(accountHash: accountHash)
        metadata.syncEngineState = Data([0x11, 0x22])
        metadata.entityBaselines[key] = CloudSyncEntityBaseline(lastSyncedHash: String(repeating: "a", count: 64), serverMetadata: Data([0x33]))
        metadata.serverMetadata = Data([0x44, 0x55])
        metadata.lastSuccessfulSync = Date(timeIntervalSince1970: 1_700_000_000)
        metadata.lastAttempt = Date(timeIntervalSince1970: 1_700_000_030)
        metadata.lastFailure = "temporarilyUnavailable"
        metadata.lastFailureCategory = .transient
        metadata.automaticRetrySuppressed = true
        metadata.zoneInitialized = true
        let fileURL = try store.metadataFileURL(forAccountRecordName: accountID)

        try store.save(metadata, forAccountRecordName: accountID)
        let restored = try XCTUnwrap(store.load(forAccountRecordName: accountID))
        let fileBytes = try Data(contentsOf: fileURL)

        XCTAssertEqual(restored, metadata)
        XCTAssertEqual(fileURL.deletingLastPathComponent().lastPathComponent, accountHash)
        XCTAssertFalse(fileURL.path.contains(accountID))
        XCTAssertNil(fileBytes.range(of: Data(accountID.utf8)))
    }

    func test_metadataAtomicReplacementLeavesOnlyCompleteCurrentFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudSyncMetadataStore(rootURL: root)
        let accountID = "account-a"
        let accountHash = try CloudSyncMetadataStore.accountHash(for: accountID)
        let first = CloudSyncMetadata(accountHash: accountHash)
        var second = first
        second.syncEngineState = Data([0xAA, 0xBB, 0xCC])
        second.zoneInitialized = true

        try store.save(first, forAccountRecordName: accountID)
        try store.save(second, forAccountRecordName: accountID)

        XCTAssertEqual(try store.load(forAccountRecordName: accountID), second)
        let directory = try XCTUnwrap(try? FileManager.default.contentsOfDirectory(atPath: store.metadataFileURL(forAccountRecordName: accountID).deletingLastPathComponent().path))
        XCTAssertEqual(directory, ["metadata.json"])
    }

    func test_accountMetadataIsIsolatedAndCorruptionIsAnExplicitError() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudSyncMetadataStore(rootURL: root)
        let accountA = "apple-user-A"
        let accountB = "apple-user-B"
        let metadataA = CloudSyncMetadata(accountHash: try CloudSyncMetadataStore.accountHash(for: accountA))
        var metadataB = CloudSyncMetadata(accountHash: try CloudSyncMetadataStore.accountHash(for: accountB))
        metadataB.automaticRetrySuppressed = true

        try store.save(metadataA, forAccountRecordName: accountA)
        try store.save(metadataB, forAccountRecordName: accountB)

        XCTAssertNotEqual(metadataA.accountHash, metadataB.accountHash)
        XCTAssertEqual(try store.load(forAccountRecordName: accountA), metadataA)
        XCTAssertEqual(try store.load(forAccountRecordName: accountB), metadataB)

        let corruptAccount = "corrupt-account"
        let corruptURL = try store.metadataFileURL(forAccountRecordName: corruptAccount)
        try FileManager.default.createDirectory(at: corruptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: corruptURL)
        XCTAssertThrowsError(try store.load(forAccountRecordName: corruptAccount)) { error in
            guard case CloudSyncMetadataStoreError.corruptedMetadata = error else {
                return XCTFail("corrupt state must be recoverable and explicit, got: \(error)")
            }
        }
    }

    func test_businessArchiveV1DoesNotAcquireTransportMetadata() throws {
        let archive = WeekyiiDataArchiveService.Payload(
            weeks: [], days: [], tasks: [], projects: [], mindStamps: [], suspendedTasks: [], taskTypes: [], habits: nil,
            settings: WeekyiiDataArchiveService.SettingsRecord(defaultKillTimeHour: 20, defaultKillTimeMinute: 0, defaultTaskTypeRaw: "regular", defaultTaskTypeIdRaw: "regular", defaultExecutionModeRaw: "strict", killTimeReminderMinutes: 30, fixedReminderEnabled: false, fixedReminderHour: 9, fixedReminderMinute: 0, weekStartsOnMonday: true, defaultProjectDurationDays: 7, defaultProjectTileSizeRaw: "medium", pendingMonthShowRegular: true, pendingMonthShowDDL: true, pendingMonthShowLeisure: true, selectedThemeRaw: "amber", appearanceModeRaw: "system", premiumThemeUnlocked: false),
            appState: WeekyiiDataArchiveService.AppStateRecord(daysStartedCount: 0, dataRevision: 0, stateTransitionRevision: 0, systemStartDate: nil, lastProcessedDate: nil, lastRolloverAt: nil)
        )
        let data = try JSONEncoder().encode(archive)
        let encoded = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(WeekyiiDataArchiveService.formatIdentifier, "com.fluentdesign.weekyii.archive")
        XCTAssertEqual(WeekyiiDataArchiveService.currentFormatVersion, 1)
        XCTAssertEqual(WeekyiiDataArchiveService.currentSchemaVersion, 8)
        XCTAssertFalse(encoded.contains("syncEngineState"))
        XCTAssertFalse(encoded.contains("entityBaselines"))
        XCTAssertFalse(encoded.contains("automaticRetrySuppressed"))
        XCTAssertTrue(encoded.contains("appState"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("weekyii-cloud-metadata-\(UUID().uuidString)", isDirectory: true)
    }
}

@MainActor
final class CloudSyncRetryPolicyTests: XCTestCase {
    func test_transientRetryBudgetUsesBoundedBackoffAndServerRetryAfter() {
        let policy = CloudSyncRetryPolicy()

        XCTAssertEqual(policy.classify(.networkUnavailable).category, .transient)
        XCTAssertEqual(policy.retryDecision(for: .networkFailure, retryNumber: 1), .retry(after: 1))
        XCTAssertEqual(policy.retryDecision(for: .serviceUnavailable(retryAfter: nil), retryNumber: 2), .retry(after: 4))
        XCTAssertEqual(policy.retryDecision(for: .requestRateLimited(retryAfter: 7), retryNumber: 1), .retry(after: 7))
        XCTAssertEqual(policy.retryDecision(for: .zoneBusy(retryAfter: 90), retryNumber: 2), .retry(after: 30))
        XCTAssertEqual(policy.retryDecision(for: .networkFailure, retryNumber: 3), .stop(category: .transient))
    }

    func test_terminalAndConflictFailuresNeverUseNetworkRetryBudget() {
        let policy = CloudSyncRetryPolicy()
        let terminalFailures: [CloudSyncFailure] = [
            .quotaExceeded, .notAuthenticated, .permissionFailure, .invalidArguments,
            .badContainer, .accountActionRequired, .entitlementActionRequired, .transportNotReady
        ]

        for failure in terminalFailures {
            XCTAssertEqual(policy.classify(failure).category, .terminal)
            XCTAssertEqual(policy.retryDecision(for: failure, retryNumber: 1), .stop(category: .terminal))
        }
        XCTAssertEqual(policy.classify(.serverRecordChanged).category, .conflict)
        XCTAssertEqual(policy.retryDecision(for: .serverRecordChanged, retryNumber: 1), .stop(category: .conflict))
    }

    func test_partialFailureRetainsPerRecordRetryClassification() throws {
        let retryableKey = SyncEntityKey(kind: .task, businessId: "task:1")
        let terminalKey = SyncEntityKey(kind: .taskType, businessId: "自定义:/类型")
        let failure = CloudSyncFailure.partialFailure([
            CloudSyncRecordFailure(entityKey: retryableKey, failure: .serviceUnavailable(retryAfter: 3)),
            CloudSyncRecordFailure(entityKey: terminalKey, failure: .permissionFailure)
        ])
        let policy = CloudSyncRetryPolicy()
        let classification = policy.classify(failure)
        let decisions = try XCTUnwrap(policy.perRecordRetryDecisions(for: failure, retryNumber: 1))

        XCTAssertEqual(classification.category, .partialFailure)
        XCTAssertEqual(classification.perRecord.map(\.entityKey), [retryableKey, terminalKey])
        XCTAssertEqual(classification.perRecord.map(\.category), [.transient, .terminal])
        XCTAssertEqual(decisions, [
            CloudSyncRecordRetryDecision(entityKey: retryableKey, decision: .retry(after: 3)),
            CloudSyncRecordRetryDecision(entityKey: terminalKey, decision: .stop(category: .terminal))
        ])
    }
}
