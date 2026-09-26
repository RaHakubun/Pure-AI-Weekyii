import Foundation
import CryptoKit

// MARK: - Errors

enum WeekyiiSnapshotCodecError: LocalizedError, Hashable {
    /// Two entities in one snapshot claim the same business identity, so the sync
    /// layer could not address them separately.
    case duplicateEntityKey(SyncEntityKey)
    /// The two sides were produced by incompatible snapshot shapes. There is no
    /// migration yet, so this is a hard stop rather than a best-effort merge.
    case versionMismatch(local: Int, remote: Int)

    var errorDescription: String? {
        switch self {
        case .duplicateEntityKey(let key):
            return "快照里有两个实体共用同一个业务标识：\(key)。"
        case .versionMismatch(let local, let remote):
            return "快照版本不一致（本地 \(local)，远端 \(remote)），无法合并。"
        }
    }
}

// MARK: - Codec

/// Turns a snapshot into bytes, and turns content into hashes.
///
/// ## Two identity layers, and why they must not be collapsed
///
/// * **Blob hash** — SHA-256 of an attachment's bytes. Two attachments holding the
///   same bytes share a blob hash, but they are still *two entities*: their
///   identity is their `UUID`, so they keep distinct `SyncEntityKey`s and both
///   survive a merge. A blob hash is never an entity key.
/// * **Entity hash** — SHA-256 of one entity's own canonical encoding. For an
///   attachment that encoding includes its `blobSHA256` (so new bytes ⇒ new entity
///   hash), but for a *task* it includes only the attachment **ids**. That is what
///   keeps an unrelated attachment edit from marking the task as changed — the
///   whole point of hoisting attachments out of the task record (§D).
///
/// ## Canonical bytes
///
/// `.sortedKeys` plus the snapshot's own sorting makes the encoding a function of
/// the graph, not of the order SwiftData returned rows in. Dates are quantised to
/// milliseconds, so a wire round-trip is lossless to the millisecond — and because
/// every content comparison goes through `entityHash` rather than `==`,
/// quantisation cannot manufacture a conflict.
///
/// ## Scope of `encode` / `decode`
///
/// Whole-snapshot serialization, binaries included. That is what the local snapshot
/// file, the archive adapter and the tests need — and it is **not** a CloudKit record
/// payload encoder. Phase D goes through `CloudRecordCodec` and sends each binary as
/// a `CKAsset`; see `encode(_:)` for the full mapping.
enum WeekyiiSnapshotCodec {

    // MARK: Whole-snapshot serialization — not CloudKit record payload

    /// Serialises the **whole** snapshot, attachment and mind-stamp bytes included.
    ///
    /// That is deliberate at this layer: the local snapshot file, the archive adapter
    /// and the tests all need one lossless round-trip of the entire graph, bytes and
    /// all. It is **not** a CloudKit encoder, and Phase D must never call
    /// `encode(_:)` to build a record payload.
    ///
    /// A CloudKit payload is metadata-only — the binary travels out-of-band as a
    /// `CKAsset` — so Phase D owns a separate `CloudRecordCodec`:
    ///
    /// | snapshot | CloudKit |
    /// |---|---|
    /// | entity metadata | normal record fields |
    /// | `AttachmentSnapshot.data` | `CKAsset` |
    /// | `MindStampSnapshot.imageBlob` | `CKAsset` |
    ///
    /// That split is already possible because `entityHash` folds a binary in as its
    /// `blobSHA256` rather than as bytes: the metadata encoding never contained the
    /// payload in the first place.
    static func encode(_ snapshot: WeekyiiBusinessSnapshot) throws -> Data {
        try encoder().encode(snapshot)
    }

    /// Counterpart of `encode(_:)`; same whole-graph, bytes-included scope.
    static func decode(_ data: Data) throws -> WeekyiiBusinessSnapshot {
        try decoder().decode(WeekyiiBusinessSnapshot.self, from: data)
    }

    /// Canonical encoding of any value, for hashing and for diffing.
    static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    // MARK: Content identity

    /// SHA-256 of the attachment's bytes. `nil` in, `nil` out — "no bytes" and
    /// "zero bytes" are different states and must not hash alike.
    static func blobHash(_ data: Data?) -> String? {
        guard let data else { return nil }
        return hex(SHA256.hash(data: data))
    }

    static func entityHash<T: Encodable>(_ entity: T) throws -> String {
        hex(SHA256.hash(data: try encoder().encode(entity)))
    }

