import SwiftUI

enum TaskType: String, Codable, CaseIterable {
    case regular
    case ddl
    case leisure

    var displayName: String {
        switch self {
        case .regular: return String(localized: "task.type.regular")
        case .ddl: return String(localized: "task.type.ddl")
        case .leisure: return String(localized: "task.type.leisure")
        }
    }

    var iconName: String {
        switch self {
        case .regular: return "checkmark.circle"
        case .ddl: return "exclamationmark.triangle"
        case .leisure: return "leaf"
        }
    }

    var color: Color {
        switch self {
        case .regular: return .taskRegular
        case .ddl: return .taskDDL
        case .leisure: return .taskLeisure
        }
    }
}
