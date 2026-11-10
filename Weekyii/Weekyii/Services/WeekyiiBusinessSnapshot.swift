import Foundation

// MARK: - Sync entity identity

/// The kinds of record the sync layer addresses individually.
///
/// **FROZEN.** The raw values are part of `SyncEntityKey`'s logical key
/// serialization. Renaming a case changes keys that remote devices have already
/// stored, which reads as a delete + insert rather than an update. Append new
/// kinds; never rename.
nonisolated enum SyncEntityKind: String, Codable, CaseIterable, Sendable {
    case week
    case day
    case task
    case suspendedTask
    case attachment
    case project
    case mindStamp
    case taskType
    case habit
    case habitDayRecord
}

/// The business identity of one synchronizable record.
///
/// **FROZEN.** `description` is the logical key serialization and must never change
/// for an existing `(kind, businessId)` pair.
///
/// It is **not** a CloudKit record name, and must not become one by accident. A
/// `SyncEntityKey` is a Weekyii-level identity; `CKRecord.ID.recordName` is a
/// CloudKit-level identity with its own character and length rules. Phase D owns a
/// separate deterministic `CKRecordNameCodec` for that, and `description` is not its
/// input contract.
///
/// Business identity is *not* the SwiftData row. It is the field the app already
/// treats as the record's identity:
///
/// | kind | `businessId` |
/// |---|---|
/// | `week` | `WeekModel.weekId` |
/// | `day` | `DayModel.dayId` |
/// | `task` | `TaskItem.id.uuidString` |
/// | `suspendedTask` | `SuspendedTaskItem.id.uuidString` |
/// | `attachment` | `TaskAttachment.id.uuidString` |
/// | `project` | `ProjectModel.id.uuidString` |
/// | `mindStamp` | `MindStampItem.id.uuidString` |
/// | `taskType` | `TaskTypeDefinition.idRaw` |
/// | `habit` | `HabitModel.id.uuidString` |
/// | `habitDayRecord` | `HabitDayRecord.id.uuidString` |
///
/// Every `UUID` is rendered with `.uuidString` (uppercase). Never lowercase it —
/// the same record would then have two keys depending on who encoded it.
///
/// A content hash is deliberately **not** an entity key. Editing a record is an
/// update to one entity, not the birth of a new one; content identity is a
/// separate layer (see `WeekyiiSnapshotMergeService`).
nonisolated struct SyncEntityKey: Hashable, Codable, Comparable, CustomStringConvertible, Sendable {
    let kind: SyncEntityKind
    let businessId: String

    init(kind: SyncEntityKind, businessId: String) {
        self.kind = kind
        self.businessId = businessId
    }

    init(kind: SyncEntityKind, id: UUID) {
        self.init(kind: kind, businessId: id.uuidString)
    }

    /// The logical key serialization, e.g. `task:0A1B2C3D-...`.
    ///
    /// Readable on purpose — logs, and the stored change log. It is a Weekyii
    /// identity, not a CloudKit record name; see the type's documentation.
    var description: String { "\(kind.rawValue):\(businessId)" }

    static func < (lhs: SyncEntityKey, rhs: SyncEntityKey) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.businessId < rhs.businessId
    }

    // MARK: Codable

    /// Encoded as the single string `"<kind>:<businessId>"` so keys stay readable
    /// in logs and in the stored change log.
    ///
    /// The split is on the **first** colon, so a `businessId` that itself contains
    /// one (a user-authored task-type slug, say) still round-trips.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let separator = raw.firstIndex(of: ":"),
              let kind = SyncEntityKind(rawValue: String(raw[raw.startIndex..<separator]))
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Malformed SyncEntityKey: \(raw)"
            )
        }
        self.kind = kind
        self.businessId = String(raw[raw.index(after: separator)...])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Which record holds an attachment.
///
/// Attachments are **their own sync entity**: a task's snapshot carries attachment
/// *ids* only, never the binary. The archive DTOs embed the binary inside the task
/// record, which makes the task aggregate change whenever an unrelated attachment
/// changes — hoisting attachments out is the point of the normalized snapshot.
///
/// Because the owner lives in the attachment's *payload* rather than its key,
/// moving an attachment between owners keeps its identity. That is what makes
/// `SuspendedTaskLifecycleService.assignTask` a move instead of a delete + insert.
enum AttachmentOwner: Hashable, Codable {
    case task(UUID)
    case suspendedTask(UUID)

    var entityKey: SyncEntityKey {
        switch self {
        case .task(let id):
            return SyncEntityKey(kind: .task, businessId: id.uuidString)
        case .suspendedTask(let id):
            return SyncEntityKey(kind: .suspendedTask, businessId: id.uuidString)
        }
    }

    var kind: SyncEntityKind {
        switch self {
        case .task: return .task
        case .suspendedTask: return .suspendedTask
        }
    }
}

// MARK: - Entity snapshots

/// One task step, **embedded** in its task rather than addressed separately.
///
/// A step has no business key of its own, which is why Phase A0 only stabilised
/// its `createdAt` instead of giving it an identity.
struct StepSnapshot: Hashable, Codable {
    let title: String
    let isCompleted: Bool
    let sortOrder: Int
    let createdAt: Date
}

