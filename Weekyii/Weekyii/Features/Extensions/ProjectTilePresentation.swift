import CoreGraphics
import Foundation

enum ProjectTileLivePanel: Hashable {
    case progress
    case metrics
    case nextTask
}

enum ProjectTileSecondaryContent: Equatable {
    case none
    case microStatsStrip
    case compactPills
}

struct ProjectTileContentInsets: Equatable {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat
}

struct ProjectTilePresentation: Equatable {
    let showsTitle: Bool
    let titleLineLimit: Int
    let showsStatusChip: Bool
    let showsNextTaskDate: Bool
    let secondaryContent: ProjectTileSecondaryContent
    let contentInsets: ProjectTileContentInsets
    let livePanel: ProjectTileLivePanel
    let showsProgressBar: Bool
    let showsTrendChart: Bool
    let trendChartMinHeight: CGFloat
    let trendChartMaxHeight: CGFloat
    let taskRowCount: Int
    let primaryNumberFontSize: CGFloat

    init(
        snapshot: ProjectTileSnapshot,
        size: ProjectTileSize,
        isEditing: Bool,
        liveTick _: Int,
        isCompactBoard: Bool = false
    ) {
        let hasNextTask = snapshot.hasUpcomingTask
        let hasTasks = snapshot.totalCount > 0

        switch size {
        case .mini:
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
            showsProgressBar = false
            showsTrendChart = false
            trendChartMinHeight = 0
            trendChartMaxHeight = 0
            taskRowCount = 0
            primaryNumberFontSize = 22
        case .small:
            showsTitle = true
            titleLineLimit = 1
            showsStatusChip = false
            showsNextTaskDate = false
            secondaryContent = (isEditing || isCompactBoard) ? .none : .microStatsStrip
            contentInsets = ProjectTileContentInsets(
                top: 6,
                leading: 8,
                bottom: isEditing ? 14 : 6,
                trailing: isEditing ? 20 : 8
            )
            showsProgressBar = hasTasks
            showsTrendChart = false
            trendChartMinHeight = 0
            trendChartMaxHeight = 0
            taskRowCount = 0
            primaryNumberFontSize = 22
        case .medium:
            showsTitle = true
            titleLineLimit = isEditing ? 1 : 2
            showsStatusChip = true
            showsNextTaskDate = !isEditing
            secondaryContent = isCompactBoard ? .none : .compactPills
            contentInsets = ProjectTileContentInsets(
                top: 12,
                leading: 12,
                bottom: isEditing ? 22 : 14,
                trailing: isEditing ? 30 : 14
            )
            showsProgressBar = hasTasks
            showsTrendChart = false
            trendChartMinHeight = 0
            trendChartMaxHeight = 0
            taskRowCount = 0
            primaryNumberFontSize = isCompactBoard ? 32 : 48
        case .wide:
            showsTitle = true
            titleLineLimit = 1
            showsStatusChip = true
            showsNextTaskDate = !isEditing
            // 窄板(≥5 列)下 wide 只放得下图表，次级行整体让位。
            secondaryContent = isCompactBoard ? .none : .compactPills
            contentInsets = ProjectTileContentInsets(
                top: 10,
                leading: 10,
                bottom: isEditing ? 18 : 12,
                trailing: isEditing ? 28 : 10
            )
            showsProgressBar = false
            showsTrendChart = hasTasks && !snapshot.trend.isEmpty
            trendChartMinHeight = isCompactBoard ? 20 : 26
            trendChartMaxHeight = isCompactBoard ? 30 : 44
            taskRowCount = (isEditing || isCompactBoard) ? 0 : 3
            primaryNumberFontSize = 34
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
