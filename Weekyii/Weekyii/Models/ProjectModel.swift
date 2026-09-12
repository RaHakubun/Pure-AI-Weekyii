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
        return tasks.filter { task in
            guard let taskDate = task.day?.date else { return false }
            return taskDate < today && task.zone != .complete
        }.count
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
