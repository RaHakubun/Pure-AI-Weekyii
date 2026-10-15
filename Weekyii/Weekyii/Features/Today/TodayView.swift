import SwiftUI
import SwiftData

private enum TodaySection: Int {
    case today
    case week
}

private enum TaskEditorContext: String {
    case draft
    case flexibleExecution
}

private enum DraftTaskEditorMode: Identifiable {
    case create(TaskEditorContext)
    case edit(TaskItem, TaskEditorContext)

    var id: String {
        switch self {
        case .create(let context):
            return "create-\(context.rawValue)"
        case .edit(let task, let context):
            return "edit-\(context.rawValue)-\(task.id.uuidString)"
        }
    }
}

enum TodayStartFlowStep: Equatable {
    case warning
    case ritual
}

struct TodayStartFlowCoordinator {
    var isPresented = false
    var step: TodayStartFlowStep = .warning

    mutating func present() {
        isPresented = true
        step = .warning
    }

    mutating func chooseDirectEnter() {
        step = .ritual
    }

    mutating func cancel() {
        isPresented = false
        step = .warning
    }
}

private struct PendingPostponeRequest {
    let taskID: UUID
    let taskTitle: String
    let targetDate: Date
}

struct TodayView: View {
    private enum TodayKillTimeConfirmMode {
        case normal
        case immediateExpire(expiredCount: Int)
    }
    private let floatingStartOverlayReserveHeight: CGFloat = 120
    let animationsActive: Bool

    init(animationsActive: Bool = true) {
        self.animationsActive = animationsActive
    }

    private static let dayIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let postponeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userSettings: UserSettings

