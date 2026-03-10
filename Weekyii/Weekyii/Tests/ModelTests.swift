import XCTest
import SwiftData
@testable import Weekyii

final class ModelTests: XCTestCase {
    @MainActor
    func test_persistentContainer_migratesLegacyProjectTilesStore() throws {
        let storeURL = try makeTemporaryStoreURL()
        let legacySchema = Schema(versionedSchema: WeekyiiSchemaV1.self)
        let legacyConfig = ModelConfiguration("Weekyii", schema: legacySchema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfig)
        let legacyContext = legacyContainer.mainContext

        let older = WeekyiiSchemaV1.ProjectModel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Older",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newer = WeekyiiSchemaV1.ProjectModel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Newer",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        legacyContext.insert(older)
        legacyContext.insert(newer)
        try legacyContext.save()

        let migratedContainer = try WeekyiiPersistence.makeModelContainer(storeURL: storeURL)
        let descriptor = FetchDescriptor<ProjectModel>(sortBy: [SortDescriptor(\ProjectModel.tileOrder)])
        let projects: [ProjectModel] = try migratedContainer.mainContext.fetch(descriptor)

        XCTAssertEqual(projects.map(\.name), ["Newer", "Older"])
        XCTAssertEqual(projects.map(\.tileSize), [ProjectTileSize.medium, ProjectTileSize.medium])
        XCTAssertEqual(projects.map(\.tileOrder), [0, 1])
    }

    func test_projectTileSize_defaultIsMedium() {
        let project = ProjectModel(name: "P", startDate: Date(), endDate: Date())
        XCTAssertEqual(project.tileSize, .medium)
    }

    func test_projectTileOrder_defaultIsZero() {
        let project = ProjectModel(name: "P", startDate: Date(), endDate: Date())
        XCTAssertEqual(project.tileOrder, 0)
    }

    func test_projectTileSize_cycleOrder() {
        XCTAssertEqual(ProjectTileSize.mini.next, .small)
        XCTAssertEqual(ProjectTileSize.small.next, .medium)
        XCTAssertEqual(ProjectTileSize.medium.next, .wide)
        XCTAssertEqual(ProjectTileSize.wide.next, .mini)
    }

    func test_projectTileSize_mapsLegacyStoredValue() {
        XCTAssertEqual(ProjectTileSize(storedValue: "small"), .small)
        XCTAssertEqual(ProjectTileSize(storedValue: "wide"), .wide)
        XCTAssertEqual(ProjectTileSize(storedValue: "large"), .wide)
    }

    func test_projectTilePresentation_miniEditingStaysCompact() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            nextTaskTitle: "下一步"
        )

        let presentation = ProjectTilePresentation(
            snapshot: snapshot,
            size: .mini,
            isEditing: true,
            liveTick: 0
        )

        XCTAssertEqual(presentation.titleLineLimit, 1)
        XCTAssertFalse(presentation.showsStatusChip)
        XCTAssertFalse(presentation.showsNextTaskDate)
        XCTAssertGreaterThan(presentation.contentInsets.trailing, presentation.contentInsets.leading)
    }

    func test_projectTilePresentation_wideCyclesAcrossNextTaskAndProgress() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            nextTaskTitle: "明天交付"
        )

        let first = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 0)
        let second = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 1)

        XCTAssertEqual(Set([first.livePanel, second.livePanel]), Set([.nextTask, .progress]))
        XCTAssertTrue(first.showsStatusChip)
    }

    func test_projectTilePresentation_wideWithoutUpcomingTaskDoesNotUseTaskPanel() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            nextTaskTitle: nil
        )

        let first = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 0)
        let second = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 1)

        XCTAssertEqual(Set([first.livePanel, second.livePanel]), Set([.metrics, .progress]))
    }

    func test_projectTilePresentation_mediumUsesSquareContract() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            nextTaskTitle: "整理材料"
        )

        let presentation = ProjectTilePresentation(
            snapshot: snapshot,
            size: .medium,
            isEditing: true,
            liveTick: 0
        )

        XCTAssertEqual(presentation.titleLineLimit, 2)
        XCTAssertTrue(presentation.showsStatusChip)
        XCTAssertTrue(presentation.showsNextTaskDate)
    }

    func test_taskNumberFormatting() {
        let task = TaskItem(title: "Test", order: 3)
        XCTAssertEqual(task.taskNumber, "T03")
    }

    func test_dayFocusUniqueness() {
        let day = DayModel(dayId: Date().dayId, date: Date())
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "B", order: 2, zone: .focus))
        XCTAssertFalse(day.hasSingleFocus)
    }

    func test_startFlowCoordinator_transitionsFromWarningToRitual() {
        var coordinator = TodayStartFlowCoordinator()
        coordinator.present()
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.step, .warning)

        coordinator.chooseDirectEnter()
        XCTAssertEqual(coordinator.step, .ritual)
    }

    func test_startFlowCoordinator_cancelResetsFlow() {
        var coordinator = TodayStartFlowCoordinator()
        coordinator.present()
        coordinator.chooseDirectEnter()
        coordinator.cancel()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertEqual(coordinator.step, .warning)
    }

    private func makeTemporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("Weekyii.store")
    }

    private func makeTileSnapshot(projectID: UUID, nextTaskTitle: String?) -> ProjectTileSnapshot {
        ProjectTileSnapshot(
            projectID: projectID,
            name: "Project",
            icon: "folder.fill",
            colorHex: "#C46A1A",
            progress: 0.4,
            completedCount: 2,
            totalCount: 5,
            remainingCount: 3,
            expiredCount: 1,
            nextTaskTitle: nextTaskTitle,
            nextTaskDate: nextTaskTitle == nil ? nil : Date(timeIntervalSince1970: 1_762_444_800)
        )
    }
}

