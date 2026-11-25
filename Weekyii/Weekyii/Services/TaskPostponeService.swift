import Foundation
import SwiftData

struct TaskDraftPayload: Equatable {
    let title: String
    let description: String
    let type: TaskType
    let taskTypeIdRaw: String
    let steps: [TaskStep]
    let attachments: [TaskAttachment]

    init(
        title: String,
        description: String,
        type: TaskType,
        taskTypeIdRaw: String? = nil,
        steps: [TaskStep] = [],
        attachments: [TaskAttachment] = []
    ) {
        self.title = title
        self.description = description
        self.type = type
        self.taskTypeIdRaw = taskTypeIdRaw ?? type.rawValue
        self.steps = steps
        self.attachments = attachments
    }
}

enum TaskMutationResult: Equatable {
    case created(UUID)
    case updated(UUID)
    case deleted(UUID)
    case moved
}

protocol TaskMutating {
    @discardableResult
    func createTask(in day: DayModel, payload: TaskDraftPayload, zone: TaskZone, project: ProjectModel?) throws -> TaskItem
    func updateTask(_ task: TaskItem, payload: TaskDraftPayload) throws
    @discardableResult
    func deleteDraftTasks(in day: DayModel, at offsets: IndexSet) throws -> [TaskItem]
    func moveDraftTasks(in day: DayModel, from source: IndexSet, to destination: Int) throws
    @discardableResult
    func deleteTasks(in day: DayModel, zone: TaskZone, at offsets: IndexSet) throws -> [TaskItem]
    func moveTasks(in day: DayModel, zone: TaskZone, from source: IndexSet, to destination: Int) throws
    func normalizeOrder(in day: DayModel, zone: TaskZone)
}

struct TaskMutationService: TaskMutating {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func createTask(in day: DayModel, payload: TaskDraftPayload, zone: TaskZone = .draft, project: ProjectModel? = nil) throws -> TaskItem {
        let normalizedTitle = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { throw WeekyiiError.taskTitleEmpty }

        let nextOrder: Int
        switch zone {
        case .draft:
            nextOrder = (day.sortedDraftTasks.last?.order ?? 0) + 1
        case .focus:
            nextOrder = 1
        case .frozen:
            nextOrder = (day.frozenTasks.last?.order ?? (day.focusTask == nil ? 0 : 1)) + 1
        case .complete:
            nextOrder = (day.completedTasks.last?.order ?? 0) + 1
        }

        let task = TaskItem(
            title: normalizedTitle,
            taskDescription: payload.description.trimmingCharacters(in: .whitespacesAndNewlines),
            taskType: payload.type,
            order: nextOrder,
            zone: zone
        )
        task.taskTypeIdRaw = payload.taskTypeIdRaw
        task.day = day
        task.project = project
        replaceTaskResources(for: task, steps: payload.steps, attachments: payload.attachments)
        day.tasks.append(task)

        if day.status == .empty, zone == .draft {
            day.status = .draft
        }
        if let project, project.status == .planning {
            project.status = .active
        }
        return task
    }

    func updateTask(_ task: TaskItem, payload: TaskDraftPayload) throws {
        let normalizedTitle = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { throw WeekyiiError.taskTitleEmpty }
        task.title = normalizedTitle
        task.taskDescription = payload.description.trimmingCharacters(in: .whitespacesAndNewlines)
        task.taskType = payload.type
        task.taskTypeIdRaw = payload.taskTypeIdRaw
        replaceTaskResources(for: task, steps: payload.steps, attachments: payload.attachments)
    }

    @discardableResult
    func deleteDraftTasks(in day: DayModel, at offsets: IndexSet) throws -> [TaskItem] {
        let deleted = try deleteTasks(in: day, zone: .draft, at: offsets)
        if day.sortedDraftTasks.isEmpty, day.status == .draft {
            day.status = .empty
        }
        return deleted
    }