    /// Attachments hash through a view that replaces the binary with its
    /// `blobSHA256`, so the hash tracks content without carrying the payload.
    static func entityHash(_ attachment: AttachmentSnapshot) throws -> String {
        try entityHash(AttachmentHashView(attachment))
    }

    /// Mind-stamp images are blobs too, and get the same treatment.
    ///
    /// Without this the generic overload would hash the whole `Codable` structure
    /// including the raw `imageBlob`, which would (a) grow the metadata payload by
    /// the size of every image and (b) make it impossible to move the image
    /// out-of-band. Phase D must be free to map `MindStamp` metadata to record
    /// fields and `imageBlob` to a `CKAsset`; that only works if the metadata
    /// encoding never contained the bytes in the first place.
    static func entityHash(_ mindStamp: MindStampSnapshot) throws -> String {
        try entityHash(MindStampHashView(mindStamp))
    }

    /// Per-entity hashes for an incremental diff.
    ///
    /// Throws on a duplicate key rather than letting one entity overwrite the
    /// other: a snapshot that addresses two records with one key is exactly the
    /// state the merge must refuse.
    static func entityHashes(_ snapshot: WeekyiiBusinessSnapshot) throws -> [SyncEntityKey: String] {
        var hashes: [SyncEntityKey: String] = [:]

        func record(_ key: SyncEntityKey, _ hash: String) throws {
            guard hashes.updateValue(hash, forKey: key) == nil else {
                throw WeekyiiSnapshotCodecError.duplicateEntityKey(key)
            }
        }

        for week in snapshot.weeks { try record(week.entityKey, entityHash(week)) }
        for day in snapshot.days { try record(day.entityKey, entityHash(day)) }
        for task in snapshot.tasks { try record(task.entityKey, entityHash(task)) }
        for task in snapshot.suspendedTasks { try record(task.entityKey, entityHash(task)) }
        for attachment in snapshot.attachments { try record(attachment.entityKey, entityHash(attachment)) }
        for project in snapshot.projects { try record(project.entityKey, entityHash(project)) }
        for stamp in snapshot.mindStamps { try record(stamp.entityKey, entityHash(stamp)) }
        for taskType in snapshot.taskTypes { try record(taskType.entityKey, entityHash(taskType)) }
        for habit in snapshot.habits { try record(habit.entityKey, entityHash(habit)) }
        for record_ in snapshot.habitDayRecords { try record(record_.entityKey, entityHash(record_)) }

        return hashes
    }

    /// One hash for the whole snapshot, independent of array order.
    ///
    /// Built from the sorted per-entity hashes rather than from the encoded
    /// snapshot, so it is a function of entity content only — attachment *bytes*
    /// are folded in through each attachment's own entity hash.
    static func snapshotHash(_ snapshot: WeekyiiBusinessSnapshot) throws -> String {
        let hashes = try entityHashes(snapshot)
        var hasher = SHA256()
        for key in hashes.keys.sorted() {
            hasher.update(data: Data("\(key)\u{1F}\(hashes[key] ?? "")\n".utf8))
        }
        return hex(hasher.finalize())
    }

    // MARK: Plumbing

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

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The entity-layer view of an attachment: everything except the payload,
    /// with the payload represented by its blob hash and length.
    private struct AttachmentHashView: Encodable {
        let id: UUID
        let owner: AttachmentOwner
        let fileName: String
        let fileType: String
        let createdAt: Date
        let byteCount: Int
        let blobSHA256: String?

        init(_ attachment: AttachmentSnapshot) {
            self.id = attachment.id
            self.owner = attachment.owner
            self.fileName = attachment.fileName
            self.fileType = attachment.fileType
            self.createdAt = attachment.createdAt
            self.byteCount = attachment.data?.count ?? 0
            self.blobSHA256 = WeekyiiSnapshotCodec.blobHash(attachment.data)
        }
    }

    /// The entity-layer view of a mind stamp: metadata plus the image's length and
    /// blob hash, never the raw bytes.
    ///
    /// Deliberately mirrors `AttachmentHashView` field for field. The two are the
    /// only blob-carrying entities, and keeping them symmetric is what makes
    /// "metadata vs blob" a rule of the architecture rather than a one-off.
    private struct MindStampHashView: Encodable {
        let id: UUID
        let text: String
        let createdAt: Date
        let imageByteCount: Int
        let imageBlobSHA256: String?

