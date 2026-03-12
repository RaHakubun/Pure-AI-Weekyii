import SwiftUI
import SwiftData
import Combine

@main
struct WeekyiiApp: App {
    let launchState: WeekyiiPersistence.LaunchState
    @StateObject private var appState = AppState()
    @StateObject private var userSettings = UserSettings()
    @State private var stateMachine: StateMachine?
    @Environment(\.scenePhase) private var scenePhase
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init() {
        if Self.isUITesting {
            do {
                launchState = .ready(try WeekyiiPersistence.makeModelContainer(inMemory: true))
            } catch {
                launchState = .failed("UI 测试容器初始化失败：\(error.localizedDescription)")
            }
        } else {
            launchState = WeekyiiPersistence.bootstrapPersistentContainer()
        }
    }

    var body: some Scene {
        WindowGroup {
            switch launchState {
            case .ready(let modelContainer):
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(userSettings)
                    .modelContainer(modelContainer)
                    .preferredColorScheme(.light)
                    .onAppear {
                        guard !Self.isRunningTests else { return }
                        initializeStateMachine(modelContainer: modelContainer)
                        Task { await NotificationService.shared.requestAuthorization() }
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
            case .failed(let message):
                PersistenceFailureView(message: message)
                    .preferredColorScheme(.light)
            }
        }
    }

    private func initializeStateMachine(modelContainer: ModelContainer) {
        stateMachine = StateMachine(
            modelContainer: modelContainer,
            timeProvider: TimeProvider(),
            notificationService: .shared,
            appState: appState,
            userSettings: userSettings
        )
    }
}

private struct PersistenceFailureView: View {
    let message: String

    var body: some View {
        ZStack {
            Color.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: WeekSpacing.lg) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.weekyiiPrimary)

                Text("数据库不可用")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(WeekSpacing.xl)
            .frame(maxWidth: 420)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous))
            .padding(WeekSpacing.base)
        }
    }
}
