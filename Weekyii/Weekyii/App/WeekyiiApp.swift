import SwiftUI
import SwiftData
import Combine

@main
struct WeekyiiApp: App {
    let modelContainer: ModelContainer
    @State private var appState = AppState()
    @State private var stateMachine: StateMachine?
    @Environment(\.scenePhase) private var scenePhase
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init() {
        do {
            let schema = Schema([WeekModel.self, DayModel.self, TaskItem.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .modelContainer(modelContainer)
                .onAppear {
                    initializeStateMachine()
                    Task { await NotificationService.shared.requestAuthorization() }
                    stateMachine?.processStateTransitions()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        stateMachine?.processStateTransitions()
                    }
                }
                .onReceive(minuteTimer) { _ in
                    if scenePhase == .active {
                        stateMachine?.processStateTransitions()
                    }
                }
        }
    }

    private func initializeStateMachine() {
        let context = modelContainer.mainContext
        stateMachine = StateMachine(
            modelContext: context,
            timeProvider: TimeProvider(),
            notificationService: .shared,
            appState: appState
        )
    }
}