/// An attachment, as a top-level entity.
struct AttachmentSnapshot: Hashable, Codable {
    let id: UUID
    let owner: AttachmentOwner
    let data: Data?
    let fileName: String
    let fileType: String
    let createdAt: Date

    var entityKey: SyncEntityKey { SyncEntityKey(kind: .attachment, id: id) }
}

struct WeekSnapshot: Hashable, Codable {
    let weekId: String
    let startDate: Date
    let endDate: Date
    let status: WeekStatus
    let completedTasksCount: Int
    let expiredTasksCount: Int
    let totalStartedDays: Int

    var entityKey: SyncEntityKey { SyncEntityKey(kind: .week, businessId: weekId) }
}

struct DaySnapshot: Hashable, Codable {
    let dayId: String
    /// Child → parent link. Parent collections are rebuilt from these, never
    /// stored on both sides.
    let weekId: String?
    let date: Date
    let dayOfWeek: String
    let status: DayStatus
    let killTimeHour: Int
    let killTimeMinute: Int
    let followsDefaultKillTime: Bool
    let initiatedAt: Date?
    let closedAt: Date?
    let executionModeRaw: String
    let isDraftZoneUnlocked: Bool
    let expiredCount: Int

    var entityKey: SyncEntityKey { SyncEntityKey(kind: .day, businessId: dayId) }
}

struct TaskSnapshot: Hashable, Codable {
    let id: UUID
    let dayId: String?
    let projectId: UUID?
    let habitId: UUID?
    let title: String
    let taskDescription: String
    let taskType: TaskType
    let taskTypeIdRaw: String
    let order: Int
    let zone: TaskZone
    let startedAt: Date?
    let endedAt: Date?
    let completedOrder: Int
    /// Embedded — a step is part of the task's own content.
    let steps: [StepSnapshot]
    /// Ids only. The binaries live in `AttachmentSnapshot`, keyed separately.
    let attachmentIds: [UUID]

    var entityKey: SyncEntityKey { SyncEntityKey(kind: .task, id: id) }
}

struct SuspendedTaskSnapshot: Hashable, Codable {
    let id: UUID
    let title: String
    let taskDescription: String
    let taskType: TaskType
    let taskTypeIdRaw: String
    let createdAt: Date
    let decisionDeadline: Date
    let preferredCountdownDays: Int
    let snoozeCount: Int
    let statusRaw: String
    let steps: [StepSnapshot]
    let attachmentIds: [UUID]

    var entityKey: SyncEntityKey { SyncEntityKey(kind: .suspendedTask, id: id) }
}

struct ProjectSnapshot: Hashable, Codable {
    let id: UUID
    let name: String
    let projectDescription: String
    let color: String
    let icon: String
    let status: ProjectStatus
    let startDate: Date
    let endDate: Date
    let createdAt: Date
    let tileSizeRaw: String
    let tileOrder: Int

    var entityKey: SyncEntityKey { SyncEntityKey(kind: .project, id: id) }
}

struct MindStampSnapshot: Hashable, Codable {
    let id: UUID
    let text: String
    let imageBlob: Data?
    let createdAt: Date

    var entityKey: SyncEntityKey { SyncEntityKey(kind: .mindStamp, id: id) }
}

struct TaskTypeSnapshot: Hashable, Codable {
    let idRaw: String
    let name: String
    let iconName: String
    let colorHex: String
    let baseKindRaw: String
    let sortOrder: Int
    let isBuiltIn: Bool
    let isArchived: Bool

    var entityKey: SyncEntityKey { SyncEntityKey(kind: .taskType, businessId: idRaw) }
}

struct HabitSnapshot: Hashable, Codable {
    let id: UUID
    let name: String
    let iconName: String
    let colorHex: String
    let categoryRaw: String
    let scheduleKindRaw: String
    let scheduleWeekdaysRaw: Int
    let scheduleMonthDaysRaw: Int
    let startDayId: String
    let isActive: Bool
    let createdAt: Date
    let sortOrder: Int

    var entityKey: SyncEntityKey { SyncEntityKey(kind: .habit, id: id) }
}

struct HabitDayRecordSnapshot: Hashable, Codable {
    let id: UUID
    let habitId: UUID?
    let dayId: String
    let statusRaw: String
    let createdAt: Date
    let completedAt: Date?

    var entityKey: SyncEntityKey { SyncEntityKey(kind: .habitDayRecord, id: id) }
}

// MARK: - Snapshot

