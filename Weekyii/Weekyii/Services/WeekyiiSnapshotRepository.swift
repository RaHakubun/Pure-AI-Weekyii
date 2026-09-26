import Foundation
import SwiftData

/// A problem found while reading — or validating — a business snapshot.
///
/// The repository never "fixes" a problem silently. Every ambiguity becomes one of
/// these so the caller, and later the sync layer, can decide what to do.
nonisolated struct WeekyiiSnapshotDiagnostic: Hashable, CustomStringConvertible {
    enum Kind: String {
        /// Two or more records claim the same business identity, so the sync layer
        /// would address them as one entity.
        case duplicateBusinessId
        /// An attachment's owner is not present in the snapshot.
        case orphanAttachment
        /// An attachment's owner does not list the attachment back.
        case attachmentOwnerMismatch
        /// More than one record lists the same attachment. `TaskAttachment.task`
        /// and `.suspendedTask` are independent relationships, so this is possible
        /// in the store — not just after a bad merge.
        case attachmentMultipleOwners
        /// A record references an attachment id with no attachment entity.
        case danglingAttachmentReference
        case missingWeek
        case missingDay
        case missingProject
        case missingHabit
    }

    let kind: Kind
    let entityKey: SyncEntityKey
    let detail: String

    var description: String { "[\(kind.rawValue)] \(entityKey) — \(detail)" }
}

/// Thrown instead of handing back a snapshot that would have required the
/// repository to guess which row is the real one.
nonisolated enum WeekyiiSnapshotRepositoryError: LocalizedError, Hashable {
    case ambiguousStore([WeekyiiSnapshotDiagnostic])

    var errorDescription: String? {
        switch self {
        case .ambiguousStore(let diagnostics):
            let summary = diagnostics.map(\.description).joined(separator: "; ")
            return "本地数据有 \(diagnostics.count) 处身份歧义，已拒绝生成可同步快照：\(summary)"
        }
    }
}

nonisolated struct WeekyiiSnapshotLoadResult {
    let snapshot: WeekyiiBusinessSnapshot
    let diagnostics: [WeekyiiSnapshotDiagnostic]

    var isClean: Bool { diagnostics.isEmpty }

    func diagnostics(of kind: WeekyiiSnapshotDiagnostic.Kind) -> [WeekyiiSnapshotDiagnostic] {
        diagnostics.filter { $0.kind == kind }
    }
}

/// Reads the SwiftData graph into a `WeekyiiBusinessSnapshot`, and validates
/// snapshots.
///
/// ## Two jobs
///
/// 1. **Normalize.** Hoist attachments to top-level entities, embed steps, resolve
///    every relationship to a business key.
/// 2. **Refuse to guess.** SwiftData does not enforce uniqueness for these logical
///    keys, so nothing at the storage layer stops two rows from claiming the same `id`.
///
/// ## Why not `Dictionary(uniqueKeysWithValues:)`
///
/// That traps on a duplicate, and `uniquingKeysWith:` silently discards one of the
/// rows. Both are worse than useless here: a duplicated `TaskItem.id` means two
/// devices can each hold "the" task, and whichever row a dictionary happened to
/// keep would silently become the winner. Duplicates surface as
/// `duplicateBusinessId`, and the survivor is chosen by a documented, deterministic
/// rule so two runs over the same store agree.
enum WeekyiiSnapshotRepository {

    // MARK: - Loading

