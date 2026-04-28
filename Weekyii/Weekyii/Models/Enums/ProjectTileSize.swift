import Foundation

enum ProjectTileSize: String, CaseIterable {
    case mini
    case small
    case medium
    case wide

    init?(storedValue: String) {
        switch storedValue {
        case "large":
            self = .wide
        case "mini", "small", "medium", "wide":
            self.init(rawValue: storedValue)
        default:
            return nil
        }
    }

    var colSpan: Int {
        switch self {
        case .mini:
            return 1
        case .small, .medium:
            return 2
        case .wide:
            return 4
        }
    }

    var rowSpan: Int {
        switch self {
        case .mini, .small:
            return 1
        case .medium, .wide:
            return 2
        }
    }

    var isSquare: Bool {
        switch self {
        case .mini, .medium:
            return true
        case .small, .wide:
            return false
        }
    }

    var displayOrder: Int {
        switch self {
        case .mini:
            return 0
        case .small:
            return 1
        case .medium:
            return 2
        case .wide:
            return 3
        }
    }

    var next: ProjectTileSize {
        switch self {
        case .mini:
            return .small
        case .small:
            return .medium
        case .medium:
            return .wide
        case .wide:
            return .mini
        }
    }
}
