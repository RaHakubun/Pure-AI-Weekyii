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
        userSettings: UserSettings,
        timeProvider: (any TimeProviding)? = nil
    ) {
        handle(
            url: url,
            modelContext: modelContext,
            appState: appState,
            userSettings: userSettings,
            notificationService: NotificationService.shared,
            liveActivityService: TodayLiveActivityService.shared,
            timeProvider: timeProvider
        )
    }

    static func handle(
        url: URL,
        modelContext: ModelContext,
        appState: AppState,
        userSettings: UserSettings,
        notificationService: any NotificationScheduling,
        liveActivityService: any LiveActivityManaging,
        timeProvider: (any TimeProviding)? = nil
    ) {
        guard let request = LiveActivityAction.parse(url: url) else { return }
        let resolvedTimeProvider = timeProvider ?? TimeProvider()
        let viewModel = TodayViewModel(
            modelContext: modelContext,
            timeProvider: resolvedTimeProvider,
            notificationService: notificationService,
            appState: appState,
            userSettings: userSettings,
            liveActivityService: liveActivityService
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
                let targetDate = resolvedTimeProvider.today.addingDays(request.days)
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
                now: resolvedTimeProvider.now,
                todayDate: resolvedTimeProvider.today,
                selectedThemeRaw: userSettings.selectedThemeRaw,
                appearanceModeRaw: userSettings.appearanceModeRaw,
                premiumThemeUnlocked: userSettings.premiumThemeUnlocked
            )
            scheduleCriticalLiveActivitySync(
                liveActivityService: liveActivityService,
                modelContext: modelContext,
                timeProvider: resolvedTimeProvider,
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

        HabitTaskMaterializer(modelContext: modelContainer.mainContext)
            .sync(today: timeProvider.today, now: timeProvider.now)

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
    @UIApplicationDelegateAdaptor(WeekyiiAppDelegate.self) private var appDelegate
    @State private var launchState: WeekyiiPersistence.LaunchState
    @State private var showLaunchOverlay = !WeekyiiApp.isUITesting && !WeekyiiApp.isRunningTests
    @StateObject private var appState = AppState()
    @StateObject private var userSettings: UserSettings
    @State private var appHealthCoordinator: AppHealthCoordinator?
    @State private var cloudSyncCoordinator: CloudSyncCoordinator
    @State private var cloudSyncNetworkMonitor: CloudSyncNetworkRecoveryMonitor?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init() {
        let userSettings = UserSettings()
        _userSettings = StateObject(wrappedValue: userSettings)
        _cloudSyncCoordinator = State(initialValue: CloudSyncCoordinator(settings: userSettings))

        if Self.isUITesting || Self.isRunningTests {
            do {
                let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
                try TaskTypeCatalog.seedBuiltInTypesIfNeeded(in: container.mainContext)
                _launchState = State(
                    initialValue: .ready(container, diagnostics: .clean)
                )
            } catch {
                _launchState = State(
                    initialValue: .failed(
                        "UI 测试容器初始化失败：\(error.localizedDescription)"
                    )
                )
            }
        } else {
            _launchState = State(initialValue: .resolving)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch launchState {
            case .resolving:
                PersistenceResolvingView()
                    .task {
                        bootstrapPersistentContainer()
                    }
            case .ready(let modelContainer, _):
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(userSettings)
                    .environment(cloudSyncCoordinator)
                    .modelContainer(modelContainer)
                    .preferredColorScheme(userSettings.effectiveColorScheme)
                    // Personalised themes restyle every SF Symbol at once via the
                    // environment, so no individual `Image(systemName:)` call needs editing.
                    .symbolVariant(userSettings.selectedTheme.visualStyle.symbolVariant.symbolVariants)
                    .onAppear {
                        guard !Self.isRunningTests else { return }
                        initializeAppHealthCoordinator(modelContainer: modelContainer)
                        Task { await NotificationService.shared.requestAuthorization() }
                        _ = appHealthCoordinator?.reconcile(trigger: .launch, force: false)
                        refreshWidgetSnapshot(modelContainer: modelContainer)
                        refreshLiveActivity(modelContainer: modelContainer)
                    }
                    .task {
                        guard !Self.isRunningTests else { return }
                        cloudSyncCoordinator.attach(
                            localStore: SwiftDataCloudSyncLocalStore(context: modelContainer.mainContext),
                            onBusinessDataChanged: { appState.bumpDataRevision() }
                        )
                        let networkMonitor = CloudSyncNetworkRecoveryMonitor {
                            await cloudSyncCoordinator.handle(.networkRecovered)
                        }
                        cloudSyncNetworkMonitor = networkMonitor
                        networkMonitor.start()
                        await cloudSyncCoordinator.handle(.appLaunch)
                        appDelegate.attach(coordinator: cloudSyncCoordinator)
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        guard !Self.isRunningTests else { return }
                        if newPhase == .active {
                            Task { await cloudSyncCoordinator.handle(.sceneActive) }
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
                    .overlay {
                        if showLaunchOverlay {
                            WeekyiiLaunchOverlay(
                                reduceMotion: systemReduceMotion || userSettings.reduceMotionEnabled,
                                onFinished: {
                                    withAnimation(.easeOut(duration: 0.35)) {
                                        showLaunchOverlay = false
                                    }
                                }
                            )
                            .transition(.opacity)
                        }
                    }
            case .failed(let message):
                PersistenceFailureView(
                    message: message,
                    canRestore: BackupRecoveryService.listSnapshots(
                        storeURL: WeekyiiPersistence.persistentStoreURL()
                    ).contains(where: \.isValid),
                    onRetry: retryPersistentStore,
                    onRestore: restoreLatestPersistentStoreSnapshot
                )
                    .preferredColorScheme(userSettings.effectiveColorScheme)
            }
        }
    }

    private func retryPersistentStore() {
        launchState = WeekyiiPersistence.bootstrapPersistentContainer()
    }

    private func restoreLatestPersistentStoreSnapshot() {
        let storeURL = WeekyiiPersistence.persistentStoreURL()
        do {
            guard try BackupRecoveryService.restoreLatestValidSnapshot(to: storeURL) != nil else {
                launchState = .failed("没有找到可用的本地恢复点。")
                return
            }
            launchState = WeekyiiPersistence.bootstrapPersistentContainer(
                storeURL: storeURL
            )
        } catch {
            launchState = .failed("恢复本地数据库失败：\(error.localizedDescription)")
        }
    }

    private func bootstrapPersistentContainer() {
        guard case .resolving = launchState else {
            assertionFailure("Weekyii opened a persistence container more than once during launch.")
            return
        }

        switch WeekyiiPersistence.bootstrapPersistentContainer() {
        case .ready(let container, let diagnostics):
            if diagnostics.invariantRepair.totalRepairs > 0 || !diagnostics.consistency.isConsistent {
                print(
                    "Weekyii: persistence bootstrap diagnostics "
                        + "repairs=\(diagnostics.invariantRepair) "
                        + "consistency=\(diagnostics.consistency.diagnostics)"
                )
            }
            launchState = .ready(container, diagnostics: diagnostics)
        case .failed(let message):
            launchState = .failed(message)
        case .resolving:
            assertionFailure("bootstrapPersistentContainer cannot return a resolving state.")
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
    let canRestore: Bool
    let onRetry: () -> Void
    let onRestore: () -> Void
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
                    Button("重试打开数据库", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(.weekyiiPrimary)

                    if canRestore {
                        Button("从最近恢复点还原", action: onRestore)
                            .buttonStyle(.bordered)
                    }

                    Button("导出诊断信息") {
                        UIPasteboard.general.string = WeekyiiPersistence.failureDiagnostics()
                        copied = true
                    }
                    .buttonStyle(.bordered)

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

private struct PersistenceResolvingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("正在打开本地数据…")
                .font(.headline)
            Text("本地数据准备完成后即可继续使用 Weekyii")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundPrimary)
    }
}

/// Full-screen launch animation shown while the storyboard splash hands off:
/// the wordmark is revealed left-to-right like being written, the subtitle fades
/// in, then the overlay cross-fades away to the home screen.
private struct WeekyiiLaunchOverlay: View {
    let reduceMotion: Bool
    let onFinished: () -> Void

    @State private var logoWidth: CGFloat = 0
    @State private var writeProgress: CGFloat = 0
    @State private var subtitleOpacity: Double = 0

    // Do not "sync" this value with LaunchScreen.storyboard: together with
    // LaunchBackground.imageset it tunes the cached splash snapshot, whose sRGB
    // bytes are read as Display P3 coordinates (#F6C47E -> #FFC172 on screen).
    // Changing either value shifts the rendered splash; re-measure instead.
    private let background = Color(red: 1.0, green: 0.760784, blue: 0.447059)
    private let brandInk = Color.black

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Weekyii")
                    .font(.custom("SnellRoundhand-Bold", size: 42))
                    .foregroundColor(brandInk)
                    .fixedSize()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.onAppear { logoWidth = proxy.size.width }
                        }
                    )
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(logoWidth * writeProgress, 0.001))
                    }

                Text("以周为核心管理你的每一天")
                    .font(.system(size: 16))
                    .foregroundColor(brandInk.opacity(0.78))
                    .opacity(subtitleOpacity)
            }
        }
        .task { await runSequence() }
    }

    private func runSequence() async {
        var attempts = 0
        while logoWidth == 0 && attempts < 30 {
            attempts += 1
            try? await Task.sleep(nanoseconds: 16_000_000)
        }

        if reduceMotion {
            writeProgress = 1
            subtitleOpacity = 1
            try? await Task.sleep(nanoseconds: 900_000_000)
            onFinished()
            return
        }

        withAnimation(.easeInOut(duration: 1.5)) {
            writeProgress = 1
        }
        try? await Task.sleep(nanoseconds: 1_550_000_000)

        withAnimation(.easeOut(duration: 0.35)) {
            subtitleOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        onFinished()
    }
}
