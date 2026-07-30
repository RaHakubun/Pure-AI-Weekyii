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

enum WorkspaceSelection: Hashable {
    case day(String)
    case date(Date)
    case week(String)
    case task(UUID)
    case project(UUID)
    case suspendedTask(UUID)
    case mindStamp(UUID)
    case insightDay(String)
    case setting(WorkspaceSettingsSection)
}

enum WorkspaceSettingsSection: String, CaseIterable, Identifiable, Hashable {
    case appearance
    case rhythm
    case taskTypes
    case future
    case projects
    case data
    case about
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "外观与主题"
        case .rhythm: "今日节奏"
        case .taskTypes: "任务管理"
        case .future: "未来"
        case .projects: "项目"
        case .data: "数据与安全"
        case .about: "关于 Weekyii"
        case .diagnostics: "开发者与诊断"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintpalette.fill"
        case .rhythm: "timer"
        case .taskTypes: "tag.fill"
        case .future: "calendar.badge.clock"
        case .projects: "folder.fill"
        case .data: "lock.shield.fill"
        case .about: "info.circle.fill"
        case .diagnostics: "hammer.fill"
        }
    }
}

final class WorkspaceSelectionStore: ObservableObject {
    @Published private var selections: [WorkspaceRoute: WorkspaceSelection] = [:]

    func selection(for route: WorkspaceRoute) -> WorkspaceSelection? {
        selections[route]
    }

    func select(_ selection: WorkspaceSelection?, for route: WorkspaceRoute) {
        selections[route] = selection
    }
}

private struct WorkspaceSelectionStoreKey: EnvironmentKey {
    static let defaultValue: WorkspaceSelectionStore? = nil
}

extension EnvironmentValues {
    var workspaceSelectionStore: WorkspaceSelectionStore? {
        get { self[WorkspaceSelectionStoreKey.self] }
        set { self[WorkspaceSelectionStoreKey.self] = newValue }
    }
}

extension Notification.Name {
    static let workspaceDataDidChange = Notification.Name("Weekyii.workspaceDataDidChange")
}

struct WorkspaceShell: View {
    @Binding var selectedRoute: WorkspaceRoute
    let animationsActive: Bool

    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingInspector = false
    @StateObject private var selectionStore = WorkspaceSelectionStore()

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
                WorkspaceInspectorView(route: $selectedRoute, selectionStore: selectionStore)
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
            .id(selectedRoute)
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
            .environment(\.workspaceSelectionStore, selectionStore)
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
            .environment(\.workspaceSelectionStore, selectionStore)
            .navigationSplitViewColumnWidth(min: 620, ideal: 800, max: 1100)
        } detail: {
            NavigationStack {
                WorkspaceInspectorView(route: $selectedRoute, selectionStore: selectionStore)
            }
            .id(selectedRoute)
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
                WorkspaceSearchView()
            }
        case .settings:
            WorkspaceSettingsCategoriesView()
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
        .onReceive(NotificationCenter.default.publisher(for: .workspaceDataDidChange)) { _ in
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

private struct WorkspaceSettingsCategoriesView: View {
    @Environment(\.workspaceSelectionStore) private var workspaceSelectionStore
    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    @State private var selectedSection: WorkspaceSettingsSection = .appearance

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 220), spacing: WeekSpacing.md)
                    ],
                    spacing: WeekSpacing.md
                ) {
                    ForEach(WorkspaceSettingsSection.allCases) { section in
                        Button {
                            selectedSection = section
                            workspaceSelectionStore?.select(.setting(section), for: .settings)
                        } label: {
                            HStack(spacing: WeekSpacing.md) {
                                Image(systemName: section.systemImage)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.weekyiiPrimary)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        Color.weekyiiPrimary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: WeekRadius.medium)
                                    )

                                Text(section.title)
                                    .font(.headline)
                                    .foregroundStyle(Color.textPrimary)

                                Spacer()

                                Image(systemName: "sidebar.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .padding(WeekSpacing.lg)
                            .background(
                                selectedSection == section
                                    ? Color.weekyiiPrimary.opacity(0.12)
                                    : Color.backgroundSecondary,
                                in: RoundedRectangle(cornerRadius: WeekRadius.large)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: WeekRadius.large)
                                    .stroke(
                                        selectedSection == section
                                            ? Color.weekyiiPrimary
                                            : Color.backgroundTertiary,
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workspaceSettingsCategory_\(section.rawValue)")
                    }
                }
                .padding(.horizontal, layoutMetrics.pageHorizontalPadding)
                .padding(.vertical, WeekSpacing.xl)
                .weekReadableContent(maxWidth: 920)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if case .setting(let section)? = workspaceSelectionStore?.selection(for: .settings) {
                selectedSection = section
            }
            workspaceSelectionStore?.select(.setting(selectedSection), for: .settings)
        }
    }
}