    @State private var viewModel: TodayViewModel?
    @State private var selectedTaskForDetail: TaskItem?
    @State private var draftTaskEditorMode: DraftTaskEditorMode?
    @State private var errorMessage: String?
    @State private var startFlowCoordinator = TodayStartFlowCoordinator()
    @State private var startFlowStamp: MindStampItem?
    @State private var startFlowDetent: PresentationDetent = .fraction(0.5)
    @State private var pendingTodayKillTimeHour: Int?
    @State private var pendingTodayKillTimeMinute: Int?
    @State private var showingTodayKillTimeConfirm = false
    @State private var todayKillTimeConfirmMode: TodayKillTimeConfirmMode = .normal
    @State private var selectedSection: TodaySection = .today
    @State private var taskForPostpone: TaskItem?
    @State private var pendingPostponeRequest: PendingPostponeRequest?
    @State private var pendingPostponePreview: TodayViewModel.PostponePreview?
    @State private var showingPostponeConfirm = false
    @State private var showingPostponeWeekCreationConfirm = false
    

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if let day = viewModel.today {
                        content(for: day, viewModel: viewModel)
                    } else if let message = viewModel.errorMessage {
                        loadingErrorView(message: message) {
                            viewModel.refresh()
                        }
                    } else {
                        ProgressView()
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WeekLogo(size: .medium, animated: true)
                }
            }
            .alert(String(localized: "alert.title"), isPresented: Binding(get: {
                errorMessage != nil
            }, set: { newValue in
                if !newValue { errorMessage = nil }
            })) {
                Button(String(localized: "action.ok"), role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .background(todaySceneBackground)
        .onAppear {
            if viewModel == nil {
                let model = TodayViewModel(
                    modelContext: modelContext,
                    timeProvider: TimeProvider(),
                    notificationService: NotificationService.shared,
                    appState: appState,
                    userSettings: userSettings,
                    liveActivityService: TodayLiveActivityService.shared
                )
                viewModel = model
            }
            viewModel?.refresh()
            viewModel?.seedDraftTasksForUITestsIfNeeded()
            viewModel?.seedFlexibleExecutionForUITestsIfNeeded()
        }
        .onChange(of: userSettings.defaultKillTimeHour) { _, _ in
            viewModel?.refresh()
        }
        .onChange(of: userSettings.defaultKillTimeMinute) { _, _ in
            viewModel?.refresh()
        }
        .refreshOnStateTransitions(using: appState) {
            viewModel?.refresh()
        }
        .onChange(of: viewModel?.errorMessage) { _, newValue in
            if let newValue {
                errorMessage = newValue
            }
        }
        .sheet(item: $selectedTaskForDetail) { task in
            // Today aggregates tasks from several sources; a habit task opens
            // its own read-only card drawn from the habit.
            if task.habit != nil {
                HabitTaskDetailSheet(task: task)
            } else {
                TaskEditorSheet(
                    title: String(localized: "task.detail.title"),
                    isReadOnly: true,
                    initialTitle: task.title,
                    initialDescription: task.taskDescription,
                    initialType: task.taskType,
                    initialTypeIdRaw: task.taskTypeIdRaw,
                    initialSteps: task.steps,
                    initialAttachments: task.attachments,
                    onSave: { _, _, _, _, _ in }
                )
            }
        }
        .sheet(item: $draftTaskEditorMode) { mode in
            draftTaskEditorSheet(mode: mode)
        }
        .sheet(isPresented: $startFlowCoordinator.isPresented, onDismiss: {
            startFlowStamp = nil
            startFlowCoordinator.cancel()
            startFlowDetent = .fraction(0.5)
        }) {
            if let viewModel {
                startFlowSheet(viewModel: viewModel)
                    .presentationDetents(
                        [.fraction(0.5), .fraction(0.62), .large],
                        selection: $startFlowDetent
                    )
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.backgroundPrimary)
            }
        }
        .sheet(item: $taskForPostpone) { task in
            PostponeTaskSheet(
                taskTitle: task.title,
                onSubmit: { targetDate in
                    stagePostponeRequest(for: task, targetDate: targetDate)
                },
                presentationStyle: .sheet,
                onCancel: {
                    taskForPostpone = nil
                }
            )
            .presentationDetents([.fraction(0.58), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.backgroundPrimary)
            .presentationCornerRadius(26)
        }
        .alert("确认后移任务", isPresented: $showingPostponeConfirm) {
            Button(String(localized: "action.cancel"), role: .cancel) {
                clearPendingPostponeContext()
            }
            Button("确认后移") {
                guard let viewModel else { return }
                confirmPostponeRequest(viewModel: viewModel)
            }
        } message: {
            Text(postponeConfirmMessage)
        }
        .alert("目标周尚未创建", isPresented: $showingPostponeWeekCreationConfirm) {
            Button(String(localized: "action.cancel"), role: .cancel) {
                clearPendingPostponeContext()
            }
            Button("创建并移动", role: .destructive) {
                guard let viewModel else { return }
                confirmPostponeWithWeekCreation(viewModel: viewModel)
            }
        } message: {
            Text(postponeCreateWeekConfirmMessage)
        }
    }

    @ViewBuilder
    private func content(for day: DayModel, viewModel: TodayViewModel) -> some View {
        TodayWeekSwitcher(selectedSection: $selectedSection, isPagingEnabled: false) {
            todayContent(day: day, viewModel: viewModel)
        } weekContent: {
            WeekOverviewContentView()
        }
            .background(Color.clear)
    }

    private func todayContent(day: DayModel, viewModel: TodayViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                // 顶部状态卡片
                statusCard(for: day)

                // 任务流区域
                taskFlowSection(day: day, viewModel: viewModel)

                // 截止时间（放在最后）
                killTimeCard(day: day, viewModel: viewModel)
            }
            .weekPadding(WeekSpacing.base)
            .padding(.bottom, shouldShowFloatingStartButton(for: day) ? floatingStartOverlayReserveHeight : 0)
        }
        .overlay(alignment: .bottom) {
            if shouldShowFloatingStartButton(for: day) {
                floatingStartButtonOverlay
            }
        }
    }

    @ViewBuilder
    private func taskFlowSection(day: DayModel, viewModel: TodayViewModel) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.lg) {
            // 根据状态显示不同内容
            switch day.status {
            case .empty:
                emptyStateContent(day: day, viewModel: viewModel)
                
            case .draft:
                draftStateContent(day: day, viewModel: viewModel)
                
            case .execute:
                executeStateContent(day: day, viewModel: viewModel)
                
            case .completed:
                completedStateContent(day: day)
                
            case .expired:
                expiredStateContent(day: day)
            }
        }
    }

    // MARK: - Status Card
    
    @ViewBuilder
    private func statusCard(for day: DayModel) -> some View {
        WeekCard(accentColor: day.status.color) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        Text(String(localized: "today.status"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        StatusBadge(status: day.status)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: WeekSpacing.xs) {
                        Text(String(localized: "today.days_started"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text("\(appState.daysStartedCount)")
                            .font(.titleMedium)
                            .foregroundColor(.weekyiiPrimary)
                    }
                }

                ThemeStatusArtwork(theme: userSettings.selectedTheme)
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                            .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                    )

                // 日期显示
                Text(formatDate(day.dayId))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func killTimeCard(day: DayModel, viewModel: TodayViewModel) -> some View {
        if day.status == .expired {
            TodayEndedKillTimeFootnote(hour: day.killTimeHour, minute: day.killTimeMinute)
        } else {
            editableKillTimeCard(day: day, viewModel: viewModel)
        }
    }

    private func killTimeTitleRow(hour: Int, minute: Int, isEditable: Bool) -> some View {
        HStack(spacing: WeekSpacing.xs) {
            Image(systemName: "clock.fill")
                .foregroundColor(.accentOrange)
            Text(String(localized: "killtime.title"))
                .font(.titleSmall)
                .foregroundColor(.textPrimary)
            Spacer(minLength: WeekSpacing.sm)
            if isEditable {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let text = killTimeRemainingText(hour: hour, minute: minute, now: context.date) {
                        Text(text)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func killTimeRemainingText(hour: Int, minute: Int, now: Date) -> String? {
        let calendar = Calendar(identifier: .iso8601)
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        guard let kill = calendar.date(from: components) else { return nil }
        let minutes = Int(kill.timeIntervalSince(now) / 60)
        guard minutes > 0 else { return nil }
        if minutes >= 60 {
            return String(
                format: String(localized: "killtime.remaining.hours", defaultValue: "还剩 %1$lld 小时 %2$lld 分"),
                locale: Locale.current,
                Int64(minutes / 60),
                Int64(minutes % 60)
            )
        }
        return String(
            format: String(localized: "killtime.remaining.minutes", defaultValue: "还剩 %lld 分钟"),
            locale: Locale.current,
            Int64(minutes)
        )
    }

    private func killTimePendingBar(hour: Int, minute: Int, viewModel: TodayViewModel) -> some View {
        HStack(spacing: WeekSpacing.md) {
            Text(String(
                format: String(localized: "killtime.pending.change_to", defaultValue: "改为 %@？"),
                String(format: "%02d:%02d", hour, minute)
            ))
            .font(.subheadline.weight(.medium))
            .foregroundColor(.textPrimary)
            .monospacedDigit()
            Spacer(minLength: WeekSpacing.sm)
            Button(String(localized: "action.cancel")) {
                pendingTodayKillTimeHour = nil
                pendingTodayKillTimeMinute = nil
            }
            .font(.subheadline)
            .foregroundColor(.textSecondary)
            .buttonStyle(.plain)
            Button {
                guard let hour = pendingTodayKillTimeHour, let minute = pendingTodayKillTimeMinute else { return }
                do {
                    let impact = try viewModel.evaluateKillTimeChangeImpact(hour: hour, minute: minute)
                    switch impact {
                    case .normal:
                        todayKillTimeConfirmMode = .normal
                    case .immediateExpire(let expiredCount):
                        todayKillTimeConfirmMode = .immediateExpire(expiredCount: expiredCount)
                    }
                    showingTodayKillTimeConfirm = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Text(String(localized: "killtime.pending.confirm", defaultValue: "确认"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.weekyiiPrimary, in: Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, WeekSpacing.md)
        .frame(maxHeight: .infinity)
        .background(Color.accentOrange.opacity(0.1), in: RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
    }

    @ViewBuilder
    private func editableKillTimeCard(day: DayModel, viewModel: TodayViewModel) -> some View {
        let displayedHour = pendingTodayKillTimeHour ?? day.killTimeHour
        let displayedMinute = pendingTodayKillTimeMinute ?? day.killTimeMinute
        let hasPendingChange = displayedHour != day.killTimeHour || displayedMinute != day.killTimeMinute

        let isEditable = day.status == .draft || day.status == .execute

        WeekCard(accentColor: .accentOrange) {
            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                // The header row turns into the confirm bar while a change is
                // pending, so the card never changes height mid-drag.
                ZStack {
                    if isEditable && hasPendingChange {
                        killTimePendingBar(hour: displayedHour, minute: displayedMinute, viewModel: viewModel)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        killTimeTitleRow(hour: displayedHour, minute: displayedMinute, isEditable: isEditable)
                            .transition(.opacity)
                    }
                }
                .frame(height: 34)
                .animation(.easeInOut(duration: 0.22), value: hasPendingChange)

                KillTimeEditor(
                    hour: displayedHour,
                    minute: displayedMinute,
                    isEditable: isEditable,
                    rangeAnchorMinutes: day.killTimeHour * 60 + day.killTimeMinute,
                    onChange: { hour, minute in
                        pendingTodayKillTimeHour = hour
                        pendingTodayKillTimeMinute = minute
                    }
                )
            }
            // Flames sit behind the content, fill the card to its edges
            // (WeekCard pads by WeekSpacing.lg and clips) and may rise up to
            // the slider's track.
            .backgroundPreferenceValue(KillTimeLayoutAnchorKey.self) { anchors in
                if isEditable {
                    GeometryReader { proxy in
                        // Measured in the content's space; the flames extend by
                        // WeekSpacing.lg to the card edges, so add it back.
                        let bottom = proxy.size.height + WeekSpacing.lg
                        let ceiling: KillTimeFlameCeiling? = anchors.slider.map { sliderAnchor in
                            let trackY = proxy[sliderAnchor].minY + KillTimeSlider.trackCenterY
                            let timeRect = anchors.time.map { proxy[$0] }
                            let totalWidth = proxy.size.width + WeekSpacing.lg * 2
                            return KillTimeFlameCeiling(
                                left: bottom - trackY + 22,
                                right: bottom - (timeRect?.minY ?? trackY - 60),
                                transition: ((timeRect?.maxX ?? proxy.size.width * 0.4) + WeekSpacing.lg) / totalWidth
                            )
                        }
                        KillTimeFlameBackground(
                            hour: displayedHour,
                            minute: displayedMinute,
                            isAnimating: animationsActive,
                            ceiling: ceiling
                        )
                        .padding(-WeekSpacing.lg)
                    }
                }
            }
        }
        .alert(
            todayKillTimeConfirmTitle,
            isPresented: $showingTodayKillTimeConfirm
        ) {
            Button(String(localized: "action.cancel"), role: .cancel) { }
            Button("确认") {
                applyPendingTodayKillTime(viewModel: viewModel)
            }
        } message: {
            Text(todayKillTimeConfirmMessage)
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private func emptyStateContent(day: DayModel, viewModel: TodayViewModel) -> some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.weekyiiGradient)
                
                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "today.empty.title"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                    
                    Text(String(localized: "today.empty.subtitle"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
        
        WeekButton(String(localized: "action.create"), icon: "plus.circle.fill", style: .primary) {
            draftTaskEditorMode = .create(.draft)
        }
    }
    
    // MARK: - Draft State
    
    @ViewBuilder
    private func draftStateContent(day: DayModel, viewModel: TodayViewModel) -> some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                DraftEditorView(
                    day: day,
                    viewModel: viewModel,
                    onAddTask: {
                        draftTaskEditorMode = .create(.draft)
                    },
                    onEditTask: { task in
                        draftTaskEditorMode = .edit(task, .draft)
                    },
                    onPostponeTask: { task in
                        taskForPostpone = task
                    }
                )
            }
        }
    }
    
    // MARK: - Execute State
    
    @ViewBuilder
    private func executeStateContent(day: DayModel, viewModel: TodayViewModel) -> some View {
        // 专注任务
        if let focusTask = day.focusTask {
            WeekCard(useGradient: true) {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.white)
                        Text(String(localized: "focus.title"))
                            .font(.titleSmall)
                            .foregroundColor(.white)
                    }
                    
                    HStack(alignment: .firstTextBaseline) {
                        Text(focusTask.title)
                            .font(.titleMedium)
                            .foregroundColor(.white)
                            .onTapGesture {
                                selectedTaskForDetail = focusTask
                            }

                        if focusTask.project != nil {
                            Spacer(minLength: WeekSpacing.sm)
                            TaskProjectOriginBadge(
                                project: focusTask.project,
                                isOnDarkBackground: true
                            )
                        }

                        if focusTask.habit != nil {
                            Spacer(minLength: WeekSpacing.sm)
                            TaskHabitOriginBadge(
                                habit: focusTask.habit,
                                isOnDarkBackground: true
                            )
                        }
                    }
                    
                    HStack {
                        if let startedAt = focusTask.startedAt {
                            HStack(spacing: WeekSpacing.xs) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text(formatTime(startedAt))
                                    .font(.caption)
                            }
                            .foregroundColor(.white.opacity(0.9))
                        }
                        
                        Spacer()
                        
                        Button {
                            taskForPostpone = focusTask
                        } label: {
                            HStack(spacing: WeekSpacing.xs) {
                                Image(systemName: "calendar.badge.clock")
                                Text("后移")
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, WeekSpacing.xs)
                            .padding(.horizontal, WeekSpacing.sm)
                        }
                        .foregroundColor(.white)
                        .background(.white.opacity(0.2), in: Capsule())
                        .buttonStyle(.plain)

                        if day.executionMode == .flexible {
                            Button {
                                do {
                                    try viewModel.exchangeFocusWithFirstDraft()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            } label: {
                                HStack(spacing: WeekSpacing.xs) {
                                    Image(systemName: "arrow.triangle.swap")
                                    Text("交换")
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.vertical, WeekSpacing.xs)
                                .padding(.horizontal, WeekSpacing.sm)
                            }
                            .foregroundColor(.white)
                            .background(.white.opacity(0.2), in: Capsule())
                        .buttonStyle(.plain)
                        .disabled(!day.isDraftZoneUnlocked || day.frozenTasks.isEmpty)
                        .opacity(day.isDraftZoneUnlocked && !day.frozenTasks.isEmpty ? 1 : 0.45)
                            .accessibilityIdentifier("focusExchangeButton")
                        }

                        Button {
                            do {
                                try viewModel.doneFocus()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            HStack(spacing: WeekSpacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(String(localized: "action.done_focus"))
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, WeekSpacing.xs)
                            .padding(.horizontal, WeekSpacing.sm)
                        }
                        .foregroundColor(.white)
                        .background(.white.opacity(0.2), in: Capsule())
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        
        if day.executionMode == .flexible {
            WeekCard {
                DraftEditorView(
                    day: day,
                    viewModel: viewModel,
                    presentationMode: .flexibleExecution,
                    onAddTask: {
                        draftTaskEditorMode = .create(.flexibleExecution)
                    },
                    onEditTask: { task in
                        draftTaskEditorMode = .edit(task, .flexibleExecution)
                    },
                    onPostponeTask: { task in
                        taskForPostpone = task
                    },
                    onToggleLock: {
                        do {
                            try viewModel.setDraftZoneUnlocked(!day.isDraftZoneUnlocked)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
            }
        } else if !day.frozenTasks.isEmpty {
            WeekCard {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    HStack {
                        Image(systemName: "snowflake")
                            .foregroundColor(.weekyiiPrimary)
                        Text(String(localized: "frozen.title"))
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        Text("\(day.frozenTasks.count)")
                            .font(.titleSmall)
                            .foregroundColor(.weekyiiPrimary)
                    }
                    
                    FrozenZoneView(
                        tasks: day.frozenTasks,
                        showsProjectOrigin: true,
                        showsHabitOrigin: true,
                        onTapTask: { task in
                            selectedTaskForDetail = task
                        },
                        onPostponeTask: { task in
                            taskForPostpone = task
                        }
                    )
                }
            }
        }

        // 已完成任务
        if !day.completedTasks.isEmpty {
            WeekCard {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentGreen)
                        Text(String(localized: "complete.title"))
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        Text("\(day.completedTasks.count)")
                            .font(.titleSmall)
                            .foregroundColor(.accentGreen)
                    }
                    
                    CompleteZoneView(tasks: day.completedTasks, onTapTask: { task in
                        selectedTaskForDetail = task
                    })
                }
            }
        }
        
    }
    
    // MARK: - Completed State
    
    @ViewBuilder
    private func completedStateContent(day: DayModel) -> some View {
        // 庆祝卡片
        WeekCard(useGradient: true) {
            VStack(spacing: WeekSpacing.lg) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white)
                
                Text(String(localized: "completed.congratulations"))
                    .font(.titleMedium)
                    .foregroundColor(.white)
                
                Text(String(localized: "completed.message"))
                    .font(.bodyMedium)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
        
        // 完成任务列表
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentGreen)
                    Text(String(localized: "complete.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                    
                    Spacer()
                    
                    Text("\(day.completedTasks.count)")
                        .font(.titleSmall)
                        .foregroundColor(.accentGreen)
                }
                
                CompleteZoneView(tasks: day.completedTasks)
            }
        }
    }
    
    // MARK: - Expired State

    @ViewBuilder
    private func expiredStateContent(day: DayModel) -> some View {
        TodayExpiredOutcomeCard(day: day)

        if !day.completedTasks.isEmpty {
            TodayExpiredCompletedList(
                tasks: day.completedTasks,
                expiredCount: day.expiredCount,
                onTapTask: { task in
                    selectedTaskForDetail = task
                }
            )
        }
    }

    // MARK: - Helper Methods

    @ViewBuilder
    private func loadingErrorView(message: String, onRetry: @escaping () -> Void) -> some View {
        WeekCard(accentColor: .taskDDL) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(spacing: WeekSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.taskDDL)
                    Text(String(localized: "alert.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                Text(message)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                WeekButton("重试", icon: "arrow.clockwise", style: .secondary, action: onRetry)
            }
        }
        .padding(WeekSpacing.base)
    }

    private func shouldShowFloatingStartButton(for day: DayModel) -> Bool {
        day.status == .draft && !day.sortedDraftTasks.isEmpty
    }

    @ViewBuilder
    /// The button floats directly over the themed scene. A solid backdrop band
    /// here would not match theme backgrounds (e.g. the sunset reflection) and
    /// read as a halo; the scroll content already reserves room underneath.
    private var floatingStartButtonOverlay: some View {
        WeekButton(
            "准备开始",
            icon: "play.circle.fill",
            style: .primary
        ) {
            startFlowDetent = .fraction(0.5)
            startFlowCoordinator.present()
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("todayFloatingStartButton")
        .padding(.horizontal, WeekSpacing.base)
        .padding(.vertical, WeekSpacing.sm)
    }

    @ViewBuilder
    private func draftTaskEditorSheet(mode: DraftTaskEditorMode) -> some View {
        switch mode {
        case .create(let context):
            TaskEditorSheet(
                title: String(localized: "draft.add_title"),
                initialType: userSettings.defaultTaskType,
                initialTypeIdRaw: userSettings.defaultTaskTypeIdRaw,
                onSave: { _, _, _, _, _ in },
                onSaveWithTypeId: { title, description, type, typeIdRaw, steps, attachments in
                    guard let viewModel else { return }
                    do {
                        switch context {
                        case .draft:
                            try viewModel.addTask(
                                title: title,
                                description: description,
                                type: type,
                                taskTypeIdRaw: typeIdRaw,
                                steps: steps,
                                attachments: attachments
                            )
                        case .flexibleExecution:
                            try viewModel.addExecutionTask(
                                title: title,
                                description: description,
                                type: type,
                                taskTypeIdRaw: typeIdRaw,
                                steps: steps,
                                attachments: attachments
                            )
                        }
                        draftTaskEditorMode = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            )
        case .edit(let task, _) where task.habit != nil:
            // Habit tasks are owned by their habit and are never edited here.
            HabitTaskDetailSheet(task: task)
        case .edit(let task, let context):
            TaskEditorSheet(
                title: String(localized: "draft.edit_title"),
                initialTitle: task.title,
                initialDescription: task.taskDescription,
                initialType: task.taskType,
                initialTypeIdRaw: task.taskTypeIdRaw,
                initialSteps: task.steps,
                initialAttachments: task.attachments,
                onSave: { _, _, _, _, _ in },
                onSaveWithTypeId: { title, description, type, typeIdRaw, steps, attachments in
                    guard let viewModel else { return }
                    do {
                        switch context {
                        case .draft:
                            try viewModel.updateTask(
                                task,
                                title: title,
                                description: description,
                                type: type,
                                taskTypeIdRaw: typeIdRaw,
                                steps: steps,
                                attachments: attachments
                            )
                        case .flexibleExecution:
                            try viewModel.updateExecutionTask(
                                task,
                                title: title,
                                description: description,
                                type: type,
                                taskTypeIdRaw: typeIdRaw,
                                steps: steps,
                                attachments: attachments
                            )
                        }
                        draftTaskEditorMode = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            )
        }
    }
    
    private func formatDate(_ dayId: String) -> String {
        guard let date = Self.dayIDFormatter.date(from: dayId) else { return dayId }
        return Self.longDateFormatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private var postponeConfirmMessage: String {
        guard let request = pendingPostponeRequest else { return "确认后移该任务？" }
        return "确认将「\(request.taskTitle)」后移到 \(formatPostponeDate(request.targetDate)) 吗？"
    }

    private var postponeCreateWeekConfirmMessage: String {
        guard let preview = pendingPostponePreview else {
            return "目标周尚未创建，确认后会自动创建并完成任务后移。"
        }
        return "将创建 \(preview.targetWeekId) 后把任务移动到 \(formatPostponeDate(preview.targetDate))。是否继续？"
    }

    private func stagePostponeRequest(for task: TaskItem, targetDate: Date) {
        taskForPostpone = nil
        pendingPostponeRequest = PendingPostponeRequest(
            taskID: task.id,
            taskTitle: task.title,
            targetDate: targetDate.startOfDay
        )
        showingPostponeConfirm = true
    }

    private func confirmPostponeRequest(viewModel: TodayViewModel) {
        guard let request = pendingPostponeRequest else { return }
        do {
            let preview = try viewModel.previewPostpone(
                taskID: request.taskID,
                taskTitle: request.taskTitle,
                targetDate: request.targetDate
            )
            pendingPostponePreview = preview
            if preview.requiresWeekCreation {
                showingPostponeWeekCreationConfirm = true
            } else {
                _ = try viewModel.commitPostpone(preview, allowWeekCreation: false)
                clearPendingPostponeContext()
            }
        } catch {
            errorMessage = error.localizedDescription
            clearPendingPostponeContext()
        }
    }

    private func confirmPostponeWithWeekCreation(viewModel: TodayViewModel) {
        guard let preview = pendingPostponePreview else { return }
        do {
            _ = try viewModel.commitPostpone(preview, allowWeekCreation: true)
            clearPendingPostponeContext()
        } catch {
            errorMessage = error.localizedDescription
            clearPendingPostponeContext()
        }
    }

    private func clearPendingPostponeContext() {
        showingPostponeConfirm = false
        showingPostponeWeekCreationConfirm = false
        taskForPostpone = nil
        pendingPostponeRequest = nil
        pendingPostponePreview = nil
    }

    private func formatPostponeDate(_ date: Date) -> String {
        Self.postponeDateFormatter.string(from: date)
    }

    private var todayKillTimeConfirmTitle: String {
        switch todayKillTimeConfirmMode {
        case .normal:
            return "确认修改截止时间"
        case .immediateExpire:
            return "新时间会导致今日任务立即过期"
        }
    }

    private var todayKillTimeConfirmMessage: String {
        switch todayKillTimeConfirmMode {
        case .normal:
            return "确认后将更新今日截止时间。"
        case .immediateExpire(let expiredCount):
            return "确认后今日未完成内容将立即过期（\(expiredCount) 项）。"
        }
    }

    private func applyPendingTodayKillTime(viewModel: TodayViewModel) {
        guard let hour = pendingTodayKillTimeHour, let minute = pendingTodayKillTimeMinute else { return }
        do {
            switch todayKillTimeConfirmMode {
            case .normal:
                try viewModel.changeKillTime(hour: hour, minute: minute, allowImmediateExpire: false)
            case .immediateExpire:
                try viewModel.changeKillTime(hour: hour, minute: minute, allowImmediateExpire: true)
            }
            pendingTodayKillTimeHour = nil
            pendingTodayKillTimeMinute = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func startFlowSheet(viewModel: TodayViewModel) -> some View {
        let day = viewModel.today
        let draftCount = day?.sortedDraftTasks.count ?? 0
        let killTimeHour = day?.killTimeHour ?? 20
        let killTimeMinute = day?.killTimeMinute ?? 0
        let killTimeText = String(format: "%02d:%02d", killTimeHour, killTimeMinute)

        VStack(alignment: .leading, spacing: WeekSpacing.base) {
            if startFlowCoordinator.step == .warning {
                StartFlowWarningStepView(
                    draftCount: draftCount,
                    killTimeText: killTimeText,
                    onCancel: {
                        startFlowStamp = nil
                        startFlowDetent = .fraction(0.5)
                        startFlowCoordinator.cancel()
                    },
                    onContinue: {
                        // When the start-day ritual is switched off, confirming the
                        // warning starts the day immediately instead of showing a stamp.
                        guard userSettings.startRitualEnabled else {
                            do {
                                try viewModel.startDay()
                                startFlowStamp = nil
                                startFlowDetent = .fraction(0.5)
                                startFlowCoordinator.cancel()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            return
                        }
                        startFlowStamp = viewModel.pickStartRitualStamp()
                        startFlowCoordinator.chooseDirectEnter()
                        withAnimation(.easeInOut(duration: 0.24)) {
                            startFlowDetent = .fraction(0.62)
                        }
                    }
                )
            } else {
                StartFlowRitualStepView(
                    stamp: startFlowStamp,
                    onConfirm: {
                        do {
                            try viewModel.startDay()
                            startFlowStamp = nil
                            startFlowDetent = .fraction(0.5)
                            startFlowCoordinator.cancel()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, WeekSpacing.base)
        .padding(.top, WeekSpacing.lg)
        .padding(.bottom, WeekSpacing.base)
        .background(Color.backgroundPrimary)
    }

    @ViewBuilder
    private var todaySceneBackground: some View {
        ZStack {
            Color.backgroundPrimary
            if userSettings.selectedTheme == .sunset {
                SunsetWaterReflectionBackground(animationsActive: animationsActive)
                    .transition(.opacity)
            } else if userSettings.selectedTheme == .lotr {
                LotrRainNightBackground(animationsActive: animationsActive)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }
    
}

private struct TodayWeekSwitcher<TodayContent: View, WeekContent: View>: View {
    @Binding var selectedSection: TodaySection
    let isPagingEnabled: Bool
    let todayContent: TodayContent
    let weekContent: WeekContent

    @GestureState private var dragTranslation: CGFloat = 0
    @GestureState private var isDragging = false

    init(
        selectedSection: Binding<TodaySection>,
        isPagingEnabled: Bool = true,
        @ViewBuilder todayContent: () -> TodayContent,
        @ViewBuilder weekContent: () -> WeekContent
    ) {
        self._selectedSection = selectedSection
        self.isPagingEnabled = isPagingEnabled
        self.todayContent = todayContent()
        self.weekContent = weekContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            // 胶囊切换器 - 独立于 GeometryReader
            SectionToggleView(
                progress: selectedSection == .today ? 0 : 1,
                selectedSection: selectedSection,
                onSelect: { target in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedSection = target
                    }
                }
            )
            .padding(.horizontal, WeekSpacing.base)
            .padding(.top, WeekSpacing.sm)
            .padding(.bottom, WeekSpacing.md)
            
            // 内容页面 - 使用 GeometryReader 测量宽度
            GeometryReader { geometry in
                let width = geometry.size.width
                let baseOffset = -CGFloat(selectedIndex) * width
                let rawOffset = baseOffset + dragTranslation
                let clampedOffset = min(0, max(rawOffset, -width))

                HStack(spacing: 0) {
                    todayContent
                        .frame(width: width)
                    weekContent
                        .frame(width: width)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(x: clampedOffset)
                .clipped()
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedSection)
                .transaction { transaction in
                    if isDragging {
                        transaction.animation = nil
                    }
                }
                .simultaneousGesture(dragGesture(width: width))
            }
        }
    }

    private var selectedIndex: Int {
        selectedSection == .today ? 0 : 1
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragTranslation) { value, state, _ in
                guard isPagingEnabled else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .updating($isDragging) { value, state, _ in
                guard isPagingEnabled else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = true
            }
            .onEnded { value in
                guard isPagingEnabled else { return }
                let baseOffset = -CGFloat(selectedIndex) * width
                let predictedOffset = baseOffset + value.predictedEndTranslation.width
                let clamped = min(0, max(predictedOffset, -width))
                let predictedProgress = max(0, min(-clamped / max(width, 1), 1))
                let target: TodaySection = predictedProgress > 0.5 ? .week : .today
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedSection = target
                }
            }
    }
}

private struct StartFlowWarningStepView: View {
    let draftCount: Int
    let killTimeText: String
    let onCancel: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.base) {
            HStack(alignment: .top, spacing: WeekSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.weekyiiPrimary.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "play.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.weekyiiGradient)
                }

                VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                    Text("是否开始今日任务流？")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.textPrimary)

                    Text("进入后将按任务顺序推进，直到完成或截止。")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("开始任务流头部信息")
            .accessibilityIdentifier("startFlowSheetHeader")

            HStack(spacing: WeekSpacing.sm) {
                summaryItem(icon: "checklist", title: "草稿任务", value: "\(draftCount) 项")
                summaryItem(icon: "clock.fill", title: "截止时间", value: killTimeText)
            }

            HStack(alignment: .top, spacing: WeekSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.bodyLarge)
                    .foregroundColor(.accentOrange)

                Text("同意后无法撤回，需要在截止时间前完成，未完成项将被过期遗忘。")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(WeekSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WeekRadius.medium)
                    .fill(Color.accentOrangeLight.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.medium)
                    .stroke(Color.accentOrange.opacity(0.25), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("开始任务流风险提示")
            .accessibilityIdentifier("startFlowWarningCard")

            HStack(spacing: WeekSpacing.sm) {
                WeekButton("我再想想", style: .outline, action: onCancel)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("startFlowSecondaryButton")

                WeekButton("直接进入", style: .primary, action: onContinue)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("startFlowPrimaryButton")
            }
        }
    }

    private func summaryItem(icon: String, title: String, value: String) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            Image(systemName: icon)
                .font(.bodyMedium.weight(.semibold))
                .foregroundStyle(Color.weekyiiGradient)

            VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text(value)
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundColor(.textPrimary)
            }
        }
        .padding(WeekSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.medium))
    }
}

private struct StartFlowRitualStepView: View {
    let stamp: MindStampItem?
    let onConfirm: () -> Void

    private var quoteText: String? {
        guard let stamp else { return nil }
        let trimmed = stamp.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: WeekSpacing.base) {
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        Text("阶段 2/2 · 呆胶布")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textSecondary)
                        Text("把注意力收束到唯一入口，然后开始今天。")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: WeekSpacing.md) {
                        Label("今日呆胶布", systemImage: "bandage.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.weekyiiPrimary)

                        if let blob = stamp?.imageBlob, let uiImage = UIImage(data: blob) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                                        .stroke(Color.backgroundTertiary, lineWidth: 1)
                                )
                        }

                        ZStack(alignment: .topLeading) {
                            Text("“")
                                .font(.system(size: 38, weight: .bold, design: .serif))
                                .foregroundStyle(Color.weekyiiPrimary.opacity(0.20))
                                .offset(x: -2, y: -8)

                            Text(contentText)
                                .font(.bodyLarge.weight(.medium))
                                .foregroundColor(quoteText == nil ? .textSecondary : .textPrimary)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, WeekSpacing.lg)
                        }
                        .padding(WeekSpacing.md)
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .background(
                            Color.weekyiiPrimary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                                .stroke(Color.weekyiiPrimary.opacity(0.18), lineWidth: 1)
                        )
                        .accessibilityIdentifier("startFlowRitualText")
                    }
                    .padding(WeekSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                            .stroke(Color.weekyiiPrimary.opacity(0.12), lineWidth: 1)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("呆胶布内容：\(contentText)")
                    .accessibilityIdentifier("startFlowRitualCard")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, WeekSpacing.base)
            }
            .scrollIndicators(.hidden)

            WeekButton("确认开始", style: .primary, action: onConfirm)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("startFlowPrimaryButton")
                .padding(.top, WeekSpacing.xs)
                .padding(.bottom, WeekSpacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var contentText: String {
        if let quoteText {
            return quoteText
        }
        return "给自己一个清晰而坚定的开始。"
    }
}
/// 高级 Segmented Control 样式的切换器
/// 两个标签始终可见，高亮胶囊在背后滑动，带渐变和玻璃质感
private struct SectionToggleView: View {
    let progress: CGFloat
    let selectedSection: TodaySection
    let onSelect: (TodaySection) -> Void
    
    private let height: CGFloat = 44
    
    var body: some View {
        HStack(spacing: 0) {
            // 今日 按钮
            Button {
                onSelect(.today)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text(String(localized: "tab.today"))
                        .font(.bodyMedium.weight(.semibold))
                }
                .foregroundColor(selectedSection == .today ? .white : .textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("todaySectionTodayButton")
            
            // 本周 按钮
            Button {
                onSelect(.week)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .medium))
                    Text(String(localized: "tab.week"))
                        .font(.bodyMedium.weight(.semibold))
                }
                .foregroundColor(selectedSection == .week ? .white : .textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("todaySectionWeekButton")
        }
        .background(
            GeometryReader { geo in
                let halfWidth = geo.size.width / 2
                let indicatorX = progress * halfWidth
                
                // 滑动的高亮胶囊 - 带渐变
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.weekyiiPrimary,
                                Color.weekyiiPrimary.opacity(0.85)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: halfWidth - 4, height: height - 6)
                    .offset(x: indicatorX + 2, y: 3)
                    // 顶部高光
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.1),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(width: halfWidth - 4, height: height - 6)
                            .offset(x: indicatorX + 2, y: 3)
                    )
                    // 边框
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                            .frame(width: halfWidth - 4, height: height - 6)
                            .offset(x: indicatorX + 2, y: 3)
                    )
                    // 阴影
                    .shadow(color: Color.weekyiiPrimary.opacity(0.4), radius: 8, x: 0, y: 4)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        )
        .background(
            // 底层背景胶囊 - 带内阴影效果
            Capsule()
                .fill(Color.backgroundSecondary.opacity(0.8))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1),
                                    Color.black.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                // 内阴影模拟
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.08), lineWidth: 2)
                        .blur(radius: 2)
                        .mask(Capsule().fill(Color.black))
                        .offset(y: 1)
                )
        )
        .clipShape(Capsule())
        .frame(height: height)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
    }
}

/// Lightweight animated scene used only by the Sunset theme on Today page.
private struct SunsetWaterReflectionBackground: View {
    let animationsActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var sunDrift = false

    private var shouldAnimate: Bool { animationsActive && !reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let sunY = sunCenterY(for: size)
            let waterlineY = waterline(for: size)

            ZStack {
                LinearGradient(
                    colors: skyGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )

                horizonGlow(y: waterlineY, size: size)
                sunDisk(y: sunY, size: size)
                reflectedSun(y: sunY, waterlineY: waterlineY, size: size)
                reflectionRipples(size: size, waterlineY: waterlineY)
            }
            .drawingGroup(opaque: false, colorMode: .linear)
            .onAppear {
                updateSunAnimation()
            }
            .onChange(of: shouldAnimate) { _, _ in
                updateSunAnimation()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var skyGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(hex: "#251414"),
                Color(hex: "#3A1D1A"),
                Color(hex: "#221917"),
                Color(hex: "#141317")
            ]
        }
        return [
            Color(hex: "#FFE5D1"),
            Color(hex: "#F9C39E"),
            Color(hex: "#DF896B"),
            Color(hex: "#B86A5C")
        ]
    }

    private func waterline(for size: CGSize) -> CGFloat {
        size.height * (colorScheme == .dark ? 0.52 : 0.56)
    }

    private func sunCenterY(for size: CGSize) -> CGFloat {
        let base = size.height * (colorScheme == .dark ? 0.23 : 0.27)
        guard shouldAnimate else { return base }
        return base + (sunDrift ? 5 : -5)
    }

    private func updateSunAnimation() {
        if shouldAnimate {
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                sunDrift = true
            }
        } else {
            withAnimation(nil) {
                sunDrift = false
            }
        }
    }

    private func sunCenterX(for size: CGSize) -> CGFloat {
        size.width * 0.382
    }

    private func horizonGlow(y: CGFloat, size: CGSize) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: colorScheme == .dark ? "#E5B099" : "#F2B28F")
                            .opacity(colorScheme == .dark ? 0.08 : 0.13),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 86)
            .position(x: size.width / 2, y: y)
    }

    private func sunDisk(y: CGFloat, size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: colorScheme == .dark ? "#FA6D5B" : "#F16250"),
                            Color(hex: colorScheme == .dark ? "#D84A3E" : "#C83D36")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 74, height: 74)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.2 : 0.24),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: 40, height: 40)
                .offset(y: -9)
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                .frame(width: 74, height: 74)
        )
        .position(x: sunCenterX(for: size), y: y)
    }

    private func reflectedSun(y: CGFloat, waterlineY: CGFloat, size: CGSize) -> some View {
        let height: CGFloat = colorScheme == .dark ? 212 : 230
        let reflectionTop = max(y + 24, waterlineY - 10)
        return RoundedRectangle(cornerRadius: 70, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "#F06B58").opacity(colorScheme == .dark ? 0.2 : 0.3),
                        Color(hex: "#D34A3F").opacity(colorScheme == .dark ? 0.14 : 0.24),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 84, height: height)
            .blur(radius: 4)
            .scaleEffect(x: 1.04, y: 1.0, anchor: .top)
            .position(x: sunCenterX(for: size) + 10, y: reflectionTop + height / 2)
    }

    private func reflectionRipples(size: CGSize, waterlineY: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimate)) { timeline in
            Canvas { context, canvasSize in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let lineCount = 13
                let leftX = canvasSize.width * 0.06
                let rightX = canvasSize.width * 0.94
                let laneHeight = max((canvasSize.height - waterlineY) / CGFloat(lineCount + 2), 8)
                let waveAmplitude: CGFloat = reduceMotion ? 0.8 : 3.8

                for idx in 0..<lineCount {
                    let progress = CGFloat(idx) / CGFloat(lineCount)
                    let baseY = waterlineY + CGFloat(idx + 1) * laneHeight
                    let phase = Double(idx) * 0.76
                    let xWave = CGFloat(sin(t * 0.55 + phase)) * (8 - progress * 5)
                    let yWave = CGFloat(cos(t * 0.65 + phase)) * waveAmplitude
                    let lineWidth = max(0.7, 2.1 - progress * 1.2)
                    let alpha = max(0.02, 0.11 - Double(progress) * 0.08)

                    var path = Path()
                    path.move(to: CGPoint(x: leftX + xWave, y: baseY + yWave))
                    path.addQuadCurve(
                        to: CGPoint(x: rightX - xWave, y: baseY - yWave * 0.35),
                        control: CGPoint(
                            x: canvasSize.width * 0.5 + CGFloat(sin(t * 0.4 + phase * 1.4)) * 26,
                            y: baseY + CGFloat(cos(t * 0.3 + phase)) * (waveAmplitude * 0.9)
                        )
                    )

                    context.stroke(
                        path,
                        with: .color(Color(hex: "#FFD6B9").opacity(alpha)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                }
            }
            .frame(width: size.width, height: size.height)
            .blendMode(.plusLighter)
        }
    }
}

