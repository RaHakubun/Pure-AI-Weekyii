import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PendingViewModel {
    struct WeekSelectionOption: Identifiable {
        let weekId: String
        let startDate: Date
        let endDate: Date
        let isExisting: Bool
        let isPast: Bool

        var id: String { weekId }
    }

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
    func createWeek(containing date: Date) -> WeekModel? {
        let today = calendar.startOfDay(for: Date())
        guard calendar.startOfDay(for: date) >= today else {
            errorMessage = "只能创建今天或未来的周"
            return nil
        }

        let weekId = date.weekId
        guard !weekExists(weekId) else {
            errorMessage = "该周已存在"
            return nil
        }

        let week = weekCalculator.makeWeek(for: date, status: .pending)
        modelContext.insert(week)
        do {
            try modelContext.save()
            refresh()
            return week
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func createWeek(weekId: String) -> WeekModel? {
        let normalizedWeekId = weekId.uppercased()
        guard !weekExists(normalizedWeekId) else {
            errorMessage = "该周已存在"
            return nil
        }
        guard let startDate = weekCalculator.weekStartDate(for: normalizedWeekId) else {
            errorMessage = String(localized: "error.date_format_invalid")
            return nil
        }

        let today = calendar.startOfDay(for: Date())
        guard startDate >= today else {
            errorMessage = "只能创建今天或未来的周"
            return nil
        }

        let week = weekCalculator.makeWeek(weekId: normalizedWeekId, startDate: startDate, status: .pending)
        modelContext.insert(week)
        do {
            try modelContext.save()
            refresh()
            return week
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func day(in week: WeekModel, for date: Date) -> DayModel? {
        let targetDayId = calendar.startOfDay(for: date).dayId
        return week.days.first { $0.dayId == targetDayId }
    }

    func weekOptions(in month: Date) -> [WeekSelectionOption] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let today = calendar.startOfDay(for: Date())

        var options: [WeekSelectionOption] = []
        var cursor = monthStart.startOfWeek

        while cursor < monthEnd {
            let weekStart = cursor
            let weekEnd = weekStart.addingDays(6)
            let weekId = weekStart.weekId
            let exists = weekExists(weekId)
            let isPast = weekEnd < today
            options.append(
                WeekSelectionOption(
                    weekId: weekId,
                    startDate: weekStart,
                    endDate: weekEnd,
                    isExisting: exists,
                    isPast: isPast
                )
            )

            guard let next = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
            cursor = next
        }

        return options
    }

    private func weekExists(_ weekId: String) -> Bool {
        let descriptor = FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })
        return (try? modelContext.fetch(descriptor).first) != nil
    }
}