@MainActor
final class TaskPostponeServiceTests: XCTestCase {
    private var container: ModelContainer!

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WeekModel.self,
            DayModel.self,
            TaskItem.self,
            TaskStep.self,
            TaskAttachment.self,
            ProjectModel.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: config)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try Self.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    func test_preview_requiresWeekCreationWhenTargetWeekMissing() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft
        let task = TaskItem(title: "Read", order: 1, zone: .draft)
        todayDay.tasks.append(task)
        try context.save()

        let targetDate = today.addingDays(10)
        let preview = try service.preview(taskID: task.id, targetDate: targetDate, today: today)

        XCTAssertTrue(preview.requiresWeekCreation)
        XCTAssertEqual(preview.targetWeekId, targetDate.weekId)
        XCTAssertEqual(preview.targetDayId, targetDate.dayId)
    }

    func test_serviceLifecycle_withoutUsage() throws {
        let context = container.mainContext
        _ = TaskPostponeService(modelContext: context)
    }

    func test_emptySmoke() {
        XCTAssertTrue(true)
    }

    func test_execute_movesDraftTaskToTargetDraftTailAndPreservesMetadata() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 10, 15)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft

        let project = ProjectModel(
            name: "P",
            startDate: today.addingDays(-1),
            endDate: today.addingDays(30)
        )
        context.insert(project)

        let sourceTask = TaskItem(title: "Source", order: 1, zone: .draft)
        sourceTask.steps.append(TaskStep(title: "S1", sortOrder: 0))
        sourceTask.project = project
        sourceTask.startedAt = makeDate(2026, 3, 5, 8, 30)
        sourceTask.endedAt = makeDate(2026, 3, 5, 9, 0)
        sourceTask.completedOrder = 99
        todayDay.tasks.append(sourceTask)

        let targetDate = today.addingDays(1)
        let targetDay = requireDay(in: todayWeek, date: targetDate)
        targetDay.status = .draft
        targetDay.tasks.append(TaskItem(title: "Existing", order: 1, zone: .draft))
        try context.save()

        let preview = try service.preview(taskID: sourceTask.id, targetDate: targetDate, today: today)
        let result = try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)

        XCTAssertFalse(result.createdWeek)
        XCTAssertEqual(result.sourceDayId, today.dayId)
        XCTAssertEqual(result.targetDayId, targetDate.dayId)
        XCTAssertEqual(todayDay.status, .empty)
        XCTAssertTrue(todayDay.tasks.isEmpty)

        let movedTask = targetDay.sortedDraftTasks.last
        XCTAssertNotNil(movedTask)
        XCTAssertEqual(movedTask?.title, "Source")
        XCTAssertEqual(movedTask?.zone, .draft)
        XCTAssertEqual(movedTask?.order, 2)
        XCTAssertEqual(movedTask?.startedAt, nil)
        XCTAssertEqual(movedTask?.endedAt, nil)
        XCTAssertEqual(movedTask?.completedOrder, 0)
        XCTAssertEqual(movedTask?.steps.count, 1)
        XCTAssertEqual(movedTask?.steps.first?.title, "S1")
        XCTAssertTrue(movedTask?.project === project)
    }

    func test_execute_fromFocusPromotesNextFrozenToFocus() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 14, 20)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .execute

        let focus = TaskItem(title: "Focus", order: 1, zone: .focus)
        focus.startedAt = makeDate(2026, 3, 5, 13, 0)
        let frozen = TaskItem(title: "FrozenNext", order: 2, zone: .frozen)
        todayDay.tasks.append(focus)
        todayDay.tasks.append(frozen)

        let targetDate = today.addingDays(1)
        let targetDay = requireDay(in: todayWeek, date: targetDate)
        targetDay.status = .draft
        try context.save()

        let preview = try service.preview(taskID: focus.id, targetDate: targetDate, today: today)
        _ = try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)

        XCTAssertEqual(todayDay.status, .execute)
        XCTAssertTrue(todayDay.focusTask === frozen)
        XCTAssertEqual(todayDay.focusTask?.zone, .focus)
        XCTAssertEqual(todayDay.focusTask?.order, 1)
        XCTAssertEqual(todayDay.focusTask?.startedAt, now)
        XCTAssertTrue(todayDay.frozenTasks.isEmpty)
        XCTAssertTrue(targetDay.sortedDraftTasks.contains(where: { $0.title == "Focus" }))
    }

    func test_execute_fromFrozenRenumbersRemainingExecutionQueue() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 15, 5)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .execute

        let focus = TaskItem(title: "Focus", order: 1, zone: .focus)
        let frozenA = TaskItem(title: "FrozenA", order: 2, zone: .frozen)
        let frozenB = TaskItem(title: "FrozenB", order: 3, zone: .frozen)
        todayDay.tasks.append(focus)
        todayDay.tasks.append(frozenA)
        todayDay.tasks.append(frozenB)

        let targetDate = today.addingDays(1)
        let targetDay = requireDay(in: todayWeek, date: targetDate)
        targetDay.status = .draft
        try context.save()

        let preview = try service.preview(taskID: frozenA.id, targetDate: targetDate, today: today)
        _ = try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)

        XCTAssertEqual(todayDay.status, .execute)
        XCTAssertTrue(todayDay.focusTask === focus)
        XCTAssertEqual(todayDay.focusTask?.order, 1)
        XCTAssertEqual(todayDay.frozenTasks.count, 1)
        XCTAssertTrue(todayDay.frozenTasks.first === frozenB)
        XCTAssertEqual(todayDay.frozenTasks.first?.order, 2)
        XCTAssertTrue(targetDay.sortedDraftTasks.contains(where: { $0.title == "FrozenA" }))
    }

    func test_execute_fromFocusWithoutFrozenMarksSourceCompleted() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 16, 30)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .execute

        let focus = TaskItem(title: "SoloFocus", order: 1, zone: .focus)
        todayDay.tasks.append(focus)

        let targetDate = today.addingDays(1)
        let targetDay = requireDay(in: todayWeek, date: targetDate)
        targetDay.status = .draft
        try context.save()

        let preview = try service.preview(taskID: focus.id, targetDate: targetDate, today: today)
        _ = try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)

        XCTAssertEqual(todayDay.status, .completed)
        XCTAssertEqual(todayDay.closedAt, now)
        XCTAssertNil(todayDay.focusTask)
        XCTAssertTrue(todayDay.frozenTasks.isEmpty)
    }

    func test_execute_implicitlyCreatesTargetDayWhenWeekExistsWithoutDay() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 18, 0)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft
        let sourceTask = TaskItem(title: "MoveMe", order: 1, zone: .draft)
        todayDay.tasks.append(sourceTask)

        let targetDate = today.addingDays(10)
        let targetWeek = WeekCalculator().makeWeek(for: targetDate, status: .pending)
        targetWeek.days.removeAll { $0.dayId == targetDate.dayId }
        context.insert(targetWeek)
        try context.save()

        let preview = try service.preview(taskID: sourceTask.id, targetDate: targetDate, today: today)
        XCTAssertFalse(preview.requiresWeekCreation)

        let result = try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)
        XCTAssertFalse(result.createdWeek)
        let createdTargetDay = targetWeek.days.first(where: { $0.dayId == targetDate.dayId })
        XCTAssertNotNil(createdTargetDay)
        XCTAssertEqual(createdTargetDay?.status, .draft)
        XCTAssertEqual(createdTargetDay?.sortedDraftTasks.count, 1)
        XCTAssertEqual(createdTargetDay?.sortedDraftTasks.first?.title, "MoveMe")
    }

    func test_execute_requiresConfirmationToCreateMissingWeek() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 19, 0)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft
        let sourceTask = TaskItem(title: "MissingWeek", order: 1, zone: .draft)
        todayDay.tasks.append(sourceTask)
        try context.save()

        let targetDate = today.addingDays(14)
        let preview = try service.preview(taskID: sourceTask.id, targetDate: targetDate, today: today)
        XCTAssertTrue(preview.requiresWeekCreation)

        XCTAssertThrowsError(
            try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)
        ) { error in
            guard case WeekyiiError.postponeTargetDayUnavailable = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }

        let result = try service.execute(preview: preview, allowCreateWeek: true, today: today, now: now)
        XCTAssertTrue(result.createdWeek)

        let targetWeekId = preview.targetWeekId
        let createdWeek = try context.fetch(FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == targetWeekId })).first
        XCTAssertEqual(createdWeek?.status, .pending)
        let createdDay = createdWeek?.days.first(where: { $0.dayId == targetDate.dayId })
        XCTAssertEqual(createdDay?.status, .draft)
        XCTAssertEqual(createdDay?.sortedDraftTasks.first?.title, "MissingWeek")
    }

    func test_preview_rejectsCompletedTask() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .completed
        let completedTask = TaskItem(title: "Done", order: 1, zone: .complete)
        todayDay.tasks.append(completedTask)
        try context.save()

        XCTAssertThrowsError(
            try service.preview(taskID: completedTask.id, targetDate: today.addingDays(1), today: today)
        ) { error in
            guard case WeekyiiError.cannotPostponeCompletedTask = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    private func requireDay(in week: WeekModel, date: Date) -> DayModel {
        guard let day = week.days.first(where: { $0.dayId == date.dayId }) else {
            XCTFail("Missing day \(date.dayId)")
            fatalError("Missing day")
        }
        return day
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        guard let date = components.date else {
            fatalError("Invalid date components")
        }
        return date
    }
}
