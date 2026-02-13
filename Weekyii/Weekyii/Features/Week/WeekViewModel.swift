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
    var errorMessage: String?

    init(modelContext: ModelContext, timeProvider: TimeProviding) {
        self.modelContext = modelContext
        self.timeProvider = timeProvider
    }

    func refresh() {
        errorMessage = nil
        if let week = fetchPresentWeek() {
            presentWeek = week
            return
        }
        let week = weekCalculator.makeWeek(for: timeProvider.today, status: .present)
        modelContext.insert(week)
        do {
            try modelContext.save()
            presentWeek = week
        } catch {
            errorMessage = error.localizedDescription
            presentWeek = nil
        }
    }

    private func fetchPresentWeek() -> WeekModel? {
        let descriptor = FetchDescriptor<WeekModel>()
        return ((try? modelContext.fetch(descriptor)) ?? []).first { $0.status == .present }
    }

}
