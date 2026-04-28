import XCTest
import SwiftData
@testable import Weekyii

final class StateMachineTests: XCTestCase {
    private var container: ModelContainer!
    private static let sharedViewModelSettings = UserSettings()
    private static var retainedTodayViewModels: [TodayViewModel] = []
    private static var retainedWeekViewModels: [WeekViewModel] = []

    private final class TestAppState: AppStateStore {
        var systemStartDate: Date?
        var lastProcessedDate: Date?
        var lastRolloverAt: Date?
        var runtimeErrorMessage: String?
        var stateTransitionRevision: Int = 0

        func save() {}

        func markProcessed(at date: Date) {
            let calendar = Calendar(identifier: .iso8601)
            lastProcessedDate = calendar.startOfDay(for: date)
            lastRolloverAt = date
        }

        func incrementDaysStarted() {}

        func bumpStateTransitionRevision() {
            stateTransitionRevision += 1
        }
    }

    private struct TestNotificationService: NotificationScheduling {
        func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int, fixedReminder: DateComponents?) {}
        func cancelKillTimeNotification(for day: DayModel) {}
        func scheduleSuspendedTaskNotifications(for task: SuspendedTaskItem) {}
        func cancelSuspendedTaskNotifications(for task: SuspendedTaskItem) {}
    }

    private struct TestSettings: KillTimeSettings {
        var defaultKillTimeHour: Int = 23
        var defaultKillTimeMinute: Int = 45
    }

    @MainActor
    private struct NoopLiveActivityService: LiveActivityManaging {
        func reconcile(
            modelContext: ModelContext,
            now: Date,
            selectedThemeRaw: String,
            appearanceModeRaw: String,
            premiumThemeUnlocked: Bool
        ) {}

        func reconcileImmediately(
            modelContext: ModelContext,
            now: Date,
            selectedThemeRaw: String,
            appearanceModeRaw: String,
            premiumThemeUnlocked: Bool
        ) async {}

        func endAll() {}
    }

    @MainActor
    private final class RecordingLiveActivityService: LiveActivityManaging {
        var immediateReconcileCount: Int = 0
        var onImmediateReconcile: ((Int) -> Void)?

        func reconcile(
            modelContext: ModelContext,
            now: Date,
            selectedThemeRaw: String,
            appearanceModeRaw: String,
            premiumThemeUnlocked: Bool
        ) {}

        func reconcileImmediately(
            modelContext: ModelContext,
            now: Date,
            selectedThemeRaw: String,
            appearanceModeRaw: String,
            premiumThemeUnlocked: Bool
        ) async {
            immediateReconcileCount += 1
            onImmediateReconcile?(immediateReconcileCount)
        }

        func endAll() {}
    }

    private final class MutableTimeProvider: TimeProviding {
        private let iso8601Calendar = Calendar(identifier: .iso8601)
        var mockDate: Date

        init(mockDate: Date) {
            self.mockDate = mockDate
        }

        var now: Date { mockDate }

        var today: Date {
            iso8601Calendar.startOfDay(for: mockDate)
        }

        var currentWeekId: String {
            let week = iso8601Calendar.component(.weekOfYear, from: mockDate)
            let year = iso8601Calendar.component(.yearForWeekOfYear, from: mockDate)
            return String(format: "%04d-W%02d", year, week)
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
            SuspendedTaskItem.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: config)
    }

    @MainActor
    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try Self.makeContainer()
    }

    @MainActor
    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func makeAppState() -> TestAppState {
        TestAppState()
    }

    private func makeSettings(hour: Int = 23, minute: Int = 45) -> TestSettings {
        TestSettings(defaultKillTimeHour: hour, defaultKillTimeMinute: minute)
    }

    private static func retainTodayViewModelForTestLifetime(_ viewModel: TodayViewModel) {
        retainedTodayViewModels.append(viewModel)
    }

    private static func retainWeekViewModelForTestLifetime(_ viewModel: WeekViewModel) {
        retainedWeekViewModels.append(viewModel)
    }

    @MainActor
    func test_crossDay_executeToExpired() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let calendar = Calendar(identifier: .iso8601)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!

        let week = WeekCalculator().makeWeek(for: yesterday, status: .present)
        context.insert(week)

        let day = week.days.first { $0.dayId == yesterday.dayId }!
        day.status = .execute
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "B", order: 2, zone: .frozen))
        try context.save()

        let mockTime = MockTimeProvider(mockDate: Date())
        let machine = StateMachine(modelContainer: container, timeProvider: mockTime, notificationService: .shared, appState: appState, userSettings: makeSettings())
        appState.lastProcessedDate = calendar.startOfDay(for: yesterday)

        machine.processStateTransitions()

        XCTAssertEqual(day.status, .expired)
        XCTAssertEqual(day.expiredCount, 2)
    }

    @MainActor
    func test_stateMachineLifecycle_withoutRun() {
        let _ = StateMachine(
            modelContainer: container,
            timeProvider: MockTimeProvider(mockDate: Date()),
            notificationService: .shared,
            appState: makeAppState(),
            userSettings: makeSettings()
        )
        XCTAssertTrue(true)
    }

    @MainActor
    func test_crossDay_draftToExpired() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let calendar = Calendar(identifier: .iso8601)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!

        let week = WeekCalculator().makeWeek(for: yesterday, status: .present)
        context.insert(week)

        let day = week.days.first { $0.dayId == yesterday.dayId }!
        day.status = .draft
        try context.save()

        let mockTime = MockTimeProvider(mockDate: Date())
        let machine = StateMachine(modelContainer: container, timeProvider: mockTime, notificationService: .shared, appState: appState, userSettings: makeSettings())
        appState.lastProcessedDate = calendar.startOfDay(for: yesterday)

        machine.processStateTransitions()

        XCTAssertEqual(day.status, .expired)
        XCTAssertEqual(day.expiredCount, 0)
    }

    @MainActor
    func test_crossWeek_presentToPast() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let calendar = Calendar(identifier: .iso8601)
        let lastWeekDate = calendar.date(byAdding: .day, value: -7, to: Date())!

        let week = WeekCalculator().makeWeek(for: lastWeekDate, status: .present)
        context.insert(week)
        try context.save()

        let mockTime = MockTimeProvider(mockDate: Date())
        let machine = StateMachine(modelContainer: container, timeProvider: mockTime, notificationService: .shared, appState: appState, userSettings: makeSettings())

        machine.processStateTransitions()

        XCTAssertEqual(week.status, .past)
    }

    @MainActor
    func test_weekViewModel_refresh_promotesCurrentPendingWeekToPresent() throws {
        let context = container.mainContext
        let now = Date()
        let currentWeekId = now.weekId
        let pendingWeek = WeekCalculator().makeWeek(for: now, status: .pending)
        context.insert(pendingWeek)
        try context.save()

        let viewModel = WeekViewModel(modelContext: context, timeProvider: MockTimeProvider(mockDate: now))
        Self.retainWeekViewModelForTestLifetime(viewModel)
        viewModel.refresh()

        let weeks = try context.fetch(FetchDescriptor<WeekModel>())
        XCTAssertEqual(weeks.filter { $0.weekId == currentWeekId }.count, 1)
        XCTAssertEqual(weeks.first { $0.weekId == currentWeekId }?.status, .present)
    }

    @MainActor
    func test_todayViewModel_refresh_promotesCurrentPendingWeekToPresent() throws {
        let context = container.mainContext
        let now = Date()
        let currentWeekId = now.weekId
        let pendingWeek = WeekCalculator().makeWeek(for: now, status: .pending)
        context.insert(pendingWeek)
        try context.save()

        let viewModel = TodayViewModel(
            modelContext: context,
            timeProvider: MockTimeProvider(mockDate: now),
            notificationService: TestNotificationService(),
            appState: makeAppState(),
            userSettings: Self.sharedViewModelSettings
        )
        Self.retainTodayViewModelForTestLifetime(viewModel)
        viewModel.refresh()

        let weeks = try context.fetch(FetchDescriptor<WeekModel>())
        XCTAssertEqual(weeks.filter { $0.weekId == currentWeekId }.count, 1)
        XCTAssertEqual(weeks.first { $0.weekId == currentWeekId }?.status, .present)
    }

    @MainActor
    func test_crossWeek_prefersCurrentPresentWeekWhenDuplicatePresentWeeksExist() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let calendar = Calendar(identifier: .iso8601)
        let today = calendar.startOfDay(for: Date())
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: today)!

        let oldPresentWeek = WeekCalculator().makeWeek(for: lastWeek, status: .present)
        let currentPresentWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(oldPresentWeek)
        context.insert(currentPresentWeek)
        try context.save()

        let mockTime = MockTimeProvider(mockDate: today)
        let machine = StateMachine(modelContainer: container, timeProvider: mockTime, notificationService: .shared, appState: appState, userSettings: makeSettings())

        machine.processStateTransitions()

        XCTAssertEqual(currentPresentWeek.status, .present)
        XCTAssertEqual(oldPresentWeek.status, .past)
    }

    @MainActor
    func test_crossWeek_promotesExistingCurrentPastWeekToPresent() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let today = Date().startOfDay

        let archivedCurrentWeek = WeekCalculator().makeWeek(for: today, status: .past)
        context.insert(archivedCurrentWeek)
        try context.save()

        let mockTime = MockTimeProvider(mockDate: today)
        let machine = StateMachine(modelContainer: container, timeProvider: mockTime, notificationService: .shared, appState: appState, userSettings: makeSettings())

        machine.processStateTransitions()

        XCTAssertEqual(archivedCurrentWeek.status, .present)
        let weeks = (try? context.fetch(FetchDescriptor<WeekModel>())) ?? []
        XCTAssertEqual(weeks.filter { $0.status == .present }.count, 1)
        XCTAssertEqual(weeks.count, 1)
    }

    @MainActor
    func test_killTime_executeToExpired() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let today = Date().startOfDay

        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)

        let day = week.days.first { $0.dayId == today.dayId }!
        day.status = .execute
        day.killTimeHour = 0
        day.killTimeMinute = 0
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .focus))
        try context.save()

        let mockTime = MockTimeProvider(mockDate: Date())
        let machine = StateMachine(modelContainer: container, timeProvider: mockTime, notificationService: .shared, appState: appState, userSettings: makeSettings())
        appState.lastProcessedDate = today

        machine.processStateTransitions()

        XCTAssertEqual(day.status, .expired)
    }

    @MainActor
    func test_killTime_draftToExpiredWithoutStart() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let today = Date().startOfDay

        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)

        let day = week.days.first { $0.dayId == today.dayId }!
        day.status = .draft
        day.killTimeHour = 0
        day.killTimeMinute = 0
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .draft))
        try context.save()

        let mockTime = MockTimeProvider(mockDate: Date())
        let machine = StateMachine(modelContainer: container, timeProvider: mockTime, notificationService: .shared, appState: appState, userSettings: makeSettings())
        appState.lastProcessedDate = today

        machine.processStateTransitions()

        XCTAssertEqual(day.status, .expired)
        XCTAssertEqual(day.expiredCount, 0)
        XCTAssertTrue(day.tasks.isEmpty)
    }

    @MainActor
    func test_staleOpenDayExpirationRefreshesWeekSummaryMetrics() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let calendar = Calendar(identifier: .iso8601)
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let week = WeekCalculator().makeWeek(for: twoDaysAgo, status: .past)
        context.insert(week)

        guard let staleDay = week.days.first(where: { $0.dayId == twoDaysAgo.dayId }) else {
            XCTFail("Failed to create stale day")
            return
        }
        staleDay.status = .execute
        staleDay.tasks.append(TaskItem(title: "A", order: 1, zone: .focus))
        staleDay.tasks.append(TaskItem(title: "B", order: 2, zone: .frozen))
        week.expiredTasksCount = 0
        try context.save()

        let mockTime = MockTimeProvider(mockDate: today)
        let machine = StateMachine(modelContainer: container, timeProvider: mockTime, notificationService: .shared, appState: appState, userSettings: makeSettings())

        machine.processStateTransitions()

        XCTAssertEqual(staleDay.status, .expired)
        XCTAssertEqual(staleDay.expiredCount, 2)
        XCTAssertGreaterThanOrEqual(week.expiredTasksCount, 2)
    }

    @MainActor
    func test_todayRefresh_doesNotOverrideKillTimeWithinSameDay() throws {
        let context = container.mainContext
        let today = Date().startOfDay
        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == today.dayId }) else {
            XCTFail("Failed to resolve today day")
            return
        }
        day.status = .draft
        day.killTimeHour = 20
        day.killTimeMinute = 0
        day.followsDefaultKillTime = true
        try context.save()

        let settings = Self.sharedViewModelSettings
        settings.defaultKillTimeHour = 23
        settings.defaultKillTimeMinute = 45

        let viewModel = TodayViewModel(
            modelContext: context,
            timeProvider: MockTimeProvider(mockDate: today),
            notificationService: TestNotificationService(),
            appState: makeAppState(),
            userSettings: settings
        )
        Self.retainTodayViewModelForTestLifetime(viewModel)
        viewModel.refresh()

        XCTAssertEqual(day.killTimeHour, 20)
        XCTAssertEqual(day.killTimeMinute, 0)
    }

    @MainActor
    func test_todayRefresh_doesNotOverrideCustomizedKillTime() throws {
        let context = container.mainContext
        let today = Date().startOfDay
        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == today.dayId }) else {
            XCTFail("Failed to resolve today day")
            return
        }
        day.status = .draft
        day.killTimeHour = 21
        day.killTimeMinute = 10
        day.followsDefaultKillTime = false
        try context.save()

        let settings = Self.sharedViewModelSettings
        settings.defaultKillTimeHour = 23
        settings.defaultKillTimeMinute = 45

        let viewModel = TodayViewModel(
            modelContext: context,
            timeProvider: MockTimeProvider(mockDate: today),
            notificationService: TestNotificationService(),
            appState: makeAppState(),
            userSettings: settings
        )
        Self.retainTodayViewModelForTestLifetime(viewModel)
        viewModel.refresh()

        XCTAssertEqual(day.killTimeHour, 21)
        XCTAssertEqual(day.killTimeMinute, 10)
    }

    @MainActor
    func test_stateMachine_rolloverSyncsTodayKillTimeFromSettings() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let calendar = Calendar(identifier: .iso8601)
        let now = Date().startOfDay.addingTimeInterval(10 * 60 * 60)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == today.dayId }) else {
            XCTFail("Failed to resolve today day")
            return
        }
        day.status = .empty
        day.killTimeHour = 20
        day.killTimeMinute = 0
        day.followsDefaultKillTime = false
        try context.save()

        let settings = makeSettings(hour: 23, minute: 59)
        appState.lastProcessedDate = yesterday

        let machine = StateMachine(
            modelContainer: container,
            timeProvider: MockTimeProvider(mockDate: now),
            notificationService: .shared,
            appState: appState,
            userSettings: settings
        )

        machine.processStateTransitions()

        XCTAssertEqual(day.killTimeHour, 23)
        XCTAssertEqual(day.killTimeMinute, 59)
        XCTAssertTrue(day.followsDefaultKillTime)
    }

    @MainActor
    func test_stateMachine_sameDayDoesNotResetManuallyAdjustedKillTime() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let calendar = Calendar(identifier: .iso8601)
        let now = Date().startOfDay.addingTimeInterval(10 * 60 * 60)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == today.dayId }) else {
            XCTFail("Failed to resolve today day")
            return
        }
        day.status = .draft
        day.killTimeHour = 20
        day.killTimeMinute = 0
        day.followsDefaultKillTime = false
        try context.save()

        let settings = makeSettings(hour: 23, minute: 59)
        appState.lastProcessedDate = yesterday

        let machine = StateMachine(
            modelContainer: container,
            timeProvider: MockTimeProvider(mockDate: now),
            notificationService: .shared,
            appState: appState,
            userSettings: settings
        )

        machine.processStateTransitions()

        day.killTimeHour = 23
        day.killTimeMinute = 0
        day.followsDefaultKillTime = false
        try context.save()

        machine.processStateTransitions()

        XCTAssertEqual(day.killTimeHour, 23)
        XCTAssertEqual(day.killTimeMinute, 0)
        XCTAssertFalse(day.followsDefaultKillTime)
    }

    @MainActor
    func test_stateMachine_processTransitionsBumpsTransitionRevision() throws {
        let appState = makeAppState()
        let machine = StateMachine(
            modelContainer: container,
            timeProvider: MockTimeProvider(mockDate: Date()),
            notificationService: .shared,
            appState: appState,
            userSettings: makeSettings()
        )

        XCTAssertEqual(appState.stateTransitionRevision, 0)

        machine.processStateTransitions()

        XCTAssertEqual(appState.stateTransitionRevision, 1)
    }

    @MainActor
    func test_todayViewModel_refreshLoadsNewDayAfterCrossDayStateTransition() throws {
        let context = container.mainContext
        let calendar = Calendar(identifier: .iso8601)
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let appState = makeAppState()

        let presentWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(presentWeek)
        guard let todayDay = presentWeek.days.first(where: { $0.dayId == today.dayId }) else {
            XCTFail("Failed to resolve today day")
            return
        }
        todayDay.status = .draft
        try context.save()

        let todayTime = MutableTimeProvider(mockDate: today.addingTimeInterval(10 * 60 * 60))
        let viewModel = TodayViewModel(
            modelContext: context,
            timeProvider: todayTime,
            notificationService: TestNotificationService(),
            appState: appState,
            userSettings: Self.sharedViewModelSettings
        )
        Self.retainTodayViewModelForTestLifetime(viewModel)
        viewModel.refresh()
        XCTAssertEqual(viewModel.today?.dayId, today.dayId)

        let transitionMachine = StateMachine(
            modelContainer: container,
            timeProvider: MockTimeProvider(mockDate: tomorrow.addingTimeInterval(9 * 60 * 60)),
            notificationService: .shared,
            appState: appState,
            userSettings: makeSettings()
        )
        appState.lastProcessedDate = today

        transitionMachine.processStateTransitions()

        todayTime.mockDate = tomorrow.addingTimeInterval(9 * 60 * 60)
        viewModel.refresh()

        XCTAssertEqual(viewModel.today?.dayId, tomorrow.dayId)
    }

    @MainActor
    func test_reconcile_isIdempotentWithinSameMinute() throws {
        let context = container.mainContext
        let appState = makeAppState()
        let now = Date().startOfDay.addingTimeInterval(9 * 60 * 60)
        let week = WeekCalculator().makeWeek(for: now, status: .present)
        context.insert(week)
        try context.save()

        let machine = StateMachine(
            modelContainer: container,
            timeProvider: MockTimeProvider(mockDate: now),
            notificationService: .shared,
            appState: appState,
            userSettings: makeSettings()
        )

        let first = machine.reconcile(now: now, force: false)
        let second = machine.reconcile(now: now.addingTimeInterval(20), force: false)

        XCTAssertFalse(first.skipped)
        XCTAssertTrue(second.skipped)
        XCTAssertEqual(appState.stateTransitionRevision, 1)
    }

    @MainActor
    func test_dataInvariantRepair_normalizesMultipleFocus() throws {
        let context = container.mainContext
        let now = Date().startOfDay.addingTimeInterval(11 * 60 * 60)
        let week = WeekCalculator().makeWeek(for: now, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == now.dayId }) else {
            XCTFail("Failed to build today")
            return
        }
        day.status = .execute
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "B", order: 2, zone: .focus))
        try context.save()

        let report = DataInvariantRepairService(modelContainer: container).repair(referenceDate: now)

        XCTAssertGreaterThanOrEqual(report.repairedFocusCount, 1)
        XCTAssertEqual(day.tasks.filter { $0.zone == .focus }.count, 1)
    }

    @MainActor
    func test_taskMutationService_createPreservesPayloadFields() throws {
        let context = container.mainContext
        let today = Date().startOfDay
        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == today.dayId }) else {
            XCTFail("Missing day")
            return
        }

        let service = TaskMutationService(modelContext: context)
        let payload = TaskDraftPayload(
            title: "Task A",
            description: "Desc",
            type: .ddl,
            steps: [TaskStep(title: "S1"), TaskStep(title: "S2")],
            attachments: [TaskAttachment(data: Data([1, 2]), fileName: "a.txt", fileType: "text/plain")]
        )

        let task = try service.createTask(in: day, payload: payload, zone: .draft, project: nil)
        try context.save()

        XCTAssertEqual(task.title, "Task A")
        XCTAssertEqual(task.taskDescription, "Desc")
        XCTAssertEqual(task.taskType, .ddl)
        XCTAssertEqual(task.steps.count, 2)
        XCTAssertEqual(task.attachments.count, 1)
    }

    @MainActor
    func test_todayActivitySnapshotBuilder_mapsExecuteDay() throws {
        let context = container.mainContext
        let now = Date().startOfDay.addingTimeInterval(10 * 60 * 60)

        let week = WeekCalculator().makeWeek(for: now, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == now.dayId }) else {
            XCTFail("Missing today")
            return
        }
        day.status = .execute
        day.killTimeHour = 23
        day.killTimeMinute = 45
        day.tasks.append(TaskItem(title: "Focus A", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "Frozen B", order: 2, zone: .frozen))
        day.tasks.append(TaskItem(title: "Done C", order: 3, zone: .complete))
        try context.save()

        let snapshot = TodayActivitySnapshotBuilder.build(
            modelContext: context,
            now: now,
            selectedThemeRaw: WeekTheme.amber.rawValue,
            appearanceModeRaw: AppearanceMode.dark.rawValue,
            premiumThemeUnlocked: false
        )

        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.dayId, now.dayId)
        XCTAssertEqual(snapshot?.focusTitle, "Focus A")
        XCTAssertEqual(snapshot?.frozenCount, 1)
        XCTAssertEqual(snapshot?.completedCount, 1)
        XCTAssertEqual(snapshot?.totalCount, 3)
    }

    @MainActor
    func test_todayActivitySnapshotBuilder_returnsNilWhenNotExecuting() throws {
        let context = container.mainContext
        let now = Date().startOfDay.addingTimeInterval(10 * 60 * 60)
        let week = WeekCalculator().makeWeek(for: now, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == now.dayId }) else {
            XCTFail("Missing today")
            return
        }
        day.status = .draft
        day.tasks.append(TaskItem(title: "Draft", order: 1, zone: .draft))
        try context.save()

        let snapshot = TodayActivitySnapshotBuilder.build(
            modelContext: context,
            now: now,
            selectedThemeRaw: WeekTheme.amber.rawValue,
            appearanceModeRaw: AppearanceMode.system.rawValue,
            premiumThemeUnlocked: false
        )

        XCTAssertNil(snapshot)
    }

    @MainActor
    func test_liveActivityAction_parseURL() {
        let parsed = LiveActivityAction.parse(url: LiveActivityAction.postponeFocus.url(days: 2))
        XCTAssertEqual(parsed?.action, .postponeFocus)
        XCTAssertEqual(parsed?.days, 2)
    }

    @MainActor
    func test_liveActivityActionRouter_doneFocusAdvancesExecutionQueue() throws {
        let context = container.mainContext
        let today = Date().startOfDay
        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == today.dayId }) else {
            XCTFail("Missing day")
            return
        }
        day.status = .execute
        day.tasks.append(TaskItem(title: "Focus", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "Frozen", order: 2, zone: .frozen))
        try context.save()

        let appState = AppState()
        let settings = UserSettings()
        LiveActivityActionRouter.handle(
            url: LiveActivityAction.doneFocus.url(),
            modelContext: context,
            appState: appState,
            userSettings: settings,
            notificationService: TestNotificationService(),
            liveActivityService: NoopLiveActivityService()
        )

        XCTAssertEqual(day.completedTasks.count, 1)
        XCTAssertEqual(day.focusTask?.title, "Frozen")
    }

    @MainActor
    func test_liveActivityActionRouter_postponeMovesFocusToTargetDay() throws {
        let context = container.mainContext
        let today = Date().startOfDay
        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == today.dayId }) else {
            XCTFail("Missing day")
            return
        }
        day.status = .execute
        day.tasks.append(TaskItem(title: "Focus", order: 1, zone: .focus))
        try context.save()

        let appState = AppState()
        let settings = UserSettings()
        LiveActivityActionRouter.handle(
            url: LiveActivityAction.postponeFocus.url(days: 1),
            modelContext: context,
            appState: appState,
            userSettings: settings,
            notificationService: TestNotificationService(),
            liveActivityService: NoopLiveActivityService()
        )

        let tomorrowId = today.addingDays(1).dayId
        let tomorrow = try context.fetch(
            FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == tomorrowId })
        ).first

        XCTAssertNotNil(tomorrow)
        XCTAssertEqual(tomorrow?.sortedDraftTasks.first?.title, "Focus")
    }

    @MainActor
    func test_liveActivityActionRouter_postponePerformsCriticalImmediateReconcile() throws {
        let context = container.mainContext
        let today = Date().startOfDay
        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)
        guard let day = week.days.first(where: { $0.dayId == today.dayId }) else {
            XCTFail("Missing day")
            return
        }
        day.status = .execute
        day.tasks.append(TaskItem(title: "Focus", order: 1, zone: .focus))
        try context.save()

        let appState = AppState()
        let settings = UserSettings()
        let service = RecordingLiveActivityService()
        let reconcileExpectation = expectation(description: "immediate reconcile called twice")
        reconcileExpectation.expectedFulfillmentCount = 2
        service.onImmediateReconcile = { _ in
            reconcileExpectation.fulfill()
        }

        LiveActivityActionRouter.handle(
            url: LiveActivityAction.postponeFocus.url(days: 1),
            modelContext: context,
            appState: appState,
            userSettings: settings,
            notificationService: TestNotificationService(),
            liveActivityService: service
        )

        wait(for: [reconcileExpectation], timeout: 2.0)
        XCTAssertGreaterThanOrEqual(service.immediateReconcileCount, 2)
    }

}