struct WorkspaceInsightsView: View {
    @Query(sort: \WeekModel.startDate, order: .reverse) private var weeks: [WeekModel]
    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    @Environment(\.workspaceSelectionStore) private var workspaceSelectionStore
    @State private var selectedDayID: String?
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
                WorkspaceMetricStrip(metrics: [
                    .init(value: "\(overview.totalCompletedTasks)", label: "完成"),
                    .init(value: "\(Int(overview.completionRate * 100))%", label: "完成率"),
                    .init(value: formatFocusHours(overview.totalFocusHours), label: "专注"),
                    .init(value: "\(overview.totalStartedDays)", label: "启动日")
                ])
                .padding(.vertical, WeekSpacing.sm)
                .accessibilityIdentifier("insightsSummary")

                if days.isEmpty {
                    WorkspacePanel(title: "尚未形成趋势", systemImage: "clock.badge.questionmark") {
                        Text("当你真正启动并结束一些任务流后，Weekyii 会在这里呈现完成率、专注时长和十二周节奏。")
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    ContributionHeatmap(data: heatmapData, dateRange: recentRange)
                    recentDayPicker

                    if let latestWeek = pastWeeks.first {
                        WeekTrendChart(
                            dataPoints: analytics.getWeekTrendData(
                                days: latestWeek.days,
                                weekStart: latestWeek.startDate
                            )
                        )
                    }
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

    private var recentDayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WeekSpacing.sm) {
                ForEach(days.sorted(by: { $0.date > $1.date }).prefix(14)) { day in
                    Button {
                        selectedDayID = day.dayId
                        workspaceSelectionStore?.select(.insightDay(day.dayId), for: .insights)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.date, format: .dateTime.month().day())
                                .font(.caption.weight(.semibold))
                            Text("\(day.completedTasks.count) 成 · \(day.expiredCount) 忘")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, WeekSpacing.md)
                        .padding(.vertical, WeekSpacing.sm)
                        .background(
                            selectedDayID == day.dayId
                                ? Color.weekyiiPrimary.opacity(0.14)
                                : Color.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: WeekRadius.medium)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: WeekRadius.medium)
                                .stroke(
                                    selectedDayID == day.dayId ? Color.weekyiiPrimary : Color.backgroundTertiary,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityIdentifier("insightsRecentDayPicker")
    }

    private func formatFocusHours(_ hours: Double) -> String {
        hours < 1 ? "\(Int((hours * 60).rounded()))m" : String(format: "%.1fh", hours)
    }
}

private struct WorkspaceSearchView: View {
    @Query(sort: \TaskItem.title) private var tasks: [TaskItem]
    @Query(sort: \ProjectModel.createdAt, order: .reverse) private var projects: [ProjectModel]
    @Query(sort: \MindStampItem.createdAt, order: .reverse) private var stamps: [MindStampItem]
    @Query(sort: \SuspendedTaskItem.decisionDeadline) private var suspendedTasks: [SuspendedTaskItem]
    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    @Environment(\.workspaceSelectionStore) private var workspaceSelectionStore
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