private struct LotrRainNightBackground: View {
    let animationsActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var shouldAnimate: Bool { animationsActive && !reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let horizonY = size.height * 0.6

            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: "#070808"), Color(hex: "#0D0F12"), Color(hex: "#13161A"), Color(hex: "#1A1D22")]
                        : [Color(hex: "#E6E7EA"), Color(hex: "#D6D8DD"), Color(hex: "#C1C4CB"), Color(hex: "#ADB1BA")],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // starless night: no stars, only layered mountain silhouettes
                mountainLayer(size: size, y: horizonY - 34, opacity: colorScheme == .dark ? 0.7 : 0.34, offset: 0)
                mountainLayer(size: size, y: horizonY - 12, opacity: colorScheme == .dark ? 0.86 : 0.46, offset: 24)

                // distant call: a tiny warm beacon near golden-left valley
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(hex: colorScheme == .dark ? "#D1A261" : "#AF7D47"))
                    .frame(width: 3, height: 12)
                    .blur(radius: 0.4)
                    .position(x: size.width * 0.362, y: horizonY - 8)

                coldRain(size: size, fromY: horizonY - 120)
            }
            .drawingGroup(opaque: false, colorMode: .linear)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func mountainLayer(size: CGSize, y: CGFloat, opacity: CGFloat, offset: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: -20, y: size.height))
            path.addLine(to: CGPoint(x: -20, y: y + 40))
            path.addCurve(
                to: CGPoint(x: size.width * 0.28, y: y - 22),
                control1: CGPoint(x: size.width * 0.05, y: y + 10),
                control2: CGPoint(x: size.width * 0.18, y: y - 26)
            )
            path.addCurve(
                to: CGPoint(x: size.width * 0.58, y: y + 6),
                control1: CGPoint(x: size.width * 0.36, y: y - 16),
                control2: CGPoint(x: size.width * 0.46, y: y + 14)
            )
            path.addCurve(
                to: CGPoint(x: size.width + 20, y: y - 12),
                control1: CGPoint(x: size.width * 0.71, y: y - 14),
                control2: CGPoint(x: size.width * 0.89, y: y - 20)
            )
            path.addLine(to: CGPoint(x: size.width + 20, y: size.height))
            path.closeSubpath()
        }
        .fill(Color.black.opacity(opacity))
        .offset(x: offset)
    }

    private func coldRain(size: CGSize, fromY: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !shouldAnimate)) { timeline in
            Canvas { context, canvas in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let columns = 24
                for idx in 0..<columns {
                    let x = (CGFloat(idx) + 0.5) / CGFloat(columns) * canvas.width
                    let phase = Double(idx) * 0.37
                    let drift = CGFloat(sin(t * 0.65 + phase)) * (reduceMotion ? 0.5 : 2.3)
                    let dropTop = fromY + CGFloat((idx % 4) * 6) + CGFloat((t * 38 + phase * 30).truncatingRemainder(dividingBy: 16))
                    let dropHeight: CGFloat = 14 + CGFloat(idx % 3) * 2
                    let rect = CGRect(x: x + drift, y: dropTop, width: 1.0, height: dropHeight)
                    let path = Path(roundedRect: rect, cornerRadius: 1)
                    context.fill(path, with: .color(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.1)))
                }
            }
        }
    }
}

