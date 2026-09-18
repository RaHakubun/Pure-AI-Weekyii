import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HabitViewModel {
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let appState: any AppStateStore
    @ObservationIgnored private let timeProvider: any TimeProviding
    @ObservationIgnored private let taskMutationService: TaskMutationService
    @ObservationIgnored private let materializer: HabitTaskMaterializer

    var activeHabits: [HabitModel] = []
    var archivedHabits: [HabitModel] = []
    var errorMessage: String?

    init(
        modelContext: ModelContext,
        appState: any AppStateStore,
        timeProvider: any TimeProviding = TimeProvider()
    ) {
        self.modelContext = modelContext
        self.appState = appState
        self.timeProvider = timeProvider
        self.taskMutationService = TaskMutationService(modelContext: modelContext)
        self.materializer = HabitTaskMaterializer(modelContext: modelContext)
    }

    nonisolated deinit {}

    // MARK: - Refresh

    func refresh() {
        errorMessage = nil
        let descriptor = FetchDescriptor<HabitModel>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        let habits = (try? modelContext.fetch(descriptor)) ?? []
        activeHabits = habits.filter(\.isActive)
        archivedHabits = habits.filter { !$0.isActive }
    }

    // MARK: - Create / Update

    @discardableResult
    func createHabit(
        name: String,
        iconName: String = "repeat.circle.fill",
        colorHex: String = "#34C759",
        category: HabitCategory = .health,
        scheduleKind: HabitScheduleKind = .weekly,
        scheduleWeekdays: Set<Int> = [1, 2, 3, 4, 5],
        scheduleMonthDays: Set<Int> = [],
        startDate: Date = Date()
    ) throws -> HabitModel {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw HabitError.nameEmpty }

        let habit = HabitModel(
            name: normalizedName,
            iconName: iconName,
            colorHex: colorHex,
            category: category,
            scheduleKind: scheduleKind,
            scheduleWeekdays: scheduleWeekdays,
            scheduleMonthDays: scheduleMonthDays,
            startDayId: startDate.dayId,
            sortOrder: nextSortOrder()
        )
        guard habit.hasSchedule else { throw HabitError.scheduleEmpty }

        modelContext.insert(habit)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw HabitError.saveFailed
        }
        syncToday()
        appState.bumpStateTransitionRevision()
        refresh()
        return habit
    }

    func updateHabit(
        _ habit: HabitModel,
        name: String,
        iconName: String,
        colorHex: String,
        category: HabitCategory,
        scheduleKind: HabitScheduleKind,
        scheduleWeekdays: Set<Int>,
        scheduleMonthDays: Set<Int>,
        startDate: Date
    ) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw HabitError.nameEmpty }
        let scheduleHasSelection: Bool
        switch scheduleKind {
        case .weekly: scheduleHasSelection = !scheduleWeekdays.isEmpty
        case .monthly: scheduleHasSelection = !scheduleMonthDays.isEmpty
        case .once: scheduleHasSelection = true
        }
        guard scheduleHasSelection else { throw HabitError.scheduleEmpty }

        let previousKindRaw = habit.scheduleKindRaw
        let previousWeekdaysRaw = habit.scheduleWeekdaysRaw
        let previousMonthDaysRaw = habit.scheduleMonthDaysRaw
        let previousStartDayId = habit.startDayId

        habit.name = normalizedName
        habit.iconName = iconName
        habit.colorHex = colorHex
        habit.category = category
        habit.scheduleKind = scheduleKind
        habit.scheduleWeekdays = scheduleWeekdays
        habit.scheduleMonthDays = scheduleMonthDays
        habit.startDayId = startDate.dayId

        let planChanged = previousKindRaw != habit.scheduleKindRaw
            || previousWeekdaysRaw != habit.scheduleWeekdaysRaw
            || previousMonthDaysRaw != habit.scheduleMonthDaysRaw
            || previousStartDayId != habit.startDayId
        if planChanged {
            let yesterdayKey = timeProvider.today.addingDays(-1).dayId
            if habit.generatedThroughDayId >= yesterdayKey {
                habit.generatedThroughDayId = yesterdayKey
            }
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw HabitError.saveFailed
        }
        syncToday()
        appState.bumpStateTransitionRevision()
        refresh()
    }

    // MARK: - Lifecycle Actions

    @discardableResult
    func assignToday(_ habit: HabitModel) throws -> HabitAssignOutcome {
        let outcome = materializer.assignToday(habit: habit, today: timeProvider.today, now: timeProvider.now)
        switch outcome {
        case .created:
            appState.bumpStateTransitionRevision()
            refresh()
        case .failed(let message):
            errorMessage = message
            throw HabitError.saveFailed
        default:
            break
        }
        return outcome
    }

    func setActive(_ habit: HabitModel, _ isActive: Bool) throws {
        habit.isActive = isActive
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw HabitError.saveFailed
        }
        if isActive {
            syncToday()
            appState.bumpStateTransitionRevision()
        }
        refresh()
    }

    func deleteHabit(_ habit: HabitModel) throws {
        let linkedTasks = habit.tasks
        modelContext.delete(habit)

        let affectedDays = linkedTasks.compactMap(\.day)
        for task in linkedTasks {
            guard let day = task.day else { continue }
            guard day.status == .empty || day.status == .draft else {
                task.habit = nil
                continue
            }
            day.tasks.removeAll { $0.id == task.id }
            modelContext.delete(task)
        }
        for day in affectedDays where day.status == .empty || day.status == .draft {
            taskMutationService.normalizeOrder(in: day, zone: .draft)
            if day.status == .draft, day.sortedDraftTasks.isEmpty {
                day.status = .empty
            }
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw HabitError.saveFailed
        }
        appState.bumpStateTransitionRevision()
        refresh()
    }

    // MARK: - Statistics

    func statistics(for habit: HabitModel) -> HabitStatistics {
        HabitStatisticsCalculator.statistics(for: habit, today: timeProvider.today)
    }

    // MARK: - Private Helpers

    private func syncToday() {
        materializer.sync(today: timeProvider.today, now: timeProvider.now)
    }

    private func nextSortOrder() -> Int {
        let descriptor = FetchDescriptor<HabitModel>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        let habits = (try? modelContext.fetch(descriptor)) ?? []
        return (habits.first?.sortOrder ?? -1) + 1
    }
}
