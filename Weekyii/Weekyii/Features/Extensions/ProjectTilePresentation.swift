import CoreGraphics
import Foundation

enum ProjectTileLivePanel: Hashable {
    case progress
    case metrics
    case nextTask
}

enum ProjectTileLayoutStyle: Equatable {
    case badge
    case compactSummary
    case dashboard
    case timeline
}

enum ProjectTileSecondaryContent: Equatable {
    case none
    case microStatsStrip
    case metricCards
    case compactPills
}

struct ProjectTileContentInsets: Equatable {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat
}

struct ProjectTilePresentation: Equatable {
    let layoutStyle: ProjectTileLayoutStyle
    let showsTitle: Bool
    let titleLineLimit: Int
    let showsStatusChip: Bool
    let showsNextTaskDate: Bool
    let secondaryContent: ProjectTileSecondaryContent
    let contentInsets: ProjectTileContentInsets
    let livePanel: ProjectTileLivePanel

    init(snapshot: ProjectTileSnapshot, size: ProjectTileSize, isEditing: Bool, liveTick _: Int) {
        let hasNextTask = snapshot.hasUpcomingTask

        switch size {
        case .mini:
            layoutStyle = .badge
            showsTitle = !isEditing
            titleLineLimit = 1
            showsStatusChip = false
            showsNextTaskDate = false
            secondaryContent = .none
            contentInsets = ProjectTileContentInsets(
                top: 6,
                leading: 6,
                bottom: isEditing ? 14 : 6,
                trailing: isEditing ? 16 : 6
            )
        case .small:
            layoutStyle = .compactSummary
            showsTitle = true
            titleLineLimit = 1
            showsStatusChip = false
            showsNextTaskDate = false
            secondaryContent = isEditing ? .none : .microStatsStrip
            contentInsets = ProjectTileContentInsets(
                top: 6,
                leading: 8,
                bottom: isEditing ? 14 : 6,
                trailing: isEditing ? 20 : 8
            )
        case .medium:
            layoutStyle = .dashboard
            showsTitle = true
            titleLineLimit = isEditing ? 1 : 2
            showsStatusChip = true
            showsNextTaskDate = !isEditing
            secondaryContent = isEditing ? .compactPills : .metricCards
            contentInsets = ProjectTileContentInsets(
                top: 12,
                leading: 12,
                bottom: isEditing ? 22 : 14,
                trailing: isEditing ? 30 : 14
            )
        case .wide:
            layoutStyle = .timeline
            showsTitle = true
            titleLineLimit = 1
            showsStatusChip = true
            showsNextTaskDate = !isEditing
            secondaryContent = .compactPills
            contentInsets = ProjectTileContentInsets(
                top: 10,
                leading: 10,
                bottom: isEditing ? 18 : 12,
                trailing: isEditing ? 28 : 10
            )
        }

        livePanel = Self.preferredPanel(
            for: size,
            hasNextTask: hasNextTask,
            totalCount: snapshot.totalCount,
            remainingCount: snapshot.remainingCount
        )
    }

    private static func preferredPanel(
        for size: ProjectTileSize,
        hasNextTask: Bool,
        totalCount: Int,
        remainingCount: Int
    ) -> ProjectTileLivePanel {
        switch size {
        case .mini:
            return remainingCount > 0 ? .metrics : (totalCount > 0 ? .progress : .metrics)
        case .small:
            return totalCount > 0 ? .progress : .metrics
        case .medium:
            return totalCount > 0 ? .progress : (hasNextTask ? .nextTask : .metrics)
        case .wide:
            return hasNextTask ? .nextTask : (totalCount > 0 ? .progress : .metrics)
        }
    }
}

private extension ProjectTileSnapshot {
    var hasUpcomingTask: Bool {
        guard let nextTaskTitle else { return false }
        return !nextTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