    @discardableResult
    func deleteTasks(in day: DayModel, zone: TaskZone, at offsets: IndexSet) throws -> [TaskItem] {
        let tasks = orderedTasks(in: day, zone: zone)
        let tasksToDelete = offsets.compactMap { index in
            tasks.indices.contains(index) ? tasks[index] : nil
        }
        day.tasks.removeAll { task in tasksToDelete.contains(where: { $0.id == task.id }) }
        for task in tasksToDelete {
            modelContext.delete(task)
        }
        normalizeOrder(in: day, zone: zone)
        return tasksToDelete
    }

    func moveDraftTasks(in day: DayModel, from source: IndexSet, to destination: Int) throws {
        try moveTasks(in: day, zone: .draft, from: source, to: destination)
    }

    func moveTasks(in day: DayModel, zone: TaskZone, from source: IndexSet, to destination: Int) throws {
        let ordered = orderedTasks(in: day, zone: zone)
        let count = ordered.count
        guard source.isEmpty == false, destination >= 0, destination <= count else { return }
        var tasks = ordered
        tasks.move(fromOffsets: source, toOffset: destination)
        let startingOrder = zone == .frozen && day.focusTask != nil ? 2 : 1
        for (index, task) in tasks.enumerated() {
            task.order = startingOrder + index
        }
    }

    func normalizeOrder(in day: DayModel, zone: TaskZone) {
        let startingOrder = zone == .frozen && day.focusTask != nil ? 2 : 1
        for (index, task) in orderedTasks(in: day, zone: zone).enumerated() {
            task.order = startingOrder + index
        }
    }

    // MARK: - Resource replacement

    /// Replaces **only** the task's steps. Attachments are left untouched, so an
    /// edit that does not concern attachments cannot churn their identity.
    func replaceTaskSteps(for task: TaskItem, steps: [TaskStep]) {
        TaskResourceIdentity.reconcileSteps(on: task, with: steps, in: modelContext)
    }

    /// Replaces **only** the task's attachments. Steps are left untouched.
    func replaceTaskAttachments(for task: TaskItem, attachments: [TaskAttachment]) {
        TaskResourceIdentity.reconcileAttachments(on: task, with: attachments, in: modelContext)
    }

    func replaceTaskSteps(for task: SuspendedTaskItem, steps: [TaskStep]) {
        TaskResourceIdentity.reconcileSteps(on: task, with: steps, in: modelContext)
    }

    func replaceTaskAttachments(for task: SuspendedTaskItem, attachments: [TaskAttachment]) {
        TaskResourceIdentity.reconcileAttachments(on: task, with: attachments, in: modelContext)
    }

    /// Replaces both resource kinds. Prefer the per-kind entry points above when
    /// only one kind actually changed — passing the other kind through is what
    /// used to rebuild it.
    func replaceTaskResources(for task: TaskItem, steps: [TaskStep], attachments: [TaskAttachment]) {
        replaceTaskSteps(for: task, steps: steps)
        replaceTaskAttachments(for: task, attachments: attachments)
    }

    func replaceTaskResources(for task: SuspendedTaskItem, steps: [TaskStep], attachments: [TaskAttachment]) {
        replaceTaskSteps(for: task, steps: steps)
        replaceTaskAttachments(for: task, attachments: attachments)
    }

    private func renumberDraftTasks(in day: DayModel) {
        for (index, task) in day.sortedDraftTasks.enumerated() {
            task.order = index + 1
        }
    }

    private func orderedTasks(in day: DayModel, zone: TaskZone) -> [TaskItem] {
        switch zone {
        case .draft:
            return day.sortedDraftTasks
        case .focus:
            return day.focusTask.map { [$0] } ?? []
        case .frozen:
            return day.frozenTasks
        case .complete:
            return day.completedTasks
        }
    }
}

struct TaskPostponeService {
    struct Preview {
        let taskID: UUID
        let targetDate: Date
        let targetDayId: String
        let targetWeekId: String
        let requiresWeekCreation: Bool
    }