    private var resultCount: Int {
        matchingTasks.count + matchingProjects.count + matchingStamps.count + matchingSuspendedTasks.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.xl) {
                if resultCount == 0 {
                    ContentUnavailableView(
                        normalizedQuery.isEmpty ? "还没有可搜索内容" : "没有匹配结果",
                        systemImage: "magnifyingglass"
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }

                resultSection("项目", icon: "folder", count: matchingProjects.count) {
                    ForEach(matchingProjects) { project in
                        searchRow(
                            title: project.name,
                            detail: "\(project.status.displayName) · \(project.totalTaskCount) 项任务",
                            icon: project.icon,
                            tint: Color(hex: project.color),
                            selection: .project(project.id)
                        )
                    }
                }

                resultSection("任务", icon: "checklist", count: matchingTasks.count) {
                    ForEach(matchingTasks.prefix(20)) { task in
                        searchRow(
                            title: task.title,
                            detail: task.day?.date.formatted(date: .abbreviated, time: .omitted) ?? "未关联日期",
                            icon: icon(for: task.zone),
                            tint: taskZoneTint(for: task.zone),
                            selection: .task(task.id)
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
                            selection: .suspendedTask(task.id)
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
                            selection: .mindStamp(stamp.id)
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

    @ViewBuilder
    private func resultSection<Content: View>(
        _ title: String,
        icon: String,
        count: Int,
        @ViewBuilder content: @escaping () -> Content
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
        selection: WorkspaceSelection
    ) -> some View {
        Button {
            workspaceSelectionStore?.select(selection, for: .search)
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

    private func icon(for zone: TaskZone) -> String {
        switch zone {
        case .draft: "pencil.line"
        case .focus: "scope"
        case .frozen: "snowflake"
        case .complete: "checkmark.circle.fill"
        }
    }

    private func taskZoneTint(for zone: TaskZone) -> Color {
        switch zone {
        case .draft: .weekyiiPrimary
        case .focus: .accentOrange
        case .frozen: .weekyiiPrimaryLight
        case .complete: .accentGreen
        }
    }
}

private struct WorkspaceInspectorView: View {
    @Binding var route: WorkspaceRoute
    @ObservedObject var selectionStore: WorkspaceSelectionStore

    @Query(sort: \DayModel.date, order: .reverse) private var days: [DayModel]
    @Query(sort: \TaskItem.order) private var tasks: [TaskItem]
    @Query(sort: \WeekModel.startDate, order: .reverse) private var weeks: [WeekModel]
    @Query(sort: \ProjectModel.createdAt, order: .reverse) private var projects: [ProjectModel]
    @Query(sort: \SuspendedTaskItem.decisionDeadline) private var suspendedTasks: [SuspendedTaskItem]
    @Query(sort: \MindStampItem.createdAt, order: .reverse) private var stamps: [MindStampItem]

    private let calendar = Calendar(identifier: .iso8601)

    private var requestedSelection: WorkspaceSelection? {
        selectionStore.selection(for: route)
    }

    private var resolvedSelection: WorkspaceSelection? {
        if let requestedSelection, selectionExists(requestedSelection) {
            return requestedSelection
        }
        return defaultSelection
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                inspectorHeader
                inspectorContent
            }
            .padding(WeekSpacing.lg)
        }
        .background(Color.backgroundSecondary)
        .accessibilityIdentifier("workspaceInspector")
    }

    private var inspectorHeader: some View {
        HStack(spacing: WeekSpacing.md) {
            Image(systemName: route.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(route.tint)
                .frame(width: 36, height: 36)
                .background(route.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: WeekRadius.medium))

            Text(route.title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .accessibilityIdentifier("workspaceInspectorTitle_\(route.rawValue)")
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch route {
        case .today:
            if let selection = resolvedSelection {
                selectionContent(selection)
            } else {
                emptyInspector("创建今天的第一项任务", systemImage: "plus.circle")
            }
        case .week:
            if let selection = resolvedSelection {
                selectionContent(selection)
            } else {
                emptyInspector("本周还没有任务记录", systemImage: "calendar")
            }
        case .pending:
            if let selection = resolvedSelection {
                selectionContent(selection)
            } else {
                emptyInspector("创建未来计划", systemImage: "calendar.badge.plus")
            }
        case .projects:
            if let selection = resolvedSelection {
                selectionContent(selection)
            } else {
                emptyInspector("新建第一个项目", systemImage: "folder.badge.plus")
            }
        case .suspended:
            if let selection = resolvedSelection {
                selectionContent(selection)
            } else {
                emptyInspector("新增悬置任务", systemImage: "hourglass.badge.plus")
            }
        case .past:
            if let selection = resolvedSelection {
                selectionContent(selection)
            } else {
                emptyInspector("完成任务后会在这里出现记录", systemImage: "clock.arrow.circlepath")
            }
        case .insights:
            insightsInspector
        case .mindStamps:
            if let selection = resolvedSelection {
                selectionContent(selection)
            } else {
                emptyInspector("添加第一条印记", systemImage: "bookmark")
            }
        case .search:
            if let selection = resolvedSelection {
                selectionContent(selection)
                searchDestinationButton(for: selection)
            } else {
                emptyInspector("选择一条搜索结果即可预览", systemImage: "magnifyingglass")
            }
        case .settings:
            settingsInspector
        }
    }

    @ViewBuilder
    private func selectionContent(_ selection: WorkspaceSelection) -> some View {
        switch selection {
        case .day(let dayID):
            if let day = days.first(where: { $0.dayId == dayID }) {
                dayInspector(day)
            }
        case .date(let date):
            if let day = days.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
                dayInspector(day)
            } else {
                VStack(spacing: WeekSpacing.md) {
                    emptyInspector(
                        "\(date.formatted(Date.FormatStyle().month().day().weekday(.wide))) 暂无任务",
                        systemImage: "calendar.badge.plus"
                    )
                    if route == .pending {
                        WorkspacePendingDateActions(date: date)
                    }
                }
            }
        case .week(let weekID):
            if let week = weeks.first(where: { $0.weekId == weekID }) {
                weekInspector(week)
            }
        case .task(let taskID):
            if let task = tasks.first(where: { $0.id == taskID }) {
                taskInspector(task)
            }
        case .project(let projectID):
            if let project = projects.first(where: { $0.id == projectID }) {
                projectInspector(project)
            }
        case .suspendedTask(let taskID):
            if let task = suspendedTasks.first(where: { $0.id == taskID }) {
                suspendedTaskInspector(task)
            }
        case .mindStamp(let stampID):
            if let stamp = stamps.first(where: { $0.id == stampID }) {
                mindStampInspector(stamp)
            }
        case .insightDay(let dayID):
            if let day = days.first(where: { $0.dayId == dayID }) {
                dayInspector(day)
            }
        case .setting(let section):
            settingsSectionInspector(section)
        }
    }

    private func taskInspector(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            WorkspaceInspectorSection(title: "任务") {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                inspectorValue("状态", value: zoneTitle(task.zone))
                inspectorValue("日期", value: task.day?.date.formatted(date: .abbreviated, time: .omitted) ?? "未安排")
                inspectorValue("项目", value: task.project?.name ?? "未关联")
            }

            if !task.steps.isEmpty {
                WorkspaceInspectorSection(title: "步骤") {
                    ForEach(task.steps.sorted { $0.sortOrder < $1.sortOrder }) { step in
                        Label(step.title, systemImage: step.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(step.isCompleted ? Color.accentGreen : Color.textPrimary)
                    }
                }
            }

            WorkspaceInspectorSection(title: "资料") {
                inspectorValue("步骤", value: "\(task.steps.count)")
                inspectorValue("附件", value: "\(task.attachments.count)")
                if let startedAt = task.startedAt {
                    inspectorValue("开始", value: startedAt.formatted(date: .omitted, time: .shortened))
                }
                if let endedAt = task.endedAt {
                    inspectorValue("结束", value: endedAt.formatted(date: .omitted, time: .shortened))
                }
            }

            if route == .today, task.day.map({ calendar.isDateInToday($0.date) }) == true {
                WorkspaceTodayTaskActions(task: task, selectionStore: selectionStore)
            } else if route == .pending || route == .projects {
                WorkspaceEditableTaskActions(task: task, route: route)
            }
        }
    }

    private func dayInspector(_ day: DayModel) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            WorkspaceInspectorSection(title: day.date.formatted(Date.FormatStyle().month().day().weekday(.wide))) {
                inspectorValue("状态", value: day.status.displayName)
                inspectorValue("截止", value: String(format: "%02d:%02d", day.killTimeHour, day.killTimeMinute))
                inspectorValue("完成", value: "\(day.completedTasks.count)")
                inspectorValue("遗忘", value: "\(day.expiredCount)")
            }

            let visibleTasks = day.tasks.sorted { $0.order < $1.order }
            if !visibleTasks.isEmpty {
                WorkspaceInspectorSection(title: "任务") {
                    ForEach(visibleTasks) { task in
                        inspectorSelectionButton(
                            title: task.title,
                            detail: zoneTitle(task.zone),
                            systemImage: icon(for: task.zone),
                            tint: tint(for: task.zone)
                        ) {
                            selectionStore.select(.task(task.id), for: route)
                        }
                    }
                }
            }

            if route == .pending, day.status == .empty || day.status == .draft {
                WorkspacePendingDateActions(date: day.date)
            }
        }
    }

    private func weekInspector(_ week: WeekModel) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            WorkspaceInspectorSection(title: "周") {
                inspectorValue("范围", value: "\(week.startDate.formatted(date: .abbreviated, time: .omitted)) – \(week.endDate.formatted(date: .abbreviated, time: .omitted))")
                inspectorValue("完成", value: "\(week.days.flatMap(\.completedTasks).count)")
                inspectorValue("遗忘", value: "\(week.days.reduce(0) { $0 + $1.expiredCount })")
            }
            WorkspaceInspectorSection(title: "日期") {
                ForEach(week.days.sorted { $0.date < $1.date }) { day in
                    inspectorSelectionButton(
                        title: day.date.formatted(Date.FormatStyle().month().day().weekday(.abbreviated)),
                        detail: day.status.displayName,
                        systemImage: "calendar",
                        tint: day.status.color
                    ) {
                        selectionStore.select(.day(day.dayId), for: route)
                    }
                }
            }
        }
    }

    private func projectInspector(_ project: ProjectModel) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            WorkspaceInspectorSection(title: "项目") {
                Label(project.name, systemImage: project.icon)
                    .font(.headline)
                    .foregroundStyle(Color(hex: project.color))
                if !project.projectDescription.isEmpty {
                    Text(project.projectDescription)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                inspectorValue("状态", value: project.status.displayName)
                inspectorValue("进度", value: "\(project.completedTaskCount)/\(project.totalTaskCount)")
                ProgressView(value: project.progress)
                    .tint(Color(hex: project.color))
            }

            if !project.tasks.isEmpty {
                WorkspaceInspectorSection(title: "任务") {
                    ForEach(project.tasks.sorted { $0.order < $1.order }) { task in
                        inspectorSelectionButton(
                            title: task.title,
                            detail: task.day?.date.formatted(date: .abbreviated, time: .omitted) ?? "未安排",
                            systemImage: icon(for: task.zone),
                            tint: tint(for: task.zone)
                        ) {
                            selectionStore.select(.task(task.id), for: route)
                        }
                    }
                }
            }

            WorkspaceProjectInspectorActions(project: project)
        }
    }

    private func suspendedTaskInspector(_ task: SuspendedTaskItem) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            WorkspaceInspectorSection(title: "悬置任务") {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                inspectorValue("决策期限", value: task.decisionDeadline.formatted(date: .abbreviated, time: .omitted))
                inspectorValue("剩余", value: SuspendedTaskMetaFormatter.deadlineText(remainingDays: task.remainingDays()))
                inspectorValue("步骤", value: "\(task.steps.count)")
                inspectorValue("附件", value: "\(task.attachments.count)")
            }
            WorkspaceSuspendedInspectorActions(task: task, selectionStore: selectionStore)
        }
    }

