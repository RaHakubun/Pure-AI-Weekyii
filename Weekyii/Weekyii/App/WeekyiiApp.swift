import SwiftUI
import SwiftData
import Combine
import UIKit

protocol NotificationSettingsReadable {
    var killTimeReminderMinutes: Int { get }
    var fixedReminderEnabled: Bool { get }
    var fixedReminderHour: Int { get }
    var fixedReminderMinute: Int { get }
}

extension UserSettings: NotificationSettingsReadable {}

enum AppHealthTrigger: String {
    case launch
    case sceneActive
    case minuteTick
    case manualResync
}

protocol AppHealthCoordinating {
    @discardableResult
    func reconcile(trigger: AppHealthTrigger, force: Bool) -> StateReconcileReport
    func diagnosticsSnapshot() -> String
}

@MainActor
final class AppHealthCoordinator: AppHealthCoordinating {
    private let modelContainer: ModelContainer
    private let timeProvider: TimeProviding
    private let notificationService: NotificationService
    private let appState: any AppStateStore
    private let userSettings: any NotificationSettingsReadable
    private var stateMachine: StateMachine
    private let calendar = Calendar(identifier: .iso8601)
    private var isReconciling = false

    init(
        modelContainer: ModelContainer,
        timeProvider: TimeProviding,
        notificationService: NotificationService,
        appState: any AppStateStore,
        userSettings: any NotificationSettingsReadable & KillTimeSettings
    ) {
        self.modelContainer = modelContainer
        self.timeProvider = timeProvider
        self.notificationService = notificationService
        self.appState = appState
        self.userSettings = userSettings
        self.stateMachine = StateMachine(
            modelContainer: modelContainer,
            timeProvider: timeProvider,
            notificationService: notificationService,
            appState: appState,
            userSettings: userSettings
        )
    }

    @discardableResult
    func reconcile(trigger: AppHealthTrigger, force: Bool = false) -> StateReconcileReport {
        guard !isReconciling else {
            var skipped = StateReconcileReport()
            skipped.skipped = true
            skipped.processedAt = timeProvider.now
            return skipped
        }
        isReconciling = true
        defer { isReconciling = false }

        let report = stateMachine.reconcile(now: timeProvider.now, force: force || trigger == .manualResync)
        rescheduleNotificationsAfterReconcile()
        return report
    }

    func diagnosticsSnapshot() -> String {
        let context = modelContainer.mainContext
        let weeks = (try? context.fetch(FetchDescriptor<WeekModel>())) ?? []
        let days = (try? context.fetch(FetchDescriptor<DayModel>())) ?? []
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let suspended = (try? context.fetch(FetchDescriptor<SuspendedTaskItem>())) ?? []
        let statusCounts = Dictionary(grouping: days, by: \.status).mapValues(\.count)
        let presentWeeks = weeks.filter { $0.status == .present }.count

        return [
            "timestamp=\(ISO8601DateFormatter().string(from: Date()))",
            "today=\(timeProvider.today.dayId)",
            "presentWeeks=\(presentWeeks)",
            "weeks=\(weeks.count),days=\(days.count),tasks=\(tasks.count),suspended=\(suspended.count)",
            "dayStatus=\(statusCounts)"
        ].joined(separator: "\n")
    }

    private func rescheduleNotificationsAfterReconcile() {
        let context = modelContainer.mainContext
        let todayId = timeProvider.today.dayId
        let days = (try? context.fetch(FetchDescriptor<DayModel>())) ?? []

        for day in days {
            let isToday = day.dayId == todayId
            let isOpen = day.status == .draft || day.status == .execute
            if isToday && isOpen {
                notificationService.scheduleKillTimeNotification(
                    for: day,
                    reminderMinutes: userSettings.killTimeReminderMinutes,
                    fixedReminder: userSettings.fixedReminderEnabled
                    ? DateComponents(hour: userSettings.fixedReminderHour, minute: userSettings.fixedReminderMinute)
                    : nil
                )
            } else {
                notificationService.cancelKillTimeNotification(for: day)
            }
        }

        let suspended = ((try? context.fetch(FetchDescriptor<SuspendedTaskItem>())) ?? [])
            .filter { $0.status == .active }
        for task in suspended {
            notificationService.scheduleSuspendedTaskNotifications(for: task)
        }
    }
}

