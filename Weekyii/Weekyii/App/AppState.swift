import Foundation
import Combine

final class AppState: ObservableObject, AppStateStore {
    @Published var daysStartedCount: Int = 0
    @Published var dataRevision: Int = 0
    /// Bumped only when the whole business store is replaced or wiped. See
    /// `bumpStructureRevision()`.
    @Published var structureRevision: Int = 0
    @Published var stateTransitionRevision: Int = 0
    @Published var systemStartDate: Date?
    @Published var lastProcessedDate: Date?
    @Published var lastRolloverAt: Date?
    @Published var runtimeErrorMessage: String?

    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func load() {
        daysStartedCount = defaults.integer(forKey: "daysStartedCount")
        dataRevision = defaults.integer(forKey: "dataRevision")
        stateTransitionRevision = defaults.integer(forKey: "stateTransitionRevision")
        systemStartDate = defaults.object(forKey: "systemStartDate") as? Date
        lastProcessedDate = defaults.object(forKey: "lastProcessedDate") as? Date
        lastRolloverAt = defaults.object(forKey: "lastRolloverAt") as? Date
    }

    func save() {
        defaults.set(daysStartedCount, forKey: "daysStartedCount")
        defaults.set(dataRevision, forKey: "dataRevision")
        defaults.set(stateTransitionRevision, forKey: "stateTransitionRevision")
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

    func markRollover(at date: Date) {
        lastRolloverAt = date
        save()
    }

    func reset() {
        daysStartedCount = 0
        dataRevision += 1
        structureRevision += 1
        stateTransitionRevision = 0
        systemStartDate = nil
        lastProcessedDate = nil
        lastRolloverAt = nil
        runtimeErrorMessage = nil
        save()
    }

    func bumpDataRevision() {
        dataRevision += 1
        save()
    }

    /// Bumped only when the whole business store is replaced or wiped (archive
    /// import, factory reset). Views keyed on this are rebuilt, which throws away
    /// every tab's navigation stack — acceptable for a reseed, wrong for a sync.
    /// Deliberately not persisted: it only needs to differ within one launch, and
    /// persisting it would change the archive's AppState record.
    func bumpStructureRevision() {
        structureRevision += 1
    }

    func bumpStateTransitionRevision() {
        stateTransitionRevision += 1
        save()
    }
}
