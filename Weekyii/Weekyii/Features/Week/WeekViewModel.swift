import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class WeekViewModel {
    private let modelContext: ModelContext
    private let timeProvider: TimeProviding
    private let weekCalculator = WeekCalculator()

    var presentWeek: WeekModel?

    init(modelContext: ModelContext, timeProvider: TimeProviding) {
        self.modelContext = modelContext
        self.timeProvider = timeProvider
    }

    func refresh() {
        let descriptor = FetchDescriptor<WeekModel>()
        let weeks = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status == .present }
        if let week = weeks.first {
            presentWeek = week
            return
        }
        let week = weekCalculator.makeWeek(for: timeProvider.today, status: .present)
        modelContext.insert(week)
        presentWeek = week
        try? modelContext.save()
    }
}
