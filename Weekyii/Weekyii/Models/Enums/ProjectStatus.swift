import Foundation

enum ProjectStatus: String, Codable, CaseIterable {
    case planning
    case active
    case completed
    case archived

    var displayName: String {
        switch self {
        case .planning: return String(localized: "project.status.planning")
        case .active: return String(localized: "project.status.active")
        case .completed: return String(localized: "project.status.completed")
        case .archived: return String(localized: "project.status.archived")
        }
    }
}
