import SwiftUI

private enum MainTab: Hashable {
    case past
    case today
    case pending
    case settings
}

struct ContentView: View {
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

            SettingsView()
                .tabItem {
                    Label(String(localized: "tab.settings"), systemImage: "gearshape")
                }
                .tag(MainTab.settings)
        }
    }
}