    struct ExecutionResult {
        let sourceDayId: String
        let targetDayId: String
        let targetDate: Date
        let createdWeek: Bool
    }

    private let modelContainer: ModelContainer
    private let calendar = Calendar(identifier: .iso8601)

    private var modelContext: ModelContext {
        modelContainer.mainContext
    }

    init(modelContext: ModelContext) {
        self.modelContainer = modelContext.container
    }

    func preview(taskID: UUID, targetDate: Date, today: Date) throws -> Preview {
        let todayStart = calendar.startOfDay(for: today)
        let normalizedTargetDate = calendar.startOfDay(for: targetDate)
        guard normalizedTargetDate > todayStart else {
            throw WeekyiiError.postponeTargetMustBeFuture
        }

        let task = try fetchTask(by: taskID)
        try validateSourceTask(task, todayDayId: todayStart.dayId)
        try validateProjectPlacement(for: task, targetDate: normalizedTargetDate)

        let targetDayId = normalizedTargetDate.dayId
        let targetWeekId = normalizedTargetDate.weekId

        if let existingTargetDay = fetchDay(by: targetDayId) {
            guard isAcceptableTargetDayStatus(existingTargetDay.status) else {
                throw WeekyiiError.postponeTargetDayUnavailable
            }
            return Preview(
                taskID: taskID,
                targetDate: normalizedTargetDate,
                targetDayId: targetDayId,
                targetWeekId: targetWeekId,
                requiresWeekCreation: false
            )
        }

        let hasWeek = fetchWeek(by: targetWeekId) != nil
        return Preview(
            taskID: taskID,
            targetDate: normalizedTargetDate,
            targetDayId: targetDayId,
            targetWeekId: targetWeekId,
            requiresWeekCreation: !hasWeek
        )
    }

    func execute(preview: Preview, allowCreateWeek: Bool, today: Date, now: Date) throws -> ExecutionResult {
        let task = try fetchTask(by: preview.taskID)
        let sourceZone = task.zone
        let sourceDay = try resolveSourceDay(for: task)

        let todayDayId = calendar.startOfDay(for: today).dayId
        guard sourceDay.dayId == todayDayId else {
            throw WeekyiiError.postponeSourceTaskNotInToday
        }
        try validateSourceTask(task, todayDayId: todayDayId)
        try validateProjectPlacement(for: task, targetDate: preview.targetDate)

        let resolution = try resolveTargetDay(preview: preview, today: today, allowCreateWeek: allowCreateWeek)
        let targetDay = resolution.day
        guard isAcceptableTargetDayStatus(targetDay.status) else {
            throw WeekyiiError.postponeTargetDayUnavailable
        }

        sourceDay.tasks.removeAll { $0.id == task.id }

        task.day = targetDay
        if targetDay.tasks.contains(where: { $0.id == task.id }) == false {
            targetDay.tasks.append(task)
        }
        if targetDay.status == .empty {
            targetDay.status = .draft
        }

        task.zone = .draft
        task.order = nextDraftOrder(in: targetDay)
        task.startedAt = nil
        task.endedAt = nil
        task.completedOrder = 0

        repairSourceDayAfterRemoval(sourceDay, removedZone: sourceZone, now: now)
        renumberDraftTasks(in: targetDay)

        return ExecutionResult(
            sourceDayId: sourceDay.dayId,
            targetDayId: targetDay.dayId,
            targetDate: preview.targetDate,
            createdWeek: resolution.createdWeek
        )
    }

    private func resolveSourceDay(for task: TaskItem) throws -> DayModel {
        guard let sourceDay = task.day else {
            throw WeekyiiError.dayNotFound("unknown")
        }
        return sourceDay
    }

