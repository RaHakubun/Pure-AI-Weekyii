import SwiftUI

enum DayStatus: String, Codable {
    case empty
    case draft
    case execute
    case completed
    case expired

    var displayName: String {
        switch self {
        case .empty: return String(localized: "status.empty")
        case .draft: return String(localized: "status.draft")
        case .execute: return String(localized: "status.execute")
        case .completed: return String(localized: "status.completed")
        case .expired: return String(localized: "status.expired")
        }
    }

    var color: Color {
        switch self {
        case .empty: return .statusEmpty
        case .draft: return .statusDraft
        case .execute: return .statusExecute
        case .completed: return .statusCompleted
        case .expired: return .statusExpired
        }
    }
}
