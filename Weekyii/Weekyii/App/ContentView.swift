import SwiftUI

private enum MainTab: Hashable {
    case past
    case today
    case pending
    case extensions
    case settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userSettings: UserSettings
    @State private var selectedTab: MainTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            PastView()
                .tabItem {
                    Label(String(localized: "tab.past"), systemImage: "clock.arrow.circlepath")
                }
                .tag(MainTab.past)
            
            TodayView()
                .tabItem {
                    Label(String(localized: "tab.today"), systemImage: "sun.max")
                }
                .tag(MainTab.today)

            PendingView()
                .tabItem {
                    Label(String(localized: "tab.pending"), systemImage: "calendar.badge.plus")
                }
                .tag(MainTab.pending)

            ExtensionsHubView()
                .tabItem {
                    Label(String(localized: "tab.extensions"), systemImage: "square.grid.2x2")
                }
                .tag(MainTab.extensions)

            SettingsView()
                .tabItem {
                    Label(String(localized: "tab.settings"), systemImage: "gearshape")
                }
                .tag(MainTab.settings)
        }
        .id("\(appState.dataRevision)-\(userSettings.selectedTheme.rawValue)-\(userSettings.appearanceModeRaw)")
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
}
