import SwiftUI
import SwiftData

enum WorkspaceRoute: String, CaseIterable, Identifiable, Hashable {
    case today
    case week
    case pending
    case projects
    case suspended
    case past
    case insights
    case mindStamps
    case search
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今天"
        case .week: "本周"
        case .pending: "未来"
        case .projects: "项目"
        case .suspended: "悬置箱"
        case .past: "过去"
        case .insights: "洞察"
        case .mindStamps: "印记"
        case .search: "全局搜索"
        case .settings: "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .today: "承诺、执行与收尾"
        case .week: "看见七天的真实负载"
        case .pending: "把未发生的事安排清楚"
        case .projects: "跨日期目标与任务台账"
        case .suspended: "暂不决定，但必须回来处理"
        case .past: "查看已经发生的每一天"
        case .insights: "从完成与遗忘中理解节奏"
        case .mindStamps: "留给启动与收尾的情绪线索"
        case .search: "跨任务、项目与印记定位"
        case .settings: "规则、主题与数据维护"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "scope"
        case .week: "rectangle.3.group"
        case .pending: "calendar.badge.plus"
        case .projects: "folder"
        case .suspended: "hourglass"
        case .past: "clock.arrow.circlepath"
        case .insights: "chart.xyaxis.line"
        case .mindStamps: "bookmark"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .today: .weekyiiPrimary
        case .week: .accentOrange
        case .pending: .weekyiiPrimaryLight
        case .projects: .weekyiiPrimary
        case .suspended: .suspendedModuleTint
        case .past: .textSecondary
        case .insights: .accentGreen
        case .mindStamps: .accentPink
        case .search: .weekyiiPrimaryLight
        case .settings: .textSecondary
        }
    }

    static let nowRoutes: [WorkspaceRoute] = [.today, .week]
    static let planningRoutes: [WorkspaceRoute] = [.pending, .projects, .suspended]
    static let reflectionRoutes: [WorkspaceRoute] = [.past, .insights, .mindStamps]
    static let persistentRoutes: [WorkspaceRoute] = [
        .today, .week, .pending, .projects, .suspended,
        .past, .insights, .mindStamps, .search, .settings
    ]
}

struct WorkspaceShell: View {
    @Binding var selectedRoute: WorkspaceRoute
    let animationsActive: Bool

    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingInspector = false

