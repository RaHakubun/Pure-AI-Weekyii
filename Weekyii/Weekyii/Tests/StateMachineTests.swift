import XCTest
import SwiftData
@testable import Weekyii

final class StateMachineTests: XCTestCase {
    private var container: ModelContainer!
    private static let sharedViewModelSettings = UserSettings()
    private static var retainedTodayViewModels: [TodayViewModel] = []

    private final class TestAppState: AppStateStore {
        var systemStartDate: Date?
        var lastProcessedDate: Date?
        var lastRolloverAt: Date?
        var runtimeErrorMessage: String?

        func save() {}

        func markProcessed(at date: Date) {
            let calendar = Calendar(identifier: .iso8601)
            lastProcessedDate = calendar.startOfDay(for: date)
            lastRolloverAt = date
        }

        func incrementDaysStarted() {}
    }

    private struct TestNotificationService: NotificationScheduling {
        func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int, fixedReminder: DateComponents?) {}
        func cancelKillTimeNotification(for day: DayModel) {}
    }

    private struct TestSettings: KillTimeSettings {
        var defaultKillTimeHour: Int = 23
        var defaultKillTimeMinute: Int = 45
    }

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

}
