import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ExtensionsViewModel {
    private let modelContext: ModelContext
    private let notificationService: any NotificationScheduling
    private let taskMutationService: TaskMutationService
    private let weekCalculator = WeekCalculator()
    private let calendar = Calendar(identifier: .iso8601)

    var projects: [ProjectModel] = []
    var suspendedTasks: [SuspendedTaskItem] = []
    var tileSnapshotsByProjectID: [UUID: ProjectTileSnapshot] = [:]
    var errorMessage: String?

    init(modelContext: ModelContext, notificationService: (any NotificationScheduling)? = nil) {
        self.modelContext = modelContext
        self.notificationService = notificationService ?? NotificationService.shared
        self.taskMutationService = TaskMutationService(modelContext: modelContext)
    }

    // MARK: - Refresh

    func refresh() {
        errorMessage = nil
        let descriptor = FetchDescriptor<ProjectModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        projects = (try? modelContext.fetch(descriptor)) ?? []
        let suspendedDescriptor = FetchDescriptor<SuspendedTaskItem>(
            sortBy: [SortDescriptor(\.decisionDeadline), SortDescriptor(\.createdAt)]
        )
        suspendedTasks = ((try? modelContext.fetch(suspendedDescriptor)) ?? [])
            .filter { $0.status == .active }
        rebuildTileSnapshots()
    }

    // MARK: - Create Project

    @discardableResult
    func createProject(
        name: String,
        description: String,
        color: String,
        icon: String,
        startDate: Date,
        endDate: Date
    ) -> ProjectModel? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = String(localized: "project.error.name_empty")
            return nil
        }
        guard endDate >= startDate else {
            errorMessage = String(localized: "project.error.date_invalid")
            return nil
        }

        let project = ProjectModel(
            name: name.trimmingCharacters(in: .whitespaces),
            projectDescription: description,
            color: color,
            icon: icon,
            startDate: startDate,
            endDate: endDate
        )
        let maxOrder = projects.map(\.tileOrder).max() ?? -1
        project.tileOrder = maxOrder + 1
        modelContext.insert(project)

        do {
            try modelContext.save()
            refresh()
            return project
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Add Task to Project

    @discardableResult
    func addTask(
        to project: ProjectModel,
        title: String,
        description: String = "",
        taskType: TaskType,
        steps: [TaskStep] = [],
        attachments: [TaskAttachment] = [],
        on date: Date
    ) -> TaskItem? {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = String(localized: "project.error.task_title_empty")
            return nil
        }
        
        // Date Validation
        let projectStart = calendar.startOfDay(for: project.startDate)
        let projectEnd = calendar.startOfDay(for: project.endDate)
        let taskDate = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        
        guard taskDate >= projectStart && taskDate <= projectEnd else {
            errorMessage = String(localized: "project.error.date_out_of_range")
            return nil
        }
        guard taskDate >= today else {
            errorMessage = String(localized: "project.error.day_expired")
            return nil
        }

        // 1. 找到或创建该日期所属的 Week
        let day = findOrCreateDay(for: date)
        guard let day else {
            errorMessage = String(localized: "error.operation_failed_retry")
            return nil
        }
        guard day.status != .expired else {
            errorMessage = String(localized: "project.error.day_expired")
            return nil
        }
        guard day.status != .completed else {
            errorMessage = String(localized: "project.error.day_completed")
            return nil
        }

        // 2. 计算 order（在该天所有任务之后）
        let payload = TaskDraftPayload(
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            type: taskType,
            steps: steps,
            attachments: attachments
        )
        let task: TaskItem
        do {
            task = try taskMutationService.createTask(in: day, payload: payload, zone: .draft, project: project)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        // 4. 更新天的状态
        if day.status == .empty {
            day.status = .draft
        }

        // 5. 更新项目状态
        if project.status == .planning {
            project.status = .active
        }

        do {
            try modelContext.save()
            refresh()
            return task
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Delete Project
    
    func deleteProject(_ project: ProjectModel, includeTasks: Bool) {
        if includeTasks {
            // 级联删除：删除项目关联的所有任务
            // 注意：SwiftData 的 deleteRule: .nullify 只会断开关联，不会删除 TaskItem
            // 所以这里需要手动删除任务
            for task in project.tasks {
                modelContext.delete(task)
            }
        } else {
            // 仅删除项目：断开关联（任务保留）- .nullify 规则会自动处理，这里显式置空更清晰
            for task in project.tasks {
                task.project = nil
            }
        }
        
        modelContext.delete(project)
        do {
            try modelContext.save()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Update Project Status

    func updateStatus(_ project: ProjectModel, to status: ProjectStatus) {
        project.status = status
        do {
            try modelContext.save()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete Project Task

    func deleteProjectTask(_ task: TaskItem) {
        if let day = task.day {
            day.tasks.removeAll { $0.id == task.id }
            if day.tasks.isEmpty && day.status == .draft {
                day.status = .empty
            }
        }
        if let project = task.project {
            project.tasks.removeAll { $0.id == task.id }
        }
        modelContext.delete(task)
        do {
            try modelContext.save()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private Helpers

    /// 找到或创建某日期对应的 DayModel（自动创建 Week）
    private func findOrCreateDay(for date: Date) -> DayModel? {
        let dayId = calendar.startOfDay(for: date).dayId

        // 先查找已有 Day
        let dayDescriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == dayId })
        if let existingDay = try? modelContext.fetch(dayDescriptor).first {
            return existingDay
        }

        // Day 不存在 → 查找或创建 Week
        let weekId = date.weekId
        let weekDescriptor = FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })

        if let existingWeek = try? modelContext.fetch(weekDescriptor).first {
            // Week 存在但 Day 缺失（不应发生，但保险起见）
            return existingWeek.days.first { $0.dayId == dayId }
        }

        // Week 也不存在 → 创建 Week（pending 状态）
        let week = weekCalculator.makeWeek(for: date, status: .pending)
        modelContext.insert(week)
        do {
            try modelContext.save()
        } catch {
            return nil
        }

        return week.days.first { $0.dayId == dayId }
    }

    // MARK: - Project Queries

    func activeProjects() -> [ProjectModel] {
        projects.filter { $0.status == .planning || $0.status == .active }
    }

    func completedProjects() -> [ProjectModel] {
        projects.filter { $0.status == .completed || $0.status == .archived }
    }

    func dueSoonSuspendedTasks(limit: Int = 3) -> [SuspendedTaskItem] {
        Array(suspendedTasks.prefix(limit))
    }

    func suspendedTaskStats(referenceDate: Date = Date()) -> (total: Int, dueSoon: Int, dueToday: Int) {
        let today = calendar.startOfDay(for: referenceDate)
        let soonLimit = today.addingDays(7)
        let dueSoon = suspendedTasks.filter { task in
            let deadlineDay = calendar.startOfDay(for: task.decisionDeadline)
            return deadlineDay >= today && deadlineDay <= soonLimit
        }.count
        let dueToday = suspendedTasks.filter { calendar.isDate($0.decisionDeadline, inSameDayAs: today) }.count
        return (suspendedTasks.count, dueSoon, dueToday)
    }

    @discardableResult
    func createSuspendedTask(
        title: String,
        description: String,
        type: TaskType,
        countdownDays: Int,
        steps: [TaskStep] = [],
        attachments: [TaskAttachment] = [],
        now: Date = Date()
    ) -> SuspendedTaskItem? {
        let service = SuspendedTaskLifecycleService(modelContext: modelContext, notificationService: notificationService)
        do {
            let task = try service.createTask(
                title: title,
                description: description,
                type: type,
                countdownDays: countdownDays,
                steps: steps,
                attachments: attachments,
                now: now
            )
            refresh()
            return task
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateSuspendedTask(
        _ task: SuspendedTaskItem,
        title: String,
        description: String,
        type: TaskType,
        countdownDays: Int,
        steps: [TaskStep] = [],
        attachments: [TaskAttachment] = [],
        now: Date = Date()
    ) {
        let service = SuspendedTaskLifecycleService(modelContext: modelContext, notificationService: notificationService)
        do {
            try service.updateTask(
                task,
                title: title,
                description: description,
                type: type,
                countdownDays: countdownDays,
                steps: steps,
                attachments: attachments,
                now: now
            )
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func extendSuspendedTask(_ task: SuspendedTaskItem, by additionalDays: Int, now: Date = Date()) {
        let service = SuspendedTaskLifecycleService(modelContext: modelContext, notificationService: notificationService)
        do {
            try service.extendTask(task, by: additionalDays, now: now)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assignSuspendedTask(_ task: SuspendedTaskItem, to targetDate: Date, today: Date = Date()) {
        let service = SuspendedTaskLifecycleService(modelContext: modelContext, notificationService: notificationService)
        do {
            try service.assignTask(task, to: targetDate, today: today)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSuspendedTask(_ task: SuspendedTaskItem) {
        let service = SuspendedTaskLifecycleService(modelContext: modelContext, notificationService: notificationService)
        do {
            try service.deleteTask(task)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sortedProjectsForBoard() -> [ProjectModel] {
        projects.sorted { lhs, rhs in
            if lhs.tileOrder != rhs.tileOrder {
                return lhs.tileOrder < rhs.tileOrder
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func cycleTileSize(for project: ProjectModel) {
        project.tileSize = project.tileSize.next
        saveBoardState()
    }

    func updateTileOrder(with orderedProjectIDs: [UUID]) {
        let mapping = Dictionary(uniqueKeysWithValues: orderedProjectIDs.enumerated().map { ($1, $0) })
        for project in projects {
            if let order = mapping[project.id] {
                project.tileOrder = order
            }
        }
        saveBoardState()
    }

    /// 按日期分组项目任务
    func tasksByDate(for project: ProjectModel) -> [(date: Date, tasks: [TaskItem])] {
        projectTaskLedgerSections(for: project).map { (date: $0.date, tasks: $0.tasks) }
    }

    func projectTaskLedgerSections(for project: ProjectModel, referenceDate: Date = Date()) -> [ProjectTaskLedgerSection] {
        ProjectDetailComposer.projectTaskLedgerSections(
            project: project,
            calendar: calendar,
            referenceDate: referenceDate
        )
    }

    func projectDetailSnapshot(for project: ProjectModel, referenceDate: Date = Date()) -> ProjectDetailSnapshot {
        ProjectDetailComposer.projectDetailSnapshot(
            project: project,
            calendar: calendar,
            referenceDate: referenceDate
        )
    }

    func updateProjectTask(
        _ task: TaskItem,
        title: String,
        description: String,
        type: TaskType,
        steps: [TaskStep] = [],
        attachments: [TaskAttachment] = []
    ) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            errorMessage = String(localized: "project.error.task_title_empty")
            return
        }

        let payload = TaskDraftPayload(
            title: normalizedTitle,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            steps: steps,
            attachments: attachments
        )
        do {
            try taskMutationService.updateTask(task, payload: payload)
            try modelContext.save()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveBoardState() {
        do {
            try modelContext.save()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replaceProjectTaskSteps(for task: TaskItem, with steps: [TaskStep]) {
        task.steps.forEach { modelContext.delete($0) }
        task.steps.removeAll(keepingCapacity: true)
        let ordered = steps
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            }
            .enumerated()
            .map { index, step in
                TaskStep(
                    title: step.title,
                    isCompleted: step.isCompleted,
                    sortOrder: index
                )
            }
        task.steps.append(contentsOf: ordered)
    }

    private func replaceProjectTaskAttachments(for task: TaskItem, with attachments: [TaskAttachment]) {
        task.attachments.forEach { modelContext.delete($0) }
        task.attachments.removeAll(keepingCapacity: true)
        let copies = attachments.map { attachment in
            TaskAttachment(
                data: attachment.data,
                fileName: attachment.fileName,
                fileType: attachment.fileType
            )
        }
        task.attachments.append(contentsOf: copies)
    }

    private func rebuildTileSnapshots() {
        var next: [UUID: ProjectTileSnapshot] = [:]
        let today = calendar.startOfDay(for: Date())
        for project in projects {
            let sortedPending = project.tasks
                .filter { $0.zone != .complete }
                .sorted { lhs, rhs in
                    let lhsDate = lhs.day?.date ?? .distantFuture
                    let rhsDate = rhs.day?.date ?? .distantFuture
                    if lhsDate != rhsDate { return lhsDate < rhsDate }
                    return lhs.order < rhs.order
                }

            let preferredTask = sortedPending.first(where: { task in
                guard let date = task.day?.date else { return false }
                return calendar.startOfDay(for: date) >= today
            }) ?? sortedPending.first

            next[project.id] = ProjectTileSnapshot(
                projectID: project.id,
                name: project.name,
                icon: project.icon,
                colorHex: project.color,
                progress: project.progress,
                completedCount: project.completedTaskCount,
                totalCount: project.totalTaskCount,
                remainingCount: max(project.totalTaskCount - project.completedTaskCount, 0),
                expiredCount: project.expiredTaskCount,
                nextTaskTitle: preferredTask?.title,
                nextTaskDate: preferredTask?.day?.date
            )
        }
        tileSnapshotsByProjectID = next
    }
}

struct ProjectTileSnapshot: Equatable {
    let projectID: UUID
    let name: String
    let icon: String
    let colorHex: String
    let progress: Double
    let completedCount: Int
    let totalCount: Int
    let remainingCount: Int
    let expiredCount: Int
    let nextTaskTitle: String?
    let nextTaskDate: Date?
}

struct ProjectTaskLedgerSection: Identifiable {
    let date: Date
    let tasks: [TaskItem]
    let isExpandedByDefault: Bool

    var id: String {
        date.dayId
    }
}

struct ProjectDetailSnapshot {
    let projectID: UUID
    let name: String
    let icon: String
    let colorHex: String
    let status: ProjectStatus
    let startDate: Date
    let endDate: Date
    let projectDescription: String
    let progress: Double
    let totalCount: Int
    let completedCount: Int
    let remainingCount: Int
    let expiredCount: Int
    let nextTaskTitle: String?
    let nextTaskDate: Date?
    let sections: [ProjectTaskLedgerSection]
}

enum ProjectDetailComposer {
    static func projectTaskLedgerSections(
        project: ProjectModel,
        calendar: Calendar,
        referenceDate: Date
    ) -> [ProjectTaskLedgerSection] {
        let today = calendar.startOfDay(for: referenceDate)
        let grouped = Dictionary(grouping: project.tasks) { task in
            calendar.startOfDay(for: task.day?.date ?? today)
        }

        return grouped
            .map { date, tasks in
                let sortedTasks = tasks.sorted { lhs, rhs in
                    if lhs.order != rhs.order {
                        return lhs.order < rhs.order
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return ProjectTaskLedgerSection(
                    date: date,
                    tasks: sortedTasks,
                    isExpandedByDefault: date >= today
                )
            }
            .sorted { $0.date < $1.date }
    }

    static func projectDetailSnapshot(
        project: ProjectModel,
        calendar: Calendar,
        referenceDate: Date
    ) -> ProjectDetailSnapshot {
        let today = calendar.startOfDay(for: referenceDate)
        let pending = project.tasks
            .filter { $0.zone != .complete }
            .sorted { lhs, rhs in
                let lhsDate = calendar.startOfDay(for: lhs.day?.date ?? .distantFuture)
                let rhsDate = calendar.startOfDay(for: rhs.day?.date ?? .distantFuture)
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let nextTask = pending.first { task in
            guard let taskDay = task.day?.date else { return false }
            return calendar.startOfDay(for: taskDay) >= today
        } ?? pending.first

        return ProjectDetailSnapshot(
            projectID: project.id,
            name: project.name,
            icon: project.icon,
            colorHex: project.color,
            status: project.status,
            startDate: project.startDate,
            endDate: project.endDate,
            projectDescription: project.projectDescription,
            progress: project.progress,
            totalCount: project.totalTaskCount,
            completedCount: project.completedTaskCount,
            remainingCount: max(project.totalTaskCount - project.completedTaskCount, 0),
            expiredCount: project.expiredTaskCount,
            nextTaskTitle: nextTask?.title,
            nextTaskDate: nextTask?.day?.date,
            sections: projectTaskLedgerSections(project: project, calendar: calendar, referenceDate: referenceDate)
        )
    }
}

struct SuspendedTaskLifecycleService {
    private let modelContext: ModelContext
    private let notificationService: any NotificationScheduling
    private let taskMutationService: TaskMutationService
    private let calendar = Calendar(identifier: .iso8601)
    private let weekCalculator = WeekCalculator()

    init(modelContext: ModelContext, notificationService: any NotificationScheduling) {
        self.modelContext = modelContext
        self.notificationService = notificationService
        self.taskMutationService = TaskMutationService(modelContext: modelContext)
    }

    func createTask(
        title: String,
        description: String,
        type: TaskType,
        countdownDays: Int,
        steps: [TaskStep] = [],
        attachments: [TaskAttachment] = [],
        now: Date
    ) throws -> SuspendedTaskItem {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw WeekyiiError.taskTitleEmpty
        }
        guard countdownDays > 0 else {
            throw WeekyiiError.dateFormatInvalid
        }

        let task = SuspendedTaskItem(
            title: normalizedTitle,
            taskDescription: description.trimmingCharacters(in: .whitespacesAndNewlines),
            taskType: type,
            createdAt: now,
            decisionDeadline: endOfDecisionWindow(from: now, countdownDays: countdownDays),
            preferredCountdownDays: countdownDays
        )
        replaceSteps(for: task, with: steps)
        replaceAttachments(for: task, with: attachments)
        modelContext.insert(task)
        try modelContext.save()
        notificationService.scheduleSuspendedTaskNotifications(for: task)
        return task
    }

    func updateTask(
        _ task: SuspendedTaskItem,
        title: String,
        description: String,
        type: TaskType,
        countdownDays: Int,
        steps: [TaskStep] = [],
        attachments: [TaskAttachment] = [],
        now: Date
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw WeekyiiError.taskTitleEmpty
        }
        guard countdownDays > 0 else {
            throw WeekyiiError.dateFormatInvalid
        }

        task.title = normalizedTitle
        task.taskDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        task.taskType = type
        task.preferredCountdownDays = countdownDays
        task.decisionDeadline = endOfDecisionWindow(from: now, countdownDays: countdownDays)
        replaceSteps(for: task, with: steps)
        replaceAttachments(for: task, with: attachments)
        try modelContext.save()
        notificationService.scheduleSuspendedTaskNotifications(for: task)
    }

    func extendTask(_ task: SuspendedTaskItem, by additionalDays: Int, now: Date) throws {
        guard additionalDays > 0 else { throw WeekyiiError.dateFormatInvalid }
        let currentDeadlineDay = calendar.startOfDay(for: task.decisionDeadline)
        let baselineDay = max(currentDeadlineDay, calendar.startOfDay(for: now))
        guard let newDeadlineDay = calendar.date(byAdding: .day, value: additionalDays, to: baselineDay) else {
            throw WeekyiiError.operationFailedRetry
        }

        task.decisionDeadline = endOfDay(for: newDeadlineDay)
        task.preferredCountdownDays = additionalDays
        task.snoozeCount += 1
        try modelContext.save()
        notificationService.scheduleSuspendedTaskNotifications(for: task)
    }

    func assignTask(_ task: SuspendedTaskItem, to targetDate: Date, today: Date) throws {
        let todayStart = calendar.startOfDay(for: today)
        let normalizedTargetDate = calendar.startOfDay(for: targetDate)
        guard normalizedTargetDate >= todayStart else {
            throw WeekyiiError.postponeTargetMustBeFuture
        }

        let resolution = try resolveTargetDay(for: normalizedTargetDate, today: todayStart)
        let targetDay = resolution.day
        guard targetDay.status == .empty || targetDay.status == .draft else {
            throw WeekyiiError.postponeTargetDayUnavailable
        }

        let order = (targetDay.sortedDraftTasks.last?.order ?? 0) + 1
        let taskItem = TaskItem(
            title: task.title,
            taskDescription: task.taskDescription,
            taskType: task.taskType,
            order: order,
            zone: .draft
        )
        replaceSteps(for: taskItem, with: task.steps)
        replaceAttachments(for: taskItem, with: task.attachments)
        targetDay.tasks.append(taskItem)
        if targetDay.status == .empty {
            targetDay.status = .draft
        }

        task.status = .assigned
        modelContext.delete(task)
        try modelContext.save()
        notificationService.cancelSuspendedTaskNotifications(for: task)
    }

    func deleteTask(_ task: SuspendedTaskItem) throws {
        notificationService.cancelSuspendedTaskNotifications(for: task)
        modelContext.delete(task)
        try modelContext.save()
    }

    func sweepExpiredTasks(now: Date) throws -> Int {
        let descriptor = FetchDescriptor<SuspendedTaskItem>()
        let allTasks = try modelContext.fetch(descriptor)
        let expired = allTasks.filter { $0.status == .active && $0.decisionDeadline <= now }

        for task in expired {
            notificationService.cancelSuspendedTaskNotifications(for: task)
            modelContext.delete(task)
        }

        if !expired.isEmpty {
            try modelContext.save()
        }
        return expired.count
    }

    private func resolveTargetDay(for date: Date, today: Date) throws -> (day: DayModel, createdWeek: Bool) {
        let dayId = date.dayId
        if let existingDay = fetchDay(by: dayId) {
            return (existingDay, false)
        }

        let weekId = date.weekId
        if let existingWeek = fetchWeek(by: weekId) {
            guard let existingDay = existingWeek.days.first(where: { $0.dayId == dayId }) else {
                throw WeekyiiError.dayNotFound(dayId)
            }
            return (existingDay, false)
        }

        let weekStatus: WeekStatus = date.startOfWeek == today.startOfWeek ? .present : .pending
        let week = weekCalculator.makeWeek(for: date, status: weekStatus)
        modelContext.insert(week)
        guard let targetDay = week.days.first(where: { $0.dayId == dayId }) else {
            throw WeekyiiError.dayNotFound(dayId)
        }
        return (targetDay, true)
    }

    private func fetchDay(by dayId: String) -> DayModel? {
        let descriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == dayId })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchWeek(by weekId: String) -> WeekModel? {
        let descriptor = FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })
        return try? modelContext.fetch(descriptor).first
    }

    private func endOfDecisionWindow(from now: Date, countdownDays: Int) -> Date {
        let today = calendar.startOfDay(for: now)
        let targetDay = calendar.date(byAdding: .day, value: countdownDays, to: today) ?? today
        return endOfDay(for: targetDay)
    }

    private func replaceSteps(for task: SuspendedTaskItem, with steps: [TaskStep]) {
        taskMutationService.replaceTaskResources(for: task, steps: steps, attachments: task.attachments)
    }

    private func replaceAttachments(for task: SuspendedTaskItem, with attachments: [TaskAttachment]) {
        taskMutationService.replaceTaskResources(for: task, steps: task.steps, attachments: attachments)
    }

    private func replaceSteps(for task: TaskItem, with steps: [TaskStep]) {
        taskMutationService.replaceTaskResources(for: task, steps: steps, attachments: task.attachments)
    }

    private func replaceAttachments(for task: TaskItem, with attachments: [TaskAttachment]) {
        taskMutationService.replaceTaskResources(for: task, steps: task.steps, attachments: attachments)
    }

    private func endOfDay(for date: Date) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 23
        components.minute = 59
        components.second = 59
        return calendar.date(from: components) ?? date
    }
}
