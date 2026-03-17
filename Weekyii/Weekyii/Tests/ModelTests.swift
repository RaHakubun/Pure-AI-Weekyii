import XCTest
import SwiftData
import Photos
import SwiftUI
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

    func test_suspendedModulePalette_usesPrimaryThemeTint() {
        for theme in WeekTheme.allCases {
            let palette = theme.suspendedModulePalette
            XCTAssertEqual(palette.tintHex, theme.primaryThemeHex)
        }
    }

    func test_suspendedModulePalette_usesPrimaryThemeGradientLightStop() {
        for theme in WeekTheme.allCases {
            let palette = theme.suspendedModulePalette
            XCTAssertEqual(palette.tintLightHex, theme.primaryThemeLightHex)
        }
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
        XCTAssertFalse(presentation.showsTitle)
        XCTAssertEqual(presentation.secondaryContent, .none)
        XCTAssertGreaterThan(presentation.contentInsets.trailing, presentation.contentInsets.leading)
    }

    func test_projectTilePresentation_miniPrioritizesRemainingCountStory() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            nextTaskTitle: "下一步"
        )

        let presentation = ProjectTilePresentation(snapshot: snapshot, size: .mini, isEditing: false, liveTick: 0)

        XCTAssertEqual(presentation.livePanel, .metrics)
    }

    func test_projectTilePresentation_smallPrioritizesProgressStoryWhenTasksExist() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            nextTaskTitle: "下一步"
        )

        let presentation = ProjectTilePresentation(snapshot: snapshot, size: .small, isEditing: false, liveTick: 0)

        XCTAssertEqual(presentation.livePanel, .progress)
    }

    func test_projectTilePresentation_smallEditingRemovesSecondaryStrip() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
            nextTaskTitle: "下一步"
        )

        let browse = ProjectTilePresentation(snapshot: snapshot, size: .small, isEditing: false, liveTick: 0)
        let edit = ProjectTilePresentation(snapshot: snapshot, size: .small, isEditing: true, liveTick: 0)

        XCTAssertEqual(browse.secondaryContent, .microStatsStrip)
        XCTAssertEqual(edit.secondaryContent, .none)
        XCTAssertTrue(edit.showsTitle)
    }

    func test_projectTilePresentation_wideRemainsStableAcrossLiveTicks() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            nextTaskTitle: "明天交付"
        )

        let first = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 0)
        let second = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 1)

        XCTAssertEqual(first.livePanel, second.livePanel)
        XCTAssertTrue(first.showsStatusChip)
        XCTAssertEqual(first.livePanel, .nextTask)
    }

    func test_projectTilePresentation_wideWithoutUpcomingTaskStaysStableAcrossLiveTicks() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            nextTaskTitle: nil
        )

        let first = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 0)
        let second = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 1)

        XCTAssertEqual(first.livePanel, second.livePanel)
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

        XCTAssertEqual(presentation.titleLineLimit, 1)
        XCTAssertTrue(presentation.showsStatusChip)
        XCTAssertFalse(presentation.showsNextTaskDate)
        XCTAssertEqual(presentation.livePanel, .progress)
        XCTAssertEqual(presentation.secondaryContent, .compactPills)
    }

    func test_projectTilePresentation_mediumBrowseUsesMetricCards() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
            nextTaskTitle: "整理材料"
        )

        let presentation = ProjectTilePresentation(
            snapshot: snapshot,
            size: .medium,
            isEditing: false,
            liveTick: 0
        )

        XCTAssertEqual(presentation.titleLineLimit, 2)
        XCTAssertTrue(presentation.showsNextTaskDate)
        XCTAssertEqual(presentation.secondaryContent, .metricCards)
    }

    func test_projectTilePresentation_wideEditingKeepsTimelineStoryButUsesCompactStrip() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
            nextTaskTitle: "明天交付"
        )

        let presentation = ProjectTilePresentation(
            snapshot: snapshot,
            size: .wide,
            isEditing: true,
            liveTick: 0
        )

        XCTAssertEqual(presentation.livePanel, .nextTask)
        XCTAssertFalse(presentation.showsNextTaskDate)
        XCTAssertEqual(presentation.secondaryContent, .compactPills)
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

    func test_weekOverviewDisplayMode_cycleOrder() {
        XCTAssertEqual(WeekOverviewDisplayMode.cards.next, .strips)
        XCTAssertEqual(WeekOverviewDisplayMode.strips.next, .collapsed)
        XCTAssertEqual(WeekOverviewDisplayMode.collapsed.next, .cards)
    }

    func test_weekOverviewDayStripSummary_prefersFocusTask() {
        let day = DayModel(dayId: "2026-03-15", date: makeDate(2026, 3, 15, 9, 0), status: .execute)
        day.tasks.append(TaskItem(title: "Write outline", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "Backlog follow-up", order: 2, zone: .draft))

        let summary = WeekOverviewDayStripSummary(day: day)

        XCTAssertEqual(summary.highlight, .focus("Write outline"))
    }

    func test_weekOverviewDayStripSummary_fallsBackToDraftTask() {
        let day = DayModel(dayId: "2026-03-16", date: makeDate(2026, 3, 16, 9, 0), status: .draft)
        day.tasks.append(TaskItem(title: "Draft landing copy", order: 2, zone: .draft))
        day.tasks.append(TaskItem(title: "Review assets", order: 1, zone: .draft))

        let summary = WeekOverviewDayStripSummary(day: day)

        XCTAssertEqual(summary.highlight, .draft("Review assets"))
    }

    func test_weekOverviewDayStripSummary_usesCompletedFallbackWhenNoActiveTasks() {
        let day = DayModel(dayId: "2026-03-17", date: makeDate(2026, 3, 17, 9, 0), status: .completed)
        let task = TaskItem(title: "Ship build", order: 1, zone: .complete)
        task.completedOrder = 1
        day.tasks.append(task)

        let summary = WeekOverviewDayStripSummary(day: day)

        XCTAssertEqual(summary.highlight, .completed("1 项已完成"))
    }

    func test_suspendedCountdownPreset_defaults() {
        XCTAssertEqual(SuspendedCountdownPreset.defaultOptions, [1, 2, 3, 5, 7, 10, 30])
    }

    func test_centeredSquareSizing_usesMinDimension() {
        let size = CenteredSquareSizing.squareSide(for: CGSize(width: 390, height: 844), scale: 0.7)
        XCTAssertEqual(size, 273, accuracy: 0.01)
    }

    func test_photoLibraryAccess_canSave_onlyWhenAuthorizedOrLimited() {
        XCTAssertTrue(PhotoLibraryAccess.canSave(status: .authorized))
        XCTAssertTrue(PhotoLibraryAccess.canSave(status: .limited))
        XCTAssertFalse(PhotoLibraryAccess.canSave(status: .denied))
        XCTAssertFalse(PhotoLibraryAccess.canSave(status: .restricted))
        XCTAssertFalse(PhotoLibraryAccess.canSave(status: .notDetermined))
    }

    func test_suspendedTaskMetaFormatter_buildsDeadlineAndCounters() {
        XCTAssertEqual(SuspendedTaskMetaFormatter.deadlineText(remainingDays: 0), "今日到期")
        XCTAssertEqual(SuspendedTaskMetaFormatter.deadlineText(remainingDays: 10), "10 天后到期")
        XCTAssertEqual(SuspendedTaskMetaFormatter.stepsText(count: 3), "3 步骤")
        XCTAssertEqual(SuspendedTaskMetaFormatter.attachmentsText(count: 2), "2 附件")
    }

    func test_arrayMove_ignoresOutOfRangeInputs() {
        var values = ["A", "B", "C"]
        values.move(fromOffsets: IndexSet(integer: 4), toOffset: 10)
        XCTAssertEqual(values, ["A", "B", "C"])

        values.move(fromOffsets: IndexSet(integer: 1), toOffset: -1)
        XCTAssertEqual(values, ["B", "A", "C"])
    }

    func test_widgetSnapshotComposer_buildsPriorityOrderedPreviewAndTheme() {
        let now = makeDate(2026, 3, 16, 9, 30)
        let day = DayModel(dayId: "2026-03-16", date: now, status: .execute)
        day.killTimeHour = 23
        day.killTimeMinute = 45

        day.tasks.append(TaskItem(title: "Focus task", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "Frozen task", order: 2, zone: .frozen))
        day.tasks.append(TaskItem(title: "Draft task", order: 3, zone: .draft))
        let completed = TaskItem(title: "Done task", order: 4, zone: .complete)
        completed.completedOrder = 1
        day.tasks.append(completed)

        let week = WeekModel(
            weekId: now.weekId,
            startDate: now.startOfWeek,
            endDate: now.startOfWeek.addingDays(6),
            status: .present
        )
        week.days = [day]

        let snapshot = WidgetSnapshotComposer.makeSnapshot(
            now: now,
            selectedTheme: WeekTheme.rose,
            appearanceMode: .dark,
            today: day,
            presentWeek: week
        )

        XCTAssertEqual(snapshot.today.totalCount, 4)
        XCTAssertEqual(snapshot.today.completedCount, 1)
        XCTAssertEqual(snapshot.today.completionPercent, 25)
        XCTAssertEqual(snapshot.today.focusTitle, "Focus task")
        XCTAssertEqual(snapshot.today.previewTasks.map(\.title), ["Focus task", "Frozen task", "Draft task"])
        XCTAssertEqual(snapshot.theme.primaryHex, WeekTheme.rose.primaryThemeHex)
        XCTAssertEqual(snapshot.theme.appearanceMode, .dark)
        XCTAssertEqual(snapshot.weekDays.count, 7)
    }

    func test_widgetThemeSnapshot_decodesLegacyPayloadWithoutDarkFields() throws {
        let legacyJSON = """
        {
          "primaryHex":"#111111",
          "primaryLightHex":"#222222",
          "accentHex":"#333333",
          "backgroundHex":"#444444",
          "textPrimaryHex":"#555555",
          "textSecondaryHex":"#666666"
        }
        """

        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(WidgetThemeSnapshot.self, from: data)

        XCTAssertEqual(decoded.darkPrimaryHex, "#111111")
        XCTAssertEqual(decoded.darkBackgroundHex, "#444444")
        XCTAssertEqual(decoded.appearanceMode, .system)
    }

    func test_widgetThemeSnapshot_resolvesPaletteForForcedDarkMode() {
        let theme = WidgetThemeSnapshot(
            primaryHex: "#101010",
            primaryLightHex: "#202020",
            accentHex: "#303030",
            backgroundHex: "#404040",
            textPrimaryHex: "#505050",
            textSecondaryHex: "#606060",
            darkPrimaryHex: "#AAAAAA",
            darkPrimaryLightHex: "#BBBBBB",
            darkAccentHex: "#CCCCCC",
            darkBackgroundHex: "#DDDDDD",
            darkTextPrimaryHex: "#EEEEEE",
            darkTextSecondaryHex: "#FFFFFF",
            appearanceModeRaw: AppearanceMode.dark.rawValue
        )

        let palette = theme.resolvedPalette(isDarkSystem: false)

        XCTAssertEqual(palette.primaryHex, "#AAAAAA")
        XCTAssertEqual(palette.backgroundHex, "#DDDDDD")
    }

    func test_widgetSnapshotStore_roundTrip() throws {
        let snapshot = WidgetSnapshot(
            generatedAt: makeDate(2026, 3, 16, 10, 0),
            theme: .init(primaryHex: "#111111", primaryLightHex: "#222222", accentHex: "#333333", backgroundHex: "#444444", textPrimaryHex: "#555555", textSecondaryHex: "#666666"),
            today: .init(
                dayId: "2026-03-16",
                weekdaySymbol: "Mon",
                statusRaw: DayStatus.execute.rawValue,
                killTimeText: "23:45",
                focusTitle: "Ship widget",
                totalCount: 5,
                completedCount: 2,
                draftCount: 1,
                frozenCount: 2,
                completionPercent: 40,
                previewTasks: [
                    .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!, title: "Ship widget", taskTypeRaw: TaskType.regular.rawValue, zoneRaw: TaskZone.focus.rawValue)
                ]
            ),
            weekDays: []
        )

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let store = WidgetSnapshotStore(directoryURL: dir)
        try store.save(snapshot)
        let loaded = try XCTUnwrap(store.load())

        XCTAssertEqual(loaded, snapshot)
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

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date ?? Date()
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
        let schema = Schema(versionedSchema: WeekyiiSchemaV4.self)
        let config = ModelConfiguration(
            "TaskPostponeServiceTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
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

    @MainActor
    func test_pendingViewModel_addDraftTaskTurnsEmptyDayIntoDraft() throws {
        throw XCTSkip("Temporarily skipped: SwiftData crashes on iOS 26.2 simulator in this unit path; behavior is covered by pending-week UI tests.")
        let context = container.mainContext
        let viewModel = PendingViewModel(modelContext: context)
        let futureDate = makeDate(2026, 3, 20)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        XCTAssertEqual(day.status, .empty)

        try viewModel.addDraftTask(
            to: day,
            title: "Plan review",
            description: "Check milestones",
            type: .ddl,
            steps: [],
            attachments: []
        )
        let draftTasks = day.sortedDraftTasks
        XCTAssertEqual(day.status, .draft)
        XCTAssertEqual(draftTasks.count, 1)
        XCTAssertEqual(draftTasks.first?.title, "Plan review")
        XCTAssertEqual(draftTasks.first?.taskType, .ddl)
    }

    @MainActor
    func test_pendingViewModel_updateDraftTaskRewritesFields() throws {
        throw XCTSkip("Temporarily skipped: SwiftData crashes on iOS 26.2 simulator in this unit path; behavior is covered by pending-week UI tests.")
        let context = container.mainContext
        let viewModel = PendingViewModel(modelContext: context)
        let futureDate = makeDate(2026, 3, 21)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        day.status = .draft
        let task = TaskItem(title: "Old", taskDescription: "Before", taskType: .regular, order: 1, zone: .draft)
        day.tasks.append(task)
        try context.save()

        try viewModel.updateDraftTask(
            task,
            in: day,
            title: "New",
            description: "After",
            type: .leisure,
            steps: [],
            attachments: []
        )

        XCTAssertEqual(task.title, "New")
        XCTAssertEqual(task.taskDescription, "After")
        XCTAssertEqual(task.taskType, .leisure)
    }

    @MainActor
    func test_pendingViewModel_deleteDraftTasksRemovesAndRenumbers() throws {
        throw XCTSkip("Temporarily skipped: SwiftData crashes on iOS 26.2 simulator in this unit path; behavior is covered by pending-week UI tests.")
        let context = container.mainContext
        let viewModel = PendingViewModel(modelContext: context)
        let futureDate = makeDate(2026, 3, 22)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        day.status = .draft
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .draft))
        day.tasks.append(TaskItem(title: "B", order: 2, zone: .draft))
        day.tasks.append(TaskItem(title: "C", order: 3, zone: .draft))
        try context.save()

        try viewModel.deleteDraftTasks(in: day, at: IndexSet(integer: 1))

        let draftTasks = day.sortedDraftTasks
        XCTAssertEqual(draftTasks.map(\.title), ["A", "C"])
        XCTAssertEqual(draftTasks.map(\.order), [1, 2])
    }

    @MainActor
    func test_pendingViewModel_moveDraftTasksReordersDay() throws {
        throw XCTSkip("Temporarily skipped: SwiftData crashes on iOS 26.2 simulator in this unit path; behavior is covered by pending-week UI tests.")
        let context = container.mainContext
        let viewModel = PendingViewModel(modelContext: context)
        let futureDate = makeDate(2026, 3, 23)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        day.status = .draft
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .draft))
        day.tasks.append(TaskItem(title: "B", order: 2, zone: .draft))
        day.tasks.append(TaskItem(title: "C", order: 3, zone: .draft))
        try context.save()

        try viewModel.moveDraftTasks(in: day, from: IndexSet(integer: 2), to: 0)

        let draftTasks = day.sortedDraftTasks
        XCTAssertEqual(draftTasks.map(\.title), ["C", "A", "B"])
        XCTAssertEqual(draftTasks.map(\.order), [1, 2, 3])
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

