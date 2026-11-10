import Foundation
import SwiftData

@Model
final class ProjectModel {
    var id: UUID = UUID()

    var name: String = ""
    var projectDescription: String = ""
    var color: String = "#C46A1A"
    var icon: String = "folder.fill"
    var status: ProjectStatus = ProjectStatus.planning
    var startDate: Date = Date.distantPast
    var endDate: Date = Date.distantPast
    var createdAt: Date = Date()
    var tileSizeRaw: String = ProjectTileSize.medium.rawValue
    var tileOrder: Int = 0

    @Relationship(deleteRule: .nullify, originalName: "tasks", inverse: \TaskItem.project)
    private var taskRecords: [TaskItem]? = []

    init(
        name: String,
        projectDescription: String = "",
        color: String = "#C46A1A",
        icon: String = "folder.fill",
        status: ProjectStatus = .planning,
        startDate: Date,
        endDate: Date
    ) {
        self.name = name
        self.projectDescription = projectDescription
        self.color = color
        self.icon = icon
        self.status = status
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = Date()
    }

    var tasks: [TaskItem] {
        get { taskRecords ?? [] }
        set { taskRecords = newValue }
    }

    // MARK: - Computed Properties

    var totalTaskCount: Int {
        tasks.count
    }

    var completedTaskCount: Int {
        tasks.filter { $0.zone == .complete }.count
    }

    var expiredTaskCount: Int {
        let isoCalendar = Calendar(identifier: .iso8601)
        let today = isoCalendar.startOfDay(for: Date())
        return tasks.filter { ProjectTaskTimeline.isOverdue($0, today: today, calendar: isoCalendar) }.count
    }

    var progress: Double {
        guard totalTaskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(totalTaskCount)
    }

    var isAllCompleted: Bool {
        totalTaskCount > 0 && completedTaskCount == totalTaskCount
    }

    var tileSize: ProjectTileSize {
        get { ProjectTileSize(storedValue: tileSizeRaw) ?? .medium }
        set { tileSizeRaw = newValue.rawValue }
    }
}

/// Single source of truth for how project screens read a task's place in time.
///
/// Read-only: nothing here mutates or persists data, so it has no effect on
/// SwiftData schemas, iCloud sync records or archives.
///
/// Weekyii's rule for expired work is "no details, count only" (see the
/// execution-mode cards in Settings). Project surfaces therefore show overdue
/// tasks as a number and never pick one as the next step.
enum ProjectTaskTimeline {
    /// An unfinished task is overdue once its day is in the past, or once its
    /// day has already expired today (kill time reached or closed early).
    static func isOverdue(_ task: TaskItem, today: Date, calendar: Calendar) -> Bool {
        guard task.zone != .complete, let day = task.day else { return false }
        if calendar.startOfDay(for: day.date) < calendar.startOfDay(for: today) {
            return true
        }
        return day.status == .expired
    }

    /// Unfinished tasks that can still be worked on, in schedule order:
    /// day, then in-day order, then id as a stable tiebreaker.
    /// Tasks without a day have no schedule and are not actionable.
    static func actionableTasks(in project: ProjectModel, today: Date, calendar: Calendar) -> [TaskItem] {
        project.tasks
            .filter { task in
                task.zone != .complete
                    && task.day != nil
                    && !isOverdue(task, today: today, calendar: calendar)
            }
            .sorted { lhs, rhs in
                let lhsDate = calendar.startOfDay(for: lhs.day?.date ?? .distantFuture)
                let rhsDate = calendar.startOfDay(for: rhs.day?.date ?? .distantFuture)
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// The next step is the earliest actionable task. Overdue tasks are never
    /// promoted: when only overdue work remains, there is no next step.
    static func nextTask(in project: ProjectModel, today: Date, calendar: Calendar) -> TaskItem? {
        actionableTasks(in: project, today: today, calendar: calendar).first
    }
}
