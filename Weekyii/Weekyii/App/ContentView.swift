import SwiftUI
import SwiftData

private enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case past
    case today
    case pending
    case extensions
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .past:
            return String(localized: "tab.past")
        case .today:
            return String(localized: "tab.today")
        case .pending:
            return String(localized: "tab.pending")
        case .extensions:
            return String(localized: "tab.extensions")
        case .settings:
            return String(localized: "tab.settings")
        }
    }

    var systemImage: String {
        switch self {
        case .past:
            return "clock.arrow.circlepath"
        case .today:
            return "sun.max"
        case .pending:
            return "calendar.badge.plus"
        case .extensions:
            return "square.grid.2x2"
        case .settings:
            return "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userSettings: UserSettings
    @Query(sort: \TaskTypeDefinition.sortOrder) private var taskTypeDefinitions: [TaskTypeDefinition]
    @State private var selectedTab: MainTab = .today
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all

    private var visualIdentity: String {
        "\(userSettings.selectedTheme.rawValue)-\(userSettings.appearanceModeRaw)"
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = WeekLayoutMetrics(availableWidth: proxy.size.width)

            Group {
                if metrics.layoutClass.supportsSidebar {
                    regularNavigation
                } else {
                    compactNavigation
                }
            }
            .environment(\.weekLayoutMetrics, metrics)
        }
        // Theme and appearance changes already invalidate this view through UserSettings.
        // Keeping them in the identity destroys every tab's NavigationStack on selection.
        .id(appState.dataRevision)
        .environment(
            \.taskTypePresentationCatalog,
            TaskTypePresentationCatalog(definitions: taskTypeDefinitions)
        )
        .tint(.weekyiiPrimary)
        .alert(String(localized: "alert.title"), isPresented: Binding(
            get: { appState.runtimeErrorMessage != nil },
            set: { newValue in
                if !newValue { appState.runtimeErrorMessage = nil }
            }
        )) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(appState.runtimeErrorMessage ?? "")
        }
        .onOpenURL { url in
            guard LiveActivityAction.parse(url: url) != nil else { return }
            selectedTab = .today
            LiveActivityActionRouter.handle(
                url: url,
                modelContext: modelContext,
                appState: appState,
                userSettings: userSettings
            )
        }
    }

    private var compactNavigation: some View {
        TabView(selection: $selectedTab) {
            tabContent(.past)
                .tabItem {
                    Label(MainTab.past.title, systemImage: MainTab.past.systemImage)
                }
                .tag(MainTab.past)

            tabContent(.today)
                .tabItem {
                    Label(MainTab.today.title, systemImage: MainTab.today.systemImage)
                }
                .tag(MainTab.today)

            tabContent(.pending)
                .tabItem {
                    Label(MainTab.pending.title, systemImage: MainTab.pending.systemImage)
                }
                .tag(MainTab.pending)

            tabContent(.extensions)
                .tabItem {
                    Label(MainTab.extensions.title, systemImage: MainTab.extensions.systemImage)
                }
                .tag(MainTab.extensions)

            tabContent(.settings)
                .tabItem {
                    Label(MainTab.settings.title, systemImage: MainTab.settings.systemImage)
                }
                .tag(MainTab.settings)
        }
    }

    private var regularNavigation: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            List(MainTab.allCases, selection: sidebarSelection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
                    .accessibilityIdentifier("mainSidebar_\(tab.rawValue)")
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("mainSidebar")
            .navigationTitle("Weekyii")
            .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 280)
        } detail: {
            GeometryReader { proxy in
                regularContentTabs
                    .environment(
                        \.weekLayoutMetrics,
                        WeekLayoutMetrics(availableWidth: proxy.size.width)
                    )
                    .background(Color.backgroundPrimary)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// A page-style TabView keeps every module's NavigationStack and local
    /// selection alive while the sidebar changes the visible module.
    private var regularContentTabs: some View {
        TabView(selection: $selectedTab) {
            tabContent(.past)
                .tag(MainTab.past)
            tabContent(.today)
                .tag(MainTab.today)
            tabContent(.pending)
                .tag(MainTab.pending)
            tabContent(.extensions)
                .tag(MainTab.extensions)
            tabContent(.settings)
                .tag(MainTab.settings)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var sidebarSelection: Binding<MainTab?> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if let newValue {
                    selectedTab = newValue
                }
            }
        )
    }

    @ViewBuilder
    private func tabContent(_ tab: MainTab) -> some View {
        switch tab {
        case .past:
            PastView()
                .id(visualIdentity)
        case .today:
            TodayView(animationsActive: selectedTab == .today && scenePhase == .active)
                .id(visualIdentity)
        case .pending:
            PendingView()
                .id(visualIdentity)
        case .extensions:
            ExtensionsHubView()
                .id(visualIdentity)
        case .settings:
            SettingsView()
        }
    }
}
