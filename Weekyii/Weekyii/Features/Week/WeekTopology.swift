import CoreGraphics
import Foundation

enum WeekTopologyResultKind: String, CaseIterable, Hashable {
    case remaining
    case completed
    case forgotten

    var title: String {
        switch self {
        case .remaining: return "剩余"
        case .completed: return "完成"
        case .forgotten: return "遗忘"
        }
    }
}

enum WeekTopologySemanticLevel: Equatable {
    case overview
    case groups
    case tasks

    init(scale: CGFloat) {
        if scale >= 2.2 {
            self = .tasks
        } else if scale >= 1.5 {
            self = .groups
        } else {
            self = .overview
        }
    }
}

struct WeekTopologyTaskNode: Identifiable, Equatable {
    let id: String
    let taskID: UUID
    let dayID: String
    let title: String
    let taskType: TaskType
    let zone: TaskZone
    let isFocus: Bool
}

struct WeekTopologyForgottenNode: Identifiable, Equatable {
    let id: String
    let dayID: String
    let title: String?
}

struct WeekTopologyDaySnapshot: Identifiable, Equatable {
    let id: String
    let dayID: String
    let date: Date
    let status: DayStatus
    let remainingTasks: [WeekTopologyTaskNode]
    let completedTasks: [WeekTopologyTaskNode]
    let forgottenNodes: [WeekTopologyForgottenNode]

    var remainingCount: Int { remainingTasks.count }
    var completedCount: Int { completedTasks.count }
    var forgottenCount: Int { forgottenNodes.count }
    var totalCount: Int { remainingCount + completedCount + forgottenCount }
    var focusTask: WeekTopologyTaskNode? { remainingTasks.first(where: \.isFocus) }

    func count(for kind: WeekTopologyResultKind) -> Int {
        switch kind {
        case .remaining: return remainingCount
        case .completed: return completedCount
        case .forgotten: return forgottenCount
        }
    }

    func groupID(for kind: WeekTopologyResultKind) -> String {
        "group:\(dayID):\(kind.rawValue)"
    }
}

struct WeekTopologySnapshot: Equatable {
    let weekID: String
    let days: [WeekTopologyDaySnapshot]

    init(week: WeekModel) {
        weekID = week.weekId
        days = week.days
            .sorted { $0.date < $1.date }
            .map { Self.makeDaySnapshot($0) }
    }

    var remainingCount: Int { days.reduce(0) { $0 + $1.remainingCount } }
    var completedCount: Int { days.reduce(0) { $0 + $1.completedCount } }
    var forgottenCount: Int { days.reduce(0) { $0 + $1.forgottenCount } }
    var totalCount: Int { remainingCount + completedCount + forgottenCount }

    var completionRate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    func day(id: String) -> WeekTopologyDaySnapshot? {
        days.first { $0.dayID == id || $0.id == id }
    }

    func task(id: String) -> WeekTopologyTaskNode? {
        for day in days {
            if let task = (day.remainingTasks + day.completedTasks).first(where: { $0.id == id }) {
                return task
            }
        }
        return nil
    }

    private static func makeDaySnapshot(_ day: DayModel) -> WeekTopologyDaySnapshot {
        let remaining = day.tasks
            .filter { $0.zone == .focus || $0.zone == .frozen || $0.zone == .draft }
            .sorted { remainingTaskOrder($0, $1) }
            .map { task in
                WeekTopologyTaskNode(
                    id: "task:\(task.id.uuidString)",
                    taskID: task.id,
                    dayID: day.dayId,
                    title: task.title,
                    taskType: task.taskType,
                    zone: task.zone,
                    isFocus: task.zone == .focus
                )
            }

        let completed = day.completedTasks.map { task in
            WeekTopologyTaskNode(
                id: "task:\(task.id.uuidString)",
                taskID: task.id,
                dayID: day.dayId,
                title: task.title,
                taskType: task.taskType,
                zone: task.zone,
                isFocus: false
            )
        }

        let forgotten = (0..<day.expiredCount).map { index in
            WeekTopologyForgottenNode(
                id: "forgotten:\(day.dayId):\(index)",
                dayID: day.dayId,
                title: nil
            )
        }

        return WeekTopologyDaySnapshot(
            id: "day:\(day.dayId)",
            dayID: day.dayId,
            date: day.date,
            status: day.status,
            remainingTasks: remaining,
            completedTasks: completed,
            forgottenNodes: forgotten
        )
    }

    private static func remainingTaskOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        let left = remainingSortKey(lhs)
        let right = remainingSortKey(rhs)
        if left != right { return left < right }
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func remainingSortKey(_ task: TaskItem) -> Int {
        switch task.zone {
        case .focus: return 0
        case .frozen: return 1
        case .draft: return 2
        case .complete: return 3
        }
    }
}

struct WeekTopologyLayout: Equatable {
    let positions: [String: CGPoint]
    let contentBounds: CGRect

    init(snapshot: WeekTopologySnapshot) {
        let horizontalInset: CGFloat = 72
        let daySpacing: CGFloat = 170
        let spineY: CGFloat = 82
        let groupY: [WeekTopologyResultKind: CGFloat] = [
            .remaining: 160,
            .completed: 238,
            .forgotten: 316
        ]
        let taskVerticalSpacing: CGFloat = 42

        var positions: [String: CGPoint] = [:]
        var maximumY = spineY

        for (dayIndex, day) in snapshot.days.enumerated() {
            let x = horizontalInset + CGFloat(dayIndex) * daySpacing
            positions[day.id] = CGPoint(x: x, y: spineY)

            for kind in WeekTopologyResultKind.allCases {
                guard day.count(for: kind) > 0, let baseY = groupY[kind] else { continue }
                positions[day.groupID(for: kind)] = CGPoint(x: x, y: baseY)
                maximumY = max(maximumY, baseY)

                let nodeIDs: [String]
                switch kind {
                case .remaining:
                    nodeIDs = day.remainingTasks.map(\.id)
                case .completed:
                    nodeIDs = day.completedTasks.map(\.id)
                case .forgotten:
                    nodeIDs = day.forgottenNodes.map(\.id)
                }

                for (taskIndex, nodeID) in nodeIDs.enumerated() {
                    let column = taskIndex % 3
                    let row = taskIndex / 3
                    let spread = CGFloat(column - 1) * 38
                    let y = baseY + 54 + CGFloat(row) * taskVerticalSpacing
                    positions[nodeID] = CGPoint(x: x + spread, y: y)
                    maximumY = max(maximumY, y)
                }
            }
        }

        let width = max(
            horizontalInset * 2,
            horizontalInset * 2 + CGFloat(max(snapshot.days.count - 1, 0)) * daySpacing
        )
        self.positions = positions
        contentBounds = CGRect(x: 0, y: 0, width: width, height: maximumY + 64)
    }
}

struct WeekTopologyViewportState: Equatable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 3.2

    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var selectedNodeID: String?

    var semanticLevel: WeekTopologySemanticLevel {
        WeekTopologySemanticLevel(scale: scale)
    }

    mutating func applyScale(_ proposedScale: CGFloat) {
        scale = min(max(proposedScale, Self.minimumScale), Self.maximumScale)
    }

    mutating func reset() {
        scale = 1
        offset = .zero
        selectedNodeID = nil
    }
}
