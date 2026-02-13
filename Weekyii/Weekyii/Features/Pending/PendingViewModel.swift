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
    var errorMessage: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh() {
        errorMessage = nil
        let descriptor = FetchDescriptor<WeekModel>()
        pendingWeeks = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.status == .pending }
            .sorted { $0.startDate < $1.startDate }
    }

    func weeks(in month: Date) -> [WeekModel] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return pendingWeeks.filter {
            $0.startDate < monthEnd && $0.endDate >= monthStart
        }.sorted { $0.startDate < $1.startDate }
    }

    @discardableResult
    func createWeek(containing date: Date) -> Bool {
        let today = calendar.startOfDay(for: Date())
        guard calendar.startOfDay(for: date) >= today else {
            errorMessage = "只能创建今天或未来的周"
            return false
        }

        let weekId = date.weekId
        guard !weekExists(weekId) else {
            errorMessage = "该周已存在"
            return false
        }

        let week = weekCalculator.makeWeek(for: date, status: .pending)
        modelContext.insert(week)
        do {
            try modelContext.save()
            refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createWeek(weekId: String) -> Bool {
        let normalizedWeekId = weekId.uppercased()
        guard !weekExists(normalizedWeekId) else {
            errorMessage = "该周已存在"
            return false
        }
        guard let startDate = weekCalculator.weekStartDate(for: normalizedWeekId) else {
            errorMessage = String(localized: "error.date_format_invalid")
            return false
        }

        let today = calendar.startOfDay(for: Date())
        guard startDate >= today else {
            errorMessage = "只能创建今天或未来的周"
            return false
        }

        let week = weekCalculator.makeWeek(weekId: normalizedWeekId, startDate: startDate, status: .pending)
        modelContext.insert(week)
        do {
            try modelContext.save()
            refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func weekExists(_ weekId: String) -> Bool {
        let descriptor = FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })
        return (try? modelContext.fetch(descriptor).first) != nil
    }
}
