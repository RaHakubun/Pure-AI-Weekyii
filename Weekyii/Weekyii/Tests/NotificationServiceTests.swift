import XCTest
@testable import Weekyii

final class NotificationServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .iso8601)

    func test_killTimePlan_includesMorningPreFinalAndDeadline() {
        let service = NotificationService.shared
        let now = makeDate(year: 2026, month: 3, day: 19, hour: 8, minute: 0)
        let input = NotificationService.KillTimeInput(
            dayId: "2026-03-19",
            dayDate: now.startOfDay,
            killTimeHour: 23,
            killTimeMinute: 45,
            unfinishedCount: 2
        )

        let plan = service.killTimeReminderPlan(
            for: input,
            reminderMinutes: 60,
            fixedReminder: DateComponents(hour: 21, minute: 0),
            now: now
        )

        XCTAssertTrue(plan.map(\.identifier).contains("killtime-2026-03-19"))
        XCTAssertTrue(plan.map(\.identifier).contains("morning-reminder-2026-03-19"))
        XCTAssertTrue(plan.map(\.identifier).contains("pre-killtime-2026-03-19"))
        XCTAssertTrue(plan.map(\.identifier).contains("final-killtime-2026-03-19"))
        XCTAssertTrue(plan.map(\.identifier).contains("fixed-reminder-2026-03-19"))
    }

    func test_killTimePlan_dedupesSameMinuteTriggers() {
        let service = NotificationService.shared
        let now = makeDate(year: 2026, month: 3, day: 19, hour: 20, minute: 0)
        let input = NotificationService.KillTimeInput(
            dayId: "2026-03-19",
            dayDate: now.startOfDay,
            killTimeHour: 20,
            killTimeMinute: 30,
            unfinishedCount: 1
        )

        let plan = service.killTimeReminderPlan(
            for: input,
            reminderMinutes: 5,
            fixedReminder: DateComponents(hour: 20, minute: 25),
            now: now
        )

        let uniqueMinuteKeys = Set(plan.map { service.minuteKey(for: $0.fireDate) })
        XCTAssertEqual(uniqueMinuteKeys.count, plan.count)
    }

    func test_suspendedPlan_emitsFourStageReminders() {
        let service = NotificationService.shared
        let now = makeDate(year: 2026, month: 3, day: 10, hour: 8, minute: 0)
        let taskID = UUID(uuidString: "2E4F12B2-A8AE-4D87-8A0D-3D8AC2D0B9CC")!
        let input = NotificationService.SuspendedInput(
            taskID: taskID,
            decisionDeadline: makeDate(year: 2026, month: 3, day: 13, hour: 23, minute: 59)
        )

        let plan = service.suspendedReminderPlan(for: input, now: now)
        XCTAssertEqual(plan.map(\.identifier), [
            "suspended-\(taskID.uuidString)-d3",
            "suspended-\(taskID.uuidString)-d1",
            "suspended-\(taskID.uuidString)-d0m",
            "suspended-\(taskID.uuidString)-d0e"
        ])
    }

    func test_suspendedPlan_keepsOnlyEveningReminderOnDueDayNoon() {
        let service = NotificationService.shared
        let dueDate = makeDate(year: 2026, month: 3, day: 13, hour: 23, minute: 59)
        let now = makeDate(year: 2026, month: 3, day: 13, hour: 12, minute: 0)
        let taskID = UUID(uuidString: "A66CF0F1-2054-43AB-9E7D-4AC1D15BAAD2")!
        let input = NotificationService.SuspendedInput(
            taskID: taskID,
            decisionDeadline: dueDate
        )

        let plan = service.suspendedReminderPlan(for: input, now: now)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.identifier, "suspended-\(taskID.uuidString)-d0e")
    }

    // MARK: - Configurable rhythm

    func test_killTimePlan_usesConfiguredMorningTime() {
        let service = NotificationService.shared
        let now = makeDate(year: 2026, month: 3, day: 19, hour: 6, minute: 0)
        let input = NotificationService.KillTimeInput(
            dayId: "2026-03-19",
            dayDate: now.startOfDay,
            killTimeHour: 23,
            killTimeMinute: 45,
            unfinishedCount: 1
        )
        var configuration = NotificationConfiguration.default
        configuration.morningHour = 7
        configuration.morningMinute = 15

        let plan = service.killTimeReminderPlan(
            for: input,
            reminderMinutes: 0,
            fixedReminder: nil,
            now: now,
            configuration: configuration
        )

        let morning = plan.first { $0.identifier == "morning-reminder-2026-03-19" }
        XCTAssertEqual(morning?.fireDate, makeDate(year: 2026, month: 3, day: 19, hour: 7, minute: 15))
    }

    func test_killTimePlan_usesDefaultMorningTimeWhenUnconfigured() {
        let service = NotificationService.shared
        let now = makeDate(year: 2026, month: 3, day: 19, hour: 6, minute: 0)
        let input = NotificationService.KillTimeInput(
            dayId: "2026-03-19",
            dayDate: now.startOfDay,
            killTimeHour: 23,
            killTimeMinute: 45,
            unfinishedCount: 1
        )

        let plan = service.killTimeReminderPlan(
            for: input,
            reminderMinutes: 0,
            fixedReminder: nil,
            now: now
        )

        let morning = plan.first { $0.identifier == "morning-reminder-2026-03-19" }
        XCTAssertEqual(morning?.fireDate, makeDate(year: 2026, month: 3, day: 19, hour: 9, minute: 0))
    }

    func test_suspendedPlan_emitsNothingWhenRemindersDisabled() {
        let service = NotificationService.shared
        let input = NotificationService.SuspendedInput(
            taskID: UUID(),
            decisionDeadline: makeDate(year: 2026, month: 3, day: 13, hour: 23, minute: 59)
        )
        var configuration = NotificationConfiguration.default
        configuration.suspendedReminderEnabled = false

        let plan = service.suspendedReminderPlan(
            for: input,
            now: makeDate(year: 2026, month: 3, day: 10, hour: 8, minute: 0),
            configuration: configuration
        )

        XCTAssertTrue(plan.isEmpty)
    }

    func test_suspendedPlan_minimalIntensityKeepsOnlyDueDayCheckpoints() {
        let service = NotificationService.shared
        let taskID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let input = NotificationService.SuspendedInput(
            taskID: taskID,
            decisionDeadline: makeDate(year: 2026, month: 3, day: 13, hour: 23, minute: 59)
        )
        var configuration = NotificationConfiguration.default
        configuration.suspendedReminderIntensity = .minimal

        let plan = service.suspendedReminderPlan(
            for: input,
            now: makeDate(year: 2026, month: 3, day: 10, hour: 8, minute: 0),
            configuration: configuration
        )

        XCTAssertEqual(plan.map(\.identifier), [
            "suspended-\(taskID.uuidString)-d0m",
            "suspended-\(taskID.uuidString)-d0e"
        ])
    }

    func test_suspendedPlan_standardIntensityAddsDayBeforeReminder() {
        let service = NotificationService.shared
        let taskID = UUID(uuidString: "66666666-7777-8888-9999-000000000000")!
        let input = NotificationService.SuspendedInput(
            taskID: taskID,
            decisionDeadline: makeDate(year: 2026, month: 3, day: 13, hour: 23, minute: 59)
        )
        var configuration = NotificationConfiguration.default
        configuration.suspendedReminderIntensity = .standard

        let plan = service.suspendedReminderPlan(
            for: input,
            now: makeDate(year: 2026, month: 3, day: 10, hour: 8, minute: 0),
            configuration: configuration
        )

        XCTAssertEqual(plan.map(\.identifier), [
            "suspended-\(taskID.uuidString)-d1",
            "suspended-\(taskID.uuidString)-d0m",
            "suspended-\(taskID.uuidString)-d0e"
        ])
    }

    func test_suspendedPlan_fullIntensityHonoursConfiguredAdvanceDays() {
        let service = NotificationService.shared
        let taskID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let input = NotificationService.SuspendedInput(
            taskID: taskID,
            decisionDeadline: makeDate(year: 2026, month: 3, day: 13, hour: 23, minute: 59)
        )
        var configuration = NotificationConfiguration.default
        configuration.suspendedAdvanceDays = 5

        let plan = service.suspendedReminderPlan(
            for: input,
            now: makeDate(year: 2026, month: 3, day: 5, hour: 8, minute: 0),
            configuration: configuration
        )

        XCTAssertEqual(plan.map(\.identifier), [
            "suspended-\(taskID.uuidString)-d5",
            "suspended-\(taskID.uuidString)-d1",
            "suspended-\(taskID.uuidString)-d0m",
            "suspended-\(taskID.uuidString)-d0e"
        ])
        // Cancellation removes pending requests by identifier, so every emitted
        // identifier must stay inside the task's own namespace.
        XCTAssertTrue(plan.allSatisfy { $0.identifier.hasPrefix("suspended-\(taskID.uuidString)-") })
    }

    func test_suspendedPlan_usesConfiguredEveningTime() {
        let service = NotificationService.shared
        let input = NotificationService.SuspendedInput(
            taskID: UUID(),
            decisionDeadline: makeDate(year: 2026, month: 3, day: 13, hour: 23, minute: 59)
        )
        var configuration = NotificationConfiguration.default
        configuration.suspendedEveningHour = 21
        configuration.suspendedEveningMinute = 45

        let plan = service.suspendedReminderPlan(
            for: input,
            now: makeDate(year: 2026, month: 3, day: 13, hour: 12, minute: 0),
            configuration: configuration
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.fireDate, makeDate(year: 2026, month: 3, day: 13, hour: 21, minute: 45))
    }

    func test_suspendedPlan_dueDayEveningBodyReflectsExpiryPolicy() {
        let service = NotificationService.shared
        let input = NotificationService.SuspendedInput(
            taskID: UUID(),
            decisionDeadline: makeDate(year: 2026, month: 3, day: 13, hour: 23, minute: 59)
        )
        let now = makeDate(year: 2026, month: 3, day: 13, hour: 12, minute: 0)

        func dueDayEveningBody(policy: SuspendedExpiryPolicy) -> String? {
            var configuration = NotificationConfiguration.default
            configuration.suspendedExpiryPolicy = policy
            return service.suspendedReminderPlan(for: input, now: now, configuration: configuration)
                .first { $0.identifier.hasSuffix("-d0e") }?
                .body
        }

        let autoDeleteBody = dueDayEveningBody(policy: .autoDelete)
        let keepOverdueBody = dueDayEveningBody(policy: .keepOverdue)

        XCTAssertNotNil(autoDeleteBody)
        XCTAssertNotNil(keepOverdueBody)
        // The reminder must not promise a deletion that will not happen.
        XCTAssertNotEqual(autoDeleteBody, keepOverdueBody)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }
}

private extension Date {
    var startOfDay: Date {
        Calendar(identifier: .iso8601).startOfDay(for: self)
    }
}