    var body: some View {
        Group {
            if layoutMetrics.layoutClass == .wide {
                wideWorkspace
            } else {
                regularWorkspace
            }
        }
        .overlay {
            WorkspaceKeyboardShortcuts(selectedRoute: $selectedRoute)
        }
        .sheet(isPresented: $showingInspector) {
            NavigationStack {
                WorkspaceInspectorView(route: selectedRoute)
                    .navigationTitle("上下文")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") {
                                showingInspector = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var regularWorkspace: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(
                selectedRoute: $selectedRoute,
                showsInspectorButton: true,
                onShowInspector: { showingInspector = true }
            )
            .navigationSplitViewColumnWidth(min: 218, ideal: 246, max: 286)
        } detail: {
            WorkspaceRouteTabs(
                selectedRoute: $selectedRoute,
                animationsActive: animationsActive
            )
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var wideWorkspace: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(
                selectedRoute: $selectedRoute,
                showsInspectorButton: false,
                onShowInspector: { }
            )
            .navigationSplitViewColumnWidth(min: 218, ideal: 246, max: 286)
        } content: {
            WorkspaceRouteTabs(
                selectedRoute: $selectedRoute,
                animationsActive: animationsActive
            )
            .navigationSplitViewColumnWidth(min: 620, ideal: 800, max: 1100)
        } detail: {
            WorkspaceInspectorView(route: selectedRoute)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 390)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct WorkspaceKeyboardShortcuts: View {
    @Binding var selectedRoute: WorkspaceRoute

    var body: some View {
        VStack {
            shortcutButton("1", route: .today)
            shortcutButton("2", route: .week)
            shortcutButton("3", route: .pending)
            shortcutButton("4", route: .projects)
            shortcutButton("5", route: .past)
            shortcutButton("k", route: .search)
        }
        .frame(width: 1, height: 1)
        .clipped()
        .opacity(0.001)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func shortcutButton(_ key: KeyEquivalent, route: WorkspaceRoute) -> some View {
        Button {
            selectedRoute = route
        } label: {
            EmptyView()
        }
        .keyboardShortcut(key, modifiers: .command)
    }
}

private struct WorkspaceSidebar: View {
    @Binding var selectedRoute: WorkspaceRoute
    let showsInspectorButton: Bool
    let onShowInspector: () -> Void

    var body: some View {
        List(selection: routeSelection) {
            brandHeader

            Button {
                selectedRoute = .search
            } label: {
                Label {
                    HStack {
                        Text("搜索")
                        Spacer()
                        Text("⌘K")
                            .font(.caption2.monospaced())
                            .foregroundStyle(Color.textTertiary)
                    }
                } icon: {
                    Image(systemName: WorkspaceRoute.search.systemImage)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            .accessibilityIdentifier("workspaceCommandSearch")

            routeSection("现在", routes: WorkspaceRoute.nowRoutes)
            routeSection("计划", routes: WorkspaceRoute.planningRoutes)
            routeSection("回望", routes: WorkspaceRoute.reflectionRoutes)

            Section("系统") {
                routeRow(.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Weekyii")
        .safeAreaInset(edge: .bottom) {
            if showsInspectorButton {
                Button(action: onShowInspector) {
                    Label("查看上下文", systemImage: "sidebar.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, WeekSpacing.md)
                        .padding(.vertical, WeekSpacing.sm)
                        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, WeekSpacing.sm)
                .padding(.bottom, WeekSpacing.xs)
                .accessibilityIdentifier("workspaceInspectorButton")
            }
        }
        .accessibilityIdentifier("workspaceSidebar")
    }

    private var routeSelection: Binding<WorkspaceRoute?> {
        Binding(
            get: { selectedRoute },
            set: { newValue in
                if let newValue {
                    selectedRoute = newValue
                }
            }
        )
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HStack(spacing: WeekSpacing.sm) {
                WeekLogo(size: .small, animated: false)
                Spacer()
                Text("WORKSPACE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.weekyiiPrimary)
            }

            Text("Plan once.\nExecute without interruption.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, WeekSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func routeSection(_ title: String, routes: [WorkspaceRoute]) -> some View {
        Section(title) {
            ForEach(routes) { route in
                routeRow(route)
            }
        }
    }

    private func routeRow(_ route: WorkspaceRoute) -> some View {
        Label(route.title, systemImage: route.systemImage)
            .tag(route)
            .dropDestination(for: String.self) { _, _ in
                false
            } isTargeted: { isTargeted in
                if isTargeted, route == .pending {
                    selectedRoute = .pending
                }
            }
            .accessibilityIdentifier("workspaceRoute_\(route.rawValue)")
    }
}

private struct WorkspaceRouteTabs: View {
    @Binding var selectedRoute: WorkspaceRoute
    let animationsActive: Bool

    var body: some View {
        GeometryReader { proxy in
            TabView(selection: $selectedRoute) {
                ForEach(WorkspaceRoute.persistentRoutes) { route in
                    routeContent(route)
                        .tag(route)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.backgroundPrimary)
            .environment(
                \.weekLayoutMetrics,
                WeekLayoutMetrics(availableWidth: proxy.size.width)
            )
        }
    }

    @ViewBuilder
    private func routeContent(_ route: WorkspaceRoute) -> some View {
        switch route {
        case .today:
            TodayView(animationsActive: animationsActive && selectedRoute == .today)
        case .week:
            NavigationStack {
                WeekOverviewContentView()
                    .navigationTitle("本周")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .pending:
            PendingView()
        case .projects, .suspended, .mindStamps:
            WorkspaceExtensionsRouteHost(route: route)
        case .past:
            PastView()
        case .insights:
            NavigationStack {
                WorkspaceInsightsView()
            }
        case .search:
            NavigationStack {
                WorkspaceSearchView(selectedRoute: $selectedRoute)
            }
        case .settings:
            SettingsView()
        }
    }
}

private struct WorkspaceExtensionsRouteHost: View {
    let route: WorkspaceRoute

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var extensionsViewModel: ExtensionsViewModel?
    @State private var mindStampViewModel: MindStampViewModel?

    var body: some View {
        NavigationStack {
            Group {
                switch route {
                case .projects:
                    if let extensionsViewModel {
                        ProjectsFullView(viewModel: extensionsViewModel)
                    } else {
                        ProgressView()
                    }
                case .suspended:
                    if let extensionsViewModel {
                        SuspendedTasksFullView(viewModel: extensionsViewModel)
                    } else {
                        ProgressView()
                    }
                case .mindStamps:
                    if let mindStampViewModel {
                        MindStampsFullView(viewModel: mindStampViewModel)
                    } else {
                        ProgressView()
                    }
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.backgroundPrimary)
        }
        .onAppear(perform: prepareViewModels)
        .refreshOnStateTransitions(using: appState) {
            extensionsViewModel?.refresh()
            mindStampViewModel?.refresh()
        }
    }

    private func prepareViewModels() {
        if extensionsViewModel == nil {
            extensionsViewModel = ExtensionsViewModel(modelContext: modelContext)
        }
        if mindStampViewModel == nil {
            mindStampViewModel = MindStampViewModel(modelContext: modelContext)
        }
        extensionsViewModel?.refresh()
        mindStampViewModel?.refresh()
    }
}

struct WorkspaceInsightsView: View {
    @Query(sort: \WeekModel.startDate, order: .reverse) private var weeks: [WeekModel]
    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    private let analytics = PastAnalyticsService()
    private let calendar = Calendar(identifier: .iso8601)

    private var pastWeeks: [WeekModel] {
        weeks.filter { $0.status == .past }
    }

    private var days: [DayModel] {
        pastWeeks.flatMap(\.days)
    }

    private var overview: PastAnalyticsService.OverviewStats {
        analytics.getOverviewStats(days: days)
    }

    private var recentRange: ClosedRange<Date> {
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -83, to: end) ?? end
        return start...end
    }

    private var heatmapData: [DayHeatmapDataPoint] {
        analytics.getHeatmapData(
            days: days,
            startDate: recentRange.lowerBound,
            endDate: recentRange.upperBound
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.xl) {
                WorkspaceHeroStage(
                    eyebrow: "REVIEW",
                    title: "从执行留下的痕迹，\n看见你的真实节奏",
                    subtitle: "洞察只解释已经完成和已经遗忘的内容，不把未完成任务重新变成负担。",
                    systemImage: "chart.xyaxis.line"
                ) {
                    WorkspaceMetricStrip(metrics: [
                        .init(value: "\(overview.totalCompletedTasks)", label: "完成"),
                        .init(value: "\(Int(overview.completionRate * 100))%", label: "完成率"),
                        .init(value: formatFocusHours(overview.totalFocusHours), label: "专注"),
                        .init(value: "\(overview.totalStartedDays)", label: "启动日")
                    ])
                }

                if days.isEmpty {
                    WorkspacePanel(title: "尚未形成趋势", systemImage: "clock.badge.questionmark") {
                        Text("当你真正启动并结束一些任务流后，Weekyii 会在这里呈现完成率、专注时长和十二周节奏。")
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    ContributionHeatmap(data: heatmapData, dateRange: recentRange)

                    if let latestWeek = pastWeeks.first {
                        WeekTrendChart(
                            dataPoints: analytics.getWeekTrendData(
                                days: latestWeek.days,
                                weekStart: latestWeek.startDate
                            )
                        )
                    }

                    insightNarrative
                }
            }
            .padding(.horizontal, layoutMetrics.pageHorizontalPadding)
            .padding(.vertical, WeekSpacing.xl)
            .weekReadableContent(maxWidth: 1180)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("洞察")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var insightNarrative: some View {
        let average = overview.averageTaskMinutes
        let completion = Int(overview.completionRate * 100)
        return WorkspacePanel(title: "节奏摘要", systemImage: "text.quote") {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                Text("你已经在 \(overview.totalStartedDays) 个启动日中完成 \(overview.totalCompletedTasks) 项任务，整体承诺兑现率为 \(completion)% 。")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                if average > 0 {
                    Text("每项已完成任务平均占用约 \(Int(average.rounded())) 分钟。这个数字来自真实开始与结束记录，而不是事前估计。")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func formatFocusHours(_ hours: Double) -> String {
        hours < 1 ? "\(Int((hours * 60).rounded()))m" : String(format: "%.1fh", hours)
    }
}

private struct WorkspaceSearchView: View {
    @Binding var selectedRoute: WorkspaceRoute
    @Query(sort: \TaskItem.title) private var tasks: [TaskItem]
    @Query(sort: \ProjectModel.createdAt, order: .reverse) private var projects: [ProjectModel]
    @Query(sort: \MindStampItem.createdAt, order: .reverse) private var stamps: [MindStampItem]
    @Query(sort: \SuspendedTaskItem.decisionDeadline) private var suspendedTasks: [SuspendedTaskItem]
    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    @State private var query = ""

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var matchingTasks: [TaskItem] {
        guard !normalizedQuery.isEmpty else { return Array(tasks.prefix(8)) }
        return tasks.filter {
            $0.title.lowercased().contains(normalizedQuery) ||
            $0.taskDescription.lowercased().contains(normalizedQuery)
        }
    }

    private var matchingProjects: [ProjectModel] {
        guard !normalizedQuery.isEmpty else { return Array(projects.prefix(5)) }
        return projects.filter {
            $0.name.lowercased().contains(normalizedQuery) ||
            $0.projectDescription.lowercased().contains(normalizedQuery)
        }
    }

    private var matchingStamps: [MindStampItem] {
        guard !normalizedQuery.isEmpty else { return Array(stamps.prefix(5)) }
        return stamps.filter { $0.text.lowercased().contains(normalizedQuery) }
    }

    private var matchingSuspendedTasks: [SuspendedTaskItem] {
        guard !normalizedQuery.isEmpty else { return Array(suspendedTasks.prefix(5)) }
        return suspendedTasks.filter {
            $0.title.lowercased().contains(normalizedQuery) ||
            $0.taskDescription.lowercased().contains(normalizedQuery)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.xl) {
                WorkspaceHeroStage(
                    eyebrow: "COMMAND",
                    title: "不用记住内容藏在哪里",
                    subtitle: "搜索任务、项目、悬置内容与印记，然后直接回到负责处理它的工作区。",
                    systemImage: "magnifyingglass"
                ) {
                    searchField
                }

                resultSection("项目", icon: "folder", count: matchingProjects.count) {
                    ForEach(matchingProjects) { project in
                        searchRow(
                            title: project.name,
                            detail: "\(project.status.displayName) · \(project.totalTaskCount) 项任务",
                            icon: project.icon,
                            tint: Color(hex: project.color),
                            route: .projects
                        )
                    }
                }

                resultSection("任务", icon: "checklist", count: matchingTasks.count) {
                    ForEach(matchingTasks.prefix(20)) { task in
                        searchRow(
                            title: task.title,
                            detail: task.day?.date.formatted(date: .abbreviated, time: .omitted) ?? "未关联日期",
                            icon: icon(for: task.zone),
                            tint: tint(for: task.zone),
                            route: route(for: task)
                        )
                    }
                }

                resultSection("悬置箱", icon: "hourglass", count: matchingSuspendedTasks.count) {
                    ForEach(matchingSuspendedTasks) { task in
                        searchRow(
                            title: task.title,
                            detail: "决策期限 \(task.decisionDeadline.formatted(date: .abbreviated, time: .omitted))",
                            icon: "hourglass",
                            tint: .suspendedModuleTint,
                            route: .suspended
                        )
                    }
                }

                resultSection("印记", icon: "bookmark", count: matchingStamps.count) {
                    ForEach(matchingStamps) { stamp in
                        searchRow(
                            title: stamp.text.isEmpty ? "仅图片印记" : stamp.text,
                            detail: stamp.createdAt.formatted(date: .abbreviated, time: .shortened),
                            icon: stamp.imageBlob == nil ? "note.text" : "photo",
                            tint: .accentPink,
                            route: .mindStamps
                        )
                    }
                }
            }
            .padding(.horizontal, layoutMetrics.pageHorizontalPadding)
            .padding(.vertical, WeekSpacing.xl)
            .weekReadableContent(maxWidth: 980)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("全局搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "任务、项目、印记")
        .accessibilityIdentifier("workspaceSearch")
    }

    private var searchField: some View {
        HStack(spacing: WeekSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textSecondary)
            TextField("输入关键词", text: $query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, WeekSpacing.md)
        .frame(height: 48)
        .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: WeekRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: WeekRadius.medium)
                .stroke(Color.backgroundTertiary, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func resultSection<Content: View>(
        _ title: String,
        icon: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if count > 0 {
            WorkspacePanel(title: title, systemImage: icon, trailing: "\(count)") {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
    }

    private func searchRow(
        title: String,
        detail: String,
        icon: String,
        tint: Color,
        route: WorkspaceRoute
    ) -> some View {
        Button {
            selectedRoute = route
        } label: {
            HStack(spacing: WeekSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: WeekRadius.small))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.vertical, WeekSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func route(for task: TaskItem) -> WorkspaceRoute {
        guard let date = task.day?.date else { return .projects }
        let calendar = Calendar(identifier: .iso8601)
        if calendar.isDateInToday(date) { return .today }
        return date > calendar.startOfDay(for: Date()) ? .pending : .past
    }

    private func icon(for zone: TaskZone) -> String {
        switch zone {
        case .draft: "pencil.line"
        case .focus: "scope"
        case .frozen: "snowflake"
        case .complete: "checkmark.circle.fill"
        }
    }

    private func tint(for zone: TaskZone) -> Color {
        switch zone {
        case .draft: .weekyiiPrimary
        case .focus: .accentOrange
        case .frozen: .weekyiiPrimaryLight
        case .complete: .accentGreen
        }
    }
}

private struct WorkspaceInspectorView: View {
    let route: WorkspaceRoute

    @Query(sort: \DayModel.date, order: .reverse) private var days: [DayModel]
    @Query(sort: \ProjectModel.createdAt, order: .reverse) private var projects: [ProjectModel]
    @Query(sort: \SuspendedTaskItem.decisionDeadline) private var suspendedTasks: [SuspendedTaskItem]
    @Query(sort: \MindStampItem.createdAt, order: .reverse) private var stamps: [MindStampItem]

    private var today: DayModel? {
        days.first { Calendar(identifier: .iso8601).isDateInToday($0.date) }
    }

    private var activeProjects: [ProjectModel] {
        projects.filter { $0.status == .planning || $0.status == .active }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.xl) {
                inspectorHeader
                contextualSummary
                commitmentRules
            }
            .padding(WeekSpacing.lg)
        }
        .background(Color.backgroundSecondary)
        .accessibilityIdentifier("workspaceInspector")
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            Image(systemName: route.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(route.tint)
                .frame(width: 42, height: 42)
                .background(route.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: WeekRadius.medium))

            VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                Text(route.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(route.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var contextualSummary: some View {
        WorkspaceInspectorSection(title: "此刻") {
            switch route {
            case .today:
                inspectorValue("状态", value: today?.status.displayName ?? "尚未建立")
                inspectorValue("Focus", value: today?.focusTask?.title ?? "暂无")
                inspectorValue("冻结队列", value: "\(today?.frozenTasks.count ?? 0) 项")
                inspectorValue("已完成", value: "\(today?.completedTasks.count ?? 0) 项")
            case .week:
                inspectorValue("已建立日期", value: "\(currentWeekDays.count) 天")
                inspectorValue("本周完成", value: "\(currentWeekDays.flatMap(\.completedTasks).count) 项")
                inspectorValue("本周遗忘", value: "\(currentWeekDays.reduce(0) { $0 + $1.expiredCount }) 项")
            case .pending:
                inspectorValue("未来草稿", value: "\(futureDraftTasks) 项")
                inspectorValue("已有计划日", value: "\(futureDays.count) 天")
            case .projects:
                inspectorValue("进行中", value: "\(activeProjects.count) 个")
                inspectorValue("项目任务", value: "\(activeProjects.flatMap(\.tasks).count) 项")
            case .suspended:
                inspectorValue("等待决定", value: "\(activeSuspendedTasks.count) 项")
                inspectorValue("七天内到期", value: "\(dueSoonSuspendedTasks.count) 项")
            case .past, .insights:
                inspectorValue("完成总数", value: "\(pastDays.flatMap(\.completedTasks).count) 项")
                inspectorValue("遗忘总数", value: "\(pastDays.reduce(0) { $0 + $1.expiredCount }) 项")
            case .mindStamps:
                inspectorValue("印记", value: "\(stamps.count) 条")
                inspectorValue("含图片", value: "\(stamps.filter { $0.imageBlob != nil }.count) 条")
            case .search:
                Text("搜索结果会把你带回负责处理该对象的工作区，不在搜索页复制编辑流程。")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            case .settings:
                Text("设置改变规则与表现，不改变已经发生的历史记录。")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var commitmentRules: some View {
        WorkspaceInspectorSection(title: "Weekyii 原则") {
            ruleRow("计划只在启动前重排", icon: "pencil.and.outline")
            ruleRow("启动后只有一个 Focus", icon: "scope")
            ruleRow("冻结队列不可跳过", icon: "snowflake")
            ruleRow("过期任务只留下数量", icon: "eye.slash")
        }
    }

    private var currentWeekDays: [DayModel] {
        let start = Date().startOfWeek
        let end = start.addingDays(6)
        return days.filter { $0.date >= start && $0.date <= end }
    }

    private var futureDays: [DayModel] {
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        return days.filter { $0.date > today }
    }

    private var futureDraftTasks: Int {
        futureDays.reduce(0) { $0 + $1.sortedDraftTasks.count }
    }

    private var activeSuspendedTasks: [SuspendedTaskItem] {
        suspendedTasks.filter { $0.status == .active }
    }

    private var dueSoonSuspendedTasks: [SuspendedTaskItem] {
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        let upperBound = today.addingDays(7)
        return activeSuspendedTasks.filter { $0.decisionDeadline >= today && $0.decisionDeadline <= upperBound }
    }

    private var pastDays: [DayModel] {
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        return days.filter { $0.date < today }
    }

    private func inspectorValue(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func ruleRow(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.weekyiiPrimary)
        }
    }
}

struct WorkspaceMetric: Identifiable {
    let id = UUID()
    let value: String
    let label: String
}

struct WorkspaceMetricStrip: View {
    let metrics: [WorkspaceMetric]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.value)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(metric.label)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if index < metrics.count - 1 {
                    Divider()
                        .padding(.horizontal, WeekSpacing.md)
                }
            }
        }
    }
}

struct WorkspaceHeroStage<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.xl) {
            HStack(alignment: .top, spacing: WeekSpacing.lg) {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    Text(eyebrow)
                        .font(.caption.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(Color.weekyiiPrimary)

                    Text(title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: WeekSpacing.md)

                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.weekyiiPrimary)
                    .frame(width: 72, height: 72)
                    .background(Color.weekyiiPrimary.opacity(0.11), in: RoundedRectangle(cornerRadius: WeekRadius.large))
            }

            content()
        }
        .padding(WeekSpacing.xl)
        .background {
            ZStack {
                Color.backgroundSecondary
                LinearGradient(
                    colors: [
                        Color.weekyiiPrimary.opacity(0.14),
                        Color.clear,
                        Color.accentOrange.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.xlarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WeekRadius.xlarge, style: .continuous)
                .stroke(Color.weekyiiPrimary.opacity(0.2), lineWidth: 1)
        }
    }
}

struct WorkspacePanel<Content: View>: View {
    let title: String
    let systemImage: String
    let trailing: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        systemImage: String,
        trailing: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HStack(spacing: WeekSpacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.weekyiiPrimary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
            }

            content()
        }
        .padding(WeekSpacing.lg)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: WeekRadius.large)
                .stroke(Color.backgroundTertiary, lineWidth: 1)
        }
    }
}

private struct WorkspaceInspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(Color.textTertiary)

            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                content()
            }
        }
        .padding(WeekSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: WeekRadius.medium))
    }
}
