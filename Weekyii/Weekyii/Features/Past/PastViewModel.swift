import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PastViewModel {
    private let modelContext: ModelContext
    private let calendar = Calendar(identifier: .iso8601)

    var pastWeeks: [WeekModel] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh() {
        let descriptor = FetchDescriptor<WeekModel>()
        pastWeeks = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status == .past }
    }

    func weeks(in month: Date) -> [WeekModel] {
        pastWeeks.filter {
            calendar.isDate($0.startDate, equalTo: month, toGranularity: .month)
        }.sorted { $0.startDate < $1.startDate }
    }
}
