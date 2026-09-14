import SwiftUI
import UIKit

struct WeekTopologyView: View {
    let week: WeekModel
    @Binding var viewport: WeekTopologyViewportState
    @Binding var selectedDayID: String?
    let isFullScreen: Bool
    let onOpenFullScreen: () -> Void
    let onOpenTask: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.taskTypePresentationCatalog) private var taskTypeCatalog
    @State private var dragOrigin: CGSize?
    @State private var scaleOrigin: CGFloat?

    /// Resolving the snapshot sorts every day's tasks and building the layout
    /// walks the whole tree, so both are derived once per `body` evaluation and
    /// threaded down as parameters. Reading them back through computed
    /// properties re-ran that work on every access — a single pass through the
    /// inspector asked for six snapshots, and `rootButton` rebuilt the tree four
    /// more times while the canvas already held one.
    private var snapshot: WeekTopologySnapshot {
        WeekTopologySnapshot(week: week)
    }

    var body: some View {
        let snapshot = self.snapshot
        let layout = WeekTopologyLayout(snapshot: snapshot)

        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            if !isFullScreen {
                header
            }

            GeometryReader { proxy in
                topologyCanvas(size: proxy.size, snapshot: snapshot, layout: layout)
            }
            .frame(height: isFullScreen ? nil : 220)
            .frame(maxHeight: isFullScreen ? .infinity : 220)
            .background(Color.backgroundSecondary.opacity(0.72))
            .clipShape(.rect(cornerRadius: WeekRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.medium)
                    .stroke(Color.backgroundTertiary, lineWidth: 1)
            )

            inspector(snapshot: snapshot)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isFullScreen ? "weekTopologyFullscreen" : "weekTopologyView")
    }

    private var header: some View {
        HStack(spacing: WeekSpacing.sm) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(Color.weekyiiPrimary)
            Text("本周任务结构")
                .font(.titleSmall)
                .foregroundStyle(Color.textPrimary)

            Spacer(minLength: 0)

            topologyButton(
                icon: "scope",
                label: "全局视图",
                identifier: "weekTopologyResetButton"
            ) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
                    viewport.reset()
                    selectedDayID = nil
                }
            }

            topologyButton(
                icon: "arrow.up.left.and.arrow.down.right",
                label: "全屏查看",
                identifier: "weekTopologyFullscreenButton",
                action: onOpenFullScreen
            )
        }
    }

    private func topologyCanvas(
        size: CGSize,
        snapshot: WeekTopologySnapshot,
        layout: WeekTopologyLayout
    ) -> some View {
        let fitScale = WeekTopologyTransform.fitScale(
            viewportSize: size,
            contentBounds: layout.contentBounds
        )
        let semanticLevel = viewport.semanticLevel(fitScale: fitScale)
        let transform = WeekTopologyTransform(
            viewportSize: size,
            contentBounds: layout.contentBounds,
            viewport: viewport
        )

        return ZStack {
            Canvas { context, _ in
                drawConnections(
                    context: &context,
                    transform: transform,
                    snapshot: snapshot,
                    layout: layout,
                    semanticLevel: semanticLevel
                )
            }
            .allowsHitTesting(false)

            if let point = layout.positions[snapshot.rootNodeID] {
                rootButton(semanticLevel: semanticLevel, snapshot: snapshot)
                    .position(transform.point(point))
            }

            ForEach(Array(snapshot.days.enumerated()), id: \.element.id) { index, day in
                if let point = layout.positions[day.id] {
                    dayButton(
                        day,
                        index: index,
                        semanticLevel: semanticLevel,
                        transform: transform,
                        canvasSize: size,
                        layout: layout
                    )
                    .position(transform.point(point))
                }
            }

            if semanticLevel != .overview {
                ForEach(snapshot.days) { day in
                    ForEach(WeekTopologyResultKind.allCases, id: \.self) { kind in
                        if day.count(for: kind) > 0,
                           let point = layout.positions[day.groupID(for: kind)] {
                            groupButton(day: day, kind: kind)
                                .position(transform.point(point))
                        }
                    }
                }
            }

            if semanticLevel == .tasks {
                ForEach(snapshot.days) { day in
                    ForEach(day.remainingTasks + day.completedTasks) { task in
                        if let point = layout.positions[task.id] {
                            taskButton(task)
                                .position(transform.point(point))
                        }
                    }

                    ForEach(day.forgottenNodes) { forgotten in
                        if let point = layout.positions[forgotten.id] {
                            forgottenButton(forgotten)
                                .position(transform.point(point))
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(panGesture.simultaneously(with: zoomGesture(fitScale: fitScale)))
        .onChange(of: size) { oldSize, newSize in
            resetViewportAfterOrientationChange(from: oldSize, to: newSize)
        }
        .clipped()
    }

    /// A position offset belongs to one concrete canvas. Keeping the portrait
    /// offset after the fullscreen cover rotates to landscape can push the
    /// whole tree outside the newly widened canvas, leaving only connector
    /// fragments on screen. Reset only for an actual portrait/landscape swap;
    /// ordinary layout passes preserve the user's current pan and zoom.
    private func resetViewportAfterOrientationChange(from oldSize: CGSize, to newSize: CGSize) {
        guard isFullScreen,
              oldSize.width > 0,
              oldSize.height > 0,
              newSize.width > 0,
              newSize.height > 0,
              (oldSize.width > oldSize.height) != (newSize.width > newSize.height) else {
            return
        }
        viewport.reset()
        selectedDayID = nil
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = viewport.offset
                }
                guard let dragOrigin else { return }
                viewport.offset = CGSize(
                    width: dragOrigin.width + value.translation.width,
                    height: dragOrigin.height + value.translation.height
                )
            }
            .onEnded { _ in
                dragOrigin = nil
            }
    }

    private func zoomGesture(fitScale: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if scaleOrigin == nil {
                    scaleOrigin = viewport.scale
                }
                viewport.applyScale((scaleOrigin ?? viewport.scale) * value, fitScale: fitScale)
            }
            .onEnded { _ in
                scaleOrigin = nil
            }
    }

    private func drawConnections(
        context: inout GraphicsContext,
        transform: WeekTopologyTransform,
        snapshot: WeekTopologySnapshot,
        layout: WeekTopologyLayout,
        semanticLevel: WeekTopologySemanticLevel
    ) {
        guard let rail = layout.rootRail else { return }

        // A single trunk and branch rail makes the hierarchy legible at a glance.
        // Drawing seven independent root-to-day elbows made the top layer look
        // like a tight bundle of wires in the compact overview.
        let railColor = Color.textPrimary.opacity(0.28)
        let railStyle = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)

        // Cards keep their point size while positions scale, so clearance is a
        // constant in screen space, and the cards themselves change size between
        // the compact overview and the expanded tiers.
        let isOverview = semanticLevel == .overview
        let rootHalf = (isOverview
            ? WeekTopologyMetrics.rootNodeCompactHeight
            : WeekTopologyMetrics.rootNodeExpandedHeight) / 2
        let dayHalf = (isOverview
            ? WeekTopologyMetrics.dayNodeCompactHeight
            : WeekTopologyMetrics.dayNodeExpandedHeight) / 2
        let edgeGap = WeekTopologyMetrics.edgeGap

        // The trunk leaves the root card's border rather than its centre.
        let rootPoint = transform.point(CGPoint(x: rail.trunkX, y: rail.trunkTopY))
        let railJunction = transform.point(CGPoint(x: rail.trunkX, y: rail.trunkBottomY))

        var trunk = Path()
        trunk.move(to: CGPoint(x: rootPoint.x, y: rootPoint.y + rootHalf + edgeGap))
        trunk.addLine(to: railJunction)

        // The rail spans the whole row of days rather than only the stretch to the
        // right of the root. Anchoring it at the root used to leave the first days
        // hanging off the end of the trunk with nothing above them.
        var railPath = Path()
        railPath.move(to: transform.point(CGPoint(x: rail.railStartX, y: rail.railY)))
        railPath.addLine(to: transform.point(CGPoint(x: rail.railEndX, y: rail.railY)))

        context.stroke(trunk, with: .color(railColor), style: railStyle)
        context.stroke(railPath, with: .color(railColor), style: railStyle)

        for day in snapshot.days {
            guard let dayPoint = layout.positions[day.id] else { continue }
            let transformedDay = transform.point(dayPoint)

            // The branch drops out of the rail and stops above the day card.
            if let span = WeekTopologyEdgeSpan(
                topCenterY: transform.point(CGPoint(x: dayPoint.x, y: rail.railY)).y,
                bottomCenterY: transformedDay.y,
                topClearance: 0,
                bottomClearance: dayHalf + edgeGap
            ) {
                var branch = Path()
                branch.move(to: CGPoint(x: transformedDay.x, y: span.startY))
                branch.addLine(to: CGPoint(x: transformedDay.x, y: span.endY))
                context.stroke(branch, with: .color(railColor), style: railStyle)
            }

            guard semanticLevel != .overview else { continue }

            // One segment per neighbouring pair down the column — see
            // `subtreeLinks`. Fanning from each parent to each of its children is
            // what used to run a line back through the cards stacked in between:
            // the edge aimed at the second task of a band crossed the first one.
            for link in layout.subtreeLinks(for: day, semanticLevel: semanticLevel) {
                guard let upper = layout.positions[link.parentID],
                      let lower = layout.positions[link.childID] else {
                    continue
                }

                // Bands stay the more solid line; the stubs into individual task
                // cards stay lighter, as they were when this was a fan.
                let entersBand = link.childID == day.groupID(for: link.kind)

                drawTreeEdge(
                    from: transform.point(upper),
                    to: transform.point(lower),
                    startClearance: link.parentHeight / 2 + edgeGap,
                    endClearance: link.childHeight / 2 + edgeGap,
                    color: link.kind.color.opacity(entersBand ? 0.5 : 0.34),
                    context: &context
                )
            }
        }
    }

    /// Draws an elbow from one card down to another, stopping at each card's
    /// border instead of running to its centre.
    ///
    /// When both cards share an x — every day, group and task in a single-column
    /// subtree does — the elbow degenerates into a plain vertical segment, so the
    /// clearance is the only thing keeping the line out of the cards.
    private func drawTreeEdge(
        from start: CGPoint,
        to end: CGPoint,
        startClearance: CGFloat,
        endClearance: CGFloat,
        color: Color,
        context: inout GraphicsContext
    ) {
        guard let span = WeekTopologyEdgeSpan(
            topCenterY: start.y,
            bottomCenterY: end.y,
            topClearance: startClearance,
            bottomClearance: endClearance
        ) else {
            return
        }

        var path = Path()
        path.move(to: CGPoint(x: start.x, y: span.startY))
        path.addLine(to: CGPoint(x: start.x, y: span.jogY))
        path.addLine(to: CGPoint(x: end.x, y: span.jogY))
        path.addLine(to: CGPoint(x: end.x, y: span.endY))
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
        )
    }

    private func rootButton(
        semanticLevel: WeekTopologySemanticLevel,
        snapshot: WeekTopologySnapshot
    ) -> some View {
        let selected = viewport.selectedNodeID == snapshot.rootNodeID

        return Button {
            selectRoot(rootNodeID: snapshot.rootNodeID)
        } label: {
            WeekTopologyRootNode(
                weekID: snapshot.weekID,
                totalCount: snapshot.totalCount,
                isSelected: selected,
                isCompact: semanticLevel == .overview
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("本周，共 \(snapshot.totalCount) 项")
        .accessibilityHint("轻点查看整周统计")
        .accessibilityIdentifier("weekTopologyRoot")
    }

    private func dayButton(
        _ day: WeekTopologyDaySnapshot,
        index: Int,
        semanticLevel: WeekTopologySemanticLevel,
        transform: WeekTopologyTransform,
        canvasSize: CGSize,
        layout: WeekTopologyLayout
    ) -> some View {
        let selected = viewport.selectedNodeID == day.id
        let isToday = Calendar(identifier: .iso8601).isDateInToday(day.date)
        let isCompact = semanticLevel == .overview

        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
                if day.totalCount > 0 {
                    focus(day: day, transform: transform, canvasSize: canvasSize, layout: layout)
                } else {
                    select(nodeID: day.id, dayID: day.dayID)
                }
            }
        } label: {
            VStack(spacing: 4) {
                WeekTopologyDayNode(
                    day: day,
                    isToday: isToday,
                    isSelected: selected,
                    reduceMotion: reduceMotion,
                    isCompact: isCompact
                )
            }
            .frame(
                width: isCompact ? WeekTopologyMetrics.dayNodeCompactWidth : 88,
                height: isCompact ? WeekTopologyMetrics.dayNodeCompactHeight : 68
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(day))
        .accessibilityHint(day.totalCount > 0 ? "轻点展开当天任务" : "轻点选择当天")
        .accessibilityIdentifier("weekTopologyDay_\(index)")
    }

    private func groupButton(
        day: WeekTopologyDaySnapshot,
        kind: WeekTopologyResultKind
    ) -> some View {
        let nodeID = day.groupID(for: kind)
        let selected = viewport.selectedNodeID == nodeID

        return Button {
            select(nodeID: nodeID, dayID: day.dayID)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: kind.iconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(kind.color)

                VStack(alignment: .leading, spacing: 0) {
                    Text(kind.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(day.count(for: kind)) 项")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(kind.color)
                }
            }
            .padding(.horizontal, 7)
            .frame(
                width: WeekTopologyMetrics.groupCardWidth,
                height: WeekTopologyMetrics.groupCardHeight,
                alignment: .leading
            )
            .background(kind.color.opacity(selected ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(kind.color.opacity(selected ? 0.95 : 0.45), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.fullDateFormatter.string(from: day.date))，\(kind.title) \(day.count(for: kind)) 项")
        .accessibilityIdentifier("weekTopologyGroup_\(nodeID)")
    }

    private func taskButton(_ task: WeekTopologyTaskNode) -> some View {
        let selected = viewport.selectedNodeID == task.id
        let resultColor: Color = task.zone == .complete ? .accentGreen : .accentOrange
        let taskType = taskTypeCatalog.resolve(idRaw: task.taskTypeIdRaw, fallback: task.taskType)

        return Button {
            select(nodeID: task.id, dayID: task.dayID)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: task.isFocus ? "scope" : taskType.iconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(task.isFocus ? Color.weekyiiPrimary : resultColor)
                Text(task.title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(
                width: WeekTopologyMetrics.taskCardWidth,
                height: WeekTopologyMetrics.taskCardHeight,
                alignment: .leading
            )
            .background(taskType.color.opacity(selected ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Color.weekyiiPrimary : taskType.color.opacity(0.52), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title)，\(taskType.name)")
        .accessibilityIdentifier("weekTopologyTask_\(task.id)")
    }

    private func forgottenButton(_ forgotten: WeekTopologyForgottenNode) -> some View {
        let selected = viewport.selectedNodeID == forgotten.id

        return Button {
            select(nodeID: forgotten.id, dayID: forgotten.dayID)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.taskDDL)
                Text("已遗忘")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.taskDDL)
            }
            .frame(
                width: WeekTopologyMetrics.forgottenCardWidth,
                height: WeekTopologyMetrics.forgottenCardHeight
            )
            .background(Color.taskDDL.opacity(selected ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.taskDDL.opacity(selected ? 0.95 : 0.52), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("已遗忘任务，无详情")
        .accessibilityIdentifier("weekTopologyForgotten_\(forgotten.id)")
    }

    @ViewBuilder
    private func inspector(snapshot: WeekTopologySnapshot) -> some View {
        if let nodeID = viewport.selectedNodeID {
            if nodeID == snapshot.rootNodeID {
                weekInspector(snapshot: snapshot)
            } else if let day = snapshot.days.first(where: { nodeBelongsToDay(nodeID, day: $0) }) {
                daySubtreeInspector(nodeID: nodeID, day: day, snapshot: snapshot)
            }
        } else {
            weekInspector(snapshot: snapshot)
        }
    }

    /// The three day-scoped inspectors all need the same owning day, so the caller
    /// resolves it once instead of re-scanning per branch.
    ///
    /// Branch order matters and mirrors the original: a task node belongs to a day
    /// (so the day lookup succeeds) but matches neither the day id nor a group id,
    /// which is what lets it fall through to `taskInspector`. Checking the task
    /// case *after* the forgotten fallback would show "任务已遗忘" for a live task.
    @ViewBuilder
    private func daySubtreeInspector(
        nodeID: String,
        day: WeekTopologyDaySnapshot,
        snapshot: WeekTopologySnapshot
    ) -> some View {
        if nodeID == day.id {
            dayInspector(day)
        } else if let kind = WeekTopologyResultKind.allCases.first(where: { day.groupID(for: $0) == nodeID }) {
            groupInspector(day: day, kind: kind)
        } else if let task = snapshot.task(id: nodeID) {
            taskInspector(task)
        } else {
            forgottenInspector(day: day)
        }
    }

    private func weekInspector(snapshot: WeekTopologySnapshot) -> some View {
        HStack(spacing: WeekSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("轻点日期展开")
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("也可拖动或双指缩放浏览")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 0)
            inspectorMetric("剩", snapshot.remainingCount, .accentOrange)
            inspectorMetric("成", snapshot.completedCount, .accentGreen)
            inspectorMetric("忘", snapshot.forgottenCount, .taskDDL)
        }
        .inspectorStyle()
        .accessibilityIdentifier("weekTopologyInspector")
    }

    private func dayInspector(_ day: WeekTopologyDaySnapshot) -> some View {
        HStack(spacing: WeekSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.fullDateFormatter.string(from: day.date))
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(day.status.displayName)
                    .font(.caption)
                    .foregroundStyle(day.status.color)
            }

            Spacer(minLength: 0)
            inspectorMetric("剩", day.remainingCount, .accentOrange)
            inspectorMetric("成", day.completedCount, .accentGreen)
            inspectorMetric("忘", day.forgottenCount, .taskDDL)

            if let model = week.days.first(where: { $0.dayId == day.dayID }) {
                NavigationLink {
                    DayDetailView(day: model)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.weekyiiPrimary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("查看当天")
            }
        }
        .inspectorStyle()
        .accessibilityIdentifier("weekTopologyInspector")
    }

    private func groupInspector(
        day: WeekTopologyDaySnapshot,
        kind: WeekTopologyResultKind
    ) -> some View {
        HStack(spacing: WeekSpacing.md) {
            Image(systemName: kind.iconName)
                .foregroundStyle(kind.color)
                .frame(width: 28, height: 28)
                .background(kind.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(kind.title) · \(day.count(for: kind)) 项")
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(Self.fullDateFormatter.string(from: day.date))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .inspectorStyle()
        .accessibilityIdentifier("weekTopologyInspector")
    }

    private func taskInspector(_ task: WeekTopologyTaskNode) -> some View {
        let taskType = taskTypeCatalog.resolve(idRaw: task.taskTypeIdRaw, fallback: task.taskType)

        return HStack(spacing: WeekSpacing.md) {
            Image(systemName: task.isFocus ? "scope" : taskType.iconName)
                .foregroundStyle(taskType.color)
                .frame(width: 30, height: 30)
                .background(taskType.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(taskType.name) · \(task.zone.displayName)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 0)
            Button {
                onOpenTask(task.taskID)
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(Color.weekyiiPrimary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("查看任务详情")
        }
        .inspectorStyle()
        .accessibilityIdentifier("weekTopologyInspector")
    }

    private func forgottenInspector(day: WeekTopologyDaySnapshot) -> some View {
        HStack(spacing: WeekSpacing.md) {
            Image(systemName: "circle.dotted")
                .foregroundStyle(Color.taskDDL)
                .frame(width: 30, height: 30)
                .background(Color.taskDDL.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("任务已遗忘")
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(Self.fullDateFormatter.string(from: day.date)) · 不保留任务详情")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .inspectorStyle()
        .accessibilityIdentifier("weekTopologyInspector")
    }

    private func inspectorMetric(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.bodyMedium.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(minWidth: 24)
    }

    private func topologyButton(
        icon: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.weekyiiPrimary)
                .frame(width: 44, height: 44)
                .background(Color.backgroundSecondary, in: Circle())
                .overlay(Circle().stroke(Color.backgroundTertiary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func select(nodeID: String, dayID: String) {
        viewport.selectedNodeID = nodeID
        selectedDayID = dayID
    }

    private func selectRoot(rootNodeID: String) {
        viewport.selectedNodeID = rootNodeID
        selectedDayID = nil
    }

    private func focus(
        day: WeekTopologyDaySnapshot,
        transform: WeekTopologyTransform,
        canvasSize: CGSize,
        layout: WeekTopologyLayout
    ) {
        viewport.selectedNodeID = day.id
        selectedDayID = day.dayID
        guard layout.positions[day.id] != nil else { return }

        let fitScale = transform.fitScale
        // Two limits decide the framing, and the lower one wins:
        //  - the day's own nodes must stop overlapping (the task tier gate);
        //  - the subtree should fit the canvas when it reasonably can.
        // Zooming past the first limit is what made a tap look like it did
        // nothing: the task tier needs ~0.86x, but at 2.6x a day's group row sits
        // 208pt under its day node — more than the compact canvas is tall.
        let available = CGSize(
            width: max(canvasSize.width - WeekTopologyMetrics.focusPadding * 2, 1),
            height: max(canvasSize.height - WeekTopologyMetrics.focusPadding * 2, 1)
        )
        let fittedScale = layout.largestEffectiveScaleFittingSubtree(
            for: day,
            canvasSize: canvasSize,
            maximumEffectiveScale: WeekTopologyViewportState.maximumEffectiveScale
        )
        let effectiveScale = min(
            max(fittedScale ?? WeekTopologyMetrics.taskClearEffectiveScale, WeekTopologyMetrics.taskClearEffectiveScale),
            WeekTopologyViewportState.maximumEffectiveScale
        )
        viewport.applyScale(effectiveScale / max(fitScale, 0.1), fitScale: fitScale)

        // Re-derive the transform after the zoom so the offset correction is
        // exact. The previous version guessed the canvas width and ignored the
        // leading inset, which left the focused day off-centre.
        let updated = WeekTopologyTransform(
            viewportSize: canvasSize,
            contentBounds: layout.contentBounds,
            viewport: viewport
        )
        guard let renderedBounds = layout.renderedSubtreeBounds(for: day, effectiveScale: effectiveScale) else {
            return
        }
        let transformOrigin = updated.point(.zero)
        let visibleBounds = renderedBounds.offsetBy(dx: transformOrigin.x, dy: transformOrigin.y)
        let renderedWidth = visibleBounds.width
        let renderedHeight = visibleBounds.height

        // Centre the subtree when it fits; otherwise pin its top to the padding
        // so the day node, its group and the first task rows are all in view and
        // the rest is a short pan away.
        let desiredTop = renderedHeight <= available.height
            ? (canvasSize.height - renderedHeight) / 2
            : WeekTopologyMetrics.focusPadding
        viewport.offset = CGSize(
            width: viewport.offset.width + ((canvasSize.width - renderedWidth) / 2 - visibleBounds.minX),
            height: viewport.offset.height + (desiredTop - visibleBounds.minY)
        )
    }

    private func nodeBelongsToDay(_ nodeID: String, day: WeekTopologyDaySnapshot) -> Bool {
        if nodeID == day.id { return true }
        if WeekTopologyResultKind.allCases.contains(where: { day.groupID(for: $0) == nodeID }) {
            return true
        }
        if day.remainingTasks.contains(where: { $0.id == nodeID }) ||
            day.completedTasks.contains(where: { $0.id == nodeID }) {
            return true
        }
        return day.forgottenNodes.contains(where: { $0.id == nodeID })
    }

    private func dayAccessibilityLabel(_ day: WeekTopologyDaySnapshot) -> String {
        "\(Self.fullDateFormatter.string(from: day.date))，\(day.status.displayName)，共 \(day.totalCount) 项，剩余 \(day.remainingCount)，完成 \(day.completedCount)，遗忘 \(day.forgottenCount)"
    }

    private static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M月d日 EEEE")
        return formatter
    }()
}

struct WeekTopologyFullScreenView: View {
    let week: WeekModel
    @Binding var viewport: WeekTopologyViewportState
    @Binding var selectedDayID: String?
    let onOpenTask: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsLegend = false

    var body: some View {
        VStack(spacing: WeekSpacing.sm) {
            HStack(spacing: WeekSpacing.sm) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("关闭全屏")
                .accessibilityIdentifier("weekTopologyFullscreenCloseButton")

                Text("本周任务结构")
                    .font(.titleSmall)
                Spacer(minLength: 0)

                Button {
                    viewport.reset()
                    selectedDayID = nil
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("全局视图")

                Button {
                    showsLegend.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("图例")
            }
            .foregroundStyle(Color.weekyiiPrimary)

            WeekTopologyView(
                week: week,
                viewport: $viewport,
                selectedDayID: $selectedDayID,
                isFullScreen: true,
                onOpenFullScreen: {},
                onOpenTask: onOpenTask
            )
        }
        .padding(.horizontal, WeekSpacing.base)
        .padding(.bottom, WeekSpacing.sm)
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            if showsLegend {
                WeekTopologyLegend()
                    .padding(.top, 62)
                    .padding(.trailing, WeekSpacing.base)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                WeekTopologyOrientation.request(.landscape)
            } catch is CancellationError {
                // The cover disappeared before the delayed orientation request.
            } catch {
                // No recovery is needed for a cancelled or failed delay.
            }
        }
        .onDisappear {
            WeekTopologyOrientation.request(.portrait)
        }
    }
}

private struct WeekTopologyRootNode: View {
    let weekID: String
    let totalCount: Int
    let isSelected: Bool
    let isCompact: Bool

    var body: some View {
        VStack(spacing: 1) {
            if isCompact {
                Text("本周")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
            } else {
                Text("本周")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("\(weekID) · \(totalCount) 项")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .opacity(0.82)
            }
        }
        .foregroundStyle(Color.white)
        .frame(
            width: isCompact
                ? WeekTopologyMetrics.rootNodeCompactWidth
                : WeekTopologyMetrics.rootNodeExpandedWidth,
            height: isCompact
                ? WeekTopologyMetrics.rootNodeCompactHeight
                : WeekTopologyMetrics.rootNodeExpandedHeight
        )
        .background(Color.textPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.weekyiiPrimary : Color.textPrimary.opacity(0.6), lineWidth: isSelected ? 3 : 1)
        )
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.weekyiiPrimary)
                .frame(width: isCompact ? 20 : 28, height: 3)
                .offset(y: -2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeekTopologyDayNode: View {
    let day: WeekTopologyDaySnapshot
    let isToday: Bool
    let isSelected: Bool
    let reduceMotion: Bool
    let isCompact: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            if day.focusTask != nil {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.weekyiiPrimary.opacity(0.28), lineWidth: 2)
                    .frame(width: cardWidth + 8, height: cardHeight + 8)
                    .scaleEffect(pulse ? 1.14 : 0.94)
                    .opacity(pulse ? 0.15 : 0.75)
            }

            Group {
                if isCompact {
                    HStack(spacing: 2) {
                        Text(Self.dayNumberFormatter.string(from: day.date))
                        if day.totalCount > 0 {
                            Text("·\(day.totalCount)")
                                .fontWeight(.bold)
                        }
                    }
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    // "d" resolves to "14日" under zh_CN, so a day carrying a count
                    // reads "14日 · 2" — about 30pt against a 28pt content box. Without
                    // these two the second glyph wraps onto its own line and collides
                    // with the count. A day with no count ("15日") fits, which is why
                    // only today's card looked broken.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isSelected ? Color.weekyiiPrimary : Color.textPrimary)
                    .frame(width: cardWidth, height: cardHeight)
                } else {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: statusIcon)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(day.status.color)
                            Text(Self.shortWeekdayFormatter.string(from: day.date))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 3) {
                            Text(day.totalCount > 0 ? "\(day.totalCount)" : "—")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(isSelected ? Color.weekyiiPrimary : Color.textPrimary)
                            Text(day.totalCount > 0 ? "项" : "空")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(width: cardWidth, height: cardHeight)
                }
            }
            .background(
                day.totalCount > 0 ? day.status.color.opacity(0.09) : Color.backgroundPrimary,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? Color.weekyiiPrimary : day.status.color.opacity(0.42), lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.accentOrange.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
            }
        }
        .frame(
            width: isCompact
                ? WeekTopologyMetrics.dayNodeCompactWidth
                : WeekTopologyMetrics.dayNodeExpandedWidth,
            height: isCompact
                ? WeekTopologyMetrics.dayNodeCompactHeight
                : WeekTopologyMetrics.dayNodeExpandedHeight
        )
        .onChange(of: day.focusTask?.id, initial: true) { _, focusTaskID in
            guard focusTaskID != nil, !reduceMotion else {
                pulse = false
                return
            }
            pulse = false
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var statusIcon: String {
        switch day.status {
        case .empty: return "circle"
        case .draft: return "pencil.line"
        case .execute: return "scope"
        case .completed: return "checkmark"
        case .expired: return "circle.slash"
        }
    }

    private var cardWidth: CGFloat {
        isCompact
            ? WeekTopologyMetrics.dayNodeCompactWidth
            : WeekTopologyMetrics.dayNodeExpandedWidth
    }

    private var cardHeight: CGFloat {
        isCompact
            ? WeekTopologyMetrics.dayNodeCompactHeight
            : WeekTopologyMetrics.dayNodeExpandedHeight
    }

    private static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()
}

private struct WeekTopologyLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            legendRow(color: .accentOrange, title: "剩余")
            legendRow(color: .accentGreen, title: "完成")
            legendRow(color: .taskDDL, title: "遗忘")
            Divider()
            Text("轻点日期直接展开任务，也可双指缩放")
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(WeekSpacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WeekRadius.medium))
        .overlay(RoundedRectangle(cornerRadius: WeekRadius.medium).stroke(Color.backgroundTertiary))
    }

    private func legendRow(color: Color, title: String) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption)
        }
    }
}

private struct WeekTopologyTransform {
    let fitScale: CGFloat
    let viewport: WeekTopologyViewportState
    let leadingInset: CGFloat
    let verticalInset: CGFloat

    /// Split out so callers can resolve the semantic zoom level before they have
    /// a transform to hand.
    static func fitScale(viewportSize: CGSize, contentBounds: CGRect) -> CGFloat {
        WeekTopologyMetrics.fitScale(
            viewportWidth: viewportSize.width,
            contentWidth: contentBounds.width
        )
    }

    init(
        viewportSize: CGSize,
        contentBounds: CGRect,
        viewport: WeekTopologyViewportState
    ) {
        self.viewport = viewport
        fitScale = Self.fitScale(viewportSize: viewportSize, contentBounds: contentBounds)
        let renderedWidth = contentBounds.width * fitScale * viewport.scale
        leadingInset = max(12, (viewportSize.width - renderedWidth) / 2)
        // Derived from the root card so its top never clips. A flat 18 cut 7pt
        // off the root node at the overview scale.
        verticalInset = WeekTopologyMetrics.verticalInset
    }

    func point(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: leadingInset + point.x * fitScale * viewport.scale + viewport.offset.width,
            y: verticalInset + point.y * fitScale * viewport.scale + viewport.offset.height
        )
    }
}

private enum WeekTopologyOrientation {
    static func request(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in
            // Rotation lock can reject the request; the fullscreen layout remains usable in portrait.
        }
    }
}

private extension WeekTopologyResultKind {
    var color: Color {
        switch self {
        case .remaining: return .accentOrange
        case .completed: return .accentGreen
        case .forgotten: return .taskDDL
        }
    }

    var iconName: String {
        switch self {
        case .remaining: return "hourglass"
        case .completed: return "checkmark"
        case .forgotten: return "circle.dotted"
        }
    }
}

private extension TaskZone {
    var displayName: String {
        switch self {
        case .draft: return "草稿"
        case .focus: return "专注中"
        case .frozen: return "待执行"
        case .complete: return "已完成"
        }
    }
}

private extension View {
    func inspectorStyle() -> some View {
        self
            .padding(.horizontal, WeekSpacing.md)
            .padding(.vertical, WeekSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.medium)
                    .stroke(Color.backgroundTertiary, lineWidth: 1)
            )
    }
}
