import XCTest
import SwiftData
@testable import Weekyii

/// Phase B1a — consolidating the legacy `Weekyii.local.store` into the canonical
/// `Weekyii.store`.
///
/// Every case drives the real entry point on file-backed stores inside a private
/// temporary directory, and passes both URLs explicitly — the same call shape
/// production uses, so a passing test is evidence about the shipping path rather
/// than about an in-memory stand-in.
@MainActor
final class LegacyStoreConsolidatorTests: XCTestCase {
    /// SwiftData containers are `@MainActor` classes, and deallocating one inside a
    /// `@MainActor` test crashes the process on the iOS 26.2 simulator
    /// (isolated-deinit back-deploy shim double-free — same cause as
    /// `WeekyiiSnapshotRepositoryTests.retainedContainers`).
    private static var retainedContainers: [ModelContainer] = []
    /// `UserSettings` / `AppState` hit the same deinit path.
    private static var retainedFixtures: [AnyObject] = []

    private var rootURL: URL!
    private var canonicalURL: URL!
    private var legacyURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "LegacyStoreConsolidatorTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekyii-consolidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        canonicalURL = rootURL.appendingPathComponent(LegacyStoreConsolidator.canonicalStoreFileName)
        legacyURL = rootURL.appendingPathComponent(LegacyStoreConsolidator.legacyStoreFileName)
    }

    override func tearDownWithError() throws {
        if let defaults, let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        defaults = nil
        suiteName = nil
        canonicalURL = nil
        legacyURL = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Store scaffolding

    private func makeContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "LegacyStoreConsolidatorTests.\(UUID().uuidString)",
            schema: WeekyiiPersistence.currentSchema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: WeekyiiPersistence.currentSchema,
            migrationPlan: WeekyiiMigrationPlan.self,
            configurations: configuration
        )
        Self.retainedContainers.append(container)
        return container
    }

    /// Creates a store at `url` and fills it. The file has to exist afterwards —
    /// otherwise "the legacy store is empty" and "the legacy store does not exist"
    /// would silently be the same test.
    private func populate(_ url: URL, _ work: (ModelContext) throws -> Void) throws {
        let container = try makeContainer(at: url)
        try work(container.mainContext)
        try container.mainContext.save()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "seeding did not create a store file at \(url.path)"
        )
    }

    private func snapshot(at url: URL) throws -> WeekyiiBusinessSnapshot {
        let container = try makeContainer(at: url)
        return try WeekyiiSnapshotRepository.requireCleanSnapshot(from: container.mainContext)
    }

    private func keys(at url: URL) throws -> Set<SyncEntityKey> {
        Set(try snapshot(at: url).entityKeys())
    }

    /// Keys of a store that may itself be ambiguous. `load(from:)` is the inspection
    /// route: it returns a best-effort snapshot instead of refusing, which is what a
    /// "was this store left untouched?" assertion needs.
    private func keysEvenIfAmbiguous(at url: URL) throws -> Set<SyncEntityKey> {
        let container = try makeContainer(at: url)
        let result = try WeekyiiSnapshotRepository.load(from: container.mainContext)
        return Set(result.snapshot.entityKeys())
    }

    private func consolidate(
        fileSystem: LegacyStoreConsolidator.RetirementFileSystem? = nil
    ) throws -> LegacyStoreConsolidator.Report {
        try LegacyStoreConsolidator.consolidateIfNeeded(
            canonicalStoreURL: canonicalURL,
            legacyStoreURL: legacyURL,
            now: makeDate(2026, 9, 22),
            defaults: defaults,
            retirementFileSystem: fileSystem ?? .live
        )
    }

    private var markerIsSet: Bool {
        defaults.object(forKey: LegacyStoreConsolidator.completionMarkerKey) != nil
    }

    private var archivesDirectoryURL: URL {
        rootURL.appendingPathComponent(LegacyStoreConsolidator.archiveDirectoryName, isDirectory: true)
    }

    private func backupFolderNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: rootURL.appendingPathComponent("Backups", isDirectory: true),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).map(\.lastPathComponent).sorted()
    }

    /// Recovery points this migration recorded, selected by the `reason:` it passed to
    /// `BackupRecoveryService`. Tolerates `Backups/` not existing, because "created no
    /// recovery point" is one of the things some cases assert.
    private func backupFolders(matching reason: String) throws -> [String] {
        let folder = rootURL.appendingPathComponent("Backups", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try backupFolderNames().filter { $0.contains(reason) }
    }

    // MARK: - Record factories

    /// A week → day → task chain, or a bare task when `dayId` is nil.
    @discardableResult
    private func makeTaskGraph(
        in context: ModelContext,
        weekId: String? = nil,
        dayId: String? = nil,
        taskTitle: String,
        taskId: UUID = UUID()
    ) -> TaskItem {
        var parentDay: DayModel?
        if let dayId {
            var parentWeek: WeekModel?
            if let weekId {
                let week = WeekModel(
                    weekId: weekId,
                    startDate: makeDate(2026, 9, 21),
                    endDate: makeDate(2026, 9, 27),
                    status: .present
                )
                context.insert(week)
                parentWeek = week
            }
            let day = DayModel(dayId: dayId, date: makeDate(2026, 9, 22), status: .draft)
            day.week = parentWeek
            context.insert(day)
            parentDay = day
        }
        let task = TaskItem(title: taskTitle, taskDescription: "", taskType: .regular, order: 1, zone: .draft)
        task.id = taskId
        task.day = parentDay
        context.insert(task)
        return task
    }

    @discardableResult
    private func makeAttachment(
        data: Data?,
        ownedByTask task: TaskItem? = nil,
        ownedBySuspendedTask suspended: SuspendedTaskItem? = nil,
        in context: ModelContext
    ) -> TaskAttachment {
        let attachment = TaskAttachment(data: data, fileName: "evidence.png", fileType: "public.png")
        attachment.task = task
        attachment.suspendedTask = suspended
        context.insert(attachment)
        return attachment
    }

    @discardableResult
    private func makeHabitGraph(in context: ModelContext, id: UUID = UUID()) -> HabitModel {
        let habit = HabitModel(
            name: "阅读",
            iconName: "book",
            colorHex: "#1F1712",
            startDayId: "2026-09-22"
        )
        habit.id = id
        context.insert(habit)
        let record = HabitDayRecord(dayId: "2026-09-22", createdAt: makeDate(2026, 9, 22))
        record.statusRaw = HabitDayRecordStatus.pending.rawValue
        record.habit = habit
        context.insert(record)
        return habit
    }

    @discardableResult
    private func makeSuspendedTask(in context: ModelContext, id: UUID = UUID()) -> SuspendedTaskItem {
        let task = SuspendedTaskItem(
            title: "悬置任务",
            taskDescription: "",
            taskType: .regular,
            createdAt: makeDate(2026, 9, 20),
            decisionDeadline: makeDate(2026, 9, 30),
            preferredCountdownDays: 10,
            snoozeCount: 0,
            status: .active
        )
        task.id = id
        context.insert(task)
        return task
    }

    @discardableResult
    private func makeBuiltInTaskType(
        in context: ModelContext,
        idRaw: String,
        name: String
    ) -> TaskTypeDefinition {
        let definition = TaskTypeDefinition(
            idRaw: idRaw,
            name: name,
            iconName: "circle",
            colorHex: "#1F1712",
            baseKind: .regular,
            sortOrder: 1,
            isBuiltIn: true,
            isArchived: false
        )
        context.insert(definition)
        return definition
    }

    @discardableResult
    private func makeCustomTaskType(
        in context: ModelContext,
        idRaw: String,
        name: String
    ) -> TaskTypeDefinition {
        let definition = TaskTypeDefinition(
            idRaw: idRaw,
            name: name,
            iconName: "square.stack",
            colorHex: "#8C4A2B",
            baseKind: .ddl,
            sortOrder: 7,
            isBuiltIn: false,
            isArchived: true
        )
        context.insert(definition)
        return definition
    }

    /// One record of every kind, with **no field left at its default**.
    ///
    /// This exists for FIX 2. A graph of empty tasks and default dates lets a writer
    /// that forgot a property still produce a store whose records hash the same as the
    /// plan — because the plan's value for that field and SwiftData's default are the
    /// same number. Distinct values turn any such omission into a hash mismatch, which
    /// is the only way "we verified the commit" can mean more than "the row exists".
    ///
    /// `-` prefixed ids and the deliberately out-of-order `sortOrder` values matter for
    /// the same reason: step order and relationship targets are fields too.
    @discardableResult
    private func makeRichGraph(in context: ModelContext, taskId: UUID = UUID()) -> TaskItem {
        let taskType = makeCustomTaskType(in: context, idRaw: "custom.deep", name: "副项目")

        let week = WeekModel(
            weekId: "2026-W41",
            startDate: makeDate(2026, 10, 12),
            endDate: makeDate(2026, 10, 18),
            status: .past
        )
        week.completedTasksCount = 3
        week.expiredTasksCount = 2
        week.totalStartedDays = 1
        context.insert(week)

        let day = DayModel(dayId: "2026-10-13", date: makeDate(2026, 10, 13), status: .completed)
        day.dayOfWeek = "Tue"
        day.killTimeHour = 21
        day.killTimeMinute = 45
        day.followsDefaultKillTime = false
        day.initiatedAt = makeDate(2026, 10, 13, 8, 15, 30)
        day.closedAt = makeDate(2026, 10, 13, 22, 5, 45)
        day.executionModeRaw = "focus"
        day.isDraftZoneUnlocked = true
        day.expiredCount = 4
        day.week = week
        context.insert(day)

        let project = ProjectModel(
            name: "归档工程",
            projectDescription: "带描述的项目",
            color: "#8C4A2B",
            icon: "folder",
            status: .active,
            startDate: makeDate(2026, 9, 1),
            endDate: makeDate(2026, 12, 31)
        )
        project.createdAt = makeDate(2026, 8, 30, 12, 0, 30)
        project.tileSizeRaw = "wide"
        project.tileOrder = 4
        context.insert(project)

        let habit = HabitModel(
            name: "晨读",
            iconName: "book",
            colorHex: "#1F1712",
            startDayId: "2026-10-13"
        )
        habit.categoryRaw = "health"
        habit.scheduleKindRaw = "weekly"
        habit.scheduleWeekdaysRaw = 0b1010101
        habit.scheduleMonthDaysRaw = 15
        habit.generatedThroughDayId = "2026-10-20"
        habit.isActive = false
        habit.createdAt = makeDate(2026, 10, 1, 6, 30)
        habit.sortOrder = 9
        context.insert(habit)

        let habitRecord = HabitDayRecord(dayId: "2026-10-13", createdAt: makeDate(2026, 10, 13, 7, 0, 15))
        habitRecord.statusRaw = HabitDayRecordStatus.completed.rawValue
        habitRecord.completedAt = makeDate(2026, 10, 13, 7, 45, 30)
        habitRecord.habit = habit
        context.insert(habitRecord)

        let task = TaskItem(
            title: "带全部字段的任务",
            taskDescription: "不是空描述",
            taskType: .ddl,
            order: 5,
            zone: .complete
        )
        task.id = taskId
        task.taskTypeIdRaw = taskType.idRaw
        task.startedAt = makeDate(2026, 10, 13, 9, 5, 10)
        task.endedAt = makeDate(2026, 10, 13, 10, 35, 50)
        task.completedOrder = 2
        task.steps = [
            TaskStep(title: "第三步", isCompleted: true, sortOrder: 1),
            TaskStep(title: "第一步", isCompleted: false, sortOrder: 3),
            TaskStep(title: "第二步", isCompleted: true, sortOrder: 2)
        ]
        task.steps[0].createdAt = makeDate(2026, 10, 13, 9, 6)
        task.steps[1].createdAt = makeDate(2026, 10, 13, 9, 7)
        task.steps[2].createdAt = makeDate(2026, 10, 13, 9, 8)
        task.day = day
        task.project = project
        task.habit = habit
        context.insert(task)

        let attachment = TaskAttachment(
            data: Data("附件字节内容".utf8),
            fileName: "evidence-v2.png",
            fileType: "public.png"
        )
        attachment.createdAt = makeDate(2026, 10, 13, 11, 11, 11)
        attachment.task = task
        context.insert(attachment)

        let suspended = makeSuspendedTask(in: context)
        suspended.taskTypeIdRaw = taskType.idRaw
        suspended.taskDescription = "悬置任务的描述"
        suspended.snoozeCount = 3
        suspended.preferredCountdownDays = 12
        suspended.steps = [TaskStep(title: "唯一子步骤", isCompleted: false, sortOrder: 8)]
        suspended.steps[0].createdAt = makeDate(2026, 9, 20, 4, 4, 4)
        let suspendedAttachment = TaskAttachment(
            data: Data("second blob".utf8),
            fileName: "note.txt",
            fileType: "public.plain-text"
        )
        suspendedAttachment.suspendedTask = suspended
        context.insert(suspendedAttachment)

        let stamp = MindStampItem(text: "此刻的想法", imageBlob: Data("image-bytes".utf8))
        stamp.createdAt = makeDate(2026, 10, 13, 23, 59, 59)
        context.insert(stamp)

        return task
    }

    private func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 9,
        _ minute: Int = 0,
        _ second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        guard let date = components.date else {
            fatalError("Invalid date components")
        }
        return date
    }

    // MARK: - Rule 1: no legacy store

    func test_missingLegacyStoreIsANoOpThatTouchesNothing() throws {
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务")
        }
        let canonicalBefore = try keys(at: canonicalURL)

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .noLegacyStore)
        XCTAssertFalse(markerIsSet)
        XCTAssertEqual(report.legacyArchive, .notAttempted)
        XCTAssertEqual(try keys(at: canonicalURL), canonicalBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archivesDirectoryURL.path))
        XCTAssertTrue(
            try backupFolders(matching: "pre-consolidation").isEmpty,
            "rule 1 returns before any store is opened, so there is nothing to protect yet"
        )
    }

    // MARK: - Rule 2 / FIX 4: what counts as migratable user data

    /// A store that exists but holds no records at all.
    ///
    /// It is still retired, exactly once. Left in place it would be inspected again on
    /// every launch, and every inspection takes a pre-open recovery point out of the
    /// same retention window the user's real restore points live in.
    func test_legacyStoreWithNoRecordsAtAllIsRetiredAndMarkedExactlyOnce() throws {
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务")
        }
        // Write a row, then delete it: the file must exist while holding zero
        // entities, because a missing file is rule 1 and not this rule.
        try populate(legacyURL) { context in
            context.insert(WeekModel(
                weekId: "2026-W40",
                startDate: makeDate(2026, 9, 28),
                endDate: makeDate(2026, 10, 4),
                status: .pending
            ))
            try context.save()
            context.delete(try XCTUnwrap(context.fetch(FetchDescriptor<WeekModel>()).first))
        }
        let canonicalBefore = try keys(at: canonicalURL)

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .retiredWithoutImport)
        XCTAssertTrue(markerIsSet)
        XCTAssertTrue(report.entitiesAdded.isEmpty)
        XCTAssertTrue(report.retirementWarnings.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try keys(at: canonicalURL), canonicalBefore, "there was nothing to import")
        XCTAssertEqual(try backupFolders(matching: "pre-consolidation-legacy").count, 1)
        XCTAssertEqual(
            try backupFolders(matching: "pre-consolidation-canonical").count,
            0,
            "canonical is not opened when there is no import to verify"
        )
        try assertRetiredExactlyOnce(bundleCount: 1)
    }

    /// The case that actually ships: `WeekyiiApp` seeds the built-in task types into
    /// whichever store it opens, so every real legacy store holds *something*. Built-ins
    /// are immutable in the product UI and the canonical runtime re-seeds them, so they
    /// alone are not worth importing — but the store is still retired and marked, or the
    /// next launch would take another safety point for a file that will never be
    /// migrated.
    func test_builtinTaskTypesAloneAreRetiredAndMarkedExactlyOnce() throws {
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务")
        }
        try populate(legacyURL) { context in
            makeBuiltInTaskType(in: context, idRaw: "ddl", name: "DDL")
            makeBuiltInTaskType(in: context, idRaw: "regular", name: "常规")
        }
        let canonicalBefore = try keys(at: canonicalURL)

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .retiredWithoutImport)
        XCTAssertTrue(markerIsSet)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try keys(at: canonicalURL), canonicalBefore, "re-seeding is the canonical runtime's job")
        XCTAssertEqual(try backupFolders(matching: "pre-consolidation-legacy").count, 1)
        XCTAssertEqual(try backupFolders(matching: "pre-consolidation-canonical").count, 0)
        try assertRetiredExactlyOnce(bundleCount: 1)
    }

    /// The "exactly once" half of both cases above: a second launch reads the marker,
    /// returns without opening anything, and leaves the recovery points as they were.
    private func assertRetiredExactlyOnce(bundleCount: Int) throws {
        let bundlesAfterFirstRun = try FileManager.default.contentsOfDirectory(atPath: archivesDirectoryURL.path)
        XCTAssertEqual(bundlesAfterFirstRun.count, bundleCount)
        XCTAssertTrue(bundlesAfterFirstRun.contains {
            $0.hasPrefix("2026-09-22") && $0.hasSuffix(LegacyStoreConsolidator.legacyStoreFileName)
        }, "the retired bundle is named after the run that retired it")

        let backupCountAfterFirstRun = try backupFolderNames().count
        let second = try consolidate()

        XCTAssertEqual(second.outcome, .alreadyConsolidated)
        XCTAssertTrue(second.recoverySnapshots.isEmpty)
        XCTAssertEqual(try backupFolderNames().count, backupCountAfterFirstRun, "no second recovery point")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: archivesDirectoryURL.path).count,
            bundleCount,
            "the archive is not re-stacked"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    /// One row the user authored is enough: a custom task type consolidates even with
    /// nothing else in the store.
    func test_customTaskTypeCountsAsUserDataAndMigrates() throws {
        try populate(canonicalURL) { context in
            makeBuiltInTaskType(in: context, idRaw: "ddl", name: "DDL")
        }
        try populate(legacyURL) { context in
            makeBuiltInTaskType(in: context, idRaw: "ddl", name: "DDL")
            makeCustomTaskType(in: context, idRaw: "side-project", name: "副项目")
        }

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .consolidated)
        XCTAssertEqual(
            report.entitiesAdded,
            [SyncEntityKey(kind: .taskType, businessId: "side-project")]
        )
        XCTAssertTrue(markerIsSet)
        let keysInCanonical = try keys(at: canonicalURL)
        XCTAssertTrue(keysInCanonical.contains(SyncEntityKey(kind: .taskType, businessId: "side-project")))
        XCTAssertTrue(keysInCanonical.contains(SyncEntityKey(kind: .taskType, businessId: "ddl")))
    }

    // MARK: - Rule 3: canonical empty, legacy holds the data

    func test_emptyCanonicalStoreImportsTheWholeLegacyGraph() throws {
        try populate(legacyURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "本地库任务")
            makeHabitGraph(in: context)
            context.insert(TaskTypeDefinition(
                idRaw: "custom-writing",
                name: "写作",
                iconName: "pencil",
                colorHex: "#1F1712",
                baseKind: .regular,
                sortOrder: 3,
                isBuiltIn: false,
                isArchived: false
            ))
            makeSuspendedTask(in: context)
        }
        let legacyKeys = try keys(at: legacyURL)
        XCTAssertFalse(legacyKeys.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalURL.path))

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .consolidated)
        XCTAssertEqual(report.entityCountBefore, 0)
        XCTAssertEqual(report.entityCountAfter, legacyKeys.count)
        XCTAssertEqual(Set(report.entitiesAdded), legacyKeys)
        XCTAssertEqual(try keys(at: canonicalURL), legacyKeys)
        XCTAssertTrue(markerIsSet)
    }

    // MARK: - Rule 4: both stores have data, disjoint ids

    func test_disjointIdsFromBothStoresAreAllKept() throws {
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务")
        }
        try populate(legacyURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W38", dayId: "2026-09-15", taskTitle: "本地库任务")
        }
        let canonicalKeys = try keys(at: canonicalURL)
        let legacyKeys = try keys(at: legacyURL)
        XCTAssertTrue(canonicalKeys.isDisjoint(with: legacyKeys), "this case is about *disjoint* ids")

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .consolidated)
        XCTAssertEqual(Set(report.entitiesAdded), legacyKeys)
        XCTAssertTrue(report.conflictsResolvedInFavourOfCanonical.isEmpty)
        XCTAssertEqual(try keys(at: canonicalURL), canonicalKeys.union(legacyKeys))
        XCTAssertTrue(report.didChangeCanonicalStore)
    }

    // MARK: - Rule 4: same key, different content — canonical wins

    func test_sameKeyConflictKeepsCanonicalsRecordAndDropsTheLegacyEdit() throws {
        let sharedId = UUID()
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, taskTitle: "当前库的版本", taskId: sharedId)
        }
        try populate(legacyURL) { context in
            let legacyTask = makeTaskGraph(in: context, taskTitle: "本地库的旧版本", taskId: sharedId)
            legacyTask.completedOrder = 9
        }
        let key = SyncEntityKey(kind: .task, id: sharedId)

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .consolidated)
        XCTAssertEqual(report.conflictsResolvedInFavourOfCanonical, [key])
        XCTAssertTrue(report.entitiesAdded.isEmpty, "a key canonical already holds must not be re-added")
        XCTAssertFalse(report.didChangeCanonicalStore)

        let merged = try snapshot(at: canonicalURL)
        XCTAssertFalse(
            merged.tasks.contains { $0.title == "本地库的旧版本" },
            "canonical is the local authority: legacy content must not overwrite it"
        )
        let surviving = try XCTUnwrap(merged.tasks.first { $0.id == sharedId })
        XCTAssertEqual(surviving.title, "当前库的版本")
        XCTAssertEqual(surviving.completedOrder, 0, "a conflict must not merge field-by-field either")
        XCTAssertTrue(markerIsSet, "the conflict was resolved, so the migration is complete")
    }

    // MARK: - Rule 5: ambiguous identity refuses loudly

    func test_legacyStoreWithDuplicateBusinessIdsRefusesBeforeWritingAnything() throws {
        let collided = UUID()
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务")
        }
        try populate(legacyURL) { context in
            makeTaskGraph(in: context, taskTitle: "重复任务甲", taskId: collided)
            makeTaskGraph(in: context, taskTitle: "重复任务乙", taskId: collided)
        }
        let canonicalBefore = try keys(at: canonicalURL)

        do {
            _ = try consolidate()
            XCTFail("a store where two rows claim one identity must not be merged")
        } catch let error as LegacyStoreConsolidator.ConsolidationError {
            guard case .legacyStoreAmbiguous(let diagnostics) = error else {
                XCTFail("expected legacyStoreAmbiguous, got \(error)")
                return
            }
            XCTAssertTrue(diagnostics.contains { $0.kind == .duplicateBusinessId })
            XCTAssertTrue(diagnostics.contains { $0.entityKey == SyncEntityKey(kind: .task, id: collided) })
        }

        XCTAssertFalse(markerIsSet)
        XCTAssertEqual(try keys(at: canonicalURL), canonicalBefore)
        // Rule 8: the source stays where it is rather than being retired on the way out.
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archivesDirectoryURL.path))
    }

    // MARK: - Rule 4/7: relationships

    func test_attachmentOwnershipAndBlobsSurviveConsolidation() throws {
        let legacyTaskId = UUID()
        let legacySuspendedId = UUID()
        let blob = Data((0..<4_096).map { UInt8($0 % 251) })
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, taskTitle: "当前库任务")
        }
        try populate(legacyURL) { context in
            let task = makeTaskGraph(in: context, taskTitle: "带附件的本地任务", taskId: legacyTaskId)
            makeAttachment(data: blob, ownedByTask: task, in: context)
            makeAttachment(data: nil, ownedByTask: task, in: context)
            makeAttachment(
                data: Data("second".utf8),
                ownedBySuspendedTask: makeSuspendedTask(in: context, id: legacySuspendedId),
                in: context
            )
        }

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .consolidated)
        let merged = try snapshot(at: canonicalURL)
        XCTAssertEqual(merged.attachments.count, 3)
        XCTAssertEqual(merged.attachments.filter { $0.owner == .task(legacyTaskId) }.count, 2)
        XCTAssertEqual(
            merged.attachments.filter { $0.owner == .suspendedTask(legacySuspendedId) }.count,
            1,
            "an attachment must join the record that owns it, not one that merely listed it"
        )
        XCTAssertEqual(Set(merged.attachments.compactMap(\.data)), [blob, Data("second".utf8)])

        // Store level: each owner sees exactly its own attachments, and no row ends
        // up with two parents — the one mistake a hand-written relationship rebuild
        // would make, and the one `TaskItem.attachments` /
        // `SuspendedTaskItem.attachments` being separate inverse pairs allows.
        let container = try makeContainer(at: canonicalURL)
        let tasks = try container.mainContext.fetch(FetchDescriptor<TaskItem>())
        let context = container.mainContext
        let legacyTask = try XCTUnwrap(tasks.first { $0.id == legacyTaskId })
        XCTAssertEqual(legacyTask.attachments.count, 2)
        let suspended = try context.fetch(FetchDescriptor<SuspendedTaskItem>())
        let legacySuspended = try XCTUnwrap(suspended.first { $0.id == legacySuspendedId })
        XCTAssertEqual(legacySuspended.attachments.count, 1)
        for attachment in try context.fetch(FetchDescriptor<TaskAttachment>()) {
            XCTAssertFalse(attachment.task != nil && attachment.suspendedTask != nil)
            XCTAssertTrue(attachment.task != nil || attachment.suspendedTask != nil)
        }
    }

    func test_retiredLegacyStoreTakesItsSidecarsOutOfTheStoreDirectory() throws {
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, taskTitle: "当前库任务")
        }
        let blob = Data(repeating: 0x41, count: 512_000)
        try populate(legacyURL) { context in
            let task = makeTaskGraph(in: context, taskTitle: "本地任务")
            makeAttachment(data: blob, ownedByTask: task, in: context)
        }
        // Every spelling Core Data has used for an `@Attribute(.externalStorage)`
        // directory: named after the store file or after its extension-stripped base
        // name, hidden or visible. `.Weekyii.local_SUPPORT` is the one
        // `WeekyiiPersistence.supportDirectoryCandidates` looks for. Whether a blob of
        // a given size actually leaves the store file is Core Data's choice, so the
        // candidate list is exercised directly instead of waiting for it to happen.
        let sidecarNames = [
            "Weekyii.local.store_SUPPORT",
            ".Weekyii.local.store_SUPPORT",
            ".Weekyii.local_SUPPORT",
        ]
        for name in sidecarNames {
            let directory = rootURL.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try blob.write(to: directory.appendingPathComponent("blob.bin"))
        }

        let report = try consolidate()

        guard case .movedToArchive(let archiveURL) = report.legacyArchive else {
            XCTFail("expected the legacy store to be archived, got \(report.legacyArchive)")
            return
        }
        XCTAssertEqual(archiveURL.deletingLastPathComponent(), archivesDirectoryURL)
        let movedNames = Set(try FileManager.default.contentsOfDirectory(atPath: archiveURL.path))
        for name in [LegacyStoreConsolidator.legacyStoreFileName] + sidecarNames {
            XCTAssertTrue(movedNames.contains(name), "\(name) was left behind in the store directory")
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: archiveURL.appendingPathComponent("Weekyii.local.store_SUPPORT/blob.bin").path
        ), "a moved directory must keep its contents, not arrive empty")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        for name in sidecarNames {
            XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(name).path))
        }
        // WAL / -shm are deliberately not swept here: in a debug test process the
        // seeding container is still open (see `retainedContainers`), so SQLite may
        // legitimately rewrite those paths after the move.
        XCTAssertEqual(try snapshot(at: canonicalURL).attachments.first?.data, blob)
    }

    // MARK: - FIX 1: a recovery point before either store is first opened

    func test_bothStoresGetARecoveryPointBeforeThisMigrationOpensThem() throws {
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务")
        }
        try populate(legacyURL) { context in
            makeRichGraph(in: context)
        }

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .consolidated)
        XCTAssertEqual(try backupFolders(matching: "pre-consolidation-legacy").count, 1)
        XCTAssertEqual(try backupFolders(matching: "pre-consolidation-canonical").count, 1)
        XCTAssertEqual(Set(report.recoverySnapshots), Set(try backupFolderNames()))
        let backups = rootURL.appendingPathComponent("Backups", isDirectory: true)
        for (folder, storeName) in zip(
            try backupFolders(matching: "pre-consolidation-legacy"),
            [LegacyStoreConsolidator.legacyStoreFileName]
        ) {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: backups.appendingPathComponent(folder, isDirectory: true)
                        .appendingPathComponent(storeName).path
                ),
                "a recovery point that never recorded the store file cannot be the safety net"
            )
        }
    }

    // MARK: - FIX 2: the commit is verified by content, not by identity

    /// The assertion FIX 2 asks for, stated once: the merged plan and the store that
    /// came back out of the commit have **identical per-entity hashes**.
    func test_richGraphCommitsToAStoreThatHashesIdenticallyToThePlan() throws {
        let richTaskId = UUID()
        try populate(canonicalURL) { context in
            makeTaskGraph(
                in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务"
            )
        }
        try populate(legacyURL) { context in
            makeRichGraph(in: context, taskId: richTaskId)
        }
        let plan = try WeekyiiSnapshotMergeService.mergePreferringLocal(
            local: snapshot(at: canonicalURL),
            remote: snapshot(at: legacyURL)
        )

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .consolidated)
        XCTAssertEqual(
            try WeekyiiSnapshotCodec.entityHashes(plan.snapshot),
            try WeekyiiSnapshotCodec.entityHashes(snapshot(at: canonicalURL))
        )
        try XCTAssertEqual(
            WeekyiiSnapshotCodec.snapshotHash(plan.snapshot),
            WeekyiiSnapshotCodec.snapshotHash(snapshot(at: canonicalURL))
        )

        // Field-level spot checks, so a failure names a field instead of only a hash.
        let committed = try snapshot(at: canonicalURL)
        let task = try XCTUnwrap(committed.tasks.first { $0.id == richTaskId })
        XCTAssertEqual(task.title, "带全部字段的任务")
        XCTAssertEqual(task.taskDescription, "不是空描述")
        XCTAssertEqual(task.taskType, .ddl)
        XCTAssertEqual(task.taskTypeIdRaw, "custom.deep")
        XCTAssertEqual(task.order, 5)
        XCTAssertEqual(task.zone, .complete)
        XCTAssertEqual(task.completedOrder, 2)
        XCTAssertEqual(task.steps.map(\.sortOrder), [1, 2, 3], "steps are embedded content, so order is data")
        XCTAssertEqual(Set(task.steps.map(\.createdAt)), [
            makeDate(2026, 10, 13, 9, 6), makeDate(2026, 10, 13, 9, 7), makeDate(2026, 10, 13, 9, 8)
        ])
        XCTAssertEqual(task.dayId, "2026-10-13")
        XCTAssertEqual(task.projectId, committed.projects.first?.id)
        XCTAssertEqual(task.habitId, committed.habits.first?.id)
        XCTAssertEqual(task.attachmentIds.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(committed.attachments.first { $0.owner == .task(richTaskId) }).data,
            Data("附件字节内容".utf8)
        )
        let day = try XCTUnwrap(committed.days.first { $0.dayId == "2026-10-13" })
        XCTAssertEqual(day.killTimeHour, 21)
        XCTAssertEqual(day.killTimeMinute, 45)
        XCTAssertFalse(day.followsDefaultKillTime)
        XCTAssertEqual(day.expiredCount, 4)
        XCTAssertEqual(day.closedAt, makeDate(2026, 10, 13, 22, 5, 45))
        let week = try XCTUnwrap(committed.weeks.first { $0.weekId == "2026-W41" })
        XCTAssertEqual(
            [week.completedTasksCount, week.expiredTasksCount, week.totalStartedDays],
            [3, 2, 1]
        )
        XCTAssertEqual(try XCTUnwrap(committed.habits.first?.scheduleWeekdaysRaw), 0b1010101)
        XCTAssertEqual(try XCTUnwrap(committed.habitDayRecords.first?.completedAt), makeDate(2026, 10, 13, 7, 45, 30))
        XCTAssertEqual(try XCTUnwrap(committed.mindStamps.first?.imageBlob), Data("image-bytes".utf8))
        XCTAssertEqual(try XCTUnwrap(committed.suspendedTasks.first?.snoozeCount), 3)

        let canonicalContainer = try makeContainer(at: canonicalURL)
        let storedHabit = try XCTUnwrap(
            canonicalContainer.mainContext.fetch(FetchDescriptor<HabitModel>()).first
        )
        XCTAssertEqual(storedHabit.generatedThroughDayId, "", "normalized consolidation must leave the V8 compatibility field at its neutral default")
    }

    /// One wrong counter on one record is the shape of "the writer forgot to copy this
    /// field". A key-only check cannot see it; `verifyContent` must.
    func test_verifyContentRejectsARecordWithOneFieldLeftAtItsDefault() throws {
        try populate(legacyURL) { context in
            makeRichGraph(in: context)
        }
        let committed = try snapshot(at: legacyURL)
        XCTAssertFalse(committed.weeks.isEmpty)

        XCTAssertThrowsError(
            try LegacyStoreConsolidator.verifyContent(
                expected: driftedWeek(in: committed),
                committed: committed
            )
        ) { error in
            guard case let LegacyStoreConsolidator.ConsolidationError
                .canonicalContentMismatch(differing, unplanned, expectedHash, committedHash) = error else {
                return XCTFail("expected canonicalContentMismatch, got \(error)")
            }
            XCTAssertEqual(differing, [SyncEntityKey(kind: .week, businessId: "2026-W41")])
            XCTAssertTrue(unplanned.isEmpty)
            XCTAssertNotEqual(expectedHash, committedHash)
        }
    }

    /// And the other direction: a store holding rows the plan never planned is drift,
    /// not success.
    func test_verifyContentRejectsRowsThePlanNeverPlanned() throws {
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务")
        }
        try populate(legacyURL) { context in
            makeRichGraph(in: context)
        }
        let underPlanned = try snapshot(at: canonicalURL)

        let report = try consolidate()

        XCTAssertEqual(report.outcome, .consolidated)
        XCTAssertThrowsError(
            try LegacyStoreConsolidator.verifyContent(
                expected: underPlanned,
                committed: snapshot(at: canonicalURL)
            )
        ) { error in
            guard case let LegacyStoreConsolidator.ConsolidationError
                .canonicalContentMismatch(differing, unplanned, _, _) = error else {
                return XCTFail("expected canonicalContentMismatch, got \(error)")
            }
            XCTAssertTrue(differing.isEmpty, "the pre-existing rows were not changed, so they still agree")
            XCTAssertEqual(Set(unplanned), Set(report.entitiesAdded))
        }
    }

    /// Helper for the two checks above: one field off on one record.
    private func driftedWeek(in snapshot: WeekyiiBusinessSnapshot) throws -> WeekyiiBusinessSnapshot {
        let week = try XCTUnwrap(snapshot.weeks.first)
        return WeekyiiBusinessSnapshot(
            weeks: snapshot.weeks.map { candidate in
                guard candidate.weekId == week.weekId else { return candidate }
                return WeekSnapshot(
                    weekId: candidate.weekId,
                    startDate: candidate.startDate,
                    endDate: candidate.endDate,
                    status: candidate.status,
                    completedTasksCount: candidate.completedTasksCount,
                    expiredTasksCount: candidate.expiredTasksCount + 1,
                    totalStartedDays: candidate.totalStartedDays
                )
            },
            days: snapshot.days,
            tasks: snapshot.tasks,
            suspendedTasks: snapshot.suspendedTasks,
            attachments: snapshot.attachments,
            projects: snapshot.projects,
            mindStamps: snapshot.mindStamps,
            taskTypes: snapshot.taskTypes,
            habits: snapshot.habits,
            habitDayRecords: snapshot.habitDayRecords
        )
    }

    // MARK: - FIX 3: retirement is finished before the latch, and is retry-safe

    // MARK: - FIX 1 (iteration 3): the archive copy is verified by content

    /// The gap this closes: verification compared relative paths and byte counts, so a
    /// copy whose bytes changed under an unchanged length verified as equal. Equal
    /// length is evidence of nothing, and this is the exact function the retirement
    /// state machine calls between copying and deleting.
    func test_copyVerificationRejectsEqualLengthBytes() throws {
        let original = rootURL.appendingPathComponent("original.bin")
        let corrupted = rootURL.appendingPathComponent("corrupted.bin")
        let identicalCopy = rootURL.appendingPathComponent("identical.bin")
        try Data(repeating: 0x41, count: 4096).write(to: original)
        try Data(repeating: 0x42, count: 4096).write(to: corrupted)
        try FileManager.default.copyItem(at: original, to: identicalCopy)

        let originalLength = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: original.path)[.size] as? Int
        )
        let corruptedLength = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: corrupted.path)[.size] as? Int
        )
        XCTAssertEqual(originalLength, corruptedLength, "the corruption under test must keep the byte count")

        XCTAssertNoThrow(
            try LegacyStoreConsolidator.verifyCopy(of: original, matches: identicalCopy, fileManager: .default)
        )
        XCTAssertThrowsError(
            try LegacyStoreConsolidator.verifyCopy(of: original, matches: corrupted, fileManager: .default)
        ) { error in
            guard case LegacyStoreConsolidator.ConsolidationError.legacyRetirementFailed = error else {
                return XCTFail("expected legacyRetirementFailed, got \(error)")
            }
        }
    }

    /// A directory compares by its complete relative-path set as well as by content: a
    /// file the copy never received is a failure, not a smaller directory.
    func test_copyVerificationRejectsADirectoryThatLostOrAlteredAFile() throws {
        let source = rootURL.appendingPathComponent("source-support", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 1024).write(to: source.appendingPathComponent("blob-a.bin"))
        try Data(repeating: 0x42, count: 512).write(to: source.appendingPathComponent("blob-b.bin"))

        let intact = rootURL.appendingPathComponent("intact-support", isDirectory: true)
        try FileManager.default.copyItem(at: source, to: intact)
        XCTAssertNoThrow(try LegacyStoreConsolidator.verifyCopy(of: source, matches: intact, fileManager: .default))

        try FileManager.default.removeItem(at: intact.appendingPathComponent("blob-b.bin"))
        XCTAssertThrowsError(try LegacyStoreConsolidator.verifyCopy(of: source, matches: intact, fileManager: .default))

        let altered = rootURL.appendingPathComponent("altered-support", isDirectory: true)
        try FileManager.default.copyItem(at: source, to: altered)
        try Data(repeating: 0x43, count: 1024).write(to: altered.appendingPathComponent("blob-a.bin"))
        XCTAssertThrowsError(try LegacyStoreConsolidator.verifyCopy(of: source, matches: altered, fileManager: .default))
    }

    // MARK: - FIX 2 (iteration 3): the primary store is the state boundary

    /// Failure at the boundary: the primary store cannot leave its active path. The
    /// marker must not be written and the source must be exactly as it was, including
    /// its sidecars and its bytes.
    func test_primaryRetirementFailureLeavesTheSourceIntactAndTheMarkerUnset() throws {
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务")
        }
        try populate(legacyURL) { context in
            makeRichGraph(in: context)
        }
        let sidecar = rootURL.appendingPathComponent("Weekyii.local.store_SUPPORT", isDirectory: true)
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
        let blob = Data(repeating: 0x5A, count: 2048)
        try blob.write(to: sidecar.appendingPathComponent("blob.bin"))
        let storeBytesBefore = try Data(contentsOf: legacyURL)
        let canonicalBefore = try keys(at: canonicalURL)

        let blockedPath = legacyURL.path
        let primaryRefuses = LegacyStoreConsolidator.RetirementFileSystem(removeItem: { url, fileManager in
            if url.path == blockedPath { throw InjectedFileSystemFault() }
            try fileManager.removeItem(at: url)
        })

        XCTAssertThrowsError(try consolidate(fileSystem: primaryRefuses)) { error in
            guard case LegacyStoreConsolidator.ConsolidationError.legacyRetirementFailed = error else {
                return XCTFail("expected legacyRetirementFailed, got \(error)")
            }
        }

        XCTAssertFalse(markerIsSet, "a marker must never exist while Weekyii.local.store is still active")
        XCTAssertEqual(try Data(contentsOf: legacyURL), storeBytesBefore, "the source is never the casualty")
        XCTAssertEqual(try Data(contentsOf: sidecar.appendingPathComponent("blob.bin")), blob)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: archivesDirectoryURL.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty, "a copy of an intact source is not recovery data, so it must not be kept")

        // The canonical half of the run already committed before retirement. That is the
        // designed add-only retry surface, not a leak.
        XCTAssertTrue(try keys(at: canonicalURL).isSuperset(of: canonicalBefore))

        let retried = try consolidate()

        XCTAssertEqual(retried.outcome, .consolidated)
        XCTAssertTrue(markerIsSet)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(retried.entitiesAdded.isEmpty, "the retry replays an add-only commit")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: archivesDirectoryURL.path).count,
            1,
            "the retry produces one bundle, not a stack of them"
        )
    }

    /// The other side of the boundary: the primary store is already gone, so trouble
    /// with the auxiliary files is a warning. The verified archive holds their bytes,
    /// and the next launch must read the marker — never reopen an incomplete legacy
    /// source to "finish" what is already finished.
    func test_auxiliaryCleanupFailureAfterPrimaryRetirementIsAWarningNotARetry() throws {
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务")
        }
        try populate(legacyURL) { context in
            makeRichGraph(in: context)
        }
        let sidecar = rootURL.appendingPathComponent("Weekyii.local.store_SUPPORT", isDirectory: true)
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
        let blob = Data(repeating: 0x5A, count: 2048)
        try blob.write(to: sidecar.appendingPathComponent("blob.bin"))

        let stubbornPath = sidecar.path
        let sidecarRefuses = LegacyStoreConsolidator.RetirementFileSystem(removeItem: { url, fileManager in
            if url.path == stubbornPath { throw InjectedFileSystemFault() }
            try fileManager.removeItem(at: url)
        })

        let report = try consolidate(fileSystem: sidecarRefuses)

        XCTAssertEqual(report.outcome, .consolidated)
        XCTAssertTrue(markerIsSet)
        XCTAssertEqual(report.retirementWarnings.count, 1, "the leftover is reported, not hidden")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path), "the state boundary was crossed")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sidecar.path),
            "the cleanup really failed — the warning is not decoration"
        )
        guard case .movedToArchive(let archiveURL) = report.legacyArchive else {
            XCTFail("expected the bundle to be archived, got \(report.legacyArchive)")
            return
        }
        XCTAssertEqual(
            try Data(contentsOf: archiveURL.appendingPathComponent("Weekyii.local.store_SUPPORT/blob.bin")),
            blob,
            "the archive was verified before the primary was retired, so its bytes are there"
        )
        let backupCountAfterFirstRun = try backupFolderNames().count

        let second = try consolidate()

        XCTAssertEqual(second.outcome, .alreadyConsolidated)
        XCTAssertTrue(second.recoverySnapshots.isEmpty, "a retired store earns no further pre-open points")
        XCTAssertEqual(try backupFolderNames().count, backupCountAfterFirstRun)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    /// A blocked archive must cost the migration its marker — never its data.
    ///
    /// `LegacyStores/` is replaced by a regular file, so the only thing that can fail
    /// is retirement. The canonical half still lands (it was already verified by
    /// content), the marker stays unset, the legacy store stays where it is, and the
    /// next run finds the records already present and finishes the job without
    /// duplicating anything.
    func test_retirementFailureRefusesTheMarkerAndTheRetryFinishesTheJob() throws {
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "当前库任务")
        }
        try populate(legacyURL) { context in
            makeRichGraph(in: context)
        }
        let canonicalBefore = try keys(at: canonicalURL)
        let legacyKeys = try keys(at: legacyURL)
        // A regular file where the archive root belongs: `createDirectory` fails.
        try Data("not a directory".utf8).write(to: archivesDirectoryURL)

        XCTAssertThrowsError(try consolidate()) { error in
            guard case LegacyStoreConsolidator.ConsolidationError.legacyRetirementFailed = error else {
                return XCTFail("expected legacyRetirementFailed, got \(error)")
            }
        }
        XCTAssertFalse(markerIsSet, "a marker must never exist while Weekyii.local.store is still active")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path), "the source is never the casualty")
        let committedByFailedRun = try snapshot(at: canonicalURL)
        XCTAssertEqual(Set(committedByFailedRun.entityKeys()).subtracting(canonicalBefore), legacyKeys)

        let unblocked = try consolidateAfterUnblockingArchive()

        XCTAssertEqual(unblocked.outcome, .consolidated)
        XCTAssertTrue(markerIsSet)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(
            unblocked.entitiesAdded.isEmpty,
            "the retry replays an add-only commit: nothing new may arrive the second time"
        )
        XCTAssertEqual(
            try WeekyiiSnapshotCodec.entityHashes(snapshot(at: canonicalURL)),
            try WeekyiiSnapshotCodec.entityHashes(committedByFailedRun),
            "and the retry must not disturb what the first run already wrote"
        )
        XCTAssertEqual(
            try snapshot(at: canonicalURL).entityCount,
            canonicalBefore.count + legacyKeys.count
        )
        guard case .movedToArchive(let archiveURL) = unblocked.legacyArchive else {
            XCTFail("expected the retry to retire the legacy store, got \(unblocked.legacyArchive)")
            return
        }
        XCTAssertEqual(archiveURL.deletingLastPathComponent(), archivesDirectoryURL)
        let bundles = try FileManager.default.contentsOfDirectory(atPath: archivesDirectoryURL.path)
        XCTAssertEqual(bundles.count, 1, "a verified copy is reused, not re-stacked on every retry")
        XCTAssertFalse(bundles.contains { $0.hasSuffix(".staging") })
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: archiveURL.appendingPathComponent(LegacyStoreConsolidator.legacyStoreFileName).path
        ))
        XCTAssertEqual(
            try archivesDirectoryURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true,
            "a migration recovery duplicate must not double the user's system backup"
        )
    }

    /// Removes the file that was blocking `LegacyStores/`. Split out so the failed and
    /// successful halves of the case above read as one story.
    private func consolidateAfterUnblockingArchive() throws -> LegacyStoreConsolidator.Report {
        try FileManager.default.removeItem(at: archivesDirectoryURL)
        return try consolidate()
    }

    // MARK: - Rule 6: preferences and account state are untouched

    func test_consolidationLeavesPreferencesAndAppStateAlone() throws {
        let settings = UserSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: "consolidation-\(UUID().uuidString)")))
        let appState = AppState()
        Self.retainedFixtures.append(settings)
        Self.retainedFixtures.append(appState)
        settings.defaultKillTimeHour = 21
        appState.daysStartedCount = 4
        try populate(legacyURL) { context in
            makeTaskGraph(in: context, taskTitle: "本地任务")
            makeHabitGraph(in: context)
        }

        _ = try consolidate()

        XCTAssertEqual(settings.defaultKillTimeHour, 21)
        XCTAssertEqual(appState.daysStartedCount, 4)
        XCTAssertNil(defaults.object(forKey: "cloudSyncEnabled"), "consolidation must not set a sync preference")
    }

    // MARK: - B1b startup wiring

    func test_bootstrapConsolidatesLegacyBeforeOpeningCanonicalContainer() throws {
        try populate(legacyURL) { context in
            makeTaskGraph(in: context, taskTitle: "启动时迁入的本地任务")
        }

        let state = WeekyiiPersistence.bootstrapPersistentContainer(
            storeURL: canonicalURL,
            storeMode: .persistent,
            legacyStoreURL: legacyURL,
            defaults: defaults
        )

        guard case .ready(let container, _) = state else {
            XCTFail("A clean legacy store should be consolidated before local launch")
            return
        }
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<TaskItem>()).contains { $0.title == "启动时迁入的本地任务" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(markerIsSet)
    }

    func test_bootstrapStopsBeforeCanonicalOpenWhenLegacyConsolidationFails() throws {
        let duplicateId = UUID()
        try populate(legacyURL) { context in
            makeTaskGraph(in: context, taskTitle: "重复身份 A", taskId: duplicateId)
            makeTaskGraph(in: context, taskTitle: "重复身份 B", taskId: duplicateId)
        }

        let state = WeekyiiPersistence.bootstrapPersistentContainer(
            storeURL: canonicalURL,
            storeMode: .persistent,
            legacyStoreURL: legacyURL,
            defaults: defaults
        )

        guard case .failed = state else {
            XCTFail("A failed legacy consolidation must stop launch")
            return
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalURL.path), "bootstrap must not open canonical after consolidation fails")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path), "the failed migration source must remain available")
        XCTAssertFalse(markerIsSet, "a failed migration must remain retryable")
    }

    // MARK: - Archive v1 contract

    func test_consolidatedStoreStillWritesAndReadsAnArchiveV1() throws {
        XCTAssertEqual(WeekyiiDataArchiveService.formatIdentifier, "com.fluentdesign.weekyii.archive")
        XCTAssertEqual(WeekyiiDataArchiveService.currentFormatVersion, 1)
        XCTAssertEqual(WeekyiiDataArchiveService.currentSchemaVersion, 8)

        try populate(legacyURL) { context in
            makeTaskGraph(in: context, weekId: "2026-W39", dayId: "2026-09-22", taskTitle: "本地库任务")
            makeHabitGraph(in: context)
        }
        _ = try consolidate()
        let canonicalKeys = try keys(at: canonicalURL)

        let canonical = try makeContainer(at: canonicalURL)
        let settings = UserSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: "consolidation-archive-\(UUID().uuidString)")))
        let appState = AppState()
        Self.retainedFixtures.append(settings)
        Self.retainedFixtures.append(appState)
        let archive = try WeekyiiDataArchiveService.export(
            modelContext: canonical.mainContext,
            settings: settings,
            appState: appState
        )

        let inspection = try WeekyiiDataArchiveService.inspect(archive)
        XCTAssertEqual(inspection.weekCount, 1)
        XCTAssertEqual(inspection.dayCount, 1)
        XCTAssertEqual(inspection.taskCount, 1)
        XCTAssertEqual(inspection.habitCount, 1)

        // The v1 importer is on a consolidated store now: a restore must still
        // reproduce the same business identities.
        let restoredURL = rootURL.appendingPathComponent("Weekyii.restored.store")
        let restored = try makeContainer(at: restoredURL)
        _ = try WeekyiiDataArchiveService.importReplacing(
            archive,
            modelContext: restored.mainContext,
            settings: settings,
            appState: appState,
            storeURL: restoredURL
        )
        XCTAssertEqual(try keys(at: restoredURL), canonicalKeys)
    }

    // MARK: - Rule 10: idempotent

    func test_completionMarkerMakesASecondRunDoNothingEvenWithFreshLegacyData() throws {
        try populate(legacyURL) { context in
            makeTaskGraph(in: context, taskTitle: "第一轮本地任务")
        }
        XCTAssertEqual(try consolidate().outcome, .consolidated)
        let afterFirstRun = try keys(at: canonicalURL)
        let backupsAfterFirstRun = try backupFolderNames()

        // A legacy store reappearing afterwards must not restart the migration.
        try populate(legacyURL) { context in
            makeTaskGraph(in: context, taskTitle: "第二轮本地任务")
        }
        let report = try consolidate()

        XCTAssertEqual(report.outcome, .alreadyConsolidated)
        XCTAssertEqual(report.entitiesAdded, [])
        XCTAssertEqual(report.legacyArchive, .notAttempted)
        XCTAssertEqual(try keys(at: canonicalURL), afterFirstRun)
        XCTAssertTrue(
            try snapshot(at: canonicalURL).tasks.allSatisfy { $0.title != "第二轮本地任务" },
            "the latch is what makes a relaunch not merge again"
        )
        XCTAssertEqual(try backupFolderNames(), backupsAfterFirstRun, "a no-op run must not take new recovery points")
    }

    func test_markerWrittenByOneRunIsSeenByTheNextProcess() throws {
        try populate(legacyURL) { context in
            makeTaskGraph(in: context, taskTitle: "本地任务")
        }
        XCTAssertEqual(try consolidate().outcome, .consolidated)

        // `consolidateIfNeeded` is a static function, so the only thing that can
        // carry across relaunches is the persisted suite — read back here as a new
        // `UserDefaults` instance standing in for a new process.
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let report = try LegacyStoreConsolidator.consolidateIfNeeded(
            canonicalStoreURL: canonicalURL,
            legacyStoreURL: legacyURL,
            now: makeDate(2026, 9, 23),
            defaults: reopened
        )
        XCTAssertEqual(report.outcome, .alreadyConsolidated)
    }

    // MARK: - Rule 8: failure preserves sources and recovery points

    func test_ambiguousCanonicalStoreKeepsRecoveryPointsForBothStores() throws {
        let collided = UUID()
        try populate(canonicalURL) { context in
            makeTaskGraph(in: context, taskTitle: "重复任务甲", taskId: collided)
            makeTaskGraph(in: context, taskTitle: "重复任务乙", taskId: collided)
        }
        try populate(legacyURL) { context in
            makeTaskGraph(in: context, taskTitle: "本地任务")
        }
        let legacyKeys = try keys(at: legacyURL)
        let canonicalKeys = try keysEvenIfAmbiguous(at: canonicalURL)

        do {
            _ = try consolidate()
            XCTFail("an ambiguous canonical store must stop the migration")
        } catch let error as LegacyStoreConsolidator.ConsolidationError {
            guard case .canonicalStoreAmbiguous = error else {
                XCTFail("expected canonicalStoreAmbiguous, got \(error)")
                return
            }
        }

        XCTAssertFalse(markerIsSet)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try keys(at: legacyURL), legacyKeys)
        XCTAssertEqual(try keysEvenIfAmbiguous(at: canonicalURL), canonicalKeys)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archivesDirectoryURL.path))

        let backups = try backupFolderNames()
        XCTAssertEqual(backups.count, 2, "both stores are protected before either is opened for writing")
        XCTAssertTrue(backups.contains { $0.contains("pre-consolidation-legacy") })
        XCTAssertTrue(backups.contains { $0.contains("pre-consolidation-canonical") })
        for name in backups {
            let folder = rootURL
                .appendingPathComponent("Backups", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
            XCTAssertTrue(
                try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasSuffix(".store") },
                "recovery point \(name) holds no store file"
            )
        }
    }

    // MARK: - Path contract

    /// Runtime uses one canonical file. The consolidator alone knows the
    /// historical migration source path.
    func test_storeURLsKeepCanonicalAndLegacyRolesSeparate() {
        XCTAssertEqual(LegacyStoreConsolidator.canonicalStoreURL(), WeekyiiPersistence.persistentStoreURL())
        XCTAssertNotEqual(LegacyStoreConsolidator.canonicalStoreURL(), LegacyStoreConsolidator.legacyStoreURL())
    }
}

/// Stands in for a filesystem failure at one chosen path. Retirement's boundaries are
/// otherwise only reachable by provoking real permission or disk-full failures, which
/// no test can do deterministically.
private struct InjectedFileSystemFault: LocalizedError {
    var errorDescription: String? { "注入的文件系统故障" }
}
