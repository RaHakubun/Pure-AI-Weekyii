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
    enum WeekOutlookTone: String, Equatable {
        case relaxed
        case steady
        case frontLooseBackTight
        case midweekCongestion
        case deadlineRush
        case overloadWarning

        var displayName: String {
            switch self {
            case .relaxed:
                return "轻松推进"
            case .steady:
                return "平稳推进"
            case .frontLooseBackTight:
                return "前松后紧"
            case .midweekCongestion:
                return "周中拥堵"
            case .deadlineRush:
                return "临期冲刺"
            case .overloadWarning:
                return "过载预警"
            }
        }
    }

    struct WeekTypeCounts: Equatable {
        let regular: Int
        let ddl: Int
        let leisure: Int
    }

    struct WeekOutlookSnapshot: Equatable {
        let tone: WeekOutlookTone
        let headline: String
        let advice: String
        let typeCounts: WeekTypeCounts
        let peakDays: [String]
        let dayLoadSeries: [Double]
    }

    struct MonthDaySummary: Equatable {
        let dayId: String
        let regularCount: Int
        let ddlCount: Int
        let leisureCount: Int
        let hasAnyRecord: Bool

        var taskCount: Int {
            regularCount + ddlCount + leisureCount
        }
    }

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
    @ObservationIgnored private let taskMutationService: TaskMutationService

    var pendingWeeks: [WeekModel] = []
    var errorMessage: String?

    init(modelContext: ModelContext, timeProvider: TimeProviding? = nil) {
        self.modelContext = modelContext
        self.timeProvider = timeProvider ?? PendingSystemTimeProvider()
        self.taskMutationService = TaskMutationService(modelContext: modelContext)
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

    func monthDaySummaries(in month: Date) -> [String: MonthDaySummary] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        let descriptor = FetchDescriptor<DayModel>()
        let allDays = (try? modelContext.fetch(descriptor)) ?? []

        var result: [String: MonthDaySummary] = [:]
        for day in allDays {
            let dayDate = calendar.startOfDay(for: day.date)
            guard dayDate >= monthStart, dayDate < monthEnd else { continue }

            let regularCount = day.tasks.filter { $0.taskType == .regular }.count
            let ddlCount = day.tasks.filter { $0.taskType == .ddl }.count
            let leisureCount = day.tasks.filter { $0.taskType == .leisure }.count
            let summary = MonthDaySummary(
                dayId: day.dayId,
                regularCount: regularCount,
                ddlCount: ddlCount,
                leisureCount: leisureCount,
                hasAnyRecord: day.status != .empty || (regularCount + ddlCount + leisureCount) > 0
            )
            result[day.dayId] = summary
        }

        return result
    }

    /// 查询某月中哪些日期已有任务或非空状态（用于绿点标记）
    func datesWithTasks(in month: Date) -> Set<String> {
        Set(monthDaySummaries(in: month).values.filter { $0.hasAnyRecord }.map(\.dayId))
    }

    /// 查询某月中哪些日期含有 DDL 类型任务（用于火焰图标标记）
    func datesWithDDL(in month: Date) -> Set<String> {
        Set(monthDaySummaries(in: month).values.filter { $0.ddlCount > 0 }.map(\.dayId))
    }

    func weekOutlook(for week: WeekModel) -> WeekOutlookSnapshot {
        Self.buildWeekOutlook(for: week)
    }

    static func buildWeekOutlook(for week: WeekModel) -> WeekOutlookSnapshot {
        let calendar = Calendar(identifier: .iso8601)
        let start = calendar.startOfDay(for: week.startDate)
        let dayMap = Dictionary(
            week.days.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var regularSeries: [Int] = []
        var ddlSeries: [Int] = []
        var leisureSeries: [Int] = []
        var dayLabels: [String] = []

        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = dayMap[date]
            let tasks = day?.tasks ?? []
            regularSeries.append(tasks.filter { $0.taskType == .regular }.count)
            ddlSeries.append(tasks.filter { $0.taskType == .ddl }.count)
            leisureSeries.append(tasks.filter { $0.taskType == .leisure }.count)
            dayLabels.append(Self.weekdayLabel(for: date))
        }

        let dayLoadSeries = zip(regularSeries, zip(ddlSeries, leisureSeries)).map { regular, tuple in
            let (ddl, leisure) = tuple
            return Double(regular) + Double(ddl) * 2.0 + Double(leisure) * 0.6
        }

        let totalRegular = regularSeries.reduce(0, +)
        let totalDDL = ddlSeries.reduce(0, +)
        let totalLeisure = leisureSeries.reduce(0, +)
        let totalLoad = dayLoadSeries.reduce(0, +)
        let peakLoad = dayLoadSeries.max() ?? 0
        let activeDays = dayLoadSeries.filter { $0 > 0 }.count

        let maxPairDDL: Int = ddlSeries.count >= 2
            ? (0..<(ddlSeries.count - 1)).map { ddlSeries[$0] + ddlSeries[$0 + 1] }.max() ?? 0
            : (ddlSeries.first ?? 0)
        let ddlClusterRatio = totalDDL > 0 ? Double(maxPairDDL) / Double(totalDDL) : 0

        let midweekLoad = dayLoadSeries.enumerated()
            .filter { [2, 3, 4].contains($0.offset) }
            .map(\.element)
            .reduce(0, +)
        let midweekShare = totalLoad > 0 ? midweekLoad / totalLoad : 0

        let frontLoad = dayLoadSeries.prefix(3).reduce(0, +)
        let backLoad = dayLoadSeries.suffix(4).reduce(0, +)
        let backVsFrontGapRatio = frontLoad > 0 ? (backLoad - frontLoad) / frontLoad : 0

        let peakDayIndexes = dayLoadSeries.enumerated()
            .filter { $0.element > 0 && $0.element == peakLoad }
            .map(\.offset)
            .prefix(2)
        let peakDays = peakDayIndexes.map { dayLabels[$0] }
        let peakDaysText = peakDays.isEmpty ? "节奏分布较均匀" : "高压在" + peakDays.joined(separator: "/")

        let tone: WeekOutlookTone
        if peakLoad >= 8 || totalLoad >= 28 {
            tone = .overloadWarning
        } else if totalDDL >= 4 && ddlClusterRatio >= 0.6 {
            tone = .deadlineRush
        } else if midweekShare >= 0.6 {
            tone = .midweekCongestion
        } else if backLoad > frontLoad && backVsFrontGapRatio >= 0.3 {
            tone = .frontLooseBackTight
        } else if totalLoad <= 6 && totalDDL <= 1 {
            tone = .relaxed
        } else {
            tone = .steady
        }

        let headline: String
        let advice: String
        switch tone {
        case .relaxed:
            headline = activeDays == 0
                ? "这一周任务较空，适合先定一个主目标"
                : "整体负载偏轻，按节奏推进即可"
            advice = "保持节奏并留1天机动"
        case .steady:
            headline = peakDays.isEmpty ? "节奏平稳，可按日常推进" : "\(peakDaysText)，整体可控"
            advice = "每天推进1-2个关键项"
        case .frontLooseBackTight:
            headline = "后半周会明显变紧，建议提前启动关键事项"
            advice = "周一周二先清关键任务"
        case .midweekCongestion:
            headline = "周中任务明显聚集，\(peakDaysText)"
            advice = "把周中任务前移一天"
        case .deadlineRush:
            headline = "DDL集中出现，\(peakDaysText)"
            advice = "先做DDL，再推进常规"
        case .overloadWarning:
            headline = "本周负载偏高，\(peakDaysText)"
            advice = "建议拆分或减载安排"
        }

        return WeekOutlookSnapshot(
            tone: tone,
            headline: headline,
            advice: advice,
            typeCounts: WeekTypeCounts(regular: totalRegular, ddl: totalDDL, leisure: totalLeisure),
            peakDays: peakDays,
            dayLoadSeries: dayLoadSeries
        )
    }

    func day(in week: WeekModel, for date: Date) -> DayModel? {
        let targetDayId = calendar.startOfDay(for: date).dayId
        return week.days.first { $0.dayId == targetDayId }
    }

    func dayRecord(on date: Date) -> DayModel? {
        fetchDay(by: calendar.startOfDay(for: date).dayId)
    }

    func resolveEditableDayForMonthAdd(on date: Date) -> DayModel? {
        let targetDate = calendar.startOfDay(for: date)
        let today = timeProvider.today
        guard targetDate >= today else {
            errorMessage = "过去日期不可添加任务"
            return nil
        }

        if let existing = fetchDay(by: targetDate.dayId) {
            guard canEdit(existing) else {
                errorMessage = "该日期任务流不可编辑"
                return nil
            }
            return existing
        }

        let week = fetchWeek(by: targetDate.weekId) ?? createWeek(containing: targetDate)
        guard let week else {
            errorMessage = errorMessage ?? String(localized: "error.operation_failed_retry")
            return nil
        }

        guard let day = day(in: week, for: targetDate) else {
            errorMessage = String(localized: "error.operation_failed_retry")
            return nil
        }
        guard canEdit(day) else {
            errorMessage = "该日期任务流不可编辑"
            return nil
        }
        return day
    }

    func tasksForDisplay(in day: DayModel) -> [TaskItem] {
        day.tasks.sorted { lhs, rhs in
            if lhs.zone == rhs.zone {
                if lhs.zone == .complete {
                    return lhs.completedOrder < rhs.completedOrder
                }
                return lhs.order < rhs.order
            }
            return zonePriority(lhs.zone) < zonePriority(rhs.zone)
        }
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
        let payload = TaskDraftPayload(
            title: title,
            description: description,
            type: type,
            steps: steps,
            attachments: attachments
        )
        _ = try taskMutationService.createTask(in: day, payload: payload, zone: .draft, project: nil)
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
        let payload = TaskDraftPayload(
            title: title,
            description: description,
            type: type,
            steps: steps,
            attachments: attachments
        )
        try taskMutationService.updateTask(task, payload: payload)
        try modelContext.save()
    }

    func deleteDraftTasks(in day: DayModel, at offsets: IndexSet) throws {
        guard canEdit(day) else { throw WeekyiiError.cannotEditStartedDay }
        _ = try taskMutationService.deleteDraftTasks(in: day, at: offsets)
        try modelContext.save()
    }

    func moveDraftTasks(in day: DayModel, from source: IndexSet, to destination: Int) throws {
        guard canEdit(day) else { throw WeekyiiError.cannotEditStartedDay }
        try taskMutationService.moveDraftTasks(in: day, from: source, to: destination)
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

    private func fetchWeek(by weekId: String) -> WeekModel? {
        let descriptor = FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchDay(by dayId: String) -> DayModel? {
        let descriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == dayId })
        return try? modelContext.fetch(descriptor).first
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

    private func zonePriority(_ zone: TaskZone) -> Int {
        switch zone {
        case .draft: return 0
        case .focus: return 1
        case .frozen: return 2
        case .complete: return 3
        }
    }

    private static func weekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}