    @MainActor
    static func load(from context: ModelContext) throws -> WeekyiiSnapshotLoadResult {
        var diagnostics: [WeekyiiSnapshotDiagnostic] = []

        let weeks = dedupe(
            try context.fetch(FetchDescriptor<WeekModel>()),
            key: { $0.entityKey },
            make: weekSnapshot,
            describe: { $0.weekId },
            into: &diagnostics
        )
        let days = dedupe(
            try context.fetch(FetchDescriptor<DayModel>()),
            key: { $0.entityKey },
            make: daySnapshot,
            describe: { $0.dayId },
            into: &diagnostics
        )
        let tasks = dedupe(
            try context.fetch(FetchDescriptor<TaskItem>()),
            key: { $0.entityKey },
            make: taskSnapshot,
            describe: { "\($0.title)@\($0.order)" },
            into: &diagnostics
        )
        let suspendedTasks = dedupe(
            try context.fetch(FetchDescriptor<SuspendedTaskItem>()),
            key: { $0.entityKey },
            make: suspendedTaskSnapshot,
            describe: { $0.title },
            into: &diagnostics
        )
        let attachments = dedupe(
            try context.fetch(FetchDescriptor<TaskAttachment>()),
            key: { $0.entityKey },
            make: attachmentSnapshot,
            describe: { attachment in
                let owner = attachment.task != nil ? "task" : (attachment.suspendedTask != nil ? "suspended" : "none")
                return "\(attachment.fileName) owner=\(owner)"
            },
            into: &diagnostics
        )
        let projects = dedupe(
            try context.fetch(FetchDescriptor<ProjectModel>()),
            key: { $0.entityKey },
            make: projectSnapshot,
            describe: { $0.name },
            into: &diagnostics
        )
        let mindStamps = dedupe(
            try context.fetch(FetchDescriptor<MindStampItem>()),
            key: { $0.entityKey },
            make: mindStampSnapshot,
            describe: { String($0.text.prefix(24)) },
            into: &diagnostics
        )
        let taskTypes = dedupe(
            try context.fetch(FetchDescriptor<TaskTypeDefinition>()),
            key: { $0.entityKey },
            make: taskTypeSnapshot,
            describe: { $0.name },
            into: &diagnostics
        )
        let habits = dedupe(
            try context.fetch(FetchDescriptor<HabitModel>()),
            key: { $0.entityKey },
            make: habitSnapshot,
            describe: { $0.name },
            into: &diagnostics
        )
        let habitDayRecords = dedupe(
            try context.fetch(FetchDescriptor<HabitDayRecord>()),
            key: { $0.entityKey },
            make: habitDayRecordSnapshot,
            describe: { "\($0.dayId) \($0.statusRaw)" },
            into: &diagnostics
        )

        let snapshot = WeekyiiBusinessSnapshot(
            weeks: weeks,
            days: days,
            tasks: tasks,
            suspendedTasks: suspendedTasks,
            attachments: attachments,
            projects: projects,
            mindStamps: mindStamps,
            taskTypes: taskTypes,
            habits: habits,
            habitDayRecords: habitDayRecords
        )

        diagnostics.append(contentsOf: validate(snapshot))
        return WeekyiiSnapshotLoadResult(
            snapshot: snapshot,
            diagnostics: sorted(diagnostics)
        )
    }

    /// The only way to obtain a snapshot that is safe to hand to sync or merge.
    ///
    /// `load(from:)` deliberately returns a best-effort snapshot *alongside* its
    /// diagnostics, because diagnostics, repair tools and migration inspection all
    /// need to be able to look at an ambiguous store. That snapshot is a guess:
    /// when two rows claim one business id, `dedupe` had to pick a survivor.
    ///
    /// Feeding a guess into sync would silently choose data on the user's behalf,
    /// which is exactly what this repository exists to prevent. So there is no
    /// "hand me the snapshot and ignore the diagnostics" convenience: a caller that
    /// wants a syncable snapshot has to take the throwing route and deal with the
    /// ambiguity.
    @MainActor
    static func requireCleanSnapshot(from context: ModelContext) throws -> WeekyiiBusinessSnapshot {
        let result = try load(from: context)
        guard result.isClean else {
            throw WeekyiiSnapshotRepositoryError.ambiguousStore(result.diagnostics)
        }
        return result.snapshot
    }

    // MARK: - Validation