    private func validateSourceTask(_ task: TaskItem, todayDayId: String) throws {
        guard let sourceDay = task.day else {
            throw WeekyiiError.dayNotFound(todayDayId)
        }
        guard sourceDay.dayId == todayDayId else {
            throw WeekyiiError.postponeSourceTaskNotInToday
        }
        guard task.habit == nil else {
            throw WeekyiiError.cannotPostponeHabitTask
        }

        switch task.zone {
        case .draft, .focus, .frozen:
            break
        case .complete:
            throw WeekyiiError.cannotPostponeCompletedTask
        }
    }

    private func validateProjectPlacement(for task: TaskItem, targetDate: Date) throws {
        guard let project = task.project else { return }
        guard project.status == .planning || project.status == .active else {
            throw WeekyiiError.projectReadOnly
        }
        let target = calendar.startOfDay(for: targetDate)
        let start = calendar.startOfDay(for: project.startDate)
        let end = calendar.startOfDay(for: project.endDate)
        guard target >= start && target <= end else {
            throw WeekyiiError.projectDateOutOfRange
        }
    }

    private func isAcceptableTargetDayStatus(_ status: DayStatus) -> Bool {
        status == .empty || status == .draft
    }

    private func resolveTargetDay(preview: Preview, today: Date, allowCreateWeek: Bool) throws -> (day: DayModel, createdWeek: Bool) {
        if let existingDay = fetchDay(by: preview.targetDayId) {
            return (existingDay, false)
        }

        if let existingWeek = fetchWeek(by: preview.targetWeekId) {
            let day = DayModel(dayId: preview.targetDayId, date: preview.targetDate, status: .empty)
            existingWeek.days.append(day)
            return (day, false)
        }

        guard allowCreateWeek else {
            throw WeekyiiError.postponeTargetDayUnavailable
        }

        let status = statusForNewWeek(targetDate: preview.targetDate, today: today)
        let resolution = try WeekDataStore(modelContext: modelContext)
            .resolveDay(on: preview.targetDate, weekStatus: status)
        return (resolution.day, resolution.createdWeek)
    }

    private func statusForNewWeek(targetDate: Date, today: Date) -> WeekStatus {
        let targetWeekStart = calendar.startOfDay(for: targetDate).startOfWeek
        let todayWeekStart = calendar.startOfDay(for: today).startOfWeek
        if targetWeekStart == todayWeekStart {
            return .present
        }
        if targetWeekStart > todayWeekStart {
            return .pending
        }
        return .past
    }

    private func nextDraftOrder(in day: DayModel) -> Int {
        (day.sortedDraftTasks.last?.order ?? 0) + 1
    }

    private func renumberDraftTasks(in day: DayModel) {
        let sorted = day.sortedDraftTasks
        for (index, task) in sorted.enumerated() {
            task.order = index + 1
        }
    }

    private func repairSourceDayAfterRemoval(_ day: DayModel, removedZone: TaskZone, now: Date) {
        switch removedZone {
        case .draft:
            renumberDraftTasks(in: day)
            if day.sortedDraftTasks.isEmpty {
                day.status = .empty
            }

        case .focus:
            if let nextFocus = day.frozenTasks.first {
                nextFocus.zone = .focus
                if nextFocus.startedAt == nil {
                    nextFocus.startedAt = now
                }
                renumberExecutionQueue(in: day)
            } else {
                day.isDraftZoneUnlocked = false
                day.status = .completed
                day.closedAt = now
            }

        case .frozen:
            renumberExecutionQueue(in: day)
            if day.status == .draft {
                renumberDraftTasks(in: day)
                if day.sortedDraftTasks.isEmpty {
                    day.status = .empty
                }
            } else if day.status == .execute, day.focusTask == nil, day.frozenTasks.isEmpty {
                day.isDraftZoneUnlocked = false
                day.status = .completed
                day.closedAt = now
            }

        case .complete:
            break
        }
    }

    private func renumberExecutionQueue(in day: DayModel) {
        guard day.status == .execute else { return }
        var order = 1
        if let focus = day.focusTask {
            focus.order = order
            order += 1
        }
        for task in day.frozenTasks {
            task.order = order
            order += 1
        }
    }

