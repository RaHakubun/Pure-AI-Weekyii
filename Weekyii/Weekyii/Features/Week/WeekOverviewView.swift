import SwiftUI
import SwiftData

enum WeekOverviewDisplayMode: String, CaseIterable, Identifiable {
    case cards
    case strips
    case collapsed

    var id: String { rawValue }

    var next: Self {
        switch self {
        case .cards:
            return .strips
        case .strips:
            return .collapsed
        case .collapsed:
            return .cards
        }
    }

    var title: String {
        switch self {
        case .cards:
            return "当前状态"
        case .strips:
            return "信息横条"
        case .collapsed:
            return "折叠"
        }
    }

    var iconName: String {
        switch self {
        case .cards:
            return "square.grid.2x2.fill"
        case .strips:
            return "rectangle.grid.1x2.fill"
        case .collapsed:
            return "rectangle.compress.vertical"
        }
    }
}

enum WeekOverviewDayHighlight: Equatable {
    case focus(String)
    case draft(String)
    case frozen(String)
    case completed(String)
    case expired(String)
    case empty(String)

    var title: String {
        switch self {
        case .focus:
            return "当前专注"
        case .draft:
            return "首条草稿"
        case .frozen:
            return "冻结队列"
        case .completed:
            return "完成回顾"
        case .expired:
            return "过期提醒"
        case .empty:
            return "暂无任务"
        }
    }

    var detail: String {
        switch self {
        case .focus(let text),
             .draft(let text),
             .frozen(let text),
             .completed(let text),
             .expired(let text),
             .empty(let text):
            return text
        }
    }

    var iconName: String {
        switch self {
        case .focus:
            return "scope"
        case .draft:
            return "pencil.line"
        case .frozen:
            return "snowflake"
        case .completed:
            return "checkmark.circle.fill"
        case .expired:
            return "exclamationmark.circle.fill"
        case .empty:
            return "tray"
        }
    }
}

struct WeekOverviewDayStripSummary: Equatable {
    let highlight: WeekOverviewDayHighlight
    let draftCount: Int
    let remainingCount: Int
    let completedCount: Int
    let expiredCount: Int
    let totalCount: Int

    init(day: DayModel) {
        draftCount = day.sortedDraftTasks.count
        completedCount = day.completedTasks.count
        expiredCount = day.expiredCount
        totalCount = day.tasks.count
        remainingCount = day.sortedDraftTasks.count + day.frozenTasks.count + (day.focusTask == nil ? 0 : 1)

        if let focusTask = day.focusTask {
            highlight = .focus(focusTask.title)
        } else if let draftTask = day.sortedDraftTasks.first {
            highlight = .draft(draftTask.title)
        } else if let frozenTask = day.frozenTasks.first {
            highlight = .frozen(frozenTask.title)
        } else if completedCount > 0 {
            highlight = .completed("\(completedCount) 项已完成")
        } else if expiredCount > 0 {
            highlight = .expired("\(expiredCount) 项已过期")
        } else {
            highlight = .empty("当天暂无可展示内容")
        }
    }
}

struct WeekOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    @State private var viewModel: WeekViewModel?

    private var columns: [GridItem] {
        let count = layoutMetrics.layoutClass == .wide ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: WeekSpacing.md), count: count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let week = viewModel?.presentWeek {
                    VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                        // 周统计卡片
                        WeekStatCard(week: week)
                        
                        // 日期网格
                        LazyVGrid(columns: columns, spacing: WeekSpacing.md) {
                            ForEach(week.days.sorted(by: { $0.date < $1.date })) { day in
                                NavigationLink {
                                    DayDetailView(day: day)
                                } label: {
                                    DayCard(day: day)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, layoutMetrics.pageHorizontalPadding)
                    .padding(.vertical, WeekSpacing.base)
                    .weekReadableContent()
                } else if let message = viewModel?.errorMessage {
                    errorState(message: message) {
                        viewModel?.refresh()
                    }
                } else {
                    ProgressView()
                }
            }
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: WeekSpacing.sm) {
                        WeekLogo(size: .small, animated: false)
                        if let week = viewModel?.presentWeek {
                            Text(week.weekId)
                                .font(.titleSmall)
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = WeekViewModel(modelContext: modelContext, timeProvider: TimeProvider())
            }
            viewModel?.refresh()
        }
    }

    @ViewBuilder
    private func errorState(message: String, onRetry: @escaping () -> Void) -> some View {
        WeekCard(accentColor: .taskDDL) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(spacing: WeekSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.taskDDL)
                    Text(String(localized: "alert.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                Text(message)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                WeekButton("重试", icon: "arrow.clockwise", style: .secondary, action: onRetry)
            }
        }
        .weekPadding(WeekSpacing.base)
    }
}

