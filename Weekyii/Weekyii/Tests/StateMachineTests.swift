import XCTest
import SwiftData
@testable import Weekyii

final class StateMachineTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([WeekModel.self, DayModel.self, TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    func test_crossDay_executeToExpired() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let calendar = Calendar(identifier: .iso8601)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!

        let week = WeekCalculator().makeWeek(for: yesterday, status: .present)
        context.insert(week)

        let day = week.days.first { $0.dayId == yesterday.dayId }!
        day.status = .execute
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "B", order: 2, zone: .frozen))

        let mockTime = MockTimeProvider(mockDate: Date())
        let machine = StateMachine(modelContext: context, timeProvider: mockTime, notificationService: .shared, appState: appState)
        appState.lastProcessedDate = calendar.startOfDay(for: yesterday)

        machine.processStateTransitions()

        XCTAssertEqual(day.status, .expired)
        XCTAssertEqual(day.expiredCount, 2)
    }

    func test_crossDay_draftToExpired() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let calendar = Calendar(identifier: .iso8601)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!

        let week = WeekCalculator().makeWeek(for: yesterday, status: .present)
        context.insert(week)

        let day = week.days.first { $0.dayId == yesterday.dayId }!
        day.status = .draft

        let mockTime = MockTimeProvider(mockDate: Date())
        let machine = StateMachine(modelContext: context, timeProvider: mockTime, notificationService: .shared, appState: appState)
        appState.lastProcessedDate = calendar.startOfDay(for: yesterday)

        machine.processStateTransitions()

        XCTAssertEqual(day.status, .expired)
        XCTAssertEqual(day.expiredCount, 0)
    }

    func test_crossWeek_presentToPast() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let calendar = Calendar(identifier: .iso8601)
        let lastWeekDate = calendar.date(byAdding: .day, value: -7, to: Date())!

        let week = WeekCalculator().makeWeek(for: lastWeekDate, status: .present)
        context.insert(week)

        let mockTime = MockTimeProvider(mockDate: Date())
        let machine = StateMachine(modelContext: context, timeProvider: mockTime, notificationService: .shared, appState: appState)

        machine.processStateTransitions()

        XCTAssertEqual(week.status, .past)
    }

    func test_killTime_executeToExpired() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let today = Date().startOfDay

        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)

        let day = week.days.first { $0.dayId == today.dayId }!
        day.status = .execute
        day.killTimeHour = 0
        day.killTimeMinute = 0
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .focus))

        let mockTime = MockTimeProvider(mockDate: Date())
        let machine = StateMachine(modelContext: context, timeProvider: mockTime, notificationService: .shared, appState: appState)

        machine.processStateTransitions()

        XCTAssertEqual(day.status, .expired)
    }
}