    private func fetchTask(by taskID: UUID) throws -> TaskItem {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == taskID })
        if let task = try modelContext.fetch(descriptor).first {
            return task
        }
        throw WeekyiiError.taskNotFound(taskID)
    }

    private func fetchDay(by dayId: String) -> DayModel? {
        let descriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == dayId })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchWeek(by weekId: String) -> WeekModel? {
        let descriptor = FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Resource identity

/// Anything that owns a task's resources.
///
/// `TaskItem` and `SuspendedTaskItem` already expose exactly these two accessors,
/// so conformance is empty — the protocol exists only so the reconciliation rules
/// below have a single implementation instead of one per owner type.
protocol TaskResourceOwner: AnyObject {
    var steps: [TaskStep] { get set }
    var attachments: [TaskAttachment] { get set }
}

extension TaskItem: TaskResourceOwner {}
extension SuspendedTaskItem: TaskResourceOwner {}

/// Identity rules for the two *resource* kinds hanging off a task: `TaskStep`
/// and `TaskAttachment`.
///
/// ## Why this exists
///
/// Both kinds are separate persisted rows attached to their owner through
/// cascade relationships. Every mutation path used to rebuild them from scratch
/// ("delete all, then re-create all"), which meant:
///
/// * `TaskAttachment.id` — the attachment's business identity, and the key the
///   sync layer addresses it by — was regenerated on **every** save, including
///   saves that never touched attachments. To a UUID-keyed incremental sync that
///   looks like "old attachment deleted, identical attachment created", so the
///   same bytes get re-uploaded and an untouched aggregate still looks dirty.
/// * `TaskStep.createdAt` was reset to "now" on every save, so a no-op save
///   changed the task's content hash.
/// * `SuspendedTaskLifecycleService.assignTask` re-created a suspended task's
///   resources instead of moving them, minting new attachment identities for
///   resources that had not changed at all.
///
/// ## The rules
///
/// | Intent | Identity |
/// |---|---|
/// | edit a resource in place | **preserved** — the row is updated, not replaced |
/// | move a resource to another owner | **preserved** — same row, re-parented |
/// | duplicate a resource | **regenerated** — new `UUID`, new `createdAt` |
///
/// Editing one resource kind must never rebuild the other kind.
///
/// `TaskStep` is deliberately *not* reconciled by identity: it has no stable
/// business key, and the sync design embeds a task's steps in the task's own
/// snapshot rather than addressing them individually. Preserving `createdAt` is
/// enough to keep that embedded representation deterministic.
enum TaskResourceIdentity {

    // MARK: - Steps

    /// Deterministic step order: `(sortOrder, createdAt)`.
    static func sortedSteps(_ steps: [TaskStep]) -> [TaskStep] {
        steps.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
    }

    /// Renumbers `sortOrder` to a dense 0-based sequence, **in place**. Reuses the
    /// existing rows and mints nothing.
    static func renumberSteps(_ steps: [TaskStep]) {
        for (index, step) in sortedSteps(steps).enumerated() {
            step.sortOrder = index
        }
    }

    /// Copies `steps` for embedding into another owner, **preserving `createdAt`**
    /// while renumbering `sortOrder`.
    ///
    /// This is the single implementation behind the `normalizedStepCopies` that
    /// used to be duplicated across four view models.
    static func stepCopies(from steps: [TaskStep]) -> [TaskStep] {
        sortedSteps(steps).enumerated().map { index, step in
            TaskStep(
                title: step.title,
                isCompleted: step.isCompleted,
                sortOrder: index,
                createdAt: step.createdAt
            )
        }
    }

    // MARK: - Attachments

    /// Copies `attachments` for a **duplication**: every copy gets a fresh `id`
    /// and `createdAt`. This is the only place where an *existing* attachment's
    /// identity is deliberately minted anew.
    static func duplicatedAttachmentCopies(from attachments: [TaskAttachment]) -> [TaskAttachment] {
        orderedUniqueAttachments(attachments).map { attachment in
            TaskAttachment(
                data: attachment.data,
                fileName: attachment.fileName,
                fileType: attachment.fileType
            )
        }
    }

    /// De-duplicates by business identity, keeping the first occurrence and the
    /// caller's order. Two rows carrying one `id` are one entity as far as the
    /// sync layer is concerned, so this is a correctness guard, not a nicety.
    static func orderedUniqueAttachments(_ attachments: [TaskAttachment]) -> [TaskAttachment] {
        var seen = Set<UUID>()
        var result: [TaskAttachment] = []
        for attachment in attachments where seen.insert(attachment.id).inserted {
            result.append(attachment)
        }
        return result
    }

    // MARK: - Reconciliation

    /// Reconciles `steps` onto `owner`.
    ///
    /// Steps carry no business key, so this is a replace: rows the owner does not
    /// already hold are deleted and re-created from `stepCopies(from:)`. When the
    /// caller hands the owner's own rows back in, they are only reordered.
    static func reconcileSteps<Owner: TaskResourceOwner>(
        on owner: Owner,
        with steps: [TaskStep],
        in context: ModelContext
    ) {
        let existing = owner.steps
        if !existing.isEmpty, holdsSameRows(existing, steps) {
            renumberSteps(steps)
            owner.steps = steps
            return
        }
        for row in existing { context.delete(row) }
        owner.steps = stepCopies(from: steps)
    }

    /// Reconciles `attachments` onto `owner` **by `id`**:
    ///
    /// * rows whose `id` is absent from `attachments` are deleted;
    /// * rows whose `id` is present are updated **in place**, keeping their
    ///   persisted row and their `createdAt`;
    /// * ids that are new are inserted carrying the caller's `id` / `createdAt`.
    ///
    /// Updating in place rather than deleting and re-inserting is the whole point:
    /// it is what keeps the attachment's business identity stable across edits.
    static func reconcileAttachments<Owner: TaskResourceOwner>(
        on owner: Owner,
        with attachments: [TaskAttachment],
        in context: ModelContext
    ) {
        let wanted = orderedUniqueAttachments(attachments)
        let wantedIDs = Set(wanted.map(\.id))

        var survivors: [UUID: TaskAttachment] = [:]
        for existing in owner.attachments {
            guard wantedIDs.contains(existing.id) else {
                context.delete(existing)
                continue
            }
            if let kept = survivors[existing.id] {
                // Two persisted rows for one business id: keep the first, drop the rest.
                if kept !== existing { context.delete(existing) }
            } else {
                survivors[existing.id] = existing
            }
        }

        var reconciled: [TaskAttachment] = []
        reconciled.reserveCapacity(wanted.count)
        for incoming in wanted {
            if let existing = survivors.removeValue(forKey: incoming.id) {
                if existing !== incoming {
                    existing.data = incoming.data
                    existing.fileName = incoming.fileName
                    existing.fileType = incoming.fileType
                }
                // `createdAt` belongs to the resource, not to the edit: the
                // persisted value wins so a later save cannot drift it.
                reconciled.append(existing)
            } else {
                reconciled.append(
                    TaskAttachment(
                        id: incoming.id,
                        data: incoming.data,
                        fileName: incoming.fileName,
                        fileType: incoming.fileType,
                        createdAt: incoming.createdAt
                    )
                )
            }
        }
        owner.attachments = reconciled
    }

    /// True when `candidate` holds exactly the same rows as `existing` — i.e. the
    /// caller passed the owner's own objects back in rather than copies.
    private static func holdsSameRows(_ existing: [TaskStep], _ candidate: [TaskStep]) -> Bool {
        guard existing.count == candidate.count else { return false }
        let existingIDs = Set(existing.map(ObjectIdentifier.init))
        return candidate.allSatisfy { existingIDs.contains(ObjectIdentifier($0)) }
    }
}