@main
struct WeekyiiApp: App {
    let launchState: WeekyiiPersistence.LaunchState
    @StateObject private var appState = AppState()
    @StateObject private var userSettings = UserSettings()
    @State private var appHealthCoordinator: AppHealthCoordinator?
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
                    .preferredColorScheme(userSettings.effectiveColorScheme)
                    .onAppear {
                        guard !Self.isRunningTests else { return }
                        initializeAppHealthCoordinator(modelContainer: modelContainer)
                        Task { await NotificationService.shared.requestAuthorization() }
                        _ = appHealthCoordinator?.reconcile(trigger: .launch, force: false)
                        refreshWidgetSnapshot(modelContainer: modelContainer)
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        guard !Self.isRunningTests else { return }
                        if newPhase == .active {
                            _ = appHealthCoordinator?.reconcile(trigger: .sceneActive, force: false)
                            refreshWidgetSnapshot(modelContainer: modelContainer)
                        }
                    }
                    .onChange(of: userSettings.selectedThemeRaw) { _, _ in
                        guard !Self.isRunningTests else { return }
                        refreshWidgetSnapshot(modelContainer: modelContainer)
                    }
                    .onChange(of: userSettings.appearanceModeRaw) { _, _ in
                        guard !Self.isRunningTests else { return }
                        refreshWidgetSnapshot(modelContainer: modelContainer)
                    }
                    .onChange(of: userSettings.premiumThemeUnlocked) { _, _ in
                        guard !Self.isRunningTests else { return }
                        refreshWidgetSnapshot(modelContainer: modelContainer)
                    }
                    .onChange(of: appState.dataRevision) { _, _ in
                        guard !Self.isRunningTests else { return }
                        refreshWidgetSnapshot(modelContainer: modelContainer)
                    }
                    .onReceive(minuteTimer) { _ in
                        guard !Self.isRunningTests else { return }
                        if scenePhase == .active {
                            _ = appHealthCoordinator?.reconcile(trigger: .minuteTick, force: false)
                            refreshWidgetSnapshot(modelContainer: modelContainer)
                        }
                    }
            case .failed(let message):
                PersistenceFailureView(message: message)
                    .preferredColorScheme(userSettings.effectiveColorScheme)
            }
        }
    }

    private func initializeAppHealthCoordinator(modelContainer: ModelContainer) {
        appHealthCoordinator = AppHealthCoordinator(
            modelContainer: modelContainer,
            timeProvider: TimeProvider(),
            notificationService: .shared,
            appState: appState,
            userSettings: userSettings
        )
    }

    private func refreshWidgetSnapshot(modelContainer: ModelContainer) {
        WidgetSnapshotComposer.syncFromModelContext(
            modelContext: modelContainer.mainContext,
            now: Date(),
            todayDate: Date(),
            selectedThemeRaw: userSettings.selectedThemeRaw,
            appearanceModeRaw: userSettings.appearanceModeRaw,
            premiumThemeUnlocked: userSettings.premiumThemeUnlocked
        )
    }
}

private struct PersistenceFailureView: View {
    let message: String
    @State private var copied = false

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

                VStack(spacing: WeekSpacing.sm) {
                    Button("导出诊断信息") {
                        UIPasteboard.general.string = WeekyiiPersistence.failureDiagnostics()
                        copied = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.weekyiiPrimary)

                    if copied {
                        Text("诊断信息已复制到剪贴板")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(WeekSpacing.xl)
            .frame(maxWidth: 420)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous))
            .padding(WeekSpacing.base)
        }
    }
}