/// A normalized, entity-per-record view of the whole business graph.
///
/// ## Why a second representation
///
/// `WeekyiiDataArchiveService` already serialises the graph, but its payload is
/// shaped for *backup*, not for sync:
///
/// * it embeds a task's attachment binaries inside the task record, so the task
///   aggregate changes whenever an unrelated attachment does;
/// * its arrays are in fetch order, which is not stable across runs;
/// * it has no per-record identity, so an incremental sync has nothing to diff on.
///
/// The snapshot fixes all three: attachments are top-level entities, every array
/// is sorted by `SyncEntityKey`, and every record has a business key.
///
/// ## Ordering is an invariant, not a convention
///
/// The initialiser sorts every array by `entityKey`, so a snapshot cannot exist in
/// a non-canonical order. Phase A2's canonical encoding (and therefore its hashes)
/// depends on that: two snapshots of the same graph must encode to the same bytes
/// regardless of the order SwiftData happened to return rows in.
///
/// ## Relationships
///
/// Only the **child → parent** direction is stored (`task.dayId`, `day.weekId`,
/// `attachment.owner`, …). Parent collections are rebuilt from the children, so
/// the two sides cannot drift apart and the merge has a single source of truth.
///
/// ## What is deliberately absent
///
/// `UserSettings` and `AppState` are not entities — they are singletons living in
/// `UserDefaults`, i.e. **device-local state**, not in SwiftData and not in iCloud
/// key-value storage. The new sync design drops KVS entirely, so these must not be
/// assumed to travel with the account. They are out of scope here; the archive
/// adapter in Phase A2 takes them as explicit parameters, and
/// `premiumThemeUnlocked` specifically must never be treated as an entitlement
/// (it is a local cache — see the plan's §C).
struct WeekyiiBusinessSnapshot: Hashable, Codable {
    /// Bumped only when the snapshot's own shape changes in a way older readers
    /// cannot handle. The archive's `formatVersion` is a different number and
    /// stays at 1.
    static let currentVersion = 1

    let version: Int
    let weeks: [WeekSnapshot]
    let days: [DaySnapshot]
    let tasks: [TaskSnapshot]
    let suspendedTasks: [SuspendedTaskSnapshot]
    let attachments: [AttachmentSnapshot]
    let projects: [ProjectSnapshot]
    let mindStamps: [MindStampSnapshot]
    let taskTypes: [TaskTypeSnapshot]
    let habits: [HabitSnapshot]
    let habitDayRecords: [HabitDayRecordSnapshot]

    init(
        version: Int = WeekyiiBusinessSnapshot.currentVersion,
        weeks: [WeekSnapshot],
        days: [DaySnapshot],
        tasks: [TaskSnapshot],
        suspendedTasks: [SuspendedTaskSnapshot],
        attachments: [AttachmentSnapshot],
        projects: [ProjectSnapshot],
        mindStamps: [MindStampSnapshot],
        taskTypes: [TaskTypeSnapshot],
        habits: [HabitSnapshot],
        habitDayRecords: [HabitDayRecordSnapshot]
    ) {
        self.version = version
        // Sorting here, rather than trusting callers, makes canonical order
        // unrepresentable-otherwise.
        self.weeks = weeks.sorted { $0.entityKey < $1.entityKey }
        self.days = days.sorted { $0.entityKey < $1.entityKey }
        self.tasks = tasks.sorted { $0.entityKey < $1.entityKey }
        self.suspendedTasks = suspendedTasks.sorted { $0.entityKey < $1.entityKey }
        self.attachments = attachments.sorted { $0.entityKey < $1.entityKey }
        self.projects = projects.sorted { $0.entityKey < $1.entityKey }
        self.mindStamps = mindStamps.sorted { $0.entityKey < $1.entityKey }
        self.taskTypes = taskTypes.sorted { $0.entityKey < $1.entityKey }
        self.habits = habits.sorted { $0.entityKey < $1.entityKey }
        self.habitDayRecords = habitDayRecords.sorted { $0.entityKey < $1.entityKey }
    }

    static let empty = WeekyiiBusinessSnapshot(
        weeks: [],
        days: [],
        tasks: [],
        suspendedTasks: [],
        attachments: [],
        projects: [],
        mindStamps: [],
        taskTypes: [],
        habits: [],
        habitDayRecords: []
    )

    var isEmpty: Bool { entityCount == 0 }

    var entityCount: Int {
        weeks.count + days.count + tasks.count + suspendedTasks.count + attachments.count
            + projects.count + mindStamps.count + taskTypes.count + habits.count + habitDayRecords.count
    }

    func entityCount(for kind: SyncEntityKind) -> Int {
        switch kind {
        case .week: return weeks.count
        case .day: return days.count
        case .task: return tasks.count
        case .suspendedTask: return suspendedTasks.count
        case .attachment: return attachments.count
        case .project: return projects.count
        case .mindStamp: return mindStamps.count
        case .taskType: return taskTypes.count
        case .habit: return habits.count
        case .habitDayRecord: return habitDayRecords.count
        }
    }

    /// Every entity key in the snapshot, in canonical order.
    func entityKeys() -> [SyncEntityKey] {
        (
            weeks.map(\.entityKey)
                + days.map(\.entityKey)
                + tasks.map(\.entityKey)
                + suspendedTasks.map(\.entityKey)
                + attachments.map(\.entityKey)
                + projects.map(\.entityKey)
                + mindStamps.map(\.entityKey)
                + taskTypes.map(\.entityKey)
                + habits.map(\.entityKey)
                + habitDayRecords.map(\.entityKey)
        ).sorted()
    }
}
