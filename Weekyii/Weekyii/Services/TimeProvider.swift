import Foundation
import Observation

protocol TimeProviding {
    var now: Date { get }
    var today: Date { get }
    var currentWeekId: String { get }
}

@Observable
final class TimeProvider: TimeProviding {
    private let iso8601Calendar = Calendar(identifier: .iso8601)

    var now: Date { Date() }

    var today: Date {
        iso8601Calendar.startOfDay(for: now)
    }

    var currentWeekId: String {
        let week = iso8601Calendar.component(.weekOfYear, from: now)
        let year = iso8601Calendar.component(.yearForWeekOfYear, from: now)
        return String(format: "%04d-W%02d", year, week)
    }
}

final class MockTimeProvider: TimeProviding {
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
