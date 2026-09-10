import SwiftUI
import SwiftData

private enum MainTab: Hashable {
    case past
    case today
    case pending
    case extensions
    case settings
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userSettings: UserSettings
    @Query(sort: \TaskTypeDefinition.sortOrder) private var taskTypeDefinitions: [TaskTypeDefinition]
    @State private var selectedTab: MainTab = .today

    private var visualIdentity: String {
        "\(userSettings.selectedTheme.rawValue)-\(userSettings.appearanceModeRaw)"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            PastView()
                .id(visualIdentity)
                .tabItem {
                    tabLabel(String(localized: "tab.past"), systemImage: "clock.arrow.circlepath")
                }
                .tag(MainTab.past)
            
            TodayView(animationsActive: selectedTab == .today && scenePhase == .active)
                .id(visualIdentity)
                .tabItem {
                    tabLabel(String(localized: "tab.today"), systemImage: "sun.max")
                }
                .tag(MainTab.today)

            PendingView()
                .id(visualIdentity)
                .tabItem {
                    tabLabel(String(localized: "tab.pending"), systemImage: "calendar")
                }
                .tag(MainTab.pending)

            ExtensionsHubView(animationsActive: selectedTab == .extensions && scenePhase == .active)
                .id(visualIdentity)
                .tabItem {
                    tabLabel(String(localized: "tab.extensions"), systemImage: "square.grid.2x2")
                }
                .tag(MainTab.extensions)

            SettingsView()
                .tabItem {
                    tabLabel(String(localized: "tab.settings"), systemImage: "gearshape")
                }
                .tag(MainTab.settings)
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

    private func tabLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .symbolVariant(.none)
        }
    }
}
