import CoreGraphics
import Foundation

enum ProjectTileLivePanel: Hashable {
    case progress
    case metrics
    case nextTask
}

struct ProjectTileContentInsets: Equatable {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat
}

struct ProjectTilePresentation: Equatable {
    let titleLineLimit: Int
    let showsStatusChip: Bool
    let showsNextTaskDate: Bool
    let contentInsets: ProjectTileContentInsets
    let livePanel: ProjectTileLivePanel

    init(snapshot: ProjectTileSnapshot, size: ProjectTileSize, isEditing: Bool, liveTick: Int) {
        let hasNextTask = snapshot.hasUpcomingTask

        switch size {
        case .mini:
            titleLineLimit = 1
            showsStatusChip = false
            showsNextTaskDate = false
            contentInsets = ProjectTileContentInsets(
                top: 6,
                leading: 6,
                bottom: isEditing ? 14 : 6,
                trailing: isEditing ? 16 : 6
            )
        case .small:
            titleLineLimit = 1
            showsStatusChip = false
            showsNextTaskDate = false
            contentInsets = ProjectTileContentInsets(
                top: 6,
                leading: 8,
                bottom: isEditing ? 14 : 6,
                trailing: isEditing ? 20 : 8
            )
        case .medium:
            titleLineLimit = 2
            showsStatusChip = true
            showsNextTaskDate = true
            contentInsets = ProjectTileContentInsets(
                top: 12,
                leading: 12,
                bottom: isEditing ? 22 : 14,
                trailing: isEditing ? 30 : 14
            )
        case .wide:
            titleLineLimit = 1
            showsStatusChip = !isEditing
            showsNextTaskDate = true
            contentInsets = ProjectTileContentInsets(
                top: 10,
                leading: 10,
                bottom: isEditing ? 18 : 12,
                trailing: isEditing ? 28 : 10
            )
        }

        let panels = Self.panelSequence(for: size, hasNextTask: hasNextTask, totalCount: snapshot.totalCount)
        let index = (Self.stableSeed(for: snapshot.projectID) + max(liveTick, 0)) % panels.count
        livePanel = panels[index]
    }

    private static func panelSequence(for size: ProjectTileSize, hasNextTask: Bool, totalCount: Int) -> [ProjectTileLivePanel] {
        switch size {
        case .mini:
            return totalCount == 0 ? [.metrics] : [.progress, .metrics]
        case .small:
            return totalCount == 0 ? [.metrics] : [.progress, .metrics]
        case .medium:
            return hasNextTask ? [.nextTask, .progress] : [.progress, .metrics]
        case .wide:
            return hasNextTask ? [.nextTask, .progress] : [.progress, .metrics]
        }
    }

    private static func stableSeed(for id: UUID) -> Int {
        withUnsafeBytes(of: id.uuid) { rawBuffer in
            rawBuffer.reduce(0) { partialResult, byte in
                (partialResult * 31 + Int(byte)) & 0x7fffffff
            }
        }
    }
}

private extension ProjectTileSnapshot {
    var hasUpcomingTask: Bool {
        guard let nextTaskTitle else { return false }
        return !nextTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
