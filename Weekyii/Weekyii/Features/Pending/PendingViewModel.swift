import Foundation
import Observation
import SwiftData

private struct PendingSystemTimeProvider: TimeProviding {
    private let iso8601Calendar = Calendar(identifier: .iso8601)

    var now: Date { Date() }

    var today: Date {
        iso8601Calendar.startOfDay(for: now)
    }

    var currentWeekId: String {
        let week = iso8601Calendar.component(.weekOfYear, from: now)
        let year = iso8601Calendar.component(.yearForWeekOfYear, from: now)
        return String(format: "%04d-W%02d", year, week)
    }
}

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

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let weekCalculator = WeekCalculator()
    @ObservationIgnored private let calendar = Calendar(identifier: .iso8601)
    @ObservationIgnored private let timeProvider: TimeProviding

    var pendingWeeks: [WeekModel] = []
    var errorMessage: String?

    init(modelContext: ModelContext, timeProvider: TimeProviding = PendingSystemTimeProvider()) {
        self.modelContext = modelContext
        self.timeProvider = timeProvider
    }

    func refresh() {
        errorMessage = nil
        let descriptor = FetchDescriptor<WeekModel>()
        pendingWeeks = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.status == .pending }
            .sorted { $0.startDate < $1.startDate }
    }

    func seedPendingWeekForUITestsIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTestingSeedPendingWeek") else { return }

        refresh()
        guard pendingWeeks.isEmpty else { return }

        let seedDate = timeProvider.today.addingDays(7)
        let week = weekCalculator.makeWeek(for: seedDate, status: .pending)
        modelContext.insert(week)

        if let day = day(in: week, for: seedDate) {
            day.status = .draft
            day.tasks.append(TaskItem(title: "Review goals", taskDescription: "Focus on the most important outcome.", taskType: .regular, order: 1, zone: .draft))
            day.tasks.append(TaskItem(title: "Write summary", taskDescription: "Keep it short and concrete.", taskType: .ddl, order: 2, zone: .draft))
        }

        try? modelContext.save()
        refresh()
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
        let today = timeProvider.today
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

        let today = timeProvider.today
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

    /// 查询某月中哪些日期已有任务或非空状态（用于绿点标记）
    func datesWithTasks(in month: Date) -> Set<String> {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        let descriptor = FetchDescriptor<DayModel>()
        let allDays = (try? modelContext.fetch(descriptor)) ?? []

        var result = Set<String>()
        for day in allDays {
            let dayDate = calendar.startOfDay(for: day.date)
            guard dayDate >= monthStart, dayDate < monthEnd else { continue }
            if day.status != .empty || !day.tasks.isEmpty {
                result.insert(day.dayId)
            }
        }
        return result
    }

    /// 查询某月中哪些日期含有 DDL 类型任务（用于火焰图标标记）
    func datesWithDDL(in month: Date) -> Set<String> {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        let descriptor = FetchDescriptor<DayModel>()
        let allDays = (try? modelContext.fetch(descriptor)) ?? []

        var result = Set<String>()
        for day in allDays {
            let dayDate = calendar.startOfDay(for: day.date)
            guard dayDate >= monthStart, dayDate < monthEnd else { continue }
            if day.tasks.contains(where: { $0.taskType == .ddl }) {
                result.insert(day.dayId)
            }
        }
        return result
    }

    func day(in week: WeekModel, for date: Date) -> DayModel? {
        let targetDayId = calendar.startOfDay(for: date).dayId
        return week.days.first { $0.dayId == targetDayId }
    }

    func canEdit(_ day: DayModel) -> Bool {
        let today = timeProvider.today
        let targetDay = calendar.startOfDay(for: day.date)
        return targetDay >= today && (day.status == .empty || day.status == .draft)
    }

    func addDraftTask(
        to day: DayModel,
        title: String,
        description: String,
        type: TaskType,
        steps: [TaskStep],
        attachments: [TaskAttachment]
    ) throws {
        guard canEdit(day) else { throw WeekyiiError.cannotEditStartedDay }
        if day.status == .empty {
            day.status = .draft
        }

        let order = (day.sortedDraftTasks.last?.order ?? 0) + 1
        let task = TaskItem(
            title: title,
            taskDescription: description,
            taskType: type,
            order: order,
            zone: .draft
        )
        appendStepCopies(to: task, from: steps)
        appendAttachmentCopies(to: task, from: attachments)
        day.tasks.append(task)
        try modelContext.save()
    }

    func updateDraftTask(
        _ task: TaskItem,
        in day: DayModel,
        title: String,
        description: String,
        type: TaskType,
        steps: [TaskStep],
        attachments: [TaskAttachment]
    ) throws {
        guard canEdit(day), task.zone == .draft else { throw WeekyiiError.cannotEditStartedDay }
        task.title = title
        task.taskDescription = description
        task.taskType = type
        replaceSteps(for: task, with: steps)
        replaceAttachments(for: task, with: attachments)
        try modelContext.save()
    }

    func deleteDraftTasks(in day: DayModel, at offsets: IndexSet) throws {
        guard canEdit(day) else { throw WeekyiiError.cannotEditStartedDay }
        let tasks = day.sortedDraftTasks
        let tasksToDelete = offsets.compactMap { index in
            tasks.indices.contains(index) ? tasks[index] : nil
        }
        day.tasks.removeAll { task in
            tasksToDelete.contains { $0.id == task.id }
        }
        for task in tasksToDelete {
            modelContext.delete(task)
        }
        renumberDraftTasks(in: day)
        if day.sortedDraftTasks.isEmpty {
            day.status = .empty
        }
        try modelContext.save()
    }

    func moveDraftTasks(in day: DayModel, from source: IndexSet, to destination: Int) throws {
        guard canEdit(day) else { throw WeekyiiError.cannotEditStartedDay }
        let count = day.sortedDraftTasks.count
        let validSource = IndexSet(source.filter { $0 >= 0 && $0 < count })
        guard validSource.isEmpty == false else { return }
        let validDestination = min(max(destination, 0), count)

        var tasks = day.sortedDraftTasks
        tasks.move(fromOffsets: validSource, toOffset: validDestination)
        for (index, task) in tasks.enumerated() {
            task.order = index + 1
        }
        try modelContext.save()
    }

    func weekOptions(in month: Date) -> [WeekSelectionOption] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let today = timeProvider.today

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

    private func renumberDraftTasks(in day: DayModel) {
        for (index, task) in day.sortedDraftTasks.enumerated() {
            task.order = index + 1
        }
    }

    private func replaceSteps(for task: TaskItem, with steps: [TaskStep]) {
        task.steps.forEach { modelContext.delete($0) }
        task.steps.removeAll(keepingCapacity: true)
        appendStepCopies(to: task, from: steps)
    }

    private func replaceAttachments(for task: TaskItem, with attachments: [TaskAttachment]) {
        task.attachments.forEach { modelContext.delete($0) }
        task.attachments.removeAll(keepingCapacity: true)
        appendAttachmentCopies(to: task, from: attachments)
    }

    private func appendStepCopies(to task: TaskItem, from steps: [TaskStep]) {
        for step in normalizedStepCopies(from: steps) {
            task.steps.append(step)
        }
    }

    private func appendAttachmentCopies(to task: TaskItem, from attachments: [TaskAttachment]) {
        for attachment in attachments {
            let copy = TaskAttachment(
                data: attachment.data,
                fileName: attachment.fileName,
                fileType: attachment.fileType
            )
            task.attachments.append(copy)
        }
    }

    private func normalizedStepCopies(from steps: [TaskStep]) -> [TaskStep] {
        steps
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
            .enumerated()
            .map { index, step in
                TaskStep(
                    title: step.title,
                    isCompleted: step.isCompleted,
                    sortOrder: index
                )
            }
    }
}
