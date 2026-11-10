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

    /// Tiers are keyed off the *rendered* size of the tree rather than the raw
    /// zoom multiplier. A compact card fits the whole week at roughly 0.27x, so
    /// a raw multiplier would still report `overview` long after the content has
    /// grown past the point where groups and tasks can be told apart.
    ///
    /// The thresholds themselves come from the node geometry: a tier is shown
    /// once its nodes stop overlapping. That keeps the gate honest when a card
    /// size changes, and it is what lets the task tier arrive at ~0.86x instead
    /// of the 2.2x a three-wide task grid demanded.
    init(effectiveScale: CGFloat) {
        if effectiveScale >= WeekTopologyMetrics.taskClearEffectiveScale {
            self = .tasks
        } else if effectiveScale >= WeekTopologyMetrics.groupClearEffectiveScale {
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
    let taskTypeIdRaw: String
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

    /// The node ids hanging off one result band, in the order the layout stacks
    /// them. Shared with the canvas so the two cannot disagree about which nodes
    /// a band holds.
    func nodeIDs(for kind: WeekTopologyResultKind) -> [String] {
        switch kind {
        case .remaining: return remainingTasks.map(\.id)
        case .completed: return completedTasks.map(\.id)
        case .forgotten: return forgottenNodes.map(\.id)
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
    var hasContent: Bool { totalCount > 0 }
    var rootNodeID: String { "week:\(weekID)" }

    /// Whether there is anything to draw, answered straight off the model.
    ///
    /// `hasContent` on a built snapshot says the same thing, but getting there
    /// sorts and maps every task in the week. The overview gates its topology
    /// card on this during `body`, so the cheap probe is what it should call.
    ///
    /// Equivalent to `totalCount > 0`: every `TaskZone` case is covered by either
    /// the remaining set (draft/focus/frozen) or the completed set, so any task at
    /// all shows up in the count.
    static func hasContent(in week: WeekModel) -> Bool {
        week.days.contains { !$0.tasks.isEmpty || $0.expiredCount > 0 }
    }

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
                    taskTypeIdRaw: task.taskTypeIdRaw,
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
                taskTypeIdRaw: task.taskTypeIdRaw,
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

/// Shared geometry constants for the topology tree.
///
/// Card sizes live here rather than in the view so the layout can reason about
/// the space a node actually occupies. Keeping both sides on one set of numbers
/// is what stops a band from being spaced tighter than the cards stacked in it.
enum WeekTopologyMetrics {
    static let horizontalInset: CGFloat = 100
    static let daySpacing: CGFloat = 152
    static let rootY: CGFloat = 24
    // Keep a deliberate vertical beat between the week root and the day layer.
    // The overview is intentionally compact, but the two levels should still
    // read as a tree instead of one crowded row.
    static let dayY: CGFloat = 212
    static let groupCardWidth: CGFloat = 70
    static let groupCardHeight: CGFloat = 38
    /// Distance from the day layer to the first group band.
    ///
    /// This is a *vertical* clearance budget, not a taste value: the day card
    /// (68pt) and a group card (38pt) keep their point size while this distance
    /// scales, so the two only stop overlapping once
    /// `groupTopOffset * effectiveScale >= 34 + 19 + gap`. At 68 that point is
    /// 0.87x, which is also where the task tier begins — the group tier would
    /// never be reachable on its own. 80 pulls it down to 0.74x and keeps the
    /// tiers distinguishable.
    static let groupTopOffset: CGFloat = 80
    static let taskCardWidth: CGFloat = 84
    static let taskCardHeight: CGFloat = 30
    static let forgottenCardWidth: CGFloat = 68
    static let forgottenCardHeight: CGFloat = 30
    /// Tasks hang off their day in a single column.
    ///
    /// A three-wide grid was tried and abandoned: a day's row then spans
    /// `2 * taskColumnSpacing + taskCardWidth = 276`, which is 1.8x the day pitch
    /// (`daySpacing = 152`). Adjacent days' outer columns therefore land 40pt
    /// apart with 84pt cards — a 44pt overlap that no amount of band spacing can
    /// remove. One column keeps a day's row at 84pt, well inside its own pitch, so
    /// neighbouring days can never collide at any zoom.
    static let taskColumnCount = 1
    static let taskColumnSpacing: CGFloat = 96
    /// Vertical rhythm of a day's subtree.
    ///
    /// These are a clearance budget, not taste, and the budget runs in two
    /// directions at once. A card keeps its point size while the distance between
    /// two centres scales, so the stack has a *lower* bound on the scale it can
    /// be drawn at; and the whole stack has to fit the compact canvas, which is an
    /// *upper* bound on the scale `focus(day:)` can frame it at. The tier only
    /// works while the lower bound stays under the upper one:
    ///
    ///     gate(46 -> 48) <= 196 / (49 + groupTopOffset + firstRow + spacing)
    ///
    /// Spacing out the rows raises the subtree height but drops the gate faster,
    /// so widening the gap is what buys room for the connectors — tightening the
    /// rows instead would push the gate past the canvas and make a focused day
    /// clip its own last card.
    static let taskVerticalSpacing: CGFloat = 48
    static let taskFirstRowOffset: CGFloat = 52
    /// Clearance kept between the last task row of a band and the next group.
    static let bandGap: CGFloat = 24
    static let bottomInset: CGFloat = 72

    /// The compact day node is the narrowest card in the tree and the one the
    /// overview layer has to fit seven of, so its width is what decides whether
    /// the overview reads as a row of days or as one continuous band.
    ///
    /// 36 rather than 34: at 34 a day carrying a count ("14日 · 2") wraps onto a
    /// second line and collides with its own badge. The view was already drawn at
    /// 36x30 — these two were the stale numbers, which is exactly how a card ends
    /// up outside the box the layout reserved for it.
    static let dayNodeCompactWidth: CGFloat = 36
    static let dayNodeCompactHeight: CGFloat = 30
    /// The selected day expands to its full card; the frame is what the tree
    /// layout has to reserve when a day is focused.
    static let dayNodeExpandedWidth: CGFloat = 88
    static let dayNodeExpandedHeight: CGFloat = 68
    /// The week root card. Its height is fixed in points while its y position
    /// scales, so it is what decides how much headroom the canvas needs.
    static let rootNodeCompactWidth: CGFloat = 58
    static let rootNodeCompactHeight: CGFloat = 28
    static let rootNodeExpandedWidth: CGFloat = 82
    static let rootNodeExpandedHeight: CGFloat = 46

    /// Horizontal breathing room reserved at the edges of the canvas.
    static let canvasHorizontalPadding: CGFloat = 24
    /// Vertical breathing room reserved above the root card.
    static let canvasVerticalPadding: CGFloat = 12
    /// Margin kept around a focused day's subtree when it is framed into the canvas.
    static let focusPadding: CGFloat = 12
    /// Clearance left between a connector and the card it points at.
    ///
    /// Kept small on purpose: it is charged twice per connector, and the compact
    /// card has little vertical slack to spare.
    static let edgeGap: CGFloat = 3
    /// The shortest connector segment still worth drawing.
    ///
    /// Below this the edge reads as a stray dot rather than a link, so the tier
    /// gate treats "no room for this" as "no room at all".
    static let minimumConnectorLength: CGFloat = 4
    /// Clearance two stacked cards need before the tier that holds them is drawn.
    ///
    /// Derived rather than picked, and that is the whole point: the gate and the
    /// connector are asking about the same gap. A gate that only cleared the
    /// *cards* (`upper/2 + lower/2 + gap`) left less room than the connector
    /// needed (`upper/2 + lower/2 + 2 * edgeGap + length`), so at exactly the
    /// scale where a tier became readable every one of its edges trimmed itself
    /// down to `nil` — the tree came apart into loose cards right at the moment
    /// it was supposed to start making sense. Folding the connector's own
    /// clearance into the gate makes the two conditions identical by
    /// construction, so a drawn tier always has drawable edges.
    static var minimumNodeGap: CGFloat {
        2 * edgeGap + minimumConnectorLength
    }

    /// Headroom above the root card.
    ///
    /// Deliberately uses the *expanded* root height regardless of the current
    /// tier: the inset is a property of the transform, and a flat 18 clipped the
    /// top of the root card at the overview scale.
    static var verticalInset: CGFloat {
        rootNodeExpandedHeight / 2 + canvasVerticalPadding
    }

    static func taskRows(for count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (count + taskColumnCount - 1) / taskColumnCount
    }

    /// The smallest horizontal centre-to-centre distance between any two task
    /// cards in the tree — either two columns of the same day, or the outermost
    /// column of two neighbouring days, whichever is tighter.
    static var taskPitch: CGFloat {
        guard taskColumnCount > 1 else { return daySpacing }
        return min(
            taskColumnSpacing,
            abs(daySpacing - CGFloat(taskColumnCount - 1) * taskColumnSpacing)
        )
    }

    /// The scale at which two vertically stacked cards stop touching *and* leave
    /// room for the connector between them.
    ///
    /// Card heights are fixed in points while the distance between their centres
    /// scales, so a stack has a hard lower bound on the scale it can be drawn at.
    /// The budget it is measured against is `minimumNodeGap`, which already
    /// carries the connector's `2 * edgeGap`, so the two conditions are one.
    static func verticalClearEffectiveScale(
        upperHeight: CGFloat,
        lowerHeight: CGFloat,
        centerDistance: CGFloat
    ) -> CGFloat {
        (upperHeight / 2 + lowerHeight / 2 + minimumNodeGap) / max(centerDistance, 1)
    }

    /// The scale at which two horizontally neighbouring cards stop touching.
    static func horizontalClearEffectiveScale(
        cardWidth: CGFloat,
        centerDistance: CGFloat
    ) -> CGFloat {
        (cardWidth + minimumNodeGap) / max(centerDistance, 1)
    }

    /// Node sizes are fixed in points while the transform only scales positions,
    /// so "is this tier worth drawing" is really "would its nodes collide".
    /// Deriving the gate from the same constants that place the nodes keeps the
    /// two in sync — a hand-picked multiplier goes stale the moment a card
    /// width changes, which is exactly how the task tier became unreachable.
    ///
    /// Both axes count. An earlier version only checked the horizontal pitch
    /// between neighbouring days, which let the day card and its own group card
    /// overlap by 12pt throughout the whole group tier.
    static var dayToGroupClearEffectiveScale: CGFloat {
        verticalClearEffectiveScale(
            upperHeight: dayNodeExpandedHeight,
            lowerHeight: groupCardHeight,
            centerDistance: groupTopOffset
        )
    }

    static var groupToTaskClearEffectiveScale: CGFloat {
        verticalClearEffectiveScale(
            upperHeight: groupCardHeight,
            lowerHeight: taskCardHeight,
            centerDistance: taskFirstRowOffset
        )
    }

    static var taskToTaskClearEffectiveScale: CGFloat {
        verticalClearEffectiveScale(
            upperHeight: taskCardHeight,
            lowerHeight: taskCardHeight,
            centerDistance: taskVerticalSpacing
        )
    }

    static var groupClearEffectiveScale: CGFloat {
        max(
            horizontalClearEffectiveScale(cardWidth: groupCardWidth, centerDistance: daySpacing),
            dayToGroupClearEffectiveScale
        )
    }

    static var taskClearEffectiveScale: CGFloat {
        max(
            horizontalClearEffectiveScale(cardWidth: taskCardWidth, centerDistance: taskPitch),
            taskToTaskClearEffectiveScale,
            groupToTaskClearEffectiveScale,
            dayToGroupClearEffectiveScale
        )
    }

    /// How far the whole tree is scaled down to fit the canvas.
    static func fitScale(viewportWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        min(1, max(0.1, (viewportWidth - canvasHorizontalPadding) / max(contentWidth, 1)))
    }

    static func contentWidth(dayCount: Int) -> CGFloat {
        max(
            horizontalInset * 2,
            horizontalInset * 2 + CGFloat(max(dayCount - 1, 0)) * daySpacing
        )
    }
}

struct WeekTopologyLayout: Equatable {
    let positions: [String: CGPoint]
    let contentBounds: CGRect
    let rootNodeID: String
    let dayIDs: [String]

    init(snapshot: WeekTopologySnapshot) {
        let horizontalInset = WeekTopologyMetrics.horizontalInset
        let daySpacing = WeekTopologyMetrics.daySpacing
        let rootY = WeekTopologyMetrics.rootY
        let dayY = WeekTopologyMetrics.dayY
        let taskVerticalSpacing = WeekTopologyMetrics.taskVerticalSpacing

        let width = WeekTopologyMetrics.contentWidth(dayCount: snapshot.days.count)

        // Each result band is sized by the tallest stack of task rows any single
        // day needs. Fixed band offsets used to let a second row of tasks land on
        // top of the next band's group node.
        var groupY: [WeekTopologyResultKind: CGFloat] = [:]
        var bandCursor = dayY + WeekTopologyMetrics.groupTopOffset
        for kind in WeekTopologyResultKind.allCases {
            let rows = WeekTopologyMetrics.taskRows(
                for: snapshot.days.map { $0.count(for: kind) }.max() ?? 0
            )
            guard rows > 0 else { continue }
            groupY[kind] = bandCursor
            let lastTaskY = bandCursor
                + WeekTopologyMetrics.taskFirstRowOffset
                + CGFloat(rows - 1) * taskVerticalSpacing
            bandCursor = lastTaskY
                + WeekTopologyMetrics.taskCardHeight / 2
                + WeekTopologyMetrics.bandGap
                + WeekTopologyMetrics.groupCardHeight / 2
        }

        var positions: [String: CGPoint] = [:]
        var maximumY = rootY

        positions[snapshot.rootNodeID] = CGPoint(x: width / 2, y: rootY)

        for (dayIndex, day) in snapshot.days.enumerated() {
            let x = horizontalInset + CGFloat(dayIndex) * daySpacing
            positions[day.id] = CGPoint(x: x, y: dayY)
            maximumY = max(maximumY, dayY)

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
                    let column = taskIndex % WeekTopologyMetrics.taskColumnCount
                    let row = taskIndex / WeekTopologyMetrics.taskColumnCount
                    let spread = CGFloat(column - WeekTopologyMetrics.taskColumnCount / 2)
                        * WeekTopologyMetrics.taskColumnSpacing
                    let y = baseY
                        + WeekTopologyMetrics.taskFirstRowOffset
                        + CGFloat(row) * taskVerticalSpacing
                    positions[nodeID] = CGPoint(x: x + spread, y: y)
                    maximumY = max(maximumY, y)
                }
            }
        }

        self.positions = positions
        self.rootNodeID = snapshot.rootNodeID
        self.dayIDs = snapshot.days.map(\.id)
        contentBounds = CGRect(x: 0, y: 0, width: width, height: maximumY + WeekTopologyMetrics.bottomInset)
    }
}

/// The trunk and branch rail that carry the week root down to the day layer.
///
/// Exposed as data so "the rail reaches every day column" is something a test
/// can assert, instead of arithmetic buried inside the canvas drawing.
struct WeekTopologyRootRail: Equatable {
    let trunkX: CGFloat
    let trunkTopY: CGFloat
    let trunkBottomY: CGFloat
    let railY: CGFloat
    let railStartX: CGFloat
    let railEndX: CGFloat
}

/// Where a connector between two vertically stacked cards starts and ends.
///
/// Cards keep their point size while their centres scale with zoom, so the
/// clearance is a constant in *screen* space rather than a content-space inset.
///
/// Exposed as a type instead of inline canvas arithmetic so "a connector never
/// overlaps the card it points at" is something a test can assert. Drawing
/// centre to centre ran every edge straight through its cards — with a single
/// task column per day, an entire subtree collapsed into one skewer threading
/// through all of its own cards.
struct WeekTopologyEdgeSpan: Equatable {
    let startY: CGFloat
    let endY: CGFloat
    /// The height at which the elbow jogs sideways, centred in the gap.
    let jogY: CGFloat

    /// `nil` when the two cards are closer than their clearances allow, in which
    /// case there is no room for a connector and the edge should be skipped.
    init?(
        topCenterY: CGFloat,
        bottomCenterY: CGFloat,
        topClearance: CGFloat,
        bottomClearance: CGFloat
    ) {
        let top = topCenterY + topClearance
        let bottom = bottomCenterY - bottomClearance
        guard bottom > top else { return nil }
        startY = top
        endY = bottom
        jogY = (top + bottom) / 2
    }

    static func clearance(cardHeight: CGFloat) -> CGFloat {
        cardHeight / 2 + WeekTopologyMetrics.edgeGap
    }
}

extension WeekTopologyLayout {
    /// One connector joining two cards that sit next to each other in a day's
    /// column, with the card heights the canvas will draw.
    ///
    /// Heights travel with the link because a link is the only place that knows
    /// both of its endpoints *and* which tier is being drawn, and the trim at each
    /// end depends on both.
    struct SubtreeLink: Equatable {
        let parentID: String
        let parentHeight: CGFloat
        let childID: String
        let childHeight: CGFloat
        let kind: WeekTopologyResultKind
    }

    /// The connectors inside a day's subtree, as a chain down its single column.
    ///
    /// The layout stacks a whole subtree in one column at the day's x, so every
    /// node in it shares an x and the subtree is really a vertical *sequence*.
    /// The connector therefore has to be a chain through that sequence — one
    /// segment per neighbouring pair — and not a fan from each parent to each of
    /// its children.
    ///
    /// Fanning is what put a line back through a card. `WeekTopologyEdgeSpan`
    /// only guarantees clearance at a segment's *two endpoints*, so a
    /// group→task edge aimed at the second task of a band ran straight through
    /// the first one, and a day→band edge aimed at the second band ran through
    /// the first. Chaining removes the possibility rather than compensating for
    /// it: every segment now spans exactly one tier gate's worth of gap, and
    /// those are precisely the gaps `taskClearEffectiveScale` already enforces.
    func subtreeLinks(
        for day: WeekTopologyDaySnapshot,
        semanticLevel: WeekTopologySemanticLevel
    ) -> [SubtreeLink] {
        // A connector may only point at a card that is rendered at the current
        // semantic level. In the groups tier, task cards are intentionally
        // hidden; retaining their links produced dangling strokes under each
        // visible group card.
        guard semanticLevel != .overview else { return [] }

        let dayHeight = semanticLevel == .overview
            ? WeekTopologyMetrics.dayNodeCompactHeight
            : WeekTopologyMetrics.dayNodeExpandedHeight
        let groupHeight = WeekTopologyMetrics.groupCardHeight
        let taskHeight = WeekTopologyMetrics.taskCardHeight
        let forgottenHeight = WeekTopologyMetrics.forgottenCardHeight

        // Top to bottom. `allCases` order is the band order the layout uses, and
        // within a band the layout walks the nodes in order too, so this matches
        // the y positions without having to sort.
        var column: [(id: String, height: CGFloat, kind: WeekTopologyResultKind?)] = [
            (day.id, dayHeight, nil)
        ]
        for kind in WeekTopologyResultKind.allCases where day.count(for: kind) > 0 {
            column.append((day.groupID(for: kind), groupHeight, kind))
            guard semanticLevel == .tasks else { continue }

            let childHeight = kind == .forgotten ? forgottenHeight : taskHeight
            for nodeID in day.nodeIDs(for: kind) {
                column.append((nodeID, childHeight, kind))
            }
        }

        return zip(column, column.dropFirst()).compactMap { upper, lower in
            guard let kind = lower.kind else { return nil }
            return SubtreeLink(
                parentID: upper.id,
                parentHeight: upper.height,
                childID: lower.id,
                childHeight: lower.height,
                kind: kind
            )
        }
    }

    var rootRail: WeekTopologyRootRail? {
        guard let root = positions[rootNodeID],
              let first = dayIDs.first.flatMap({ positions[$0] }),
              let last = dayIDs.last.flatMap({ positions[$0] }) else {
            return nil
        }

        let branchY = (root.y + first.y) / 2
        return WeekTopologyRootRail(
            trunkX: root.x,
            trunkTopY: root.y,
            trunkBottomY: branchY,
            railY: branchY,
            railStartX: min(root.x, first.x),
            railEndX: max(root.x, last.x)
        )
    }

    /// The content-space box covering a day node and everything hanging off it.
    ///
    /// `focus(day:)` frames this box rather than the day node on its own.
    /// Centring just the day node put its own group and task rows ~208pt below
    /// the node at the scale the task tier needs — further than the compact
    /// card's whole canvas is tall, so tapping a day appeared to reveal nothing.
    ///
    /// Each node contributes its own card size. Inflating the whole box by the
    /// largest node instead made it ~19pt taller than the cards actually need,
    /// which was enough to push a framed day back over the canvas edge.
    func subtreeBounds(for day: WeekTopologyDaySnapshot) -> CGRect? {
        renderedSubtreeBounds(for: day, effectiveScale: 1)
    }

    /// Returns the subtree's real rendered bounds for an effective scale.
    ///
    /// The topology transform scales node centres, but cards themselves retain
    /// their point sizes. Scaling a previously-unioned content box would shrink
    /// those card extents too and could claim a focused subtree fit when its
    /// visible cards still clipped at the canvas edge.
    func renderedSubtreeBounds(
        for day: WeekTopologyDaySnapshot,
        effectiveScale: CGFloat
    ) -> CGRect? {
        guard let dayPoint = positions[day.id] else { return nil }

        var box = CGRect(
            x: dayPoint.x * effectiveScale - WeekTopologyMetrics.dayNodeExpandedWidth / 2,
            y: dayPoint.y * effectiveScale - WeekTopologyMetrics.dayNodeExpandedHeight / 2,
            width: WeekTopologyMetrics.dayNodeExpandedWidth,
            height: WeekTopologyMetrics.dayNodeExpandedHeight
        )

        func union(_ nodeID: String, width: CGFloat, height: CGFloat) {
            guard let point = positions[nodeID] else { return }
            box = box.union(
                CGRect(
                    x: point.x * effectiveScale - width / 2,
                    y: point.y * effectiveScale - height / 2,
                    width: width,
                    height: height
                )
            )
        }

        for kind in WeekTopologyResultKind.allCases where day.count(for: kind) > 0 {
            union(
                day.groupID(for: kind),
                width: WeekTopologyMetrics.groupCardWidth,
                height: WeekTopologyMetrics.groupCardHeight
            )
        }
        for task in day.remainingTasks + day.completedTasks {
            union(
                task.id,
                width: WeekTopologyMetrics.taskCardWidth,
                height: WeekTopologyMetrics.taskCardHeight
            )
        }
        for forgotten in day.forgottenNodes {
            union(
                forgotten.id,
                width: WeekTopologyMetrics.forgottenCardWidth,
                height: WeekTopologyMetrics.forgottenCardHeight
            )
        }

        return box
    }

    /// Finds the largest rendered scale that keeps a day's fixed-size cards
    /// inside the requested canvas. The bound is monotonic because every node
    /// centre is scaled by the same positive factor while card sizes stay fixed.
    func largestEffectiveScaleFittingSubtree(
        for day: WeekTopologyDaySnapshot,
        canvasSize: CGSize,
        maximumEffectiveScale: CGFloat
    ) -> CGFloat? {
        let available = CGSize(
            width: max(canvasSize.width - WeekTopologyMetrics.focusPadding * 2, 1),
            height: max(canvasSize.height - WeekTopologyMetrics.focusPadding * 2, 1)
        )

        func fits(_ scale: CGFloat) -> Bool {
            guard let bounds = renderedSubtreeBounds(for: day, effectiveScale: scale) else {
                return false
            }
            return bounds.width <= available.width && bounds.height <= available.height
        }

        guard renderedSubtreeBounds(for: day, effectiveScale: 0) != nil else { return nil }
        guard !fits(maximumEffectiveScale) else { return maximumEffectiveScale }

        var lower: CGFloat = 0
        var upper = maximumEffectiveScale
        for _ in 0..<32 {
            let candidate = (lower + upper) / 2
            if fits(candidate) {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        return lower
    }
}

struct WeekTopologyViewportState: Equatable {
    static let minimumScale: CGFloat = 1
    /// The zoom ceiling is expressed as a *rendered* scale rather than a raw
    /// multiplier. Node cards keep their point size while the transform only
    /// spreads their positions, so past roughly 1.8x the extra zoom buys
    /// whitespace and nothing else. A flat multiplier would mean very different
    /// things on the compact card (fit ~0.28) and in fullscreen (fit ~0.39).
    static let maximumEffectiveScale: CGFloat = 1.8

    /// The smallest rendered scale at which a day's tasks stop overlapping —
    /// the scale `focus(day:)` has to reach before the task layer is worth
    /// showing.
    static var tasksReachEffectiveScale: CGFloat {
        WeekTopologyMetrics.taskClearEffectiveScale
    }

    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var selectedNodeID: String?

    /// The canvas fit ratio is intentionally *not* stored here: the card and the
    /// fullscreen cover share one viewport, and their canvas widths differ.
    func effectiveScale(fitScale: CGFloat) -> CGFloat {
        fitScale * scale
    }

    func semanticLevel(fitScale: CGFloat) -> WeekTopologySemanticLevel {
        WeekTopologySemanticLevel(effectiveScale: effectiveScale(fitScale: fitScale))
    }

    func clampedScale(_ proposedScale: CGFloat, fitScale: CGFloat) -> CGFloat {
        let ceiling = max(
            Self.minimumScale,
            Self.maximumEffectiveScale / max(fitScale, 0.1)
        )
        return min(max(proposedScale, Self.minimumScale), ceiling)
    }

    mutating func applyScale(_ proposedScale: CGFloat, fitScale: CGFloat) {
        scale = clampedScale(proposedScale, fitScale: fitScale)
    }

    /// Translates "frame this day's subtree" into a rendered scale.
    ///
    /// Two limits decide it and the lower one wins: the subtree should fit the
    /// canvas when it reasonably can, but the day's own nodes must have stopped
    /// overlapping first — otherwise framing zooms past the point where the task
    /// layer is drawable and a tap appears to reveal nothing.
    static func focusEffectiveScale(
        subtreeSize: CGSize,
        canvasSize: CGSize
    ) -> CGFloat {
        let available = CGSize(
            width: max(canvasSize.width - WeekTopologyMetrics.focusPadding * 2, 1),
            height: max(canvasSize.height - WeekTopologyMetrics.focusPadding * 2, 1)
        )
        let fitted = min(
            available.width / max(subtreeSize.width, 1),
            available.height / max(subtreeSize.height, 1)
        )
        return min(
            max(fitted, WeekTopologyMetrics.taskClearEffectiveScale),
            maximumEffectiveScale
        )
    }

    mutating func reset() {
        scale = 1
        offset = .zero
        selectedNodeID = nil
    }
}
