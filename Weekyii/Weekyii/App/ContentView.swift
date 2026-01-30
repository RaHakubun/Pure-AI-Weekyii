import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            PastView()
                .tabItem {
                    Label(String(localized: "tab.past"), systemImage: "clock.arrow.circlepath")
                }
            
            TodayView()
                .tabItem {
                    Label(String(localized: "tab.today"), systemImage: "sun.max")
                }

            WeekOverviewView()
                .tabItem {
                    Label(String(localized: "tab.week"), systemImage: "calendar")
                }

            PendingView()
                .tabItem {
                    Label(String(localized: "tab.pending"), systemImage: "calendar.badge.plus")
                }

            SettingsView()
                .tabItem {
                    Label(String(localized: "tab.settings"), systemImage: "gearshape")
                }
        }
    }
}
