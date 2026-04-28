import SwiftUI
import SwiftData
import Combine
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

protocol NotificationSettingsReadable {
    var killTimeReminderMinutes: Int { get }
    var fixedReminderEnabled: Bool { get }
    var fixedReminderHour: Int { get }
    var fixedReminderMinute: Int { get }
}

extension UserSettings: NotificationSettingsReadable {}

protocol LiveActivityThemeReadable {
    var selectedThemeRaw: String { get }
    var appearanceModeRaw: String { get }
    var premiumThemeUnlocked: Bool { get }
}

extension UserSettings: LiveActivityThemeReadable {}

@MainActor
protocol LiveActivityManaging {
    func reconcile(
        modelContext: ModelContext,
        now: Date,
        selectedThemeRaw: String,
        appearanceModeRaw: String,
        premiumThemeUnlocked: Bool
    )
    func reconcileImmediately(
        modelContext: ModelContext,
        now: Date,
        selectedThemeRaw: String,
        appearanceModeRaw: String,
        premiumThemeUnlocked: Bool
    ) async
    func endAll()
}

struct TodayActivitySnapshot: Equatable {
    var dayId: String
    var focusTitle: String
    var taskTypeRaw: String
    var killTime: Date
    var remainingSeconds: Int
    var completionPercent: Int
    var completedCount: Int
    var totalCount: Int
    var frozenCount: Int
    var liveTheme: LiveActivityThemeSnapshot
}

enum TodayActivitySnapshotBuilder {
    private static let calendar = Calendar(identifier: .iso8601)

    static func build(
        modelContext: ModelContext,
        now: Date,
        selectedThemeRaw: String,
        appearanceModeRaw: String,
        premiumThemeUnlocked: Bool
    ) -> TodayActivitySnapshot? {
        let todayId = calendar.startOfDay(for: now).dayId
        let descriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == todayId })
        guard let day = try? modelContext.fetch(descriptor).first else { return nil }
        guard day.status == .execute else { return nil }
        guard let focus = day.focusTask else { return nil }
        guard let killTime = killDate(for: day) else { return nil }

        let completedCount = day.completedTasks.count
        let frozenCount = day.frozenTasks.count
        let totalCount = completedCount + frozenCount + 1
        let completionPercent = totalCount > 0 ? Int((Double(completedCount) / Double(totalCount) * 100).rounded()) : 0
        let remainingSeconds = max(Int(killTime.timeIntervalSince(now)), 0)

        let theme = WeekTheme.resolvedTheme(rawValue: selectedThemeRaw, premiumThemeUnlocked: premiumThemeUnlocked)
        let appearanceMode = AppearanceMode(rawValue: appearanceModeRaw) ?? .system

        return TodayActivitySnapshot(
            dayId: day.dayId,
            focusTitle: focus.title,
            taskTypeRaw: focus.taskType.rawValue,
            killTime: killTime,
            remainingSeconds: remainingSeconds,
            completionPercent: completionPercent,
            completedCount: completedCount,
            totalCount: totalCount,
            frozenCount: frozenCount,
            liveTheme: theme.liveActivityThemeSnapshot(appearanceMode: appearanceMode)
        )
    }

    private static func killDate(for day: DayModel) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day.date)
        components.hour = day.killTimeHour
        components.minute = day.killTimeMinute
        components.second = 0
        return calendar.date(from: components)
    }
}

@MainActor
final class TodayLiveActivityService: LiveActivityManaging {
    static let shared = TodayLiveActivityService()

    private init() {}

    func reconcile(
        modelContext: ModelContext,
        now: Date,
        selectedThemeRaw: String,
        appearanceModeRaw: String,
        premiumThemeUnlocked: Bool
    ) {
        Task {
            await reconcileImmediately(
                modelContext: modelContext,
                now: now,
                selectedThemeRaw: selectedThemeRaw,
                appearanceModeRaw: appearanceModeRaw,
                premiumThemeUnlocked: premiumThemeUnlocked
            )
        }
    }