        init(_ stamp: MindStampSnapshot) {
            self.id = stamp.id
            self.text = stamp.text
            self.createdAt = stamp.createdAt
            self.imageByteCount = stamp.imageBlob?.count ?? 0
            self.imageBlobSHA256 = WeekyiiSnapshotCodec.blobHash(stamp.imageBlob)
        }
    }
}

// MARK: - Merge

/// What a merge did, entity by entity.
///
/// `conflicting` is the honest part: those are the keys where both sides held the
/// entity **and the content differed**. They are not errors — the merge resolved
/// them in favour of local, by rule — but a caller that wants to surface "this
/// device's version won" has the list.
struct WeekyiiSnapshotMergeReport: Hashable {
    /// Present only remotely; taken as-is.
    let addedFromRemote: [SyncEntityKey]
    /// Present on both sides; local was kept.
    let keptLocal: [SyncEntityKey]
    /// Present on both sides with different content; local was kept anyway.
    let conflicting: [SyncEntityKey]
    /// Tasks whose `attachmentIds` were rebuilt because they disagreed with the
    /// attachments' own `owner`.
    let relationshipConflictsResolved: [SyncEntityKey]
    /// Diagnostics on the **merged result** — what the caller still has to act on.
    let diagnostics: [WeekyiiSnapshotDiagnostic]

    /// True when the **local snapshot** gained something from the remote side: an
    /// entity it did not have, or an attachment link that had to be rebuilt.
    ///
    /// Named for exactly what it measures, and nothing more. A same-key conflict
    /// can leave this `false` while `conflicting` is non-empty — the local snapshot
    /// really did not change, because local won. **This is not a "needs
    /// synchronisation" flag**: the incremental engine in Phase E decides what to
    /// upload from its baseline comparison, never from this. Do not reach for it as
    /// a remote-sync predicate.
    var localSnapshotChanged: Bool {
        !addedFromRemote.isEmpty || !relationshipConflictsResolved.isEmpty
    }

    var isClean: Bool { diagnostics.isEmpty }
}

struct WeekyiiSnapshotMergeResult {
    let snapshot: WeekyiiBusinessSnapshot
    let report: WeekyiiSnapshotMergeReport
}

/// The result of rebuilding parent → child links from child → parent links.
struct WeekyiiSnapshotRelationshipRebuild {
    let snapshot: WeekyiiBusinessSnapshot
    /// Tasks and suspended tasks whose `attachmentIds` changed.
    let changedOwners: [SyncEntityKey]
}

/// Merges two snapshots, and rebuilds the relationships the snapshot format
/// deliberately leaves implicit.
///
/// ## This helper is not the convergence algorithm
///
/// `mergePreferringLocal` is one **building block**: given a local and a remote
/// snapshot, it produces the local-preference result, deterministically and with no
/// clock and no tie-break. It is intentionally non-commutative — the roles are part
/// of the contract — and it is *not* a proof that the distributed system converges.
///
/// The complete incremental algorithm lives in Phase E and works off a **baseline**:
///
/// ```
/// local unchanged, remote changed -> accept remote
/// local changed,   remote unchanged -> upload local
/// both changed                      -> local wins on this device,
///                                      and the selected local version is uploaded
/// upload confirmed by the server    -> advance the baseline
/// ```
///
/// So a same-key conflict is not a permanent split: this device resolves it in
/// favour of local **and uploads that winner**, and another device whose own value
/// has not changed since its baseline will later accept the uploaded version under
/// quiescence. Convergence is the engine's job, not this function's.
///
/// **SHA-256 is content identity, never authority.** There is deliberately no
/// "lower hash wins" / "higher hash wins" rule here: a content hash says whether
/// two things differ, not which one the user meant. Picking a winner by hash would
/// be a coin toss dressed up as a rule.
///
/// ## What the local preference buys
///
/// It makes the plan's product principle mechanical: sync is an optional extra, so
/// a remote record must never silently overwrite work that exists on this device.
/// Same-key differences are reported through `report.conflicting` rather than hidden.
///
/// ## Relationship reconstruction
///
/// A snapshot stores only child → parent links, but "which attachments belong to
/// task T" has **two** sources: `task.attachmentIds` and `attachment.owner`. They
/// can disagree after a merge.
///
/// `rebuildRelationships` resolves that by rule: **the attachment's own `owner`
/// wins**, because `owner` is part of the attachment entity and is what makes
/// moving an attachment between owners a move rather than a delete + insert. The
/// alternative — trusting `attachmentIds` — would silently drop an attachment that
/// arrived from the remote side with an owner the local task did not know about.
///
/// Parent links (`task.dayId`, `day.weekId`, `projectId`, `habitId`) are *not*
/// rewritten. They have a single source (the child's own field), so there is
/// nothing to reconcile, and clearing one would destroy which parent a record
/// belonged to — information a later merge may still be able to satisfy. A missing
/// parent is reported through `WeekyiiSnapshotRepository.validate` instead.
enum WeekyiiSnapshotMergeService {

