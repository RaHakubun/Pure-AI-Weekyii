import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PendingViewModel {
    private let modelContext: ModelContext
    private let weekCalculator = WeekCalculator()
    private let calendar = Calendar(identifier: .iso8601)

    var pendingWeeks: [WeekModel] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh() {
        let descriptor = FetchDescriptor<WeekModel>()
        pendingWeeks = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status == .pending }
    }

    func weeks(in month: Date) -> [WeekModel] {
        pendingWeeks.filter {
            calendar.isDate($0.startDate, equalTo: month, toGranularity: .month)
        }.sorted { $0.startDate < $1.startDate }
    }

    func createWeek(containing date: Date) {
        let weekId = date.weekId
        guard !weekExists(weekId) else { return }
        let week = weekCalculator.makeWeek(for: date, status: .pending)
        modelContext.insert(week)
        try? modelContext.save()
        refresh()
    }

    func createWeek(weekId: String) {
        guard !weekExists(weekId) else { return }
        guard let startDate = weekStartDate(for: weekId) else { return }
        let week = weekCalculator.makeWeek(weekId: weekId, startDate: startDate, status: .pending)
        modelContext.insert(week)
        try? modelContext.save()
        refresh()
    }

    private func weekExists(_ weekId: String) -> Bool {
        let descriptor = FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })
        return (try? modelContext.fetch(descriptor).first) != nil
    }

    private func weekStartDate(for weekId: String) -> Date? {
        let parts = weekId.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]) else { return nil }
        let weekPart = parts[1].replacingOccurrences(of: "W", with: "")
        guard let week = Int(weekPart) else { return nil }
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 2
        return calendar.date(from: components)
    }
}