    func reconcileImmediately(
        modelContext: ModelContext,
        now: Date,
        selectedThemeRaw: String,
        appearanceModeRaw: String,
        premiumThemeUnlocked: Bool
    ) async {
        guard let snapshot = TodayActivitySnapshotBuilder.build(
            modelContext: modelContext,
            now: now,
            selectedThemeRaw: selectedThemeRaw,
            appearanceModeRaw: appearanceModeRaw,
            premiumThemeUnlocked: premiumThemeUnlocked
        ) else {
            await endAllActivities()
            return
        }

        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAllActivities()
            return
        }

        await upsert(snapshot: snapshot)
        #endif
    }

    func endAll() {
        Task {
            await endAllActivities()
        }
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
private extension TodayLiveActivityService {
    func endAllActivitiesImpl() async {
        for activity in Activity<TodayActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
#endif

private extension TodayLiveActivityService {
    func endAllActivities() async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        await endAllActivitiesImpl()
        #endif
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
private extension TodayLiveActivityService {
    func upsert(snapshot: TodayActivitySnapshot) async {
        let contentState = TodayActivityAttributes.ContentState(
            dayId: snapshot.dayId,
            focusTitle: snapshot.focusTitle,
            taskTypeRaw: snapshot.taskTypeRaw,
            killTime: snapshot.killTime,
            remainingSeconds: snapshot.remainingSeconds,
            completionPercent: snapshot.completionPercent,
            completedCount: snapshot.completedCount,
            totalCount: snapshot.totalCount,
            frozenCount: snapshot.frozenCount,
            liveTheme: snapshot.liveTheme
        )
        let content = ActivityContent(state: contentState, staleDate: snapshot.killTime.addingTimeInterval(60))
        let activities = Activity<TodayActivityAttributes>.activities

        if let existing = activities.first(where: { $0.attributes.dayId == snapshot.dayId }) {
            await existing.update(content)
            for activity in activities where activity.id != existing.id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let attributes = TodayActivityAttributes(dayId: snapshot.dayId)
        _ = try? Activity<TodayActivityAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }
}
#endif

@MainActor
enum LiveActivityActionRouter {
    private static var retainedViewModels: [TodayViewModel] = []

    static func handle(
        url: URL,
        modelContext: ModelContext,
        appState: AppState,
        userSettings: UserSettings
    ) {
        handle(
            url: url,
            modelContext: modelContext,
            appState: appState,
            userSettings: userSettings,
            notificationService: NotificationService.shared,
            liveActivityService: TodayLiveActivityService.shared
        )
    }

    static func handle(
        url: URL,
        modelContext: ModelContext,
        appState: AppState,
        userSettings: UserSettings,
        notificationService: any NotificationScheduling,
        liveActivityService: any LiveActivityManaging
    ) {
        guard let request = LiveActivityAction.parse(url: url) else { return }
        let timeProvider = TimeProvider()
        let viewModel = TodayViewModel(
            modelContext: modelContext,
            timeProvider: timeProvider,
            notificationService: notificationService,
            appState: appState,
            userSettings: userSettings
        )
        retainedViewModels.append(viewModel)
        if retainedViewModels.count > 8 {
            retainedViewModels.removeFirst(retainedViewModels.count - 8)
        }
        viewModel.refresh()

        do {
            switch request.action {
            case .doneFocus:
                try viewModel.doneFocus()
            case .postponeFocus:
                guard let focus = viewModel.today?.focusTask else { return }
                let targetDate = timeProvider.today.addingDays(request.days)
                let preview = try viewModel.previewPostpone(
                    taskID: focus.id,
                    taskTitle: focus.title,
                    targetDate: targetDate
                )
                _ = try viewModel.commitPostpone(preview, allowWeekCreation: true)
            case .openToday:
                break
            }

            appState.bumpDataRevision()
            WidgetSnapshotComposer.syncFromModelContext(
                modelContext: modelContext,
                now: timeProvider.now,
                todayDate: timeProvider.today,
                selectedThemeRaw: userSettings.selectedThemeRaw,
                appearanceModeRaw: userSettings.appearanceModeRaw,
                premiumThemeUnlocked: userSettings.premiumThemeUnlocked
            )
            scheduleCriticalLiveActivitySync(
                liveActivityService: liveActivityService,
                modelContext: modelContext,
                timeProvider: timeProvider,
                userSettings: userSettings
            )
        } catch {
            appState.runtimeErrorMessage = error.localizedDescription
        }
    }

    private static func scheduleCriticalLiveActivitySync(
        liveActivityService: any LiveActivityManaging,
        modelContext: ModelContext,
        timeProvider: TimeProviding,
        userSettings: UserSettings
    ) {
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "weekyii.live-action-sync",
            expirationHandler: nil
        )

        Task { @MainActor in
            defer {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }

            await liveActivityService.reconcileImmediately(
                modelContext: modelContext,
                now: timeProvider.now,
                selectedThemeRaw: userSettings.selectedThemeRaw,
                appearanceModeRaw: userSettings.appearanceModeRaw,
                premiumThemeUnlocked: userSettings.premiumThemeUnlocked
            )
            try? await Task.sleep(nanoseconds: 350_000_000)
            await liveActivityService.reconcileImmediately(
                modelContext: modelContext,
                now: timeProvider.now,
                selectedThemeRaw: userSettings.selectedThemeRaw,
                appearanceModeRaw: userSettings.appearanceModeRaw,
                premiumThemeUnlocked: userSettings.premiumThemeUnlocked
            )
        }
    }
}

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
    private let userSettings: any NotificationSettingsReadable & KillTimeSettings & LiveActivityThemeReadable
    private let liveActivityService: any LiveActivityManaging
    private var stateMachine: StateMachine
    private let calendar = Calendar(identifier: .iso8601)
    private var isReconciling = false

    init(
        modelContainer: ModelContainer,
        timeProvider: TimeProviding,
        notificationService: NotificationService,
        appState: any AppStateStore,
        userSettings: any NotificationSettingsReadable & KillTimeSettings & LiveActivityThemeReadable,
        liveActivityService: any LiveActivityManaging
    ) {
        self.modelContainer = modelContainer
        self.timeProvider = timeProvider
        self.notificationService = notificationService
        self.appState = appState
        self.userSettings = userSettings
        self.liveActivityService = liveActivityService
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
        liveActivityService.reconcile(
            modelContext: modelContainer.mainContext,
            now: timeProvider.now,
            selectedThemeRaw: userSettings.selectedThemeRaw,
            appearanceModeRaw: userSettings.appearanceModeRaw,
            premiumThemeUnlocked: userSettings.premiumThemeUnlocked
        )
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
                        refreshLiveActivity(modelContainer: modelContainer)
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        guard !Self.isRunningTests else { return }
                        if newPhase == .active {
                            _ = appHealthCoordinator?.reconcile(trigger: .sceneActive, force: false)
                            refreshWidgetSnapshot(modelContainer: modelContainer)
                            refreshLiveActivity(modelContainer: modelContainer)
                        }
                    }
                    .onChange(of: userSettings.selectedThemeRaw) { _, _ in
                        guard !Self.isRunningTests else { return }
                        refreshWidgetSnapshot(modelContainer: modelContainer)
                        refreshLiveActivity(modelContainer: modelContainer)
                    }
                    .onChange(of: userSettings.appearanceModeRaw) { _, _ in
                        guard !Self.isRunningTests else { return }
                        refreshWidgetSnapshot(modelContainer: modelContainer)
                        refreshLiveActivity(modelContainer: modelContainer)
                    }
                    .onChange(of: userSettings.premiumThemeUnlocked) { _, _ in
                        guard !Self.isRunningTests else { return }
                        refreshWidgetSnapshot(modelContainer: modelContainer)
                        refreshLiveActivity(modelContainer: modelContainer)
                    }
                    .onChange(of: appState.dataRevision) { _, _ in
                        guard !Self.isRunningTests else { return }
                        refreshWidgetSnapshot(modelContainer: modelContainer)
                        refreshLiveActivity(modelContainer: modelContainer)
                    }
                    .onReceive(minuteTimer) { _ in
                        guard !Self.isRunningTests else { return }
                        if scenePhase == .active {
                            _ = appHealthCoordinator?.reconcile(trigger: .minuteTick, force: false)
                            refreshWidgetSnapshot(modelContainer: modelContainer)
                            refreshLiveActivity(modelContainer: modelContainer)
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
            userSettings: userSettings,
            liveActivityService: TodayLiveActivityService.shared
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

    private func refreshLiveActivity(modelContainer: ModelContainer) {
        TodayLiveActivityService.shared.reconcile(
            modelContext: modelContainer.mainContext,
            now: Date(),
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