// MARK: - Expired Day Presentation

/// Outcome card shown once today has expired. It distinguishes a started day
/// that ran out of time from a planned day that was never started, reading
/// only persisted fields (`expiredCount`, `initiatedAt`, raw draft records).
private struct TodayExpiredOutcomeCard: View {
    let day: DayModel

    /// Same rule as the Past calendar's grey face.
    private var isNotStarted: Bool {
        day.expiredCount == 0 && day.initiatedAt == nil
    }

    private var failureKind: PastDayFailureKind {
        isNotStarted ? .notStarted : .unfinished
    }

    private var tint: Color {
        isNotStarted ? .textTertiary : .taskDDL
    }

    private var killTimeText: String {
        String(format: "%02d:%02d", day.killTimeHour, day.killTimeMinute)
    }

    /// Draft records survive expiry (hidden by `DayModel`'s terminal getters)
    /// until garbage collection, so today's planned count is still readable.
    private var plannedCount: Int {
        day.tasks.filter { $0.zone == .draft }.count
    }

    private var completedCount: Int { day.completedTasks.count }
    private var expiredCount: Int { day.expiredCount }

    private var completionPercent: Int {
        let total = completedCount + expiredCount
        guard total > 0 else { return 0 }
        return Int((Double(completedCount) / Double(total) * 100).rounded())
    }

