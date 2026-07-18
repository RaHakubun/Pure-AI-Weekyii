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

    private var snapshot: WeekTopologySnapshot {
        WeekTopologySnapshot(week: week)
    }

    private var layout: WeekTopologyLayout {
        WeekTopologyLayout(snapshot: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            if !isFullScreen {
                header
            }

            GeometryReader { proxy in
                topologyCanvas(size: proxy.size)
            }
            .frame(height: isFullScreen ? nil : 220)
            .frame(maxHeight: isFullScreen ? .infinity : 220)
            .background(Color.backgroundSecondary.opacity(0.72))
            .clipShape(.rect(cornerRadius: WeekRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.medium)
                    .stroke(Color.backgroundTertiary, lineWidth: 1)
            )

            inspector
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isFullScreen ? "weekTopologyFullscreen" : "weekTopologyView")
    }

    private var header: some View {
        HStack(spacing: WeekSpacing.sm) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(Color.weekyiiPrimary)
            Text("本周拓扑")
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

    private func topologyCanvas(size: CGSize) -> some View {
        let transform = WeekTopologyTransform(
            viewportSize: size,
            contentBounds: layout.contentBounds,
            viewport: viewport
        )

        return ZStack {
            Canvas { context, _ in
                drawConnections(context: &context, transform: transform)
            }
            .allowsHitTesting(false)

            ForEach(Array(snapshot.days.enumerated()), id: \.element.id) { index, day in
                if let point = layout.positions[day.id] {
                    dayButton(day, index: index)
                        .position(transform.point(point))
                }
            }

            if viewport.semanticLevel != .overview {
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

            if viewport.semanticLevel == .tasks {
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
        .gesture(panGesture.simultaneously(with: zoomGesture))
        .clipped()
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

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if scaleOrigin == nil {
                    scaleOrigin = viewport.scale
                }
                viewport.applyScale((scaleOrigin ?? viewport.scale) * value)
            }
            .onEnded { _ in
                scaleOrigin = nil
            }
    }

    private func drawConnections(
        context: inout GraphicsContext,
        transform: WeekTopologyTransform
    ) {
        let days = snapshot.days
        guard let first = days.first,
              let last = days.last,
              let firstPoint = layout.positions[first.id],
              let lastPoint = layout.positions[last.id] else {
            return
        }

        var spine = Path()
        spine.move(to: transform.point(firstPoint))
        spine.addLine(to: transform.point(lastPoint))
        context.stroke(
            spine,
            with: .color(Color.textTertiary.opacity(0.35)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )

        guard viewport.semanticLevel != .overview else { return }

        for day in days {
            guard let dayPoint = layout.positions[day.id] else { continue }
            for kind in WeekTopologyResultKind.allCases {
                let groupID = day.groupID(for: kind)
                guard day.count(for: kind) > 0,
                      let groupPoint = layout.positions[groupID] else {
                    continue
                }

                drawCurve(
                    from: transform.point(dayPoint),
                    to: transform.point(groupPoint),
                    color: kind.color.opacity(0.5),
                    context: &context
                )

                guard viewport.semanticLevel == .tasks else { continue }
                let nodeIDs: [String]
                switch kind {
                case .remaining:
                    nodeIDs = day.remainingTasks.map(\.id)
                case .completed:
                    nodeIDs = day.completedTasks.map(\.id)
                case .forgotten:
                    nodeIDs = day.forgottenNodes.map(\.id)
                }

                for nodeID in nodeIDs {
                    guard let taskPoint = layout.positions[nodeID] else { continue }
                    drawCurve(
                        from: transform.point(groupPoint),
                        to: transform.point(taskPoint),
                        color: kind.color.opacity(0.34),
                        context: &context
                    )
                }
            }
        }
    }

    private func drawCurve(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        let midpointY = (start.y + end.y) / 2
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x, y: midpointY),
            control2: CGPoint(x: end.x, y: midpointY)
        )
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
        )
    }

    private func dayButton(_ day: WeekTopologyDaySnapshot, index: Int) -> some View {
        let selected = viewport.selectedNodeID == day.id
        let isToday = Calendar(identifier: .iso8601).isDateInToday(day.date)

        return Button {
            select(nodeID: day.id, dayID: day.dayID)
        } label: {
            VStack(spacing: 4) {
                WeekTopologyDayNode(
                    day: day,
                    isToday: isToday,
                    isSelected: selected,
                    reduceMotion: reduceMotion
                )
                Text(Self.shortWeekdayFormatter.string(from: day.date))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected ? Color.weekyiiPrimary : Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                focus(day: day)
            }
        )
        .accessibilityLabel(dayAccessibilityLabel(day))
        .accessibilityHint("轻点选择，轻点两次聚焦当天分支")
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
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(kind.color.opacity(selected ? 0.24 : 0.14))
                    Circle()
                        .stroke(kind.color.opacity(selected ? 0.9 : 0.45), lineWidth: selected ? 2 : 1)
                    Text("\(day.count(for: kind))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(kind.color)
                }
                .frame(width: 30, height: 30)

                Text(kind.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 54, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.fullDateFormatter.string(from: day.date))，\(kind.title) \(day.count(for: kind)) 项")
    }

    private func taskButton(_ task: WeekTopologyTaskNode) -> some View {
        let selected = viewport.selectedNodeID == task.id
        let resultColor: Color = task.zone == .complete ? .accentGreen : .accentOrange
        let taskType = taskTypeCatalog.resolve(idRaw: task.taskTypeIdRaw, fallback: task.taskType)

        return Button {
            select(nodeID: task.id, dayID: task.dayID)
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(taskType.color.opacity(0.18))
                    Circle()
                        .stroke(selected ? Color.weekyiiPrimary : taskType.color.opacity(0.7), lineWidth: selected ? 2 : 1)
                    Image(systemName: task.isFocus ? "scope" : taskType.iconName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(task.isFocus ? Color.weekyiiPrimary : resultColor)
                }
                .frame(width: 25, height: 25)

                Text(task.title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .frame(width: 62)
            }
            .frame(width: 68, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title)，\(taskType.name)")
    }

    private func forgottenButton(_ forgotten: WeekTopologyForgottenNode) -> some View {
        let selected = viewport.selectedNodeID == forgotten.id

        return Button {
            select(nodeID: forgotten.id, dayID: forgotten.dayID)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.taskDDL.opacity(selected ? 0.24 : 0.12))
                Circle()
                    .stroke(Color.taskDDL.opacity(selected ? 0.9 : 0.5), lineWidth: selected ? 2 : 1)
                Image(systemName: "circle.dotted")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.taskDDL)
            }
            .frame(width: 25, height: 25)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("已遗忘任务，无详情")
    }

    @ViewBuilder
    private var inspector: some View {
        if let nodeID = viewport.selectedNodeID,
           let day = snapshot.days.first(where: { nodeBelongsToDay(nodeID, day: $0) }) {
            if nodeID == day.id {
                dayInspector(day)
            } else if let kind = WeekTopologyResultKind.allCases.first(where: { day.groupID(for: $0) == nodeID }) {
                groupInspector(day: day, kind: kind)
            } else if let task = snapshot.task(id: nodeID) {
                taskInspector(task)
            } else {
                forgottenInspector(day: day)
            }
        } else {
            weekInspector
        }
    }

    private var weekInspector: some View {
        HStack(spacing: WeekSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("整周概览")
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("完成率 \(Int((snapshot.completionRate * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 0)
            inspectorMetric("总", snapshot.totalCount, .weekyiiPrimary)
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

    private func focus(day: WeekTopologyDaySnapshot) {
        viewport.selectedNodeID = day.id
        selectedDayID = day.dayID
        guard let position = layout.positions[day.id] else { return }
        let focusedScale: CGFloat = max(viewport.scale, 1.75)
        let approximateWidth: CGFloat = isFullScreen ? 800 : 330
        let fitScale = approximateWidth / max(layout.contentBounds.width, 1)
        viewport.applyScale(focusedScale)
        viewport.offset = CGSize(
            width: approximateWidth / 2 - position.x * fitScale * focusedScale,
            height: isFullScreen ? 20 : 36
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

                Text("本周拓扑")
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
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                WeekTopologyOrientation.request(.landscape)
            }
        }
        .onDisappear {
            WeekTopologyOrientation.request(.portrait)
        }
    }
}

private struct WeekTopologyDayNode: View {
    let day: WeekTopologyDaySnapshot
    let isToday: Bool
    let isSelected: Bool
    let reduceMotion: Bool

    @State private var pulse = false

    private var size: CGFloat {
        switch day.totalCount {
        case 0: return 30
        case 1...4: return 36
        default: return 42
        }
    }

    var body: some View {
        ZStack {
            if day.focusTask != nil {
                Circle()
                    .stroke(Color.weekyiiPrimary.opacity(0.28), lineWidth: 2)
                    .frame(width: size + 14, height: size + 14)
                    .scaleEffect(pulse ? 1.14 : 0.94)
                    .opacity(pulse ? 0.15 : 0.75)
            }

            if isToday {
                Circle()
                    .stroke(Color.accentOrange.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .frame(width: size + 11, height: size + 11)
            }

            segmentedRing
                .frame(width: size + 5, height: size + 5)

            Circle()
                .fill(Color.backgroundPrimary)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.weekyiiPrimary : day.status.color.opacity(0.48), lineWidth: isSelected ? 3 : 1)
                )

            Image(systemName: statusIcon)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(day.status.color)
        }
        .frame(width: 56, height: 56)
        .onAppear {
            guard day.focusTask != nil, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private var segmentedRing: some View {
        if day.totalCount > 0 {
            ZStack {
                resultArc(count: day.remainingCount, preceding: 0, color: .accentOrange)
                resultArc(count: day.completedCount, preceding: day.remainingCount, color: .accentGreen)
                resultArc(
                    count: day.forgottenCount,
                    preceding: day.remainingCount + day.completedCount,
                    color: .taskDDL
                )
            }
            .rotationEffect(.degrees(-90))
        } else {
            Circle()
                .stroke(Color.textTertiary.opacity(0.28), lineWidth: 3)
        }
    }

    private func resultArc(count: Int, preceding: Int, color: Color) -> some View {
        let total = max(day.totalCount, 1)
        let start = CGFloat(preceding) / CGFloat(total)
        let end = CGFloat(preceding + count) / CGFloat(total)
        return Circle()
            .trim(from: start, to: end)
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
}

private struct WeekTopologyLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            legendRow(color: .accentOrange, title: "剩余")
            legendRow(color: .accentGreen, title: "完成")
            legendRow(color: .taskDDL, title: "遗忘")
            Divider()
            Text("缩放后展开结果组和任务")
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

    init(
        viewportSize: CGSize,
        contentBounds: CGRect,
        viewport: WeekTopologyViewportState
    ) {
        self.viewport = viewport
        fitScale = min(1, max(0.1, (viewportSize.width - 24) / max(contentBounds.width, 1)))
        let renderedWidth = contentBounds.width * fitScale * viewport.scale
        leadingInset = max(12, (viewportSize.width - renderedWidth) / 2)
        verticalInset = 18
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
