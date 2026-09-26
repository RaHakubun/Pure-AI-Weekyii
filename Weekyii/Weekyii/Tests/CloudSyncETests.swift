import Foundation
import SwiftData
import XCTest
@testable import Weekyii

@MainActor
final class CloudSyncReconcilerTests: XCTestCase {
    func test_localOnlyInsertUploadsAndEstablishesPerEntityBaseline() async throws {
        let entity = CloudSyncEntity.task(task(title: "local insert"))
        let harness = try await makeHarness(local: snapshot([entity]))

        let report = try await harness.reconciler().reconcile()
        let remote = await harness.remoteRecords()
        let metadata = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: harness.account))

        XCTAssertEqual(report.localUpserts, 1)
        XCTAssertEqual(remote.map(\.entityKey), [entity.key])
        XCTAssertEqual(metadata.entityBaselines[entity.key]?.lastSyncedHash, try CloudRecordCodec.encode(entity).payloadHash)
    }

    func test_remoteOnlyInsertAppliesLocallyWithoutUploadingItBack() async throws {
        let remote = try CloudRecordCodec.encode(.task(task(title: "remote insert")))
        let harness = try await makeHarness(local: snapshot([]), seedRecords: [remote])

        let report = try await harness.reconciler().reconcile()

        XCTAssertEqual(harness.localStore.snapshot.tasks.map(\.title), ["remote insert"])
        XCTAssertEqual(report.remoteAppliedUpserts, 1)
        XCTAssertEqual(report.localUpserts, 0)
    }

    func test_localUpdateUploadsWhenRemoteIsUnchanged() async throws {
        let base = task(title: "base")
        let original = CloudSyncEntity.task(base)
        let updated = CloudSyncEntity.task(task(id: base.id, title: "local edit"))
        let harness = try await makeHarness(local: snapshot([updated]), seedRecords: [try CloudRecordCodec.encode(original)])
        try await harness.establishBaseline([original])

        let report = try await harness.reconciler().reconcile()

        XCTAssertEqual(report.localUpserts, 1)
        let remoteRecords = await harness.remoteRecords()
        XCTAssertEqual(try CloudRecordCodec.decode(try XCTUnwrap(remoteRecords.first)), updated)
    }

    func test_remoteUpdateAppliesWhenLocalMatchesBaseline() async throws {
        let base = CloudSyncEntity.task(task(title: "base"))
        let updated = CloudSyncEntity.task(task(id: try taskID(from: base), title: "remote edit"))
        let harness = try await makeHarness(local: snapshot([base]), seedRecords: [try CloudRecordCodec.encode(base)])
        try await harness.establishBaseline([base])
        _ = await harness.transport.upsert([try CloudRecordCodec.encode(updated)])

        let report = try await harness.reconciler().reconcile()

        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "remote edit")
        XCTAssertEqual(report.remoteAppliedUpserts, 1)
        XCTAssertEqual(report.localUpserts, 0)
    }

    func test_sameIDConcurrentUpdateKeepsLocalAndUploadsIt() async throws {
        let base = CloudSyncEntity.task(task(title: "base"))
        let updatedRemote = CloudSyncEntity.task(task(id: try taskID(from: base), title: "remote edit"))
        let updatedLocal = CloudSyncEntity.task(task(id: try taskID(from: base), title: "local edit"))
        let harness = try await makeHarness(local: snapshot([updatedLocal]), seedRecords: [try CloudRecordCodec.encode(base)])
        try await harness.establishBaseline([base])
        _ = await harness.transport.upsert([try CloudRecordCodec.encode(updatedRemote)])

        let report = try await harness.reconciler().reconcile()
        let remoteRecords = await harness.remoteRecords()
        let uploaded = try XCTUnwrap(remoteRecords.first)

        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "local edit")
        XCTAssertEqual(try CloudRecordCodec.decode(uploaded), updatedLocal)
        XCTAssertGreaterThanOrEqual(report.conflicts, 1)
    }

    func test_localDeleteDeletesRemoteRecord() async throws {
        let original = CloudSyncEntity.task(task(title: "delete"))
        let harness = try await makeHarness(local: snapshot([]), seedRecords: [try CloudRecordCodec.encode(original)])
        try await harness.establishBaseline([original])

        let report = try await harness.reconciler().reconcile()

        let remoteRecords = await harness.remoteRecords()
        XCTAssertTrue(remoteRecords.isEmpty)
        XCTAssertEqual(report.localDeletionsSent, 1)
        XCTAssertNil(try harness.metadataStore.load(forAccountRecordName: harness.account)?.entityBaselines[original.key])
    }

    func test_remoteDeleteRemovesUnchangedLocalEntity() async throws {
        let original = CloudSyncEntity.task(task(title: "delete remotely"))
        let harness = try await makeHarness(local: snapshot([original]), seedRecords: [try CloudRecordCodec.encode(original)])
        try await harness.establishBaseline([original])
        _ = await harness.transport.delete([original.key])

        let report = try await harness.reconciler().reconcile()

        XCTAssertTrue(harness.localStore.snapshot.tasks.isEmpty)
        XCTAssertEqual(report.remoteDeletionsApplied, 1)
    }

    func test_remoteDeleteWithLocalEditRecreatesRemoteAndPreservesLocal() async throws {
        let base = CloudSyncEntity.task(task(title: "base"))
        let edit = CloudSyncEntity.task(task(id: try taskID(from: base), title: "edited offline"))
        let harness = try await makeHarness(local: snapshot([edit]), seedRecords: [try CloudRecordCodec.encode(base)])
        try await harness.establishBaseline([base])
        _ = await harness.transport.delete([base.key])

        let report = try await harness.reconciler().reconcile()

        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "edited offline")
        let remoteRecords = await harness.remoteRecords()
        XCTAssertEqual(try CloudRecordCodec.decode(try XCTUnwrap(remoteRecords.first)), edit)
        XCTAssertEqual(report.localUpserts, 1)
        XCTAssertGreaterThanOrEqual(report.conflicts, 1)
    }

    func test_differentIDInsertsAreUnioned() async throws {
        let local = CloudSyncEntity.task(task(title: "local"))
        let remote = try CloudRecordCodec.encode(.task(task(title: "remote")))
        let harness = try await makeHarness(local: snapshot([local]), seedRecords: [remote])

        _ = try await harness.reconciler().reconcile()

        guard case .task(let localTask) = local,
              case .task(let remoteTask) = try CloudRecordCodec.decode(remote) else {
            return XCTFail("Fixtures must decode to task entities")
        }
        XCTAssertEqual(Set(harness.localStore.snapshot.tasks.map(\.id)), Set([localTask.id, remoteTask.id]))
        let remoteRecords = await harness.remoteRecords()
        XCTAssertEqual(remoteRecords.count, 2)
    }

    func test_blobOnlyAttachmentEditDoesNotDirtyOwningTask() async throws {
        let taskID = UUID()
        let attachmentID = UUID()
        let taskValue = CloudSyncEntity.task(task(id: taskID, title: "owner", attachmentIds: [attachmentID]))
        let attachmentBefore = CloudSyncEntity.attachment(attachment(id: attachmentID, owner: .task(taskID), bytes: [1]))
        let harness = try await makeHarness(
            local: snapshot([taskValue, .attachment(attachment(id: attachmentID, owner: .task(taskID), bytes: [2]))]),
            seedRecords: [try CloudRecordCodec.encode(taskValue), try CloudRecordCodec.encode(attachmentBefore)]
        )
        try await harness.establishBaseline([taskValue, attachmentBefore])

        let report = try await harness.reconciler().reconcile()

        XCTAssertEqual(report.localUpserts, 1)
        let records = await harness.remoteRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.filter { $0.kind == .attachment }.count, 1)
        XCTAssertEqual(records.first(where: { $0.kind == .task })?.payloadHash, try CloudRecordCodec.encode(taskValue).payloadHash)
        XCTAssertEqual(records.first(where: { $0.kind == .attachment })?.blob?.data, Data([2]))
    }

    func test_attachmentMoveKeepsUUIDAndUploadsOneAttachmentAggregate() async throws {
        let taskID = UUID()
        let suspendedID = UUID()
        let attachmentID = UUID()
        let beforeTask = CloudSyncEntity.task(task(id: taskID, title: "task", attachmentIds: [attachmentID]))
        let beforeSuspended = CloudSyncEntity.suspendedTask(suspendedTask(id: suspendedID, attachmentIds: []))
        let beforeAttachment = CloudSyncEntity.attachment(attachment(id: attachmentID, owner: .task(taskID), bytes: [7]))
        let afterTask = CloudSyncEntity.task(task(id: taskID, title: "task", attachmentIds: []))
        let afterSuspended = CloudSyncEntity.suspendedTask(suspendedTask(id: suspendedID, attachmentIds: [attachmentID]))
        let afterAttachment = CloudSyncEntity.attachment(attachment(id: attachmentID, owner: .suspendedTask(suspendedID), bytes: [7]))
        let harness = try await makeHarness(
            local: snapshot([afterTask, afterSuspended, afterAttachment]),
            seedRecords: try [beforeTask, beforeSuspended, beforeAttachment].map(CloudRecordCodec.encode)
        )
        try await harness.establishBaseline([beforeTask, beforeSuspended, beforeAttachment])

        let report = try await harness.reconciler().reconcile()
        let remote = await harness.remoteRecords()

        XCTAssertEqual(remote.filter { $0.kind == .attachment }.count, 1)
        XCTAssertEqual(remote.first(where: { $0.kind == .attachment })?.entityKey, afterAttachment.key)
        XCTAssertEqual(try CloudRecordCodec.decode(try XCTUnwrap(remote.first(where: { $0.kind == .attachment }))), afterAttachment)
        XCTAssertEqual(report.localUpserts, 3, "owner membership changes each owning aggregate and the attachment aggregate")
    }

    func test_attachmentDeletionSendsAttachmentTombstoneAndUpdatedMembership() async throws {
        let taskID = UUID()
        let attachmentID = UUID()
        let taskBefore = CloudSyncEntity.task(task(id: taskID, title: "owner", attachmentIds: [attachmentID]))
        let taskAfter = CloudSyncEntity.task(task(id: taskID, title: "owner", attachmentIds: []))
        let attachment = CloudSyncEntity.attachment(attachment(id: attachmentID, owner: .task(taskID), bytes: [8]))
        let harness = try await makeHarness(
            local: snapshot([taskAfter]),
            seedRecords: try [taskBefore, attachment].map(CloudRecordCodec.encode)
        )
        try await harness.establishBaseline([taskBefore, attachment])

        let report = try await harness.reconciler().reconcile()
        let remote = await harness.remoteRecords()

        XCTAssertEqual(remote.map(\.entityKey), [taskAfter.key])
        XCTAssertEqual(try CloudRecordCodec.decode(try XCTUnwrap(remote.first)), taskAfter)
        XCTAssertEqual(report.localUpserts, 1)
        XCTAssertEqual(report.localDeletionsSent, 1)
    }

    func test_mindStampBinaryUpdateUsesSeparateBlobChannel() async throws {
        let id = UUID()
        let before = CloudSyncEntity.mindStamp(MindStampSnapshot(id: id, text: "stamp", imageBlob: Data([1]), createdAt: date(1)))
        let after = CloudSyncEntity.mindStamp(MindStampSnapshot(id: id, text: "stamp", imageBlob: Data([2, 3]), createdAt: date(1)))
        let harness = try await makeHarness(local: snapshot([after]), seedRecords: [try CloudRecordCodec.encode(before)])
        try await harness.establishBaseline([before])

        _ = try await harness.reconciler().reconcile()
        let remoteRecords = await harness.remoteRecords()
        let remote = try XCTUnwrap(remoteRecords.first)
        let payload = String(decoding: remote.payload, as: UTF8.self)

        XCTAssertEqual(remote.blob?.role, .mindStampImage)
        XCTAssertEqual(remote.blob?.data, Data([2, 3]))
        XCTAssertFalse(payload.contains(Data([2, 3]).base64EncodedString()))
    }

    func test_partialFailureAdvancesOnlySuccessfulSiblingBaseline() async throws {
        let first = CloudSyncEntity.task(task(title: "fails"))
        let second = CloudSyncEntity.task(task(title: "succeeds"))
        let harness = try await makeHarness(local: snapshot([first, second]))
        let memoryTransport = try XCTUnwrap(harness.memoryTransport)
        await memoryTransport.injectFailure(.quotaExceeded, for: first.key, operation: .upsert)

        let report = try await harness.reconciler().reconcile()
        let metadata = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: harness.account))

        XCTAssertEqual(report.perRecordFailures.map(\.entityKey), [first.key])
        XCTAssertNil(metadata.entityBaselines[first.key])
        XCTAssertNotNil(metadata.entityBaselines[second.key])
        let remoteRecords = await harness.remoteRecords()
        XCTAssertEqual(remoteRecords.map(\.entityKey), [second.key])
    }

    func test_serverRecordChangedFetchesLatestAndResendsLocalOnlyOnce() async throws {
        let base = CloudSyncEntity.task(task(title: "base"))
        let local = CloudSyncEntity.task(task(id: try taskID(from: base), title: "local winner"))
        let latestRemote = try CloudRecordCodec.encode(.task(task(id: try taskID(from: base), title: "newer server version")))
        let baseTransport = InMemoryCloudSyncTransport(seedRecords: [try CloudRecordCodec.encode(base)])
        let transport = ConflictOnceTransport(base: baseTransport, conflictKey: base.key, latestRecord: latestRemote)
        let harness = try await makeHarness(local: snapshot([local]), transport: transport)
        try await harness.establishBaseline([base])

        let report = try await harness.reconciler().reconcile()

        let upsertAttempts = await transport.upsertAttempts(for: base.key)
        let remoteRecords = await baseTransport.remoteRecords()
        XCTAssertEqual(upsertAttempts, 2)
        XCTAssertEqual(try CloudRecordCodec.decode(try XCTUnwrap(remoteRecords.first)), local)
        XCTAssertTrue(report.perRecordFailures.isEmpty)
        XCTAssertGreaterThanOrEqual(report.conflicts, 1)
    }

    func test_localEditDuringSuspendedFetchIsNotOverwritten() async throws {
        let base = CloudSyncEntity.task(task(title: "base"))
        let updatedRemote = try CloudRecordCodec.encode(.task(task(id: try taskID(from: base), title: "remote update")))
        let gate = TestAsyncGate()
        let baseTransport = InMemoryCloudSyncTransport(seedRecords: [try CloudRecordCodec.encode(base)])
        let transport = GatedCloudSyncTransport(base: baseTransport, gate: gate)
        let harness = try await makeHarness(local: snapshot([base]), transport: transport)
        try await harness.establishBaseline([base])
        _ = await baseTransport.upsert([updatedRemote])

        await transport.suspendNextFetch()
        let running = Task { try await harness.reconciler().reconcile() }
        await gate.waitUntilEntered()
        harness.localStore.snapshot = snapshot([.task(task(id: try taskID(from: base), title: "edited while waiting"))])
        await gate.release()
        let report = try await running.value

        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "edited while waiting")
        let remoteRecords = await baseTransport.remoteRecords()
        guard case .task(let uploadedTask) = try CloudRecordCodec.decode(try XCTUnwrap(remoteRecords.first)) else {
            return XCTFail("Expected the local task to remain the uploaded winner")
        }
        XCTAssertEqual(uploadedTask.title, "edited while waiting")
        XCTAssertEqual(harness.localStore.applyCount, 0, "the remote winner was converted to a local upload before any stale apply")
        XCTAssertGreaterThanOrEqual(report.conflicts, 1)
    }

    func test_remoteHabitDayRecordsWithDifferentUUIDsConvergeDeterministically() async throws {
        let habit = HabitSnapshot(id: UUID(), name: "habit", iconName: "repeat", colorHex: "#123456", categoryRaw: "health", scheduleKindRaw: "weekly", scheduleWeekdaysRaw: 31, scheduleMonthDaysRaw: 0, startDayId: "2026-09-01", isActive: true, createdAt: date(0), sortOrder: 0)
        let completed = HabitDayRecordSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, habitId: habit.id, dayId: "2026-09-25", statusRaw: "completed", createdAt: date(1), completedAt: date(2))
        let missed = HabitDayRecordSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, habitId: habit.id, dayId: "2026-09-25", statusRaw: "missed", createdAt: date(3), completedAt: nil)
        let remote = try [CloudSyncEntity.habit(habit), .habitDayRecord(completed), .habitDayRecord(missed)].map(CloudRecordCodec.encode)
        let harness = try await makeHarness(local: snapshot([]), seedRecords: remote)

        let report = try await harness.reconciler().reconcile()
        let records = harness.localStore.snapshot.habitDayRecords

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, completed.id)
        XCTAssertEqual(records.first?.statusRaw, HabitDayRecordStatus.completed.rawValue)
        XCTAssertEqual(records.first?.completedAt, date(2))
        XCTAssertEqual(report.semanticHabitDuplicateGroups, 1)
        let remoteRecords = await harness.remoteRecords()
        XCTAssertFalse(remoteRecords.contains { $0.entityKey == missed.entityKey })
    }

    func test_swiftDataApplyRebuildsAllExplicitRelationshipsWithoutReplacingStore() async throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let storeURL = WeekyiiPersistence.persistentStoreURL()
        let week = WeekSnapshot(weekId: "2026-W39", startDate: date(0), endDate: date(6), status: .present, completedTasksCount: 0, expiredTasksCount: 0, totalStartedDays: 0)
        let day = DaySnapshot(dayId: "2026-09-25", weekId: week.weekId, date: date(1), dayOfWeek: "Fri", status: .draft, killTimeHour: 20, killTimeMinute: 0, followsDefaultKillTime: true, initiatedAt: nil, closedAt: nil, executionModeRaw: ExecutionMode.strict.rawValue, isDraftZoneUnlocked: false, expiredCount: 0)
        let projectID = UUID()
        let habitID = UUID()
        let taskID = UUID()
        let attachmentID = UUID()
        let habitDayID = UUID()
        let project = ProjectSnapshot(id: projectID, name: "project", projectDescription: "", color: "#112233", icon: "folder", status: .active, startDate: date(0), endDate: date(20), createdAt: date(0), tileSizeRaw: "medium", tileOrder: 0)
        let habit = HabitSnapshot(id: habitID, name: "habit", iconName: "repeat", colorHex: "#112233", categoryRaw: "health", scheduleKindRaw: "weekly", scheduleWeekdaysRaw: 31, scheduleMonthDaysRaw: 0, startDayId: "2026-09-25", isActive: true, createdAt: date(0), sortOrder: 0)
        let attachment = AttachmentSnapshot(id: attachmentID, owner: .task(taskID), data: Data([1, 2]), fileName: "a", fileType: "application/octet-stream", createdAt: date(1))
        let taskValue = TaskSnapshot(id: taskID, dayId: day.dayId, projectId: projectID, habitId: habitID, title: "task", taskDescription: "", taskType: .regular, taskTypeIdRaw: "regular", order: 0, zone: .draft, startedAt: nil, endedAt: nil, completedOrder: 0, steps: [StepSnapshot(title: "step", isCompleted: false, sortOrder: 0, createdAt: date(1))], attachmentIds: [attachmentID])
        let log = HabitDayRecordSnapshot(id: habitDayID, habitId: habitID, dayId: day.dayId, statusRaw: "completed", createdAt: date(1), completedAt: date(2))
        let target = WeekyiiBusinessSnapshot(weeks: [week], days: [day], tasks: [taskValue], suspendedTasks: [], attachments: [attachment], projects: [project], mindStamps: [], taskTypes: [], habits: [habit], habitDayRecords: [log])
        let localStore = SwiftDataCloudSyncLocalStore(context: context)

        try localStore.apply(target)
        let applied = try localStore.currentSnapshot()
        let taskModel = try XCTUnwrap(context.fetch(FetchDescriptor<TaskItem>()).first)
        let dayModel = try XCTUnwrap(context.fetch(FetchDescriptor<DayModel>()).first)
        let attachmentModel = try XCTUnwrap(context.fetch(FetchDescriptor<TaskAttachment>()).first)
        let habitModel = try XCTUnwrap(context.fetch(FetchDescriptor<HabitModel>()).first)
        let recordModel = try XCTUnwrap(context.fetch(FetchDescriptor<HabitDayRecord>()).first)

        XCTAssertEqual(applied, target)
        XCTAssertEqual(dayModel.week?.weekId, week.weekId)
        XCTAssertEqual(taskModel.day?.dayId, day.dayId)
        XCTAssertEqual(taskModel.project?.id, projectID)
        XCTAssertEqual(taskModel.habit?.id, habitID)
        XCTAssertEqual(attachmentModel.task?.id, taskID)
        XCTAssertEqual(recordModel.habit?.id, habitID)
        XCTAssertEqual(habitModel.generatedThroughDayId, "")
        XCTAssertEqual(WeekyiiPersistence.persistentStoreURL(), storeURL)
    }

    func test_remoteChangeOrderingDoesNotChangeAppliedSwiftDataGraph() async throws {
        let week = WeekSnapshot(weekId: "2026-W39", startDate: date(0), endDate: date(6), status: .present, completedTasksCount: 0, expiredTasksCount: 0, totalStartedDays: 0)
        let day = DaySnapshot(dayId: "2026-09-25", weekId: week.weekId, date: date(1), dayOfWeek: "Fri", status: .draft, killTimeHour: 20, killTimeMinute: 0, followsDefaultKillTime: true, initiatedAt: nil, closedAt: nil, executionModeRaw: ExecutionMode.strict.rawValue, isDraftZoneUnlocked: false, expiredCount: 0)
        let projectID = UUID()
        let habitID = UUID()
        let taskID = UUID()
        let attachmentID = UUID()
        let habitDayID = UUID()
        let entities: [CloudSyncEntity] = [
            .week(week),
            .day(day),
            .project(ProjectSnapshot(id: projectID, name: "project", projectDescription: "", color: "#112233", icon: "folder", status: .active, startDate: date(0), endDate: date(20), createdAt: date(0), tileSizeRaw: "medium", tileOrder: 0)),
            .habit(HabitSnapshot(id: habitID, name: "habit", iconName: "repeat", colorHex: "#112233", categoryRaw: "health", scheduleKindRaw: "weekly", scheduleWeekdaysRaw: 31, scheduleMonthDaysRaw: 0, startDayId: "2026-09-25", isActive: true, createdAt: date(0), sortOrder: 0)),
            .task(TaskSnapshot(id: taskID, dayId: day.dayId, projectId: projectID, habitId: habitID, title: "task", taskDescription: "", taskType: .regular, taskTypeIdRaw: "regular", order: 0, zone: .draft, startedAt: nil, endedAt: nil, completedOrder: 0, steps: [], attachmentIds: [attachmentID])),
            .attachment(attachment(id: attachmentID, owner: .task(taskID), bytes: [1, 2])),
            .habitDayRecord(HabitDayRecordSnapshot(id: habitDayID, habitId: habitID, dayId: day.dayId, statusRaw: "completed", createdAt: date(1), completedAt: date(2)))
        ]
        let records = try entities.map(CloudRecordCodec.encode)
        let forwardSnapshot = try await applyRemoteRecords(records, reversed: false)
        let reversedSnapshot = try await applyRemoteRecords(records, reversed: true)

        XCTAssertEqual(forwardSnapshot, reversedSnapshot)
        XCTAssertEqual(forwardSnapshot.tasks.first?.dayId, day.dayId)
        XCTAssertEqual(forwardSnapshot.tasks.first?.projectId, projectID)
        XCTAssertEqual(forwardSnapshot.tasks.first?.habitId, habitID)
        XCTAssertEqual(forwardSnapshot.attachments.first?.owner, .task(taskID))
        XCTAssertEqual(forwardSnapshot.habitDayRecords.first?.habitId, habitID)
    }

    private func applyRemoteRecords(_ records: [CloudSyncRecord], reversed: Bool) async throws -> WeekyiiBusinessSnapshot {
        let base = InMemoryCloudSyncTransport(seedRecords: records)
        let transport = OrderedChangeCloudSyncTransport(base: base, reverseChanges: reversed)
        _ = try await transport.ensureInfrastructure()
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let localStore = SwiftDataCloudSyncLocalStore(context: container.mainContext)
        let metadataRoot = FileManager.default.temporaryDirectory.appendingPathComponent("WeekyiiSyncEOrder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: metadataRoot) }
        let metadataStore = CloudSyncMetadataStore(rootURL: metadataRoot)
        let account = "change-order-\(UUID().uuidString)"
        let reconciler = CloudSyncReconciler(localStore: localStore, transport: transport, metadataStore: metadataStore, accountRecordName: account)

        _ = try await reconciler.reconcile()
        return try localStore.currentSnapshot()
    }

    // MARK: Harness

    func test_reconcileCommitPreservesTransportStateAndNewReverseIndexWrittenDuringFetch() async throws {
        let original = CloudSyncEntity.task(task(title: "before fetch"))
        let updated = CloudSyncEntity.task(task(id: try taskID(from: original), title: "remote update"))
        let base = InMemoryCloudSyncTransport(seedRecords: [try CloudRecordCodec.encode(original)])
        let gate = TestAsyncGate()
        let gated = GatedCloudSyncTransport(base: base, gate: gate)
        let harness = try await makeHarness(local: snapshot([original]), transport: gated, memoryTransport: base)
        try await harness.establishBaseline([original])
        _ = await base.upsert([try CloudRecordCodec.encode(updated)])
        await gated.suspendNextFetch()

        let running = Task { try await harness.reconciler().reconcile() }
        await gate.waitUntilEntered()
        let extraKey = SyncEntityKey(kind: .task, businessId: UUID().uuidString)
        let extraName = CKRecordNameCodec.recordName(for: extraKey)
        try harness.metadataStore.update(forAccountRecordName: harness.account) { metadata in
            metadata.syncEngineState = Data([0x44, 0x55])
            metadata.remember(extraKey, recordName: extraName)
        }
        await gate.release()
        _ = try await running.value

        let committed = try XCTUnwrap(harness.metadataStore.load(forAccountRecordName: harness.account))
        XCTAssertEqual(harness.localStore.snapshot.tasks.first?.title, "remote update")
        XCTAssertEqual(committed.syncEngineState, Data([0x44, 0x55]))
        XCTAssertEqual(committed.entityKey(forRecordName: extraName), extraKey)
        XCTAssertEqual(committed.entityBaselines[original.key]?.lastSyncedHash, try CloudRecordCodec.encode(updated).payloadHash)
    }

    @MainActor
    private struct Harness {
        let localStore: MemoryCloudSyncLocalStore
        let transport: any CloudSyncTransport
        let memoryTransport: InMemoryCloudSyncTransport?
        let metadataStore: CloudSyncMetadataStore
        let metadataRoot: URL
        let account: String

        func reconciler() -> CloudSyncReconciler {
            CloudSyncReconciler(localStore: localStore, transport: transport, metadataStore: metadataStore, accountRecordName: account, now: { Date(timeIntervalSince1970: 864_000) })
        }

        func remoteRecords() async -> [CloudSyncRecord] {
            await memoryTransport?.remoteRecords() ?? []
        }

        func establishBaseline(_ entities: [CloudSyncEntity]) async throws {
            let token = try await transport.fetchChanges(since: nil).nextToken
            let hash = try CloudSyncMetadataStore.accountHash(for: account)
            var metadata = CloudSyncMetadata(accountHash: hash)
            metadata.remoteChangeToken = token
            for entity in entities {
                let record = try CloudRecordCodec.encode(entity)
                metadata.entityBaselines[entity.key] = CloudSyncEntityBaseline(lastSyncedHash: record.payloadHash, recordName: record.recordName)
                metadata.remember(entity.key, recordName: record.recordName)
            }
            try metadataStore.save(metadata, forAccountRecordName: account)
        }
    }

    private func makeHarness(
        local: WeekyiiBusinessSnapshot,
        seedRecords: [CloudSyncRecord] = []
    ) async throws -> Harness {
        let transport = InMemoryCloudSyncTransport(seedRecords: seedRecords)
        _ = try await transport.ensureInfrastructure()
        return try await makeHarness(local: local, transport: transport)
    }

    private func makeHarness(
        local: WeekyiiBusinessSnapshot,
        transport: InMemoryCloudSyncTransport
    ) async throws -> Harness {
        try await makeHarness(local: local, transport: transport, memoryTransport: transport)
    }

    private func makeHarness(
        local: WeekyiiBusinessSnapshot,
        transport: any CloudSyncTransport,
        memoryTransport: InMemoryCloudSyncTransport? = nil
    ) async throws -> Harness {
        _ = try await transport.ensureInfrastructure()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeekyiiSyncETest-\(UUID().uuidString)")
        let account = "test-account-\(UUID().uuidString)"
        let metadataStore = CloudSyncMetadataStore(rootURL: root)
        let metadata = CloudSyncMetadata(accountHash: try CloudSyncMetadataStore.accountHash(for: account))
        try metadataStore.save(metadata, forAccountRecordName: account)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Harness(localStore: MemoryCloudSyncLocalStore(snapshot: local), transport: transport, memoryTransport: memoryTransport, metadataStore: metadataStore, metadataRoot: root, account: account)
    }

    private func snapshot(_ entities: [CloudSyncEntity]) -> WeekyiiBusinessSnapshot {
        var weeks: [WeekSnapshot] = []; var days: [DaySnapshot] = []; var tasks: [TaskSnapshot] = []
        var suspended: [SuspendedTaskSnapshot] = []; var attachments: [AttachmentSnapshot] = []; var projects: [ProjectSnapshot] = []
        var stamps: [MindStampSnapshot] = []; var types: [TaskTypeSnapshot] = []; var habits: [HabitSnapshot] = []; var records: [HabitDayRecordSnapshot] = []
        for entity in entities {
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

    private func task(id: UUID = UUID(), title: String, attachmentIds: [UUID] = []) -> TaskSnapshot {
        TaskSnapshot(id: id, dayId: nil, projectId: nil, habitId: nil, title: title, taskDescription: "", taskType: .regular, taskTypeIdRaw: "regular", order: 0, zone: .draft, startedAt: nil, endedAt: nil, completedOrder: 0, steps: [], attachmentIds: attachmentIds)
    }

    private func taskID(from entity: CloudSyncEntity) throws -> UUID {
        guard case .task(let value) = entity else { throw CloudRecordCodecError.entityKeyMismatch }
        return value.id
    }

    private func attachment(id: UUID, owner: AttachmentOwner, bytes: [UInt8]) -> AttachmentSnapshot {
        AttachmentSnapshot(id: id, owner: owner, data: Data(bytes), fileName: "asset.bin", fileType: "application/octet-stream", createdAt: date(1))
    }

    private func suspendedTask(id: UUID, attachmentIds: [UUID]) -> SuspendedTaskSnapshot {
        SuspendedTaskSnapshot(id: id, title: "suspended", taskDescription: "", taskType: .regular, taskTypeIdRaw: "regular", createdAt: date(0), decisionDeadline: date(10), preferredCountdownDays: 10, snoozeCount: 0, statusRaw: "active", steps: [], attachmentIds: attachmentIds)
    }

    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day * 86_400)) }
}

