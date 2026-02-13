import SwiftUI
import SwiftData
import Combine

@main
struct WeekyiiApp: App {
    let modelContainer: ModelContainer
    let startupWarning: String?
    @StateObject private var appState = AppState()
    @StateObject private var userSettings = UserSettings()
    @State private var stateMachine: StateMachine?
    @Environment(\.scenePhase) private var scenePhase
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        let schema = Schema([WeekModel.self, DayModel.self, TaskItem.self, TaskStep.self, TaskAttachment.self])
        let storeURL = Self.persistentStoreURL()
        let config = ModelConfiguration("Weekyii", schema: schema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: config)
            startupWarning = nil
        } catch {
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                modelContainer = try ModelContainer(for: schema, configurations: memoryConfig)
                startupWarning = "本地数据暂时不可用，已进入只保启动模式。请尽快备份并重启。"
            } catch {
                fatalError("Failed to initialize ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(userSettings)
                .modelContainer(modelContainer)
                .preferredColorScheme(.light)
                .onAppear {
                    guard !Self.isRunningTests else { return }
                    initializeStateMachine()
                    Task { await NotificationService.shared.requestAuthorization() }
                    if let startupWarning {
                        appState.runtimeErrorMessage = startupWarning
                    }
                    stateMachine?.processStateTransitions()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard !Self.isRunningTests else { return }
                    if newPhase == .active {
                        stateMachine?.processStateTransitions()
                    }
                }
                .onReceive(minuteTimer) { _ in
                    guard !Self.isRunningTests else { return }
                    if scenePhase == .active {
                        stateMachine?.processStateTransitions()
                    }
                }
        }
    }

    private func initializeStateMachine() {
        stateMachine = StateMachine(
            modelContainer: modelContainer,
            timeProvider: TimeProvider(),
            notificationService: .shared,
            appState: appState
        )
    }

    private static func persistentStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Weekyii", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Weekyii.store")
    }
}
