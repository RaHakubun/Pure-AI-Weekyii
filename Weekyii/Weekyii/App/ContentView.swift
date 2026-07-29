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
    @State private var selectedWorkspaceRoute: WorkspaceRoute = .today

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
            selectedWorkspaceRoute = .today
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
        WorkspaceShell(
            selectedRoute: $selectedWorkspaceRoute,
            animationsActive: scenePhase == .active
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