struct WeekOverviewContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    @EnvironmentObject private var appState: AppState
    @State private var viewModel: WeekViewModel?
    @State private var displayMode: WeekOverviewDisplayMode = .cards
    @State private var topologyViewport = WeekTopologyViewportState()
    @State private var selectedDayID: String?
    @State private var topologyWeekID: String?
    @State private var showingTopologyFullScreen = false
    @State private var selectedTopologyTask: TaskItem?

    var body: some View {
        ScrollView {
            if let week = viewModel?.presentWeek {
                VStack(alignment: .leading, spacing: WeekSpacing.xl) {
                    weekHeroStage(week: week)

                    Group {
                        if layoutMetrics.layoutClass.supportsTwoColumns {
                            HStack(alignment: .top, spacing: WeekSpacing.xl) {
                                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                                    WeekStatCard(week: week)
                                    topologyCard(week: week)
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                                WeekOverviewDetailSection(
                                    week: week,
                                    displayMode: $displayMode,
                                    selectedDayID: selectedDayID
                                )
                                .frame(width: layoutMetrics.auxiliaryColumnWidth)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                                WeekStatCard(week: week)
                                topologyCard(week: week)
                                WeekOverviewDetailSection(
                                    week: week,
                                    displayMode: $displayMode,
                                    selectedDayID: selectedDayID
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, layoutMetrics.pageHorizontalPadding)
                .padding(.vertical, WeekSpacing.base)
                .weekReadableContent(maxWidth: 1180)
                .onAppear {
                    reconcileTopologyState(for: week)
                }
                .onChange(of: week.weekId) { _, _ in
                    reconcileTopologyState(for: week)
                }
            } else if let message = viewModel?.errorMessage {
                errorState(message: message) {
                    viewModel?.refresh()
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = WeekViewModel(modelContext: modelContext, timeProvider: TimeProvider())
            }
            viewModel?.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel?.refresh()
            }
        }
        .refreshOnStateTransitions(using: appState) {
            viewModel?.refresh()
        }
        .fullScreenCover(isPresented: $showingTopologyFullScreen) {
            if let week = viewModel?.presentWeek {
                WeekTopologyFullScreenView(
                    week: week,
                    viewport: $topologyViewport,
                    selectedDayID: $selectedDayID,
                    onOpenTask: { taskID in
                        selectedTopologyTask = task(with: taskID, in: week)
                    }
                )
            }
        }
        .sheet(item: $selectedTopologyTask) { task in
            TaskEditorSheet(
                title: "任务详情",
                isReadOnly: true,
                initialTitle: task.title,
                initialDescription: task.taskDescription,
                initialType: task.taskType,
                initialTypeIdRaw: task.taskTypeIdRaw,
                initialSteps: task.steps,
                initialAttachments: task.attachments,
                onSave: { _, _, _, _, _ in }
            )
        }
    }

    private func weekHeroStage(week: WeekModel) -> some View {
        let sortedDays = week.days.sorted { $0.date < $1.date }
        let completed = sortedDays.reduce(0) { $0 + $1.completedTasks.count }
        let forgotten = sortedDays.reduce(0) { $0 + $1.expiredCount }
        let remaining = sortedDays.reduce(0) {
            $0 + $1.sortedDraftTasks.count + $1.frozenTasks.count + ($1.focusTask == nil ? 0 : 1)
        }
        let activeDays = sortedDays.filter { $0.status != .empty }.count

        return WorkspaceHeroStage(
            eyebrow: "WEEK BOARD",
            title: "七天不是七张卡片，\n而是一条承诺轨道",
            subtitle: "同时看见今天的位置、尚未兑现的负载与已经结束的结果，再决定是否需要调整未来几天。",
            systemImage: "rectangle.3.group"
        ) {
            WorkspaceMetricStrip(metrics: [
                .init(value: "\(activeDays)/7", label: "已有内容"),
                .init(value: "\(remaining)", label: "待兑现"),
                .init(value: "\(completed)", label: "已完成"),
                .init(value: "\(forgotten)", label: "已遗忘")
            ])
        }
        .accessibilityIdentifier("weekHeroStage")
    }

    private func topologyCard(week: WeekModel) -> some View {
        WeekCard {
            WeekTopologyView(
                week: week,
                viewport: $topologyViewport,
                selectedDayID: $selectedDayID,
                isFullScreen: false,
                onOpenFullScreen: {
                    showingTopologyFullScreen = true
                },
                onOpenTask: { taskID in
                    selectedTopologyTask = task(with: taskID, in: week)
                }
            )
        }
    }

    private func reconcileTopologyState(for week: WeekModel) {
        if topologyWeekID != week.weekId {
            topologyWeekID = week.weekId
            topologyViewport.reset()
            selectedDayID = nil
            return
        }

        let snapshot = WeekTopologySnapshot(week: week)
        guard let selectedNodeID = topologyViewport.selectedNodeID else { return }
        let selectedNodeStillExists = snapshot.days.contains { day in
            selectedNodeID == day.id ||
            WeekTopologyResultKind.allCases.contains(where: { day.groupID(for: $0) == selectedNodeID }) ||
            day.remainingTasks.contains(where: { $0.id == selectedNodeID }) ||
            day.completedTasks.contains(where: { $0.id == selectedNodeID }) ||
            day.forgottenNodes.contains(where: { $0.id == selectedNodeID })
        }

        if !selectedNodeStillExists, let selectedDayID, let day = snapshot.day(id: selectedDayID) {
            topologyViewport.selectedNodeID = day.id
        }
    }

    private func task(with id: UUID, in week: WeekModel) -> TaskItem? {
        week.days.lazy.flatMap(\.tasks).first { $0.id == id }
    }

    @ViewBuilder
    private func errorState(message: String, onRetry: @escaping () -> Void) -> some View {
        WeekCard(accentColor: .taskDDL) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(spacing: WeekSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.taskDDL)
                    Text(String(localized: "alert.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                Text(message)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                WeekButton("重试", icon: "arrow.clockwise", style: .secondary, action: onRetry)
            }
        }
        .weekPadding(WeekSpacing.base)
    }
}

private struct WeekOverviewDetailSection: View {
    let week: WeekModel
    @Binding var displayMode: WeekOverviewDisplayMode
    let selectedDayID: String?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var sortedDays: [DayModel] {
        week.days.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            Text("本周详情")
                .font(.titleSmall)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    Button {
                        displayMode = displayMode.next
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.weekyiiPrimary)
                            .frame(width: 46, height: 46)
                            .background(
                                Circle()
                                    .fill(Color.backgroundSecondary)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.backgroundTertiary, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weekOverviewModeCycleButton")
                }

            WeekOverviewModeSwitcher(displayMode: $displayMode)

            Group {
                switch displayMode {
                case .cards:
                    LazyVGrid(columns: columns, spacing: WeekSpacing.md) {
                        ForEach(Array(sortedDays.enumerated()), id: \.element.dayId) { index, day in
                            NavigationLink {
                                DayDetailView(day: day)
                            } label: {
                                DayCard(day: day)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous)
                                            .stroke(
                                                selectedDayID == day.dayId ? day.status.color : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .accessibilityIdentifier("weekDayCard_\(index)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("weekOverviewCardsGrid")

                case .strips:
                    VStack(spacing: WeekSpacing.sm) {
                        ForEach(Array(sortedDays.enumerated()), id: \.element.dayId) { index, day in
                            NavigationLink {
                                DayDetailView(day: day)
                            } label: {
                                WeekOverviewStripRow(
                                    day: day,
                                    isSelected: selectedDayID == day.dayId
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("weekStripRow_\(index)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("weekOverviewStripList")

                case .collapsed:
                    WeekCard(accentColor: .weekyiiPrimary) {
                        HStack(alignment: .top, spacing: WeekSpacing.md) {
                            Image(systemName: "rectangle.compress.vertical")
                                .font(.title3)
                                .foregroundStyle(Color.weekyiiPrimary)

                            VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                                Text("七天详情已折叠")
                                    .font(.bodyMedium.weight(.semibold))
            .foregroundStyle(Color.textPrimary)
                                Text("上方拓扑仍可使用；需要展开详情时，切回“当前状态”或“信息横条”。")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("weekOverviewCollapsedState")
                }
            }
        }
    }
}

private struct WeekOverviewModeSwitcher: View {
    @Binding var displayMode: WeekOverviewDisplayMode

    var body: some View {
        HStack(spacing: WeekSpacing.xs) {
            ForEach(WeekOverviewDisplayMode.allCases) { mode in
                Button {
                    displayMode = mode
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.iconName)
                            .font(.callout.weight(.semibold))
                        Text(mode.title)
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(displayMode == mode ? Color.white : Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WeekSpacing.md)
                    .background(
                        Capsule()
                            .fill(displayMode == mode ? Color.weekyiiPrimary : Color.backgroundSecondary)
                    )
                    .overlay(
                        Capsule()
                            .stroke(displayMode == mode ? Color.clear : Color.backgroundTertiary, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("weekOverviewMode_\(mode.rawValue)")
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: displayMode)
    }
}

private struct WeekOverviewStripRow: View {
    let day: DayModel
    let isSelected: Bool
    private let summary: WeekOverviewDayStripSummary

    init(day: DayModel, isSelected: Bool = false) {
        self.day = day
        self.isSelected = isSelected
        self.summary = WeekOverviewDayStripSummary(day: day)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE Md")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HStack(alignment: .center, spacing: WeekSpacing.sm) {
                Text(Self.weekdayFormatter.string(from: day.date))
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 0)

                StatusBadge(status: day.status)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            HStack(alignment: .top, spacing: WeekSpacing.sm) {
                Image(systemName: summary.highlight.iconName)
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(highlightTint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.highlight.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(summary.highlight.detail)
                        .font(.bodyMedium.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: WeekSpacing.xs) {
                metricPill(label: "总", value: summary.totalCount, tint: .weekyiiPrimary)
                metricPill(label: "剩余", value: summary.remainingCount, tint: .accentOrange)
                metricPill(label: "完成", value: summary.completedCount, tint: .accentGreen)
                if summary.expiredCount > 0 {
                    metricPill(label: "过期", value: summary.expiredCount, tint: .taskDDL)
                }
            }
        }
        .padding(WeekSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .stroke(isSelected ? day.status.color : Color.backgroundTertiary, lineWidth: isSelected ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var highlightTint: Color {
        switch summary.highlight {
        case .focus:
            return .weekyiiPrimary
        case .draft:
            return .accentOrange
        case .frozen:
            return .taskLeisure
        case .completed:
            return .accentGreen
        case .expired:
            return .taskDDL
        case .empty:
            return .textSecondary
        }
    }

    private func metricPill(label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text("\(value)")
                .fontWeight(.semibold)
        }
        .font(.caption2)
        .foregroundStyle(tint)
        .padding(.horizontal, WeekSpacing.sm)
        .padding(.vertical, WeekSpacing.xs)
        .background(tint.opacity(0.12), in: Capsule())
    }
}