@MainActor
private final class MemoryCloudSyncLocalStore: CloudSyncLocalStore {
    var snapshot: WeekyiiBusinessSnapshot
    private(set) var applyCount = 0

    init(snapshot: WeekyiiBusinessSnapshot) { self.snapshot = snapshot }
    func currentSnapshot() throws -> WeekyiiBusinessSnapshot { snapshot }
    func apply(_ snapshot: WeekyiiBusinessSnapshot) throws { self.snapshot = snapshot; applyCount += 1 }
}

private actor TestAsyncGate {
    private var isEntered = false
    private var operationContinuation: CheckedContinuation<Void, Never>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            operationContinuation = continuation
            isEntered = true
            enteredContinuation?.resume()
            enteredContinuation = nil
        }
    }

    func waitUntilEntered() async {
        guard !isEntered else { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func release() {
        operationContinuation?.resume()
        operationContinuation = nil
    }
}

private actor OrderedChangeCloudSyncTransport: CloudSyncTransport {
    private let base: InMemoryCloudSyncTransport
    private let reverseChanges: Bool

    init(base: InMemoryCloudSyncTransport, reverseChanges: Bool) {
        self.base = base
        self.reverseChanges = reverseChanges
    }

    var databaseScope: CloudSyncDatabaseScope { get async { await base.databaseScope } }

    func ensureInfrastructure() async throws -> CloudSyncRemoteInfrastructure {
        try await base.ensureInfrastructure()
    }

    func inspectRemoteZone() async throws -> CloudSyncZoneInspection {
        try await base.inspectRemoteZone()
    }

    func resetCustomZone() async throws {
        try await base.resetCustomZone()
    }

    func fetchChanges(since token: Data?) async throws -> CloudSyncChangeBatch {
        let batch = try await base.fetchChanges(since: token)
        return CloudSyncChangeBatch(changes: reverseChanges ? Array(batch.changes.reversed()) : batch.changes, nextToken: batch.nextToken)
    }

    func upsert(_ records: [CloudSyncRecord]) async -> [CloudSyncRecordResult] {
        await base.upsert(records)
    }

    func delete(_ keys: [SyncEntityKey]) async -> [CloudSyncRecordResult] {
        await base.delete(keys)
    }

    func restoreTransportState(_ state: Data?) async {
        await base.restoreTransportState(state)
    }

    func persistedTransportState() async -> Data? {
        await base.persistedTransportState()
    }
}

private actor GatedCloudSyncTransport: CloudSyncTransport {
    private let base: InMemoryCloudSyncTransport
    private let gate: TestAsyncGate
    private var shouldSuspendNextFetch = false

    init(base: InMemoryCloudSyncTransport, gate: TestAsyncGate) {
        self.base = base
        self.gate = gate
    }

    var databaseScope: CloudSyncDatabaseScope { get async { await base.databaseScope } }

    func ensureInfrastructure() async throws -> CloudSyncRemoteInfrastructure {
        try await base.ensureInfrastructure()
    }

    func inspectRemoteZone() async throws -> CloudSyncZoneInspection {
        try await base.inspectRemoteZone()
    }

    func resetCustomZone() async throws {
        try await base.resetCustomZone()
    }

    func suspendNextFetch() {
        shouldSuspendNextFetch = true
    }

    func fetchChanges(since token: Data?) async throws -> CloudSyncChangeBatch {
        if shouldSuspendNextFetch {
            shouldSuspendNextFetch = false
            await gate.wait()
        }
        return try await base.fetchChanges(since: token)
    }

    func upsert(_ records: [CloudSyncRecord]) async -> [CloudSyncRecordResult] {
        await base.upsert(records)
    }

    func delete(_ keys: [SyncEntityKey]) async -> [CloudSyncRecordResult] {
        await base.delete(keys)
    }

    func restoreTransportState(_ state: Data?) async {
        await base.restoreTransportState(state)
    }

    func persistedTransportState() async -> Data? {
        await base.persistedTransportState()
    }
}

private actor ConflictOnceTransport: CloudSyncTransport {
    private let base: InMemoryCloudSyncTransport
    private let conflictKey: SyncEntityKey
    private let latestRecord: CloudSyncRecord
    private var attempts: [SyncEntityKey: Int] = [:]

    init(base: InMemoryCloudSyncTransport, conflictKey: SyncEntityKey, latestRecord: CloudSyncRecord) {
        self.base = base
        self.conflictKey = conflictKey
        self.latestRecord = latestRecord
    }

    var databaseScope: CloudSyncDatabaseScope { get async { await base.databaseScope } }

    func ensureInfrastructure() async throws -> CloudSyncRemoteInfrastructure {
        try await base.ensureInfrastructure()
    }

    func inspectRemoteZone() async throws -> CloudSyncZoneInspection {
        try await base.inspectRemoteZone()
    }

    func resetCustomZone() async throws {
        try await base.resetCustomZone()
    }

    func fetchChanges(since token: Data?) async throws -> CloudSyncChangeBatch {
        try await base.fetchChanges(since: token)
    }

    func upsert(_ records: [CloudSyncRecord]) async -> [CloudSyncRecordResult] {
        var results: [CloudSyncRecordResult] = []
        for record in records {
            attempts[record.entityKey, default: 0] += 1
            if record.entityKey == conflictKey, attempts[record.entityKey] == 1 {
                _ = await base.upsert([latestRecord])
                results.append(CloudSyncRecordResult(entityKey: conflictKey, outcome: .failed(.serverRecordChanged)))
            } else {
                results += await base.upsert([record])
            }
        }
        return results
    }

    func delete(_ keys: [SyncEntityKey]) async -> [CloudSyncRecordResult] {
        await base.delete(keys)
    }

    func restoreTransportState(_ state: Data?) async {
        await base.restoreTransportState(state)
    }

    func persistedTransportState() async -> Data? {
        await base.persistedTransportState()
    }

    func upsertAttempts(for key: SyncEntityKey) -> Int {
        attempts[key, default: 0]
    }
}