@MainActor
final class SuspendedTaskLifecycleServiceTests: XCTestCase {
    private var container: ModelContainer!

    private final class TestNotificationService: NotificationScheduling {
        var scheduledTaskIDs: [UUID] = []
        var cancelledTaskIDs: [UUID] = []

        func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int, fixedReminder: DateComponents?) {}
        func cancelKillTimeNotification(for day: DayModel) {}

        func scheduleSuspendedTaskNotifications(for task: SuspendedTaskItem) {
            scheduledTaskIDs.append(task.id)
        }

        func cancelSuspendedTaskNotifications(for task: SuspendedTaskItem) {
            cancelledTaskIDs.append(task.id)
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WeekModel.self,
            DayModel.self,
            TaskItem.self,
            TaskStep.self,
            TaskAttachment.self,
            ProjectModel.self,
            MindStampItem.self,
            SuspendedTaskItem.self,
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

    func test_createSuspendedTaskRequiresCountdownAndSchedulesNotifications() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let now = makeDate(2026, 3, 12, 10, 0)
        let steps = [
            TaskStep(title: "S1", sortOrder: 1),
            TaskStep(title: "S0", sortOrder: 0),
        ]
        let attachments = [
            TaskAttachment(data: Data([0x01, 0x02]), fileName: "note.png", fileType: "image/png")
        ]

        let task = try service.createTask(
            title: "Wait for venue",
            description: "Need a concrete day later.",
            type: .regular,
            countdownDays: 10,
            steps: steps,
            attachments: attachments,
            now: now
        )

        XCTAssertEqual(task.title, "Wait for venue")
        XCTAssertEqual(task.preferredCountdownDays, 10)
        XCTAssertEqual(
            task.steps.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.title),
            ["S0", "S1"]
        )
        XCTAssertEqual(task.attachments.count, 1)
        XCTAssertEqual(task.attachments.first?.fileName, "note.png")
        assertLocalDeadline(task.decisionDeadline, year: 2026, month: 3, day: 22)
        XCTAssertEqual(notifications.scheduledTaskIDs, [task.id])
    }

    func test_extendSuspendedTaskPushesDeadlineAndReschedulesNotifications() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let now = makeDate(2026, 3, 12, 10, 0)

        let task = try service.createTask(
            title: "Explore vendor",
            description: "",
            type: .ddl,
            countdownDays: 10,
            now: now
        )

        notifications.scheduledTaskIDs.removeAll()
        try service.extendTask(task, by: 30, now: now)

        assertLocalDeadline(task.decisionDeadline, year: 2026, month: 4, day: 21)
        XCTAssertEqual(task.snoozeCount, 1)
        XCTAssertEqual(notifications.scheduledTaskIDs, [task.id])
    }

    func test_assignSuspendedTaskAppendsToExistingDraftDayAndDeletesSource() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let today = makeDate(2026, 3, 12)
        let targetDate = makeDate(2026, 3, 14)

        let presentWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(presentWeek)
        let targetDay = requireDay(in: presentWeek, date: targetDate)
        targetDay.status = .draft
        targetDay.tasks.append(TaskItem(title: "Existing", order: 1, zone: .draft))
        let steps = [TaskStep(title: "Step A", sortOrder: 0)]
        let attachments = [TaskAttachment(data: Data([0x0A]), fileName: "proof.jpg", fileType: "image/jpeg")]

        let task = try service.createTask(
            title: "Hold for later",
            description: "Put it on a real day when ready.",
            type: .leisure,
            countdownDays: 10,
            steps: steps,
            attachments: attachments,
            now: today
        )

        try service.assignTask(task, to: targetDate, today: today)

        XCTAssertEqual(targetDay.sortedDraftTasks.map(\.title), ["Existing", "Hold for later"])
        let assigned = targetDay.sortedDraftTasks.last
        XCTAssertEqual(assigned?.steps.map(\.title), ["Step A"])
        XCTAssertEqual(assigned?.attachments.first?.fileName, "proof.jpg")
        XCTAssertEqual(assigned?.attachments.first?.fileType, "image/jpeg")
        let suspended = try context.fetch(FetchDescriptor<SuspendedTaskItem>())
        XCTAssertTrue(suspended.isEmpty)
        XCTAssertEqual(notifications.cancelledTaskIDs, [task.id])
    }

    func test_assignSuspendedTaskCreatesMissingFutureWeekAndDay() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let today = makeDate(2026, 3, 12)
        let targetDate = makeDate(2026, 3, 26)

        let presentWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(presentWeek)

        let task = try service.createTask(
            title: "Decide later",
            description: "",
            type: .regular,
            countdownDays: 30,
            now: today
        )

        try service.assignTask(task, to: targetDate, today: today)

        let weekId = targetDate.weekId
        let targetWeek = try context.fetch(FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })).first
        XCTAssertEqual(targetWeek?.status, .pending)
        let targetDay = targetWeek?.days.first(where: { $0.dayId == targetDate.dayId })
        XCTAssertEqual(targetDay?.status, .draft)
        XCTAssertEqual(targetDay?.sortedDraftTasks.first?.title, "Decide later")
    }

    func test_sweepExpiredSuspendedTasksDeletesExpiredRecordsAndCancelsNotifications() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let now = makeDate(2026, 3, 20, 12, 0)

        let expired = SuspendedTaskItem(
            title: "Expired",
            decisionDeadline: makeDate(2026, 3, 19, 23, 59, 59),
            preferredCountdownDays: 10
        )
        let active = SuspendedTaskItem(
            title: "Active",
            decisionDeadline: makeDate(2026, 3, 25, 23, 59, 59),
            preferredCountdownDays: 10
        )
        context.insert(expired)
        context.insert(active)
        try context.save()

        let deletedCount = try service.sweepExpiredTasks(now: now)
        let remaining = try context.fetch(FetchDescriptor<SuspendedTaskItem>())

        XCTAssertEqual(deletedCount, 1)
        XCTAssertEqual(remaining.map(\.title), ["Active"])
        XCTAssertEqual(notifications.cancelledTaskIDs, [expired.id])
    }

    private func requireDay(in week: WeekModel, date: Date) -> DayModel {
        guard let day = week.days.first(where: { $0.dayId == date.dayId }) else {
            XCTFail("Missing day \(date.dayId)")
            fatalError("Missing day")
        }
        return day
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0, _ second: Int = 0) -> Date {
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

    private func assertLocalDeadline(_ date: Date, year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(components.year, year)
        XCTAssertEqual(components.month, month)
        XCTAssertEqual(components.day, day)
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 59)
        XCTAssertEqual(components.second, 59)
    }
}