    /// Checks a snapshot for internal consistency.
    ///
    /// Deliberately a **pure function of the snapshot**, not of the store. Two
    /// reasons:
    ///
    /// * A live store can barely violate referential integrity on its own —
    ///   SwiftData maintains the inverse relationships, and deleting a week
    ///   cascades to its days, so `task.dayId` cannot dangle. Most of these checks
    ///   would be unreachable, and therefore untestable, if they only ran on
    ///   `load`. As a pure function they can be exercised with hand-built input.
    /// * The merge in Phase A2 has to validate its *result* before applying it.
    ///   That result is a snapshot, never a store.
    static func validate(_ snapshot: WeekyiiBusinessSnapshot) -> [WeekyiiSnapshotDiagnostic] {
        var diagnostics: [WeekyiiSnapshotDiagnostic] = []

        let weekIds = Set(snapshot.weeks.map(\.weekId))
        let dayIds = Set(snapshot.days.map(\.dayId))
        let projectIds = Set(snapshot.projects.map(\.id))
        let habitIds = Set(snapshot.habits.map(\.id))
        let attachmentIds = Set(snapshot.attachments.map(\.id))
        let taskIds = Set(snapshot.tasks.map(\.id))
        let suspendedIds = Set(snapshot.suspendedTasks.map(\.id))

        // Duplicate business identities inside the snapshot itself.
        var occurrences: [SyncEntityKey: Int] = [:]
        for key in snapshot.entityKeys() {
            occurrences[key, default: 0] += 1
        }
        for (key, count) in occurrences where count > 1 {
            diagnostics.append(
                WeekyiiSnapshotDiagnostic(
                    kind: .duplicateBusinessId,
                    entityKey: key,
                    detail: "\(count) entities share this business id"
                )
            )
        }

        for day in snapshot.days {
            guard let weekId = day.weekId, !weekIds.contains(weekId) else { continue }
            diagnostics.append(
                WeekyiiSnapshotDiagnostic(
                    kind: .missingWeek,
                    entityKey: day.entityKey,
                    detail: "weekId \(weekId) has no week entity"
                )
            )
        }

        for task in snapshot.tasks {
            if let dayId = task.dayId, !dayIds.contains(dayId) {
                diagnostics.append(
                    WeekyiiSnapshotDiagnostic(
                        kind: .missingDay,
                        entityKey: task.entityKey,
                        detail: "dayId \(dayId) has no day entity"
                    )
                )
            }
            if let projectId = task.projectId, !projectIds.contains(projectId) {
                diagnostics.append(
                    WeekyiiSnapshotDiagnostic(
                        kind: .missingProject,
                        entityKey: task.entityKey,
                        detail: "projectId \(projectId.uuidString) has no project entity"
                    )
                )
            }
            if let habitId = task.habitId, !habitIds.contains(habitId) {
                diagnostics.append(
                    WeekyiiSnapshotDiagnostic(
                        kind: .missingHabit,
                        entityKey: task.entityKey,
                        detail: "habitId \(habitId.uuidString) has no habit entity"
                    )
                )
            }
        }

        for record in snapshot.habitDayRecords {
            guard let habitId = record.habitId, !habitIds.contains(habitId) else { continue }
            diagnostics.append(
                WeekyiiSnapshotDiagnostic(
                    kind: .missingHabit,
                    entityKey: record.entityKey,
                    detail: "habitId \(habitId.uuidString) has no habit entity"
                )
            )
        }

        // Every id any record claims to hold.
        var listedBy: [UUID: [SyncEntityKey]] = [:]
        for task in snapshot.tasks {
            for id in task.attachmentIds { listedBy[id, default: []].append(task.entityKey) }
        }
        for task in snapshot.suspendedTasks {
            for id in task.attachmentIds { listedBy[id, default: []].append(task.entityKey) }
        }

        for (id, holders) in listedBy where !attachmentIds.contains(id) {
            for holder in holders {
                diagnostics.append(
                    WeekyiiSnapshotDiagnostic(
                        kind: .danglingAttachmentReference,
                        entityKey: holder,
                        detail: "attachmentId \(id.uuidString) has no attachment entity"
                    )
                )
            }
        }

        for attachment in snapshot.attachments {
            let ownerExists: Bool
            let ownerListsIt: Bool
            switch attachment.owner {
            case .task(let id):
                ownerExists = taskIds.contains(id)
                ownerListsIt = snapshot.tasks.first { $0.id == id }?.attachmentIds.contains(attachment.id) ?? false
            case .suspendedTask(let id):
                ownerExists = suspendedIds.contains(id)
                ownerListsIt = snapshot.suspendedTasks.first { $0.id == id }?.attachmentIds.contains(attachment.id) ?? false
            }

            if !ownerExists {
                diagnostics.append(
                    WeekyiiSnapshotDiagnostic(
                        kind: .orphanAttachment,
                        entityKey: attachment.entityKey,
                        detail: "owner \(attachment.owner.entityKey) is not in the snapshot"
                    )
                )
            } else if !ownerListsIt {
                diagnostics.append(
                    WeekyiiSnapshotDiagnostic(
                        kind: .attachmentOwnerMismatch,
                        entityKey: attachment.entityKey,
                        detail: "owner \(attachment.owner.entityKey) does not reference this attachment"
                    )
                )
            }

            let holders = listedBy[attachment.id] ?? []
            if holders.count > 1 {
                diagnostics.append(
                    WeekyiiSnapshotDiagnostic(
                        kind: .attachmentMultipleOwners,
                        entityKey: attachment.entityKey,
                        detail: "listed by \(holders.map(\.description).sorted().joined(separator: ", ")) but owned by \(attachment.owner.entityKey)"
                    )
                )
            }
        }

        return sorted(diagnostics)
    }