    /// Produces the local-preference merge of two snapshots.
    ///
    /// Deliberately non-commutative: `mergePreferringLocal(local: a, remote: b)` and
    /// `mergePreferringLocal(local: b, remote: a)` differ, because "which side is
    /// local" is the whole point. See the type's documentation for why that is a
    /// building block rather than the convergence algorithm.
    static func mergePreferringLocal(
        local: WeekyiiBusinessSnapshot,
        remote: WeekyiiBusinessSnapshot
    ) throws -> WeekyiiSnapshotMergeResult {
        guard local.version == remote.version else {
            throw WeekyiiSnapshotCodecError.versionMismatch(local: local.version, remote: remote.version)
        }

        var tally = Tally()

        let union = WeekyiiBusinessSnapshot(
            version: local.version,
            weeks: try union(local.weeks, remote.weeks, key: { $0.entityKey }, hash: { try WeekyiiSnapshotCodec.entityHash($0) }, tally: &tally),
            days: try union(local.days, remote.days, key: { $0.entityKey }, hash: { try WeekyiiSnapshotCodec.entityHash($0) }, tally: &tally),
            tasks: try union(local.tasks, remote.tasks, key: { $0.entityKey }, hash: { try WeekyiiSnapshotCodec.entityHash($0) }, tally: &tally),
            suspendedTasks: try union(local.suspendedTasks, remote.suspendedTasks, key: { $0.entityKey }, hash: { try WeekyiiSnapshotCodec.entityHash($0) }, tally: &tally),
            attachments: try union(local.attachments, remote.attachments, key: { $0.entityKey }, hash: { try WeekyiiSnapshotCodec.entityHash($0) }, tally: &tally),
            projects: try union(local.projects, remote.projects, key: { $0.entityKey }, hash: { try WeekyiiSnapshotCodec.entityHash($0) }, tally: &tally),
            mindStamps: try union(local.mindStamps, remote.mindStamps, key: { $0.entityKey }, hash: { try WeekyiiSnapshotCodec.entityHash($0) }, tally: &tally),
            taskTypes: try union(local.taskTypes, remote.taskTypes, key: { $0.entityKey }, hash: { try WeekyiiSnapshotCodec.entityHash($0) }, tally: &tally),
            habits: try union(local.habits, remote.habits, key: { $0.entityKey }, hash: { try WeekyiiSnapshotCodec.entityHash($0) }, tally: &tally),
            habitDayRecords: try union(local.habitDayRecords, remote.habitDayRecords, key: { $0.entityKey }, hash: { try WeekyiiSnapshotCodec.entityHash($0) }, tally: &tally)
        )

        let rebuilt = rebuildRelationships(union)
        let diagnostics = WeekyiiSnapshotRepository.validate(rebuilt.snapshot)

        return WeekyiiSnapshotMergeResult(
            snapshot: rebuilt.snapshot,
            report: WeekyiiSnapshotMergeReport(
                addedFromRemote: tally.added.sorted(),
                keptLocal: tally.kept.sorted(),
                conflicting: tally.conflicting.sorted(),
                relationshipConflictsResolved: rebuilt.changedOwners,
                diagnostics: diagnostics
            )
        )
    }

    /// Rebuilds every parent's attachment list from the attachments' own owners.
    ///
    /// Idempotent: running it on its own output changes nothing.
    static func rebuildRelationships(_ snapshot: WeekyiiBusinessSnapshot) -> WeekyiiSnapshotRelationshipRebuild {
        var idsByOwner: [AttachmentOwner: [UUID]] = [:]
        for attachment in snapshot.attachments {
            idsByOwner[attachment.owner, default: []].append(attachment.id)
        }

        func sortedIDs(for owner: AttachmentOwner) -> [UUID] {
            (idsByOwner[owner] ?? []).sorted { $0.uuidString < $1.uuidString }
        }

        var changedOwners: [SyncEntityKey] = []

        let tasks = snapshot.tasks.map { task -> TaskSnapshot in
            let ids = sortedIDs(for: .task(task.id))
            guard ids != task.attachmentIds else { return task }
            changedOwners.append(task.entityKey)
            return task.withAttachmentIds(ids)
        }

        let suspendedTasks = snapshot.suspendedTasks.map { task -> SuspendedTaskSnapshot in
            let ids = sortedIDs(for: .suspendedTask(task.id))
            guard ids != task.attachmentIds else { return task }
            changedOwners.append(task.entityKey)
            return task.withAttachmentIds(ids)
        }

        return WeekyiiSnapshotRelationshipRebuild(
            snapshot: WeekyiiBusinessSnapshot(
                version: snapshot.version,
                weeks: snapshot.weeks,
                days: snapshot.days,
                tasks: tasks,
                suspendedTasks: suspendedTasks,
                attachments: snapshot.attachments,
                projects: snapshot.projects,
                mindStamps: snapshot.mindStamps,
                taskTypes: snapshot.taskTypes,
                habits: snapshot.habits,
                habitDayRecords: snapshot.habitDayRecords
            ),
            changedOwners: changedOwners.sorted()
        )
    }