    private var title: String {
        isNotStarted
            ? String(localized: "today.expired.not_started.title", defaultValue: "今天没有开始")
            : String(localized: "today.expired.unfinished.title", defaultValue: "今天没能全部完成")
    }

    private var subtitle: String {
        if isNotStarted {
            if plannedCount > 0 {
                return String(
                    format: String(
                        localized: "today.expired.not_started.subtitle",
                        defaultValue: "写好的 %1$lld 项计划在 %2$@ 过期了"
                    ),
                    plannedCount,
                    killTimeText
                )
            }
            return String(
                format: String(localized: "today.expired.not_started.subtitle_no_count", defaultValue: "计划在 %@ 过期了"),
                killTimeText
            )
        }
        return String(
            format: String(localized: "today.expired.unfinished.subtitle", defaultValue: "%1$@ 截止时还剩 %2$lld 项"),
            killTimeText,
            expiredCount
        )
    }

    var body: some View {
        WeekCard(accentColor: tint) {
            HStack(spacing: WeekSpacing.md) {
                PastFailureFaceMark(kind: failureKind)
                    .frame(width: 26, height: 26)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(tint.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                Spacer(minLength: 0)
            }

            if isNotStarted {
                Text(String(
                    localized: "today.expired.not_started.comfort",
                    defaultValue: "没关系。明天早一点点“开始”，让计划真正动起来。"
                ))
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: WeekSpacing.sm) {
                    outcomeBar
                    HStack {
                        Text(String(
                            format: String(localized: "today.expired.stat.completed", defaultValue: "完成 %lld"),
                            completedCount
                        ))
                        .foregroundColor(.accentGreen)
                        Spacer()
                        Text(String(
                            format: String(localized: "today.expired.stat.expired", defaultValue: "过期 %lld"),
                            expiredCount
                        ))
                        .foregroundColor(.taskDDL)
                        Spacer()
                        Text(String(
                            format: String(localized: "today.expired.stat.rate", defaultValue: "完成率 %lld%%"),
                            completionPercent
                        ))
                        .foregroundColor(.textSecondary)
                    }
                    .font(.captionBold)
                    .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Completed vs. expired share of the day, green then muted red.
    private var outcomeBar: some View {
        GeometryReader { proxy in
            let total = max(completedCount + expiredCount, 1)
            let gap: CGFloat = completedCount > 0 && expiredCount > 0 ? 2 : 0
            let usable = max(proxy.size.width - gap, 0)
            let completedWidth = usable * CGFloat(completedCount) / CGFloat(total)
            HStack(spacing: gap) {
                if completedCount > 0 {
                    Capsule().fill(Color.accentGreen)
                        .frame(width: completedWidth)
                }
                if expiredCount > 0 {
                    Capsule().fill(Color.taskDDL.opacity(0.55))
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Compact list of what did get done today: one hairline row per task with
/// its finish time, plus a reminder that expired tasks keep no details.
private struct TodayExpiredCompletedList: View {
    let tasks: [TaskItem]
    let expiredCount: Int
    let onTapTask: (TaskItem) -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = WeekyiiTimeZone.timeZone
        return formatter
    }()

    var body: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(String(localized: "today.expired.completed.title", defaultValue: "今日完成"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("\(tasks.count)")
                        .font(.titleSmall)
                        .foregroundColor(.accentGreen)
                }
                .padding(.bottom, WeekSpacing.sm)

                ForEach(tasks) { task in
                    Divider()
                    Button {
                        onTapTask(task)
                    } label: {
                        HStack(spacing: WeekSpacing.sm) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.accentGreen)
                            Text(task.title)
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: WeekSpacing.sm)
                            if let endedAt = task.endedAt {
                                Text(Self.timeFormatter.string(from: endedAt))
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if expiredCount > 0 {
                    Text(String(
                        format: String(
                            localized: "today.expired.completed.forgotten",
                            defaultValue: "过期的 %lld 项不保留详情"
                        ),
                        expiredCount
                    ))
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .padding(.top, WeekSpacing.sm)
                }
            }
        }
    }
}

/// Replaces the kill-time editor once the day is over: nothing left to adjust,
/// so it becomes a quiet, locked footnote instead of a live countdown.
private struct TodayEndedKillTimeFootnote: View {
    let hour: Int
    let minute: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text(String(
                format: String(localized: "today.expired.killtime_footnote", defaultValue: "截止于 %@ · 今天已结束"),
                String(format: "%02d:%02d", hour, minute)
            ))
            .monospacedDigit()
        }
        .font(.caption)
        .foregroundColor(.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, WeekSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Habit Task Detail

/// Read-only detail for a task generated by a habit. Same sheet as the normal
/// task detail, but redrawn from the habit: the category sets the hero visual,
/// the schedule kind sets the rhythm module. Reads existing data only.
private struct HabitTaskDetailSheet: View {
    let task: TaskItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let habit = task.habit {
                    HabitTaskDetailContent(task: task, habit: habit)
                        .weekPadding(WeekSpacing.base)
                }
            }
            .background(Color.backgroundPrimary)
            .navigationTitle(String(localized: "task.detail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HabitTaskDetailContent: View {
    let task: TaskItem
    let habit: HabitModel

    private var stats: HabitStatistics { HabitStatisticsCalculator.statistics(for: habit) }
    private var tint: Color { Color.weekyiiEmphasis(hex: habit.colorHex) }
    private var isDoneToday: Bool { task.zone == .complete }
    private var weekDays: [HabitWeekStripDay] { HabitWeekStripDay.currentWeek(for: habit) }

    /// Share of this week's scheduled days already completed (0...1).
    private var weekRatio: Double {
        let scheduled = weekDays.filter { $0.state != .rest }
        guard !scheduled.isEmpty else { return isDoneToday ? 1 : 0 }
        let done = scheduled.filter { $0.state == .completed }.count
        return Double(done) / Double(scheduled.count)
    }

    private var isCentered: Bool { habit.category == .mindfulness }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            headerCard
            rhythmCard
            if habit.scheduleKind != .once {
                statsCard
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        WeekCard(accentColor: tint) {
            if isCentered {
                VStack(spacing: WeekSpacing.sm) {
                    hero.frame(width: 120, height: 96)
                    titleBlock(alignment: .center)
                    Text(String(localized: "habit.detail.mindfulness.line", defaultValue: "慢一点。这一件事，今天只为它留出时间。"))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .center, spacing: WeekSpacing.md) {
                    hero.frame(width: 84, height: 84)
                    titleBlock(alignment: .leading)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func titleBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(habit.name)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
            Text(habit.category.displayName + " · " + habit.scheduleSummary)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            statusChip
        }
    }

    private var statusChip: some View {
        Text(isDoneToday
             ? String(localized: "habit.detail.status.done", defaultValue: "今日已打卡")
             : String(localized: "habit.detail.status.pending", defaultValue: "今日待打卡"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isDoneToday ? Color.accentGreen : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((isDoneToday ? Color.accentGreen : tint).opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var hero: some View {
        switch habit.category {
        case .fitness:
            HabitHeroRings(outer: weekRatio, inner: Double(stats.currentStreak) / Double(max(stats.longestStreak, 1)), tint: tint)
        case .learning:
            HabitHeroBooks(completed: stats.completedCount, isDoneToday: isDoneToday, tint: tint)
        case .mindfulness:
            HabitHeroBreath(tint: tint)
        case .health:
            HabitHeroDrop(fill: weekRatio, tint: tint)
        case .creativity:
            HabitHeroSparks(lit: stats.completedCount, tint: tint)
        case .social:
            HabitHeroCircles(isTogether: isDoneToday, tint: tint)
        case .productivity:
            HabitHeroTarget(rate: stats.completionRate ?? 0, tint: tint)
        }
    }

    // MARK: Rhythm

    @ViewBuilder
    private var rhythmCard: some View {
        switch habit.scheduleKind {
        case .weekly:
            WeekCard {
                sectionLabel(
                    String(localized: "habit.detail.rhythm.week", defaultValue: "本周节奏"),
                    trailing: "\(weekDays.filter { $0.state == .completed }.count) / \(weekDays.filter { $0.state != .rest }.count)"
                )
                HabitDetailWeekStrip(days: weekDays, tint: tint)
            }
        case .monthly:
            WeekCard {
                sectionLabel(Date().formatted(.dateTime.month(.wide)), trailing: monthProgressText)
                HabitDetailMonthGrid(habit: habit, tint: tint)
            }
        case .once:
            WeekCard {
                VStack(spacing: WeekSpacing.xs) {
                    Text(String(localized: "habit.detail.once.label", defaultValue: "约定的那一天"))
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    if let date = habit.startDate {
                        Text(date.formatted(.dateTime.month(.defaultDigits)) + " · " + date.formatted(.dateTime.day()))
                            .font(.system(size: 40, weight: .regular, design: .serif))
                            .foregroundStyle(tint)
                    }
                    Text(isDoneToday
                         ? String(localized: "habit.detail.once.done", defaultValue: "已经完成，这个习惯就此圆满")
                         : String(localized: "habit.detail.once.today", defaultValue: "就是今天，完成后这个习惯自然结束"))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthProgressText: String {
        let days = HabitDetailMonthGrid.monthStates(for: habit)
        let scheduled = days.filter { $0.state != .rest }
        return "\(scheduled.filter { $0.state == .completed }.count) / \(scheduled.count)"
    }

    // MARK: Stats

    private var statsCard: some View {
        WeekCard {
            HStack(spacing: 0) {
                if habit.scheduleKind == .weekly {
                    statItem("\(stats.currentStreak)", String(localized: "habit.detail.stat.current_streak", defaultValue: "当前连续"))
                    statItem("\(stats.longestStreak)", String(localized: "habit.detail.stat.longest_streak", defaultValue: "最长连续"))
                } else {
                    statItem("\(stats.completedCount)", String(localized: "habit.detail.stat.completed", defaultValue: "累计完成"))
                    statItem("\(stats.missedCount)", String(localized: "habit.detail.stat.missed", defaultValue: "中断"))
                }
                statItem(
                    stats.completionRatePercent.map { "\($0)%" } ?? "—",
                    String(localized: "habit.detail.stat.rate", defaultValue: "完成率")
                )
            }
        }
    }

    private func statItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func sectionLabel(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.textTertiary)
            Spacer()
            Text(trailing)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.textTertiary)
                .monospacedDigit()
        }
    }
}

// MARK: Rhythm modules

private struct HabitDetailWeekStrip: View {
    let days: [HabitWeekStripDay]
    let tint: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    HabitDayMark(state: day.state, tint: tint)
                        .frame(width: 26, height: 26)
                    Text(WeekyiiWeekday.localizedSymbol(for: day.isoWeekday))
                        .font(.system(size: 11, weight: day.isToday ? .semibold : .regular))
                        .foregroundStyle(day.isToday ? Color.weekyiiPrimary : Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HabitDetailMonthGrid: View {
    let habit: HabitModel
    let tint: Color

    struct Cell: Identifiable {
        let id: String
        let day: Int
        let isToday: Bool
        let state: HabitWeekStripDay.State
    }

    /// Same rules as the week strip, applied to every day of the current month.
    @MainActor
    static func monthStates(for habit: HabitModel, today: Date = Date()) -> [Cell] {
        let calendar = WeekyiiTimeZone.calendar
        let todayStart = today.startOfDay
        guard let interval = calendar.dateInterval(of: .month, for: todayStart) else { return [] }
        let start = habit.startDate?.startOfDay
        var statusByDay: [String: HabitDayRecordStatus] = [:]
        for record in habit.records {
            statusByDay[record.dayId] = record.status
        }
        var cells: [Cell] = []
        var cursor = interval.start.startOfDay
        while cursor < interval.end {
            let dayId = cursor.dayId
            let isToday = dayId == todayStart.dayId
            let state: HabitWeekStripDay.State
            if let start, cursor >= start, habit.isScheduled(on: cursor) {
                switch statusByDay[dayId] {
                case .completed: state = .completed
                case .missed: state = .missed
                case .pending: state = cursor < todayStart ? .unrecorded : .pendingToday
                case nil: state = isToday ? .pendingToday : (cursor < todayStart ? .unrecorded : .upcoming)
                }
            } else {
                state = .rest
            }
            cells.append(Cell(id: dayId, day: calendar.component(.day, from: cursor), isToday: isToday, state: state))
            cursor = cursor.addingDays(1)
        }
        return cells
    }

    var body: some View {
        let cells = Self.monthStates(for: habit)
        let leading = cells.first.flatMap { WeekyiiDayId.date(from: $0.id)?.isoWeekday }.map { $0 - 1 } ?? 0
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(1...7, id: \.self) { weekday in
                    Text(WeekyiiWeekday.localizedSymbol(for: weekday))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                }
                ForEach(0..<leading, id: \.self) { index in
                    Color.clear.frame(height: 26).id("lead-\(index)")
                }
                ForEach(cells) { cell in
                    ZStack {
                        HabitDayMark(state: cell.state, tint: tint, shape: .rounded)
                        Text("\(cell.day)")
                            .font(.system(size: 10, weight: cell.isToday ? .bold : .regular))
                            .foregroundStyle(cell.state == .completed ? .white : Color.textSecondary)
                    }
                    .frame(height: 26)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HabitDayMark: View {
    enum MarkShape { case circle, rounded }

    let state: HabitWeekStripDay.State
    let tint: Color
    var shape: MarkShape = .circle

    var body: some View {
        switch state {
        case .completed:
            base.fill(tint)
        case .missed:
            base.fill(Color.taskDDL.opacity(0.3))
        case .unrecorded:
            base.stroke(Color.textTertiary.opacity(0.4), lineWidth: 1.5).padding(1)
        case .pendingToday:
            base.stroke(tint, style: StrokeStyle(lineWidth: 2, dash: [3, 2.5])).padding(1)
        case .upcoming:
            base.fill(tint.opacity(0.14))
        case .rest:
            if shape == .rounded {
                base.fill(Color.backgroundTertiary.opacity(0.5))
            } else {
                Circle().fill(Color.backgroundTertiary).frame(width: 7, height: 7)
            }
        }
    }

    private var base: AnyShape {
        shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: Category heroes (decorative, derived from existing statistics)

private struct HabitHeroRings: View {
    let outer: Double
    let inner: Double
    let tint: Color

    var body: some View {
        ZStack {
            ring(progress: outer, lineWidth: 9, inset: 0, color: tint)
            ring(progress: inner, lineWidth: 7, inset: 15, color: Color.accentOrange)
        }
        .accessibilityHidden(true)
    }

    private func ring(progress: Double, lineWidth: CGFloat, inset: CGFloat, color: Color) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0.001), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset + lineWidth / 2)
    }
}

private struct HabitHeroBooks: View {
    let completed: Int
    let isDoneToday: Bool
    let tint: Color

    private let heights: [CGFloat] = [0.72, 0.86, 0.64, 0.8, 0.7, 0.9, 0.6]

    var body: some View {
        let solid = min(completed, 6)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<solid, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint.opacity(index.isMultiple(of: 2) ? 1 : 0.6))
                    .frame(width: 9)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .scaleEffect(y: heights[index % heights.count], anchor: .bottom)
            }
            if !isDoneToday {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .frame(width: 9)
                    .scaleEffect(y: 0.66, anchor: .bottom)
            }
            if solid == 0 && isDoneToday {
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 9).scaleEffect(y: 0.7, anchor: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

private struct HabitHeroBreath: View {
    let tint: Color
    @Environment(\.weekyiiReduceMotion) private var reduceMotion
    @State private var inhale = false

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(tint.opacity([0.08, 0.12, 0.2, 0.5][index]))
                    .scaleEffect(CGFloat(4 - index) / 4 * (inhale ? 1 : 0.88))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                inhale = true
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HabitHeroDrop: View {
    let fill: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Image(systemName: "drop.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint.opacity(0.15))
                Rectangle()
                    .fill(tint)
                    .frame(height: proxy.size.height * min(max(fill, 0.06), 1))
                    .mask(alignment: .bottom) {
                        Image(systemName: "drop.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

private struct HabitHeroSparks: View {
    let lit: Int
    let tint: Color

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<9, id: \.self) { index in
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(index < min(lit, 9) ? tint : tint.opacity(0.15))
                    .rotationEffect(.degrees(Double(index * 17 % 40) - 20))
            }
        }
        .padding(4)
        .accessibilityHidden(true)
    }
}

private struct HabitHeroCircles: View {
    let isTogether: Bool
    let tint: Color

    var body: some View {
        let offset: CGFloat = isTogether ? 9 : 18
        ZStack {
            Circle().fill(tint.opacity(0.35)).frame(width: 46, height: 46).offset(x: -offset)
            Circle().fill(tint.opacity(0.75)).frame(width: 46, height: 46).offset(x: offset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private struct HabitHeroTarget: View {
    let rate: Double
    let tint: Color

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(tint.opacity(0.2 + Double(index) * 0.15), lineWidth: 2)
                    .padding(CGFloat(index) * 13 + 6)
            }
            Circle()
                .trim(from: 0, to: min(max(rate, 0.001), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            Circle().fill(tint).frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}