    /// Stable order, so two runs over the same input produce identical output —
    /// otherwise a test could pass or fail on dictionary iteration order.
    private static func sorted(_ diagnostics: [WeekyiiSnapshotDiagnostic]) -> [WeekyiiSnapshotDiagnostic] {
        diagnostics.sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            if $0.entityKey != $1.entityKey { return $0.entityKey < $1.entityKey }
            return $0.detail < $1.detail
        }
    }

    // MARK: - Record → snapshot

    private static func weekSnapshot(_ week: WeekModel) -> WeekSnapshot {
        WeekSnapshot(
            weekId: week.weekId,
            startDate: week.startDate,
            endDate: week.endDate,
            status: week.status,
            completedTasksCount: week.completedTasksCount,
            expiredTasksCount: week.expiredTasksCount,
            totalStartedDays: week.totalStartedDays
        )
    }

    private static func daySnapshot(_ day: DayModel) -> DaySnapshot {
        DaySnapshot(
            dayId: day.dayId,
            weekId: day.week?.weekId,
            date: day.date,
            dayOfWeek: day.dayOfWeek,
            status: day.status,
            killTimeHour: day.killTimeHour,
            killTimeMinute: day.killTimeMinute,
            followsDefaultKillTime: day.followsDefaultKillTime,
            initiatedAt: day.initiatedAt,
            closedAt: day.closedAt,
            executionModeRaw: day.executionModeRaw,
            isDraftZoneUnlocked: day.isDraftZoneUnlocked,
            expiredCount: day.expiredCount
        )
    }

    private static func taskSnapshot(_ task: TaskItem) -> TaskSnapshot {
        TaskSnapshot(
            id: task.id,
            dayId: task.day?.dayId,
            projectId: task.project?.id,
            habitId: task.habit?.id,
            title: task.title,
            taskDescription: task.taskDescription,
            taskType: task.taskType,
            taskTypeIdRaw: task.taskTypeIdRaw,
            order: task.order,
            zone: task.zone,
            startedAt: task.startedAt,
            endedAt: task.endedAt,
            completedOrder: task.completedOrder,
            steps: stepSnapshots(task.steps),
            attachmentIds: task.attachments.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
    }

    private static func suspendedTaskSnapshot(_ task: SuspendedTaskItem) -> SuspendedTaskSnapshot {
        SuspendedTaskSnapshot(
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
            steps: stepSnapshots(task.steps),
            attachmentIds: task.attachments.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
    }

    /// `TaskAttachment.task` and `.suspendedTask` are two independent
    /// relationships, not inverses of each other, so a row can have both or
    /// neither. A row with neither is reported as `orphanAttachment`; the
    /// placeholder owner below keeps the snapshot's types non-optional and is only
    /// ever observable together with that diagnostic.
    private static func attachmentSnapshot(_ attachment: TaskAttachment) -> AttachmentSnapshot {
        let owner: AttachmentOwner
        if let task = attachment.task {
            owner = .task(task.id)
        } else if let suspended = attachment.suspendedTask {
            owner = .suspendedTask(suspended.id)
        } else {
            owner = .task(attachment.id)
        }
        return AttachmentSnapshot(
            id: attachment.id,
            owner: owner,
            data: attachment.data,
            fileName: attachment.fileName,
            fileType: attachment.fileType,
            createdAt: attachment.createdAt
        )
    }

    private static func projectSnapshot(_ project: ProjectModel) -> ProjectSnapshot {
        ProjectSnapshot(
            id: project.id,
            name: project.name,
            projectDescription: project.projectDescription,
            color: project.color,
            icon: project.icon,
            status: project.status,
            startDate: project.startDate,
            endDate: project.endDate,
            createdAt: project.createdAt,
            tileSizeRaw: project.tileSizeRaw,
            tileOrder: project.tileOrder
        )
    }

    private static func mindStampSnapshot(_ stamp: MindStampItem) -> MindStampSnapshot {
        MindStampSnapshot(id: stamp.id, text: stamp.text, imageBlob: stamp.imageBlob, createdAt: stamp.createdAt)
    }

    private static func taskTypeSnapshot(_ definition: TaskTypeDefinition) -> TaskTypeSnapshot {
        TaskTypeSnapshot(
            idRaw: definition.idRaw,
            name: definition.name,
            iconName: definition.iconName,
            colorHex: definition.colorHex,
            baseKindRaw: definition.baseKindRaw,
            sortOrder: definition.sortOrder,
            isBuiltIn: definition.isBuiltIn,
            isArchived: definition.isArchived
        )
    }

    private static func habitSnapshot(_ habit: HabitModel) -> HabitSnapshot {
        HabitSnapshot(
            id: habit.id,
            name: habit.name,
            iconName: habit.iconName,
            colorHex: habit.colorHex,
            categoryRaw: habit.categoryRaw,
            scheduleKindRaw: habit.scheduleKindRaw,
            scheduleWeekdaysRaw: habit.scheduleWeekdaysRaw,
            scheduleMonthDaysRaw: habit.scheduleMonthDaysRaw,
            startDayId: habit.startDayId,
            isActive: habit.isActive,
            createdAt: habit.createdAt,
            sortOrder: habit.sortOrder
        )
    }

    private static func habitDayRecordSnapshot(_ record: HabitDayRecord) -> HabitDayRecordSnapshot {
        HabitDayRecordSnapshot(
            id: record.id,
            habitId: record.habit?.id,
            dayId: record.dayId,
            statusRaw: record.statusRaw,
            createdAt: record.createdAt,
            completedAt: record.completedAt
        )
    }

    /// Step order must be total, or two runs over the same store could encode
    /// different bytes. `TaskResourceIdentity.sortedSteps` orders by
    /// `(sortOrder, createdAt)` — right for the app, but two steps can tie on both,
    /// so the snapshot adds a final tie-break on content.
    private static func stepSnapshots(_ steps: [TaskStep]) -> [StepSnapshot] {
        steps
            .map {
                StepSnapshot(
                    title: $0.title,
                    isCompleted: $0.isCompleted,
                    sortOrder: $0.sortOrder,
                    createdAt: $0.createdAt
                )
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                if $0.title != $1.title { return $0.title < $1.title }
                return !$0.isCompleted && $1.isCompleted
            }
    }

    // MARK: - Duplicate detection

    /// Keeps exactly one snapshot per business id and reports every collision.
    ///
    /// The survivor is the one with the smallest canonical encoding — deterministic
    /// and independent of fetch order. Two rows agreeing on their id *and* on all
    /// content are indistinguishable, so which one survives does not matter; two
    /// rows differing only below millisecond precision can tie, and the choice
    /// between those is then arbitrary. Both cases are reported either way.
    @MainActor
    private static func dedupe<Record, Snapshot: Encodable>(
        _ records: [Record],
        key: @MainActor (Record) -> SyncEntityKey,
        make: @MainActor (Record) -> Snapshot,
        describe: @MainActor (Record) -> String,
        into diagnostics: inout [WeekyiiSnapshotDiagnostic]
    ) -> [Snapshot] {
        var groups: [SyncEntityKey: [(record: Record, snapshot: Snapshot)]] = [:]
        for record in records {
            groups[key(record), default: []].append((record, make(record)))
        }

        var kept: [Snapshot] = []
        kept.reserveCapacity(groups.count)
        for entityKey in groups.keys.sorted() {
            guard let group = groups[entityKey] else { continue }
            if group.count > 1 {
                let labels = group.map { describe($0.record) }.sorted().joined(separator: ", ")
                diagnostics.append(
                    WeekyiiSnapshotDiagnostic(
                        kind: .duplicateBusinessId,
                        entityKey: entityKey,
                        detail: "\(group.count) rows share this business id (\(labels)); kept the canonical-first row"
                    )
                )
            }
            let winner = group.min { canonicalSortKey($0.snapshot) < canonicalSortKey($1.snapshot) }
            if let winner { kept.append(winner.snapshot) }
        }
        return kept
    }

    private static func canonicalSortKey<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Model → business key

/// Which field carries each record's business identity.
///
/// File-scoped on purpose. `SyncEntityKey` is the sync layer's vocabulary, and
/// these mappings are the only place it touches the model layer — keeping them
/// here means the whole contract (`SyncEntityKey` + this block) can be reviewed in
/// one sitting, and no `@Model` type grows a sync-only property.
///
/// **Every `UUID` goes through `.uuidString`, which is uppercase.** Lowercasing one
/// of these would give the same record two different keys.
private extension WeekModel {
    var entityKey: SyncEntityKey { SyncEntityKey(kind: .week, businessId: weekId) }
}

private extension DayModel {
    var entityKey: SyncEntityKey { SyncEntityKey(kind: .day, businessId: dayId) }
}

private extension TaskItem {
    var entityKey: SyncEntityKey { SyncEntityKey(kind: .task, id: id) }
}

private extension SuspendedTaskItem {
    var entityKey: SyncEntityKey { SyncEntityKey(kind: .suspendedTask, id: id) }
}

private extension TaskAttachment {
    var entityKey: SyncEntityKey { SyncEntityKey(kind: .attachment, id: id) }
}

private extension ProjectModel {
    var entityKey: SyncEntityKey { SyncEntityKey(kind: .project, id: id) }
}

private extension MindStampItem {
    var entityKey: SyncEntityKey { SyncEntityKey(kind: .mindStamp, id: id) }
}

private extension TaskTypeDefinition {
    var entityKey: SyncEntityKey { SyncEntityKey(kind: .taskType, businessId: idRaw) }
}

private extension HabitModel {
    var entityKey: SyncEntityKey { SyncEntityKey(kind: .habit, id: id) }
}

private extension HabitDayRecord {
    var entityKey: SyncEntityKey { SyncEntityKey(kind: .habitDayRecord, id: id) }
}