    // MARK: - Union

    private struct Tally {
        var added: [SyncEntityKey] = []
        var kept: [SyncEntityKey] = []
        var conflicting: [SyncEntityKey] = []
    }

    private static func union<Entity>(
        _ local: [Entity],
        _ remote: [Entity],
        key: (Entity) -> SyncEntityKey,
        hash: (Entity) throws -> String,
        tally: inout Tally
    ) throws -> [Entity] {
        var localByKey: [SyncEntityKey: Entity] = [:]
        for entity in local {
            let entityKey = key(entity)
            guard localByKey.updateValue(entity, forKey: entityKey) == nil else {
                throw WeekyiiSnapshotCodecError.duplicateEntityKey(entityKey)
            }
        }
        var remoteByKey: [SyncEntityKey: Entity] = [:]
        for entity in remote {
            let entityKey = key(entity)
            guard remoteByKey.updateValue(entity, forKey: entityKey) == nil else {
                throw WeekyiiSnapshotCodecError.duplicateEntityKey(entityKey)
            }
        }

        var merged: [Entity] = []
        merged.reserveCapacity(localByKey.count + remoteByKey.count)

        // Local first, and local always wins.
        for (entityKey, localEntity) in localByKey {
            merged.append(localEntity)
            guard let remoteEntity = remoteByKey[entityKey] else { continue }
            tally.kept.append(entityKey)
            if try hash(localEntity) != hash(remoteEntity) {
                tally.conflicting.append(entityKey)
            }
        }

        for (entityKey, remoteEntity) in remoteByKey where localByKey[entityKey] == nil {
            merged.append(remoteEntity)
            tally.added.append(entityKey)
        }

        return merged
    }
}

// MARK: - Rebuilt copies

/// `attachmentIds` is a `let` on the snapshot structs, and the rebuilt value has to
/// come from somewhere. Rather than make it a `var` — which would let any caller
/// mutate a link the merge is supposed to own — the copy is explicit and lives
/// here, next to its only user.
extension TaskSnapshot {
    func withAttachmentIds(_ ids: [UUID]) -> TaskSnapshot {
        TaskSnapshot(
            id: id,
            dayId: dayId,
            projectId: projectId,
            habitId: habitId,
            title: title,
            taskDescription: taskDescription,
            taskType: taskType,
            taskTypeIdRaw: taskTypeIdRaw,
            order: order,
            zone: zone,
            startedAt: startedAt,
            endedAt: endedAt,
            completedOrder: completedOrder,
            steps: steps,
            attachmentIds: ids
        )
    }
}

extension SuspendedTaskSnapshot {
    func withAttachmentIds(_ ids: [UUID]) -> SuspendedTaskSnapshot {
        SuspendedTaskSnapshot(
            id: id,
            title: title,
            taskDescription: taskDescription,
            taskType: taskType,
            taskTypeIdRaw: taskTypeIdRaw,
            createdAt: createdAt,
            decisionDeadline: decisionDeadline,
            preferredCountdownDays: preferredCountdownDays,
            snoozeCount: snoozeCount,
            statusRaw: statusRaw,
            steps: steps,
            attachmentIds: ids
        )
    }
}

// MARK: - Archive adapter

