import Foundation
import Observation

@Observable
final class AppState {
    var daysStartedCount: Int = 0
    var systemStartDate: Date?
    var lastProcessedDate: Date?
    var lastRolloverAt: Date?

    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func load() {
        daysStartedCount = defaults.integer(forKey: "daysStartedCount")
        systemStartDate = defaults.object(forKey: "systemStartDate") as? Date
        lastProcessedDate = defaults.object(forKey: "lastProcessedDate") as? Date
        lastRolloverAt = defaults.object(forKey: "lastRolloverAt") as? Date
    }

    func save() {
        defaults.set(daysStartedCount, forKey: "daysStartedCount")
        defaults.set(systemStartDate, forKey: "systemStartDate")
        defaults.set(lastProcessedDate, forKey: "lastProcessedDate")
        defaults.set(lastRolloverAt, forKey: "lastRolloverAt")
    }

    func incrementDaysStarted() {
        daysStartedCount += 1
        save()
    }

    func markProcessed(at date: Date) {
        let calendar = Calendar(identifier: .iso8601)
        lastProcessedDate = calendar.startOfDay(for: date)
        lastRolloverAt = date
        save()
    }
}
