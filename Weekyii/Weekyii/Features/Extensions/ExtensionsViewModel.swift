import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ExtensionsViewModel {
    private let modelContext: ModelContext
    private let weekCalculator = WeekCalculator()
    private let calendar = Calendar(identifier: .iso8601)

    var projects: [ProjectModel] = []
    var tileSnapshotsByProjectID: [UUID: ProjectTileSnapshot] = [:]
    var errorMessage: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Refresh

    func refresh() {
        errorMessage = nil
        let descriptor = FetchDescriptor<ProjectModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        projects = (try? modelContext.fetch(descriptor)) ?? []
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
        taskType: TaskType,
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
        let maxOrder = day.tasks.map(\.order).max() ?? 0
        let newOrder = maxOrder + 1

        // 3. 创建 TaskItem
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespaces),
            taskType: taskType,
            order: newOrder,
            zone: .draft
        )
        task.day = day
        task.project = project
        modelContext.insert(task)

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
        let grouped = Dictionary(grouping: project.tasks) { task in
            calendar.startOfDay(for: task.day?.date ?? Date())
        }
        return grouped.sorted { $0.key < $1.key }.map { (date: $0.key, tasks: $0.value.sorted { $0.order < $1.order }) }
    }

    private func saveBoardState() {
        do {
            try modelContext.save()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
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
