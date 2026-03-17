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
        let currentWeekId = timeProvider.currentWeekId
        let descriptor = FetchDescriptor<WeekModel>()
        let allWeeks = (try? modelContext.fetch(descriptor)) ?? []
        let presentWeeks = allWeeks.filter { $0.status == .present }

        if let currentPresent = presentWeeks.first(where: { $0.weekId == currentWeekId }) {
            for extra in presentWeeks where extra.id != currentPresent.id {
                extra.status = .past
            }
            persist { presentWeek = currentPresent }
            return
        }

        if let existingCurrent = allWeeks.first(where: { $0.weekId == currentWeekId }) {
            existingCurrent.status = .present
            for week in presentWeeks where week.id != existingCurrent.id {
                week.status = .past
            }
            persist { presentWeek = existingCurrent }
            return
        }

        for week in presentWeeks {
            week.status = .past
        }
        let week = weekCalculator.makeWeek(for: timeProvider.today, status: .present)
        modelContext.insert(week)
        persist { presentWeek = week }
    }

    private func persist(onSuccess: () -> Void) {
        do {
            try modelContext.save()
            onSuccess()
        } catch {
            errorMessage = error.localizedDescription
            presentWeek = nil
        }
    }

}