/// Converts between the backup archive's payload and the normalized snapshot.
///
/// The two shapes carry the same ten families but nest them differently:
///
/// | | archive | snapshot |
/// |---|---|---|
/// | attachment | inside `TaskRecord` / `SuspendedTaskRecord` | top-level, carries `owner` |
/// | habit day record | inside `HabitRecord.dayLogs` | top-level, carries `habitId` |
/// | settings / app state | in the payload | absent |
///
/// `formatVersion` stays **1**: this adapter changes the in-memory shape only, and
/// the bytes it hands to `WeekyiiDataArchiveService` are the same bytes that
/// service already produces.
///
/// `@MainActor` because the archive service it bridges to is.
@MainActor
enum WeekyiiSnapshotArchiveAdapter {

    /// Archive payload → normalized snapshot.
    static func snapshot(from payload: WeekyiiDataArchiveService.Payload) -> WeekyiiBusinessSnapshot {
        var attachments: [AttachmentSnapshot] = []
        var habitDayRecords: [HabitDayRecordSnapshot] = []

        let tasks = payload.tasks.map { record -> TaskSnapshot in
            attachments.append(contentsOf: record.attachments.map {
                AttachmentSnapshot(
                    id: $0.id,
                    owner: .task(record.id),
                    data: $0.data,
                    fileName: $0.fileName,
                    fileType: $0.fileType,
                    createdAt: $0.createdAt
                )
            })
            return TaskSnapshot(
                id: record.id,
                dayId: record.dayId,
                projectId: record.projectId,
                habitId: record.habitId,
                title: record.title,
                taskDescription: record.taskDescription,
                taskType: record.taskType,
                taskTypeIdRaw: record.taskTypeIdRaw,
                order: record.order,
                zone: record.zone,
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                completedOrder: record.completedOrder,
                steps: record.steps.map(stepSnapshot),
                attachmentIds: record.attachments.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
        }

        let suspendedTasks = payload.suspendedTasks.map { record -> SuspendedTaskSnapshot in
            attachments.append(contentsOf: record.attachments.map {
                AttachmentSnapshot(
                    id: $0.id,
                    owner: .suspendedTask(record.id),
                    data: $0.data,
                    fileName: $0.fileName,
                    fileType: $0.fileType,
                    createdAt: $0.createdAt
                )
            })
            return SuspendedTaskSnapshot(
                id: record.id,
                title: record.title,
                taskDescription: record.taskDescription,
                taskType: record.taskType,
                taskTypeIdRaw: record.taskTypeIdRaw,
                createdAt: record.createdAt,
                decisionDeadline: record.decisionDeadline,
                preferredCountdownDays: record.preferredCountdownDays,
                snoozeCount: record.snoozeCount,
                statusRaw: record.statusRaw,
                steps: record.steps.map(stepSnapshot),
                attachmentIds: record.attachments.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
        }

        let habits = (payload.habits ?? []).map { record -> HabitSnapshot in
            habitDayRecords.append(contentsOf: (record.dayLogs ?? []).map {
                HabitDayRecordSnapshot(
                    id: $0.id,
                    habitId: record.id,
                    dayId: $0.dayId,
                    statusRaw: $0.statusRaw,
                    createdAt: $0.createdAt,
                    completedAt: $0.completedAt
                )
            })
            return HabitSnapshot(
                id: record.id,
                name: record.name,
                iconName: record.iconName,
                colorHex: record.colorHex,
                categoryRaw: record.categoryRaw,
                scheduleKindRaw: record.scheduleKindRaw,
                scheduleWeekdaysRaw: record.scheduleWeekdaysRaw,
                scheduleMonthDaysRaw: record.scheduleMonthDaysRaw,
                startDayId: record.startDayId,
                isActive: record.isActive,
                createdAt: record.createdAt,
                sortOrder: record.sortOrder
            )
        }

        return WeekyiiBusinessSnapshot(
            weeks: payload.weeks.map {
                WeekSnapshot(
                    weekId: $0.weekId,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    status: $0.status,
                    completedTasksCount: $0.completedTasksCount,
                    expiredTasksCount: $0.expiredTasksCount,
                    totalStartedDays: $0.totalStartedDays
                )
            },
            days: payload.days.map {
                DaySnapshot(
                    dayId: $0.dayId,
                    weekId: $0.weekId,
                    date: $0.date,
                    dayOfWeek: $0.dayOfWeek,
                    status: $0.status,
                    killTimeHour: $0.killTimeHour,
                    killTimeMinute: $0.killTimeMinute,
                    followsDefaultKillTime: $0.followsDefaultKillTime,
                    initiatedAt: $0.initiatedAt,
                    closedAt: $0.closedAt,
                    executionModeRaw: $0.executionModeRaw,
                    isDraftZoneUnlocked: $0.isDraftZoneUnlocked,
                    expiredCount: $0.expiredCount
                )
            },
            tasks: tasks,
            suspendedTasks: suspendedTasks,
            attachments: attachments,
            projects: payload.projects.map {
                ProjectSnapshot(
                    id: $0.id,
                    name: $0.name,
                    projectDescription: $0.projectDescription,
                    color: $0.color,
                    icon: $0.icon,
                    status: $0.status,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    createdAt: $0.createdAt,
                    tileSizeRaw: $0.tileSizeRaw,
                    tileOrder: $0.tileOrder
                )
            },
            mindStamps: payload.mindStamps.map {
                MindStampSnapshot(id: $0.id, text: $0.text, imageBlob: $0.imageBlob, createdAt: $0.createdAt)
            },
            taskTypes: payload.taskTypes.map {
                TaskTypeSnapshot(
                    idRaw: $0.idRaw,
                    name: $0.name,
                    iconName: $0.iconName,
                    colorHex: $0.colorHex,
                    baseKindRaw: $0.baseKindRaw,
                    sortOrder: $0.sortOrder,
                    isBuiltIn: $0.isBuiltIn,
                    isArchived: $0.isArchived
                )
            },
            habits: habits,
            habitDayRecords: habitDayRecords
        )
    }

    /// Normalized snapshot → archive payload.
    ///
    /// The archive nests attachments under their owner and habit day records under
    /// their habit, so anything whose parent is absent from the snapshot cannot be
    /// represented. Those are returned in `droppedEntities` rather than silently
    /// discarded — the same rule the repository follows when it refuses to collapse
    /// two records onto one identity.
    static func export(
        _ snapshot: WeekyiiBusinessSnapshot,
        settings: WeekyiiDataArchiveService.SettingsRecord,
        appState: WeekyiiDataArchiveService.AppStateRecord
    ) -> WeekyiiSnapshotArchiveExport {
        let taskIDs = Set(snapshot.tasks.map(\.id))
        let suspendedIDs = Set(snapshot.suspendedTasks.map(\.id))
        let habitIDs = Set(snapshot.habits.map(\.id))

        var attachmentsByOwner: [AttachmentOwner: [WeekyiiDataArchiveService.AttachmentRecord]] = [:]
        var dayLogsByHabit: [UUID: [WeekyiiDataArchiveService.HabitDayLog]] = [:]
        var dropped: [SyncEntityKey] = []

        for attachment in snapshot.attachments {
            let representable: Bool
            switch attachment.owner {
            case .task(let id): representable = taskIDs.contains(id)
            case .suspendedTask(let id): representable = suspendedIDs.contains(id)
            }
            guard representable else {
                dropped.append(attachment.entityKey)
                continue
            }
            attachmentsByOwner[attachment.owner, default: []].append(
                WeekyiiDataArchiveService.AttachmentRecord(
                    id: attachment.id,
                    data: attachment.data,
                    fileName: attachment.fileName,
                    fileType: attachment.fileType,
                    createdAt: attachment.createdAt
                )
            )
        }

        for record in snapshot.habitDayRecords {
            guard let habitId = record.habitId, habitIDs.contains(habitId) else {
                dropped.append(record.entityKey)
                continue
            }
            dayLogsByHabit[habitId, default: []].append(
                WeekyiiDataArchiveService.HabitDayLog(
                    id: record.id,
                    dayId: record.dayId,
                    statusRaw: record.statusRaw,
                    createdAt: record.createdAt,
                    completedAt: record.completedAt
                )
            )
        }

        let payload = WeekyiiDataArchiveService.Payload(
            weeks: snapshot.weeks.map {
                WeekyiiDataArchiveService.WeekRecord(
                    weekId: $0.weekId,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    status: $0.status,
                    completedTasksCount: $0.completedTasksCount,
                    expiredTasksCount: $0.expiredTasksCount,
                    totalStartedDays: $0.totalStartedDays
                )
            },
            days: snapshot.days.map {
                WeekyiiDataArchiveService.DayRecord(
                    dayId: $0.dayId,
                    weekId: $0.weekId,
                    date: $0.date,
                    dayOfWeek: $0.dayOfWeek,
                    status: $0.status,
                    killTimeHour: $0.killTimeHour,
                    killTimeMinute: $0.killTimeMinute,
                    followsDefaultKillTime: $0.followsDefaultKillTime,
                    initiatedAt: $0.initiatedAt,
                    closedAt: $0.closedAt,
                    executionModeRaw: $0.executionModeRaw,
                    isDraftZoneUnlocked: $0.isDraftZoneUnlocked,
                    expiredCount: $0.expiredCount
                )
            },
            tasks: snapshot.tasks.map { task in
                WeekyiiDataArchiveService.TaskRecord(
                    id: task.id,
                    dayId: task.dayId,
                    projectId: task.projectId,
                    title: task.title,
                    taskDescription: task.taskDescription,
                    taskType: task.taskType,
                    taskTypeIdRaw: task.taskTypeIdRaw,
                    order: task.order,
                    zone: task.zone,
                    startedAt: task.startedAt,
                    endedAt: task.endedAt,
                    completedOrder: task.completedOrder,
                    steps: task.steps.map(stepRecord),
                    attachments: attachmentsByOwner[.task(task.id)] ?? [],
                    habitId: task.habitId
                )
            },
            projects: snapshot.projects.map {
                WeekyiiDataArchiveService.ProjectRecord(
                    id: $0.id,
                    name: $0.name,
                    projectDescription: $0.projectDescription,
                    color: $0.color,
                    icon: $0.icon,
                    status: $0.status,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    createdAt: $0.createdAt,
                    tileSizeRaw: $0.tileSizeRaw,
                    tileOrder: $0.tileOrder
                )
            },
            mindStamps: snapshot.mindStamps.map {
                WeekyiiDataArchiveService.MindStampRecord(
                    id: $0.id,
                    text: $0.text,
                    imageBlob: $0.imageBlob,
                    createdAt: $0.createdAt
                )
            },
            suspendedTasks: snapshot.suspendedTasks.map { task in
                WeekyiiDataArchiveService.SuspendedTaskRecord(
                    id: task.id,
                    title: task.title,
                    taskDescription: task.taskDescription,
                    taskType: task.taskType,
                    taskTypeIdRaw: task.taskTypeIdRaw,
                    createdAt: task.createdAt,
                    decisionDeadline: task.decisionDeadline,
                    preferredCountdownDays: task.preferredCountdownDays,
                    snoozeCount: task.snoozeCount,
                    statusRaw: task.statusRaw,
                    steps: task.steps.map(stepRecord),
                    attachments: attachmentsByOwner[.suspendedTask(task.id)] ?? []
                )
            },
            taskTypes: snapshot.taskTypes.map {
                WeekyiiDataArchiveService.TaskTypeRecord(
                    idRaw: $0.idRaw,
                    name: $0.name,
                    iconName: $0.iconName,
                    colorHex: $0.colorHex,
                    baseKindRaw: $0.baseKindRaw,
                    sortOrder: $0.sortOrder,
                    isBuiltIn: $0.isBuiltIn,
                    isArchived: $0.isArchived
                )
            },
            habits: snapshot.habits.map {
                WeekyiiDataArchiveService.HabitRecord(
                    id: $0.id,
                    name: $0.name,
                    iconName: $0.iconName,
                    colorHex: $0.colorHex,
                    categoryRaw: $0.categoryRaw,
                    scheduleKindRaw: $0.scheduleKindRaw,
                    scheduleWeekdaysRaw: $0.scheduleWeekdaysRaw,
                    scheduleMonthDaysRaw: $0.scheduleMonthDaysRaw,
                    startDayId: $0.startDayId,
                    generatedThroughDayId: "",
                    isActive: $0.isActive,
                    createdAt: $0.createdAt,
                    sortOrder: $0.sortOrder,
                    dayLogs: dayLogsByHabit[$0.id] ?? []
                )
            },
            settings: settings,
            appState: appState
        )

        return WeekyiiSnapshotArchiveExport(payload: payload, droppedEntities: dropped.sorted())
    }

    private static func stepSnapshot(_ record: WeekyiiDataArchiveService.StepRecord) -> StepSnapshot {
        StepSnapshot(
            title: record.title,
            isCompleted: record.isCompleted,
            sortOrder: record.sortOrder,
            createdAt: record.createdAt
        )
    }

    private static func stepRecord(_ step: StepSnapshot) -> WeekyiiDataArchiveService.StepRecord {
        WeekyiiDataArchiveService.StepRecord(
            title: step.title,
            isCompleted: step.isCompleted,
            sortOrder: step.sortOrder,
            createdAt: step.createdAt
        )
    }
}

/// The archive payload plus whatever the archive format could not hold.
struct WeekyiiSnapshotArchiveExport {
    let payload: WeekyiiDataArchiveService.Payload
    let droppedEntities: [SyncEntityKey]

    var isLossless: Bool { droppedEntities.isEmpty }
}