    private func mindStampInspector(_ stamp: MindStampItem) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            if let blob = stamp.imageBlob, let image = UIImage(data: blob) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium))
            }
            WorkspaceInspectorSection(title: "印记") {
                Text(stamp.text.isEmpty ? "仅图片记录" : stamp.text)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                inspectorValue("创建时间", value: stamp.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            WorkspaceMindStampInspectorActions(stamp: stamp, selectionStore: selectionStore)
        }
    }

    private var insightsInspector: some View {
        let pastDays = days.filter { $0.date < calendar.startOfDay(for: Date()) }
        let completed = pastDays.flatMap(\.completedTasks).count
        let expired = pastDays.reduce(0) { $0 + $1.expiredCount }
        return VStack(alignment: .leading, spacing: WeekSpacing.md) {
            WorkspaceInspectorSection(title: "当前范围") {
                inspectorValue("周期", value: "最近 12 周")
                inspectorValue("完成", value: "\(completed)")
                inspectorValue("遗忘", value: "\(expired)")
                inspectorValue("兑现率", value: completed + expired == 0 ? "—" : "\(Int((Double(completed) / Double(completed + expired) * 100).rounded()))%")
            }
            if let selection = resolvedSelection {
                selectionContent(selection)
            }
        }
    }

    private var settingsInspector: some View {
        Group {
            if case .setting(let section)? = resolvedSelection {
                settingsSectionInspector(section)
            }
        }
    }

    private func settingsSectionInspector(_ section: WorkspaceSettingsSection) -> some View {
        SettingsView(workspaceSection: section)
            .frame(minHeight: 720)
    }

    private func searchDestinationButton(for selection: WorkspaceSelection) -> some View {
        Button {
            if let destination = destinationRoute(for: selection) {
                selectionStore.select(selection, for: destination)
                route = destination
            }
        } label: {
            Label("在对应工作区打开", systemImage: "arrow.up.right.square")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, WeekSpacing.sm)
        }
        .buttonStyle(.borderedProminent)
        .tint(.weekyiiPrimary)
        .disabled(destinationRoute(for: selection) == nil)
    }

    private func destinationRoute(for selection: WorkspaceSelection) -> WorkspaceRoute? {
        switch selection {
        case .day(let dayID), .insightDay(let dayID):
            guard let day = days.first(where: { $0.dayId == dayID }) else { return nil }
            if calendar.isDateInToday(day.date) { return .today }
            return day.date > calendar.startOfDay(for: Date()) ? .pending : .past
        case .date(let date):
            if calendar.isDateInToday(date) { return .today }
            return date > calendar.startOfDay(for: Date()) ? .pending : .past
        case .week(let weekID):
            guard let week = weeks.first(where: { $0.weekId == weekID }) else { return nil }
            if week.status == .present { return .week }
            return week.status == .pending ? .pending : .past
        case .task(let taskID):
            guard let task = tasks.first(where: { $0.id == taskID }) else { return nil }
            if let date = task.day?.date {
                if calendar.isDateInToday(date) { return .today }
                return date > calendar.startOfDay(for: Date()) ? .pending : .past
            }
            return task.project == nil ? nil : .projects
        case .project: return .projects
        case .suspendedTask: return .suspended
        case .mindStamp: return .mindStamps
        case .setting: return .settings
        }
    }

    private var defaultSelection: WorkspaceSelection? {
        switch route {
        case .today:
            guard let today = days.first(where: { calendar.isDateInToday($0.date) }) else { return nil }
            if let focus = today.focusTask { return .task(focus.id) }
            if let draft = today.sortedDraftTasks.first { return .task(draft.id) }
            return .day(today.dayId)
        case .week:
            let start = Date().startOfWeek
            let end = start.addingDays(6)
            if let today = days.first(where: { calendar.isDateInToday($0.date) }) {
                return .day(today.dayId)
            }
            return days.first(where: { $0.date >= start && $0.date <= end }).map { .day($0.dayId) }
        case .pending:
            return days
                .filter { $0.date > calendar.startOfDay(for: Date()) }
                .sorted { $0.date < $1.date }
                .first
                .map { .day($0.dayId) }
        case .projects:
            return projects.first(where: { $0.status == .active || $0.status == .planning }).map { .project($0.id) }
        case .suspended:
            return suspendedTasks.first(where: { $0.status == .active }).map { .suspendedTask($0.id) }
        case .past:
            return days.first(where: { $0.date < calendar.startOfDay(for: Date()) }).map { .day($0.dayId) }
        case .insights:
            return days.first(where: { $0.date < calendar.startOfDay(for: Date()) }).map { .insightDay($0.dayId) }
        case .mindStamps:
            return stamps.first.map { .mindStamp($0.id) }
        case .search:
            return nil
        case .settings:
            return .setting(.appearance)
        }
    }

    private func selectionExists(_ selection: WorkspaceSelection) -> Bool {
        switch selection {
        case .day(let id), .insightDay(let id): days.contains { $0.dayId == id }
        case .date: true
        case .week(let id): weeks.contains { $0.weekId == id }
        case .task(let id): tasks.contains { $0.id == id }
        case .project(let id): projects.contains { $0.id == id }
        case .suspendedTask(let id): suspendedTasks.contains { $0.id == id && $0.status == .active }
        case .mindStamp(let id): stamps.contains { $0.id == id }
        case .setting: true
        }
    }

    private func emptyInspector(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func inspectorSelectionButton(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: WeekSpacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func zoneTitle(_ zone: TaskZone) -> String {
        switch zone {
        case .draft: "草稿"
        case .focus: "专注"
        case .frozen: "冻结"
        case .complete: "完成"
        }
    }
}

private struct WorkspacePendingDateActions: View {
    let date: Date

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: UserSettings
    @State private var viewModel: PendingViewModel?
    @State private var targetDay: DayModel?
    @State private var showingEditor = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            guard let viewModel else { return }
            guard let day = viewModel.resolveEditableDayForMonthAdd(on: date) else {
                errorMessage = viewModel.errorMessage ?? "无法建立该日期"
                return
            }
            targetDay = day
            showingEditor = true
        } label: {
            Label("在这一天创建任务", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, WeekSpacing.sm)
        }
        .buttonStyle(.borderedProminent)
        .tint(.weekyiiPrimary)
        .onAppear {
            guard viewModel == nil else { return }
            let created = PendingViewModel(modelContext: modelContext)
            created.refresh()
            viewModel = created
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            viewModel?.refresh()
        }) {
            if let targetDay {
                TaskEditorSheet(
                    title: String(localized: "draft.add_title"),
                    initialType: settings.defaultTaskType,
                    initialTypeIdRaw: settings.defaultTaskTypeIdRaw,
                    onSave: { _, _, _, _, _ in },
                    onSaveWithTypeId: { title, description, type, typeID, steps, attachments in
                        do {
                            try viewModel?.addDraftTask(
                                to: targetDay,
                                title: title,
                                description: description,
                                type: type,
                                taskTypeIdRaw: typeID,
                                steps: steps,
                                attachments: attachments
                            )
                            NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
            }
        }
        .alert(
            String(localized: "alert.title"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct WorkspaceEditableTaskActions: View {
    let task: TaskItem
    let route: WorkspaceRoute

    @Environment(\.modelContext) private var modelContext
    @State private var pendingViewModel: PendingViewModel?
    @State private var extensionsViewModel: ExtensionsViewModel?
    @State private var showingEditor = false
    @State private var errorMessage: String?

    private var canEdit: Bool {
        guard task.zone == .draft else { return false }
        switch route {
        case .pending:
            guard let day = task.day else { return false }
            return pendingViewModel?.canEdit(day) == true
        case .projects:
            guard let project = task.project, let day = task.day else { return false }
            return (project.status == .planning || project.status == .active)
                && (day.status == .empty || day.status == .draft)
        default:
            return false
        }
    }

    var body: some View {
        Group {
            if canEdit {
                WorkspaceInspectorSection(title: "操作") {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("编辑任务", systemImage: "pencil")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                }
                .sheet(isPresented: $showingEditor) {
                    TaskEditorSheet(
                        title: String(localized: "draft.edit_title"),
                        initialTitle: task.title,
                        initialDescription: task.taskDescription,
                        initialType: task.taskType,
                        initialTypeIdRaw: task.taskTypeIdRaw,
                        initialSteps: task.steps,
                        initialAttachments: task.attachments,
                        onSave: { _, _, _, _, _ in },
                        onSaveWithTypeId: { title, description, type, typeID, steps, attachments in
                            do {
                                if route == .pending, let day = task.day {
                                    try pendingViewModel?.updateDraftTask(
                                        task,
                                        in: day,
                                        title: title,
                                        description: description,
                                        type: type,
                                        taskTypeIdRaw: typeID,
                                        steps: steps,
                                        attachments: attachments
                                    )
                                } else if route == .projects {
                                extensionsViewModel?.updateProjectTask(
                                        task,
                                        title: title,
                                        description: description,
                                        type: type,
                                        taskTypeIdRaw: typeID,
                                        steps: steps,
                                    attachments: attachments
                                )
                            }
                            NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    )
                }
                .alert(
                    String(localized: "alert.title"),
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } }
                    )
                ) {
                    Button(String(localized: "action.ok"), role: .cancel) { }
                } message: {
                    Text(errorMessage ?? "")
                }
            }
        }
        .onAppear {
            if route == .pending, pendingViewModel == nil {
                let created = PendingViewModel(modelContext: modelContext)
                created.refresh()
                pendingViewModel = created
            } else if route == .projects, extensionsViewModel == nil {
                let created = ExtensionsViewModel(modelContext: modelContext)
                created.refresh()
                extensionsViewModel = created
            }
        }
    }
}

private struct WorkspaceTodayTaskActions: View {
    let task: TaskItem
    @ObservedObject var selectionStore: WorkspaceSelectionStore

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: UserSettings
    @State private var viewModel: TodayViewModel?
    @State private var showingPostpone = false
    @State private var showingCompleteConfirmation = false
    @State private var postponePreview: TodayViewModel.PostponePreview?
    @State private var errorMessage: String?

    var body: some View {
        WorkspaceInspectorSection(title: "操作") {
            if task.zone == .focus {
                Button {
                    showingCompleteConfirmation = true
                } label: {
                    Label("完成当前 Focus", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if task.zone != .complete {
                Button {
                    showingPostpone = true
                } label: {
                    Label("后移到未来", systemImage: "calendar.badge.clock")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if task.zone == .focus,
               task.day?.executionMode == .flexible,
               task.day?.isDraftZoneUnlocked == true,
               task.day?.frozenTasks.isEmpty == false {
                Button {
                    do {
                        try viewModel?.exchangeFocusWithFirstDraft()
                        selectCurrentFocus()
                        NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Label("与队首任务交换", systemImage: "arrow.triangle.swap")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.borderless)
        .onAppear {
            guard viewModel == nil else { return }
            let created = TodayViewModel(
                modelContext: modelContext,
                timeProvider: TimeProvider(),
                notificationService: NotificationService.shared,
                appState: appState,
                userSettings: settings
            )
            created.refresh()
            viewModel = created
        }
        .sheet(isPresented: $showingPostpone) {
            PostponeTaskSheet(taskTitle: task.title) { date in
                do {
                    guard let viewModel else { return }
                    let preview = try viewModel.previewPostpone(
                        taskID: task.id,
                        taskTitle: task.title,
                        targetDate: date
                    )
                    if preview.requiresWeekCreation {
                        postponePreview = preview
                    } else {
                        _ = try viewModel.commitPostpone(preview, allowWeekCreation: false)
                        selectionStore.select(nil, for: .today)
                        NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "需要建立未来周",
            isPresented: Binding(
                get: { postponePreview != nil },
                set: { if !$0 { postponePreview = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("建立并后移") {
                guard let preview = postponePreview else { return }
                do {
                    _ = try viewModel?.commitPostpone(preview, allowWeekCreation: true)
                    postponePreview = nil
                    selectionStore.select(nil, for: .today)
                    NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("取消", role: .cancel) {
                postponePreview = nil
            }
        } message: {
            Text("目标日期所在周尚未建立。")
        }
        .confirmationDialog(
            "完成当前 Focus？",
            isPresented: $showingCompleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("完成") {
                do {
                    try viewModel?.doneFocus()
                    selectCurrentFocus()
                    NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("取消", role: .cancel) { }
        }
        .alert(
            String(localized: "alert.title"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func selectCurrentFocus() {
        viewModel?.refresh()
        if let focus = viewModel?.today?.focusTask {
            selectionStore.select(.task(focus.id), for: .today)
        } else if let day = viewModel?.today {
            selectionStore.select(.day(day.dayId), for: .today)
        } else {
            selectionStore.select(nil, for: .today)
        }
    }
}

private struct WorkspaceProjectInspectorActions: View {
    let project: ProjectModel

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ExtensionsViewModel?
    @State private var showingAddTask = false
    @State private var showingEditProject = false

    private var isWritable: Bool {
        project.status == .planning || project.status == .active
    }

    var body: some View {
        WorkspaceInspectorSection(title: "操作") {
            if let viewModel {
                if isWritable {
                    Button {
                        showingAddTask = true
                    } label: {
                        Label("新增项目任务", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        showingEditProject = true
                    } label: {
                        Label("编辑项目信息", systemImage: "pencil")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                NavigationLink {
                    ProjectDetailView(project: project, viewModel: viewModel)
                } label: {
                    Label("打开完整项目台账", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.borderless)
        .onAppear {
            guard viewModel == nil else { return }
            let created = ExtensionsViewModel(modelContext: modelContext)
            created.refresh()
            viewModel = created
        }
        .sheet(isPresented: $showingAddTask, onDismiss: {
            viewModel?.refresh()
            NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
        }) {
            if let viewModel {
                AddProjectTaskSheet(project: project, viewModel: viewModel)
                    .weekFormWidth()
            }
        }
        .sheet(isPresented: $showingEditProject, onDismiss: {
            viewModel?.refresh()
            NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
        }) {
            if let viewModel {
                CreateProjectSheet(viewModel: viewModel, projectToEdit: project)
                    .weekFormWidth()
            }
        }
    }
}

private struct WorkspaceSuspendedInspectorActions: View {
    let task: SuspendedTaskItem
    @ObservedObject var selectionStore: WorkspaceSelectionStore

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ExtensionsViewModel?
    @State private var showingEditor = false
    @State private var showingAssignment = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        WorkspaceInspectorSection(title: "操作") {
            Button {
                showingAssignment = true
            } label: {
                Label("安排到日期", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                showingEditor = true
            } label: {
                Label("编辑", systemImage: "pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Menu {
                Button("续期 10 天") {
                    viewModel?.extendSuspendedTask(task, by: 10)
                    NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
                }
                Button("续期 30 天") {
                    viewModel?.extendSuspendedTask(task, by: 30)
                    NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
                }
            } label: {
                Label("调整期限", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("删除", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.borderless)
        .onAppear {
            guard viewModel == nil else { return }
            let created = ExtensionsViewModel(modelContext: modelContext)
            created.refresh(rebuildProjectSnapshots: false)
            viewModel = created
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            viewModel?.refresh(rebuildProjectSnapshots: false)
            NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
        }) {
            SuspendedTaskEditorSheet(
                title: "编辑悬置任务",
                initialTitle: task.title,
                initialDescription: task.taskDescription,
                initialType: task.taskType,
                initialTypeIdRaw: task.taskTypeIdRaw,
                initialCountdownDays: task.preferredCountdownDays,
                initialSteps: task.steps,
                initialAttachments: task.attachments
            ) { title, description, type, typeID, countdownDays, steps, attachments in
                viewModel?.updateSuspendedTask(
                    task,
                    title: title,
                    description: description,
                    type: type,
                    taskTypeIdRaw: typeID,
                    countdownDays: countdownDays,
                    steps: steps,
                    attachments: attachments
                )
            }
        }
        .sheet(isPresented: $showingAssignment, onDismiss: {
            viewModel?.refresh()
        }) {
            SuspendedTaskAssignSheet(taskTitle: task.title) { date in
                viewModel?.assignSuspendedTask(task, to: date)
                selectionStore.select(nil, for: .suspended)
                NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
            }
        }
        .confirmationDialog(
            "删除悬置任务",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                viewModel?.deleteSuspendedTask(task)
                selectionStore.select(nil, for: .suspended)
                NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后不会保留后路。")
        }
    }
}

private struct WorkspaceMindStampInspectorActions: View {
    let stamp: MindStampItem
    @ObservedObject var selectionStore: WorkspaceSelectionStore

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MindStampViewModel?
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        WorkspaceInspectorSection(title: "操作") {
            Button {
                showingEditor = true
            } label: {
                Label("编辑印记", systemImage: "pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("删除印记", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.borderless)
        .onAppear {
            guard viewModel == nil else { return }
            let created = MindStampViewModel(modelContext: modelContext)
            created.refresh()
            viewModel = created
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            viewModel?.refresh()
            NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
        }) {
            if let viewModel {
                MindStampEditorSheet(viewModel: viewModel, editingItem: stamp)
            }
        }
        .alert(
            String(localized: "mindstamp.delete.title"),
            isPresented: $showingDeleteConfirmation
        ) {
            Button(String(localized: "mindstamp.delete.confirm"), role: .destructive) {
                viewModel?.deleteStamp(stamp)
                selectionStore.select(nil, for: .mindStamps)
                NotificationCenter.default.post(name: .workspaceDataDidChange, object: nil)
            }
            Button(String(localized: "action.cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "mindstamp.delete.message"))
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
