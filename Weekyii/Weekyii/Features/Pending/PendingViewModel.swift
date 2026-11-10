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
                return String(localized: "pending.week.outlook.tone.relaxed", defaultValue: "轻松推进")
            case .steady:
                return String(localized: "pending.week.outlook.tone.steady", defaultValue: "平稳推进")
            case .frontLooseBackTight:
                return String(localized: "pending.week.outlook.tone.frontLooseBackTight", defaultValue: "前松后紧")
            case .midweekCongestion:
                return String(localized: "pending.week.outlook.tone.midweekCongestion", defaultValue: "周中拥堵")
            case .deadlineRush:
                return String(localized: "pending.week.outlook.tone.deadlineRush", defaultValue: "临期冲刺")
            case .overloadWarning:
                return String(localized: "pending.week.outlook.tone.overloadWarning", defaultValue: "过载预警")
            }
        }
    }

    struct WeekTypeCounts: Equatable {
        let regular: Int
        let ddl: Int
        let leisure: Int
    }

    /// One day of the week card's distribution strip. Plain task counts, so
    /// every number the card shows can be checked against the week detail.
    struct WeekOutlookDay: Equatable {
        let date: Date
        let taskCount: Int
        let deadlineCount: Int
    }

    /// A task worth preparing ahead, shown on the week card without opening it.
    struct WeekOutlookKeyTask: Equatable, Identifiable {
        enum Reason: Equatable {
            /// A DDL task. `typeName` is set for custom DDL-based task types.
            case deadline(typeName: String?)
            /// The task's project ends within this week.
            case projectDue
            /// Part of a project that ends later.
            case project(name: String)
            /// A task broken into several steps.
            case steps(Int)
        }

        let id: UUID
        let title: String
        let date: Date
        let baseKind: TaskType
        let reason: Reason
    }

    /// One concrete, data-backed suggestion. Day values are indexes into
    /// `WeekOutlookSnapshot.days` (0 = Monday).
    enum WeekOutlookHint: Equatable {
        case noTasks
        /// DDL concentrate on `deadlineDays`, and an earlier day is at most half as full.
        case startDeadlinesEarly(deadlineDays: [Int], deadlineCount: Int, lightDay: Int, lightDayTaskCount: Int)
        case deadlineCluster(deadlineDays: [Int], deadlineCount: Int)
        /// One day is clearly busier than the week's average.
        case busiestDay(day: Int, taskCount: Int, lightDay: Int, lightDayTaskCount: Int)
        case evenlySpread(minCount: Int, maxCount: Int)
    }

    struct WeekOutlookSnapshot: Equatable {
        let tone: WeekOutlookTone
        let typeCounts: WeekTypeCounts
        /// Weighted load per day (Monday first). Drives the tone only.
        let dayLoadSeries: [Double]
        /// Seven days, Monday first.
        var days: [WeekOutlookDay] = []
        /// At most `PendingViewModel.keyTaskLimit` tasks, most important first.
        var keyTasks: [WeekOutlookKeyTask] = []
        /// Key tasks left out by the limit, and how many of them are DDL.
        var hiddenKeyTaskCount: Int = 0
        var hiddenDeadlineCount: Int = 0
        var hint: WeekOutlookHint = .noTasks

        var hasTasks: Bool { days.contains { $0.taskCount > 0 } }
    }

    /// Key tasks shown on a week card; the rest are summarised as a count.
    static let keyTaskLimit = 3
    /// A task with at least this many steps counts as key work.
    static let keyTaskMinimumSteps = 3

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

    init(
        modelContext: ModelContext,
        timeProvider: TimeProviding? = nil
    ) {
        self.modelContext = modelContext
        self.timeProvider = timeProvider ?? PendingSystemTimeProvider()
        self.taskMutationService = TaskMutationService(modelContext: modelContext)
    }

    func refresh() {
        errorMessage = nil
        let descriptor = FetchDescriptor<WeekModel>()
        pendingWeeks = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { Self.isFutureWeek($0, relativeTo: timeProvider.today) }
            .sorted { $0.startDate < $1.startDate }
    }

    static func isFutureWeek(_ week: WeekModel, relativeTo today: Date) -> Bool {
        let nextWeekStart = today.startOfWeek.addingDays(7)
        return week.status == .pending && week.startDate >= nextWeekStart
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

        do {
            let resolution = try WeekDataStore(modelContext: modelContext)
                .resolveWeek(containing: date, status: .pending)
            guard resolution.created else {
                errorMessage = "该周已存在"
                return nil
            }
            try modelContext.save()
            refresh()
            return resolution.week
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func createWeek(weekId: String) -> WeekModel? {
        let normalizedWeekId = weekId.uppercased()
        guard let startDate = weekCalculator.weekStartDate(for: normalizedWeekId) else {
            errorMessage = String(localized: "error.date_format_invalid")
            return nil
        }

        let today = timeProvider.today
        guard startDate >= today else {
            errorMessage = "只能创建今天或未来的周"
            return nil
        }

        do {
            let resolution = try WeekDataStore(modelContext: modelContext)
                .resolveWeek(containing: startDate, status: .pending)
            guard resolution.created else {
                errorMessage = "该周已存在"
                return nil
            }
            try modelContext.save()
            refresh()
            return resolution.week
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
        let catalog = try? TaskTypeCatalog.load(in: modelContext)
        for day in allDays {
            let dayDate = calendar.startOfDay(for: day.date)
            guard dayDate >= monthStart, dayDate < monthEnd else { continue }

            let regularCount = day.tasks.filter { taskBaseKind($0, catalog: catalog) == .regular }.count
            let ddlCount = day.tasks.filter { taskBaseKind($0, catalog: catalog) == .ddl }.count
            let leisureCount = day.tasks.filter { taskBaseKind($0, catalog: catalog) == .leisure }.count
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
        Self.buildWeekOutlook(for: week, catalog: try? TaskTypeCatalog.load(in: modelContext))
    }

    static func buildWeekOutlook(for week: WeekModel, catalog: TaskTypeCatalog? = nil) -> WeekOutlookSnapshot {
        let calendar = Calendar(identifier: .iso8601)
        let start = calendar.startOfDay(for: week.startDate)
        let dayMap = Dictionary(
            week.days.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let weekLastDay = calendar.date(byAdding: .day, value: 6, to: start) ?? start

        var regularSeries: [Int] = []
        var ddlSeries: [Int] = []
        var leisureSeries: [Int] = []
        var days: [WeekOutlookDay] = []
        var keyTaskCandidates: [KeyTaskCandidate] = []

        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = dayMap[date]
            let tasks = day?.tasks ?? []
            let ddlCount = tasks.filter { taskBaseKind($0, catalog: catalog) == .ddl }.count
            regularSeries.append(tasks.filter { taskBaseKind($0, catalog: catalog) == .regular }.count)
            ddlSeries.append(ddlCount)
            leisureSeries.append(tasks.filter { taskBaseKind($0, catalog: catalog) == .leisure }.count)
            days.append(WeekOutlookDay(date: date, taskCount: tasks.count, deadlineCount: ddlCount))
            for task in tasks where task.zone != .complete {
                if let candidate = keyTaskCandidate(
                    task,
                    on: date,
                    weekRange: start...weekLastDay,
                    catalog: catalog,
                    calendar: calendar
                ) {
                    keyTaskCandidates.append(candidate)
                }
            }
        }

        let rankedKeyTasks = keyTaskCandidates
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                if lhs.task.date != rhs.task.date { return lhs.task.date < rhs.task.date }
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.task.id.uuidString < rhs.task.id.uuidString
            }
            .map(\.task)
        let shownKeyTasks = Array(rankedKeyTasks.prefix(keyTaskLimit))
        let hiddenKeyTasks = rankedKeyTasks.dropFirst(keyTaskLimit)

        let dayLoadSeries = zip(regularSeries, zip(ddlSeries, leisureSeries)).map { regular, tuple in
            let (ddl, leisure) = tuple
            return Double(regular) + Double(ddl) * 2.0 + Double(leisure) * 0.6
        }

        let totalRegular = regularSeries.reduce(0, +)
        let totalDDL = ddlSeries.reduce(0, +)
        let totalLeisure = leisureSeries.reduce(0, +)
        let totalLoad = dayLoadSeries.reduce(0, +)
        let peakLoad = dayLoadSeries.max() ?? 0

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

        return WeekOutlookSnapshot(
            tone: tone,
            typeCounts: WeekTypeCounts(regular: totalRegular, ddl: totalDDL, leisure: totalLeisure),
            dayLoadSeries: dayLoadSeries,
            days: days,
            keyTasks: shownKeyTasks,
            hiddenKeyTaskCount: hiddenKeyTasks.count,
            hiddenDeadlineCount: hiddenKeyTasks.filter { $0.baseKind == .ddl }.count,
            hint: weekHint(for: days)
        )
    }

    private struct KeyTaskCandidate {
        /// 0 = DDL, 1 = project ends this week, 2 = other project task or multi-step task.
        let tier: Int
        let order: Int
        let task: WeekOutlookKeyTask
    }

    private static func keyTaskCandidate(
        _ task: TaskItem,
        on date: Date,
        weekRange: ClosedRange<Date>,
        catalog: TaskTypeCatalog?,
        calendar: Calendar
    ) -> KeyTaskCandidate? {
        let kind = taskBaseKind(task, catalog: catalog)
        let tier: Int
        let reason: WeekOutlookKeyTask.Reason
        if kind == .ddl {
            tier = 0
            reason = .deadline(typeName: customTypeName(for: task, catalog: catalog))
        } else if let project = task.project, weekRange.contains(calendar.startOfDay(for: project.endDate)) {
            tier = 1
            reason = .projectDue
        } else if let project = task.project {
            tier = 2
            reason = .project(name: project.name)
        } else if task.steps.count >= keyTaskMinimumSteps {
            tier = 2
            reason = .steps(task.steps.count)
        } else {
            return nil
        }
        return KeyTaskCandidate(
            tier: tier,
            order: task.order,
            task: WeekOutlookKeyTask(id: task.id, title: task.title, date: date, baseKind: kind, reason: reason)
        )
    }

    /// Name of a user-defined task type; nil for the built-in types.
    private static func customTypeName(for task: TaskItem, catalog: TaskTypeCatalog?) -> String? {
        guard let catalog else { return nil }
        let definition = catalog.definition(for: task.taskTypeIdRaw)
        guard definition.idRaw == task.taskTypeIdRaw, !definition.isBuiltIn else { return nil }
        let name = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Picks the first rule that fits the week's actual task counts:
    /// 1. no tasks; 2. where DDL concentrate (and whether an earlier day is
    /// light enough to start them early); 3. one clearly busiest day;
    /// 4. otherwise an even spread.
    static func weekHint(for days: [WeekOutlookDay]) -> WeekOutlookHint {
        let counts = days.map(\.taskCount)
        let deadlines = days.map(\.deadlineCount)
        let total = counts.reduce(0, +)
        guard total > 0 else { return .noTasks }

        var deadlineDays: [Int] = []
        if deadlines.count >= 2 {
            var bestStart = 0
            var bestSum = -1
            for index in 0..<(deadlines.count - 1) where deadlines[index] + deadlines[index + 1] > bestSum {
                bestSum = deadlines[index] + deadlines[index + 1]
                bestStart = index
            }
            if bestSum >= 3, deadlines[bestStart] > 0, deadlines[bestStart + 1] > 0 {
                deadlineDays = [bestStart, bestStart + 1]
            }
        }
        if deadlineDays.isEmpty, let peak = deadlines.max(), peak >= 2, let index = deadlines.firstIndex(of: peak) {
            deadlineDays = [index]
        }
        if let firstDeadlineDay = deadlineDays.first {
            let deadlineCount = deadlineDays.map { deadlines[$0] }.reduce(0, +)
            let fullest = deadlineDays.map { counts[$0] }.max() ?? 0
            // Lightest earlier day that is at most half as full; on ties, the
            // one closest to the deadlines.
            let lightDay = (0..<firstDeadlineDay)
                .filter { counts[$0] * 2 <= fullest }
                .min { counts[$0] != counts[$1] ? counts[$0] < counts[$1] : $0 > $1 }
            if let lightDay {
                return .startDeadlinesEarly(
                    deadlineDays: deadlineDays,
                    deadlineCount: deadlineCount,
                    lightDay: lightDay,
                    lightDayTaskCount: counts[lightDay]
                )
            }
            return .deadlineCluster(deadlineDays: deadlineDays, deadlineCount: deadlineCount)
        }

        let maxCount = counts.max() ?? 0
        let average = Double(total) / Double(counts.count)
        if let busiest = counts.firstIndex(of: maxCount),
           Double(maxCount) >= average * 1.5,
           Double(maxCount) - average >= 3,
           let lightDay = counts.indices
               .filter({ $0 != busiest })
               .min(by: { counts[$0] != counts[$1] ? counts[$0] < counts[$1] : $0 < $1 }) {
            return .busiestDay(day: busiest, taskCount: maxCount, lightDay: lightDay, lightDayTaskCount: counts[lightDay])
        }
        return .evenlySpread(minCount: counts.min() ?? 0, maxCount: maxCount)
    }

    private static func taskBaseKind(_ task: TaskItem, catalog: TaskTypeCatalog?) -> TaskType {
        catalog?.baseKind(for: task.taskTypeIdRaw) ?? task.taskType
    }

    private func taskBaseKind(_ task: TaskItem, catalog: TaskTypeCatalog?) -> TaskType {
        Self.taskBaseKind(task, catalog: catalog)
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
        taskTypeIdRaw: String? = nil,
        steps: [TaskStep],
        attachments: [TaskAttachment]
    ) throws {
        guard canEdit(day) else { throw WeekyiiError.cannotEditStartedDay }
        let payload = TaskDraftPayload(
            title: title,
            description: description,
            type: type,
            taskTypeIdRaw: taskTypeIdRaw,
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
        taskTypeIdRaw: String? = nil,
        steps: [TaskStep],
        attachments: [TaskAttachment]
    ) throws {
        guard canEdit(day), task.zone == .draft else { throw WeekyiiError.cannotEditStartedDay }
        let payload = TaskDraftPayload(
            title: title,
            description: description,
            type: type,
            taskTypeIdRaw: taskTypeIdRaw,
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

    // These four helpers currently have no call sites — this view model delegates
    // its CRUD to `taskMutationService` (see `addDraftTask` / `updateDraftTask`).
    // They are kept delegating to `TaskResourceIdentity` rather than deleted so
    // that wiring them up later cannot reintroduce identity churn.

    private func replaceSteps(for task: TaskItem, with steps: [TaskStep]) {
        TaskResourceIdentity.reconcileSteps(on: task, with: steps, in: modelContext)
    }

    private func replaceAttachments(for task: TaskItem, with attachments: [TaskAttachment]) {
        TaskResourceIdentity.reconcileAttachments(on: task, with: attachments, in: modelContext)
    }

    private func appendStepCopies(to task: TaskItem, from steps: [TaskStep]) {
        task.steps.append(contentsOf: TaskResourceIdentity.stepCopies(from: steps))
    }

    private func appendAttachmentCopies(to task: TaskItem, from attachments: [TaskAttachment]) {
        task.attachments.append(contentsOf: TaskResourceIdentity.duplicatedAttachmentCopies(from: attachments))
    }

    private func zonePriority(_ zone: TaskZone) -> Int {
        switch zone {
        case .draft: return 0
        case .focus: return 1
        case .frozen: return 2
        case .complete: return 3
        }
    }

    /// Short weekday in the app's language: "周四" / "Thu".
    static func weekdayLabel(for date: Date) -> String {
        weekdayLabel(for: date, template: "EEE")
    }

    /// Narrow weekday for the distribution strip: "四" / "T".
    static func narrowWeekdayLabel(for date: Date) -> String {
        weekdayLabel(for: date, template: "EEEEE")
    }

    private static func weekdayLabel(for date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

}

// MARK: - Week outlook text

/// All user-facing week outlook wording, localized (en / zh-Hans).
enum WeekOutlookText {
    typealias KeyTask = PendingViewModel.WeekOutlookKeyTask
    typealias Hint = PendingViewModel.WeekOutlookHint
    typealias Day = PendingViewModel.WeekOutlookDay

    static var title: String {
        String(localized: "pending.week.outlook.title", defaultValue: "周预报")
    }

    static var emptyWeek: String {
        String(localized: "pending.week.outlook.empty", defaultValue: "还没有安排任务")
    }

    static var noKeyTasks: String {
        String(localized: "pending.week.outlook.noKeyTasks", defaultValue: "这一周没有 DDL 或项目任务")
    }

    static func reason(_ reason: KeyTask.Reason) -> String {
        switch reason {
        case .deadline(let typeName):
            return typeName ?? TaskType.ddl.displayName
        case .projectDue:
            return String(localized: "pending.week.outlook.reason.projectDue", defaultValue: "项目截止")
        case .project(let name):
            return name
        case .steps(let count):
            return String(
                format: String(localized: "pending.week.outlook.reason.steps", defaultValue: "%lld 步"),
                locale: Locale.current,
                Int64(count)
            )
        }
    }

    /// "另有 N 个 DDL" when everything hidden is DDL, otherwise "另有 N 项重点任务".
    static func hiddenKeyTasks(total: Int, deadlines: Int) -> String? {
        guard total > 0 else { return nil }
        if deadlines == total {
            return String(
                format: String(localized: "pending.week.outlook.more.deadlines", defaultValue: "另有 %lld 个 DDL"),
                locale: Locale.current,
                Int64(total)
            )
        }
        return String(
            format: String(localized: "pending.week.outlook.more.keyTasks", defaultValue: "另有 %lld 项重点任务"),
            locale: Locale.current,
            Int64(total)
        )
    }

    static func hint(_ hint: Hint, days: [Day]) -> String {
        func dayName(_ index: Int) -> String {
            guard days.indices.contains(index) else { return "" }
            return PendingViewModel.weekdayLabel(for: days[index].date)
        }
        func dayNames(_ indexes: [Int]) -> String {
            guard indexes.count == 2 else { return indexes.map(dayName).joined() }
            return String(
                format: String(localized: "pending.week.outlook.days.pair", defaultValue: "%1$@、%2$@"),
                locale: Locale.current,
                dayName(indexes[0]),
                dayName(indexes[1])
            )
        }

        switch hint {
        case .noTasks:
            return String(localized: "pending.week.outlook.hint.noTasks", defaultValue: "先定一个主目标")
        case let .startDeadlinesEarly(deadlineDays, deadlineCount, lightDay, lightDayTaskCount):
            return String(
                format: String(
                    localized: "pending.week.outlook.hint.startEarly",
                    defaultValue: "%1$@有 %2$lld 个 DDL，%3$@只有 %4$lld 项，可以提前处理"
                ),
                locale: Locale.current,
                dayNames(deadlineDays),
                Int64(deadlineCount),
                dayName(lightDay),
                Int64(lightDayTaskCount)
            )
        case let .deadlineCluster(deadlineDays, deadlineCount):
            return String(
                format: String(localized: "pending.week.outlook.hint.deadlineCluster", defaultValue: "DDL 集中在%1$@（共 %2$lld 个）"),
                locale: Locale.current,
                dayNames(deadlineDays),
                Int64(deadlineCount)
            )
        case let .busiestDay(day, taskCount, lightDay, lightDayTaskCount):
            return String(
                format: String(localized: "pending.week.outlook.hint.busiest", defaultValue: "%1$@最满（%2$lld 项），%3$@只有 %4$lld 项"),
                locale: Locale.current,
                dayName(day),
                Int64(taskCount),
                dayName(lightDay),
                Int64(lightDayTaskCount)
            )
        case let .evenlySpread(minCount, maxCount):
            if minCount == maxCount {
                return String(
                    format: String(localized: "pending.week.outlook.hint.evenSame", defaultValue: "每天 %lld 项，分布均匀"),
                    locale: Locale.current,
                    Int64(maxCount)
                )
            }
            return String(
                format: String(localized: "pending.week.outlook.hint.even", defaultValue: "每天 %1$lld–%2$lld 项，分布较均匀"),
                locale: Locale.current,
                Int64(minCount),
                Int64(maxCount)
            )
        }
    }
}
