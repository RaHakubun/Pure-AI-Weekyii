import SwiftUI
import SwiftData

private enum TodaySection: Int {
    case today
    case week
}

private enum DraftTaskEditorMode: Identifiable {
    case create
    case edit(TaskItem)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let task):
            return "edit-\(task.id.uuidString)"
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

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userSettings: UserSettings

    @State private var viewModel: TodayViewModel?
    @State private var selectedTaskForDetail: TaskItem?
    @State private var draftTaskEditorMode: DraftTaskEditorMode?
    @State private var errorMessage: String?
    @State private var startFlowCoordinator = TodayStartFlowCoordinator()
    @State private var startFlowStamp: MindStampItem?
    @State private var pendingTodayKillTimeHour: Int?
    @State private var pendingTodayKillTimeMinute: Int?
    @State private var showingTodayKillTimeConfirm = false
    @State private var todayKillTimeConfirmMode: TodayKillTimeConfirmMode = .normal
    @State private var selectedSection: TodaySection = .today
    @State private var taskForPostpone: TaskItem?
    @State private var isDraftFullscreenPresented = false
    @State private var draftFullscreenSourceRect: CGRect = .zero
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
        .onAppear {
            if viewModel == nil {
                let model = TodayViewModel(
                    modelContext: modelContext,
                    timeProvider: TimeProvider(),
                    notificationService: NotificationService.shared,
                    appState: appState,
                    userSettings: userSettings
                )
                viewModel = model
            }
            viewModel?.refresh()
            viewModel?.seedDraftTasksForUITestsIfNeeded()
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
            TaskEditorSheet(
                title: String(localized: "task.detail.title"),
                isReadOnly: true,
                initialTitle: task.title,
                initialDescription: task.taskDescription,
                initialType: task.taskType,
                initialSteps: task.steps,
                initialAttachments: task.attachments,
                onSave: { _, _, _, _, _ in }
            )
        }
        .sheet(item: $draftTaskEditorMode) { mode in
            draftTaskEditorSheet(mode: mode)
        }
        .sheet(isPresented: $startFlowCoordinator.isPresented) {
            if let viewModel {
                startFlowSheet(viewModel: viewModel)
                    .presentationDetents([.fraction(0.5), .large])
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
        .fullScreenCover(isPresented: $isDraftFullscreenPresented) {
            if let viewModel, let day = viewModel.today {
                DraftFullscreenEditorView(
                    day: day,
                    viewModel: viewModel,
                    sourceRect: draftFullscreenSourceRect,
                    onAddTask: {
                        draftTaskEditorMode = .create
                    },
                    onEditTask: { task in
                        draftTaskEditorMode = .edit(task)
                    },
                    onPostponeTask: { task in
                        taskForPostpone = task
                    },
                    onClose: {
                        isDraftFullscreenPresented = false
                    }
                )
                .interactiveDismissDisabled(false)
            }
        }
        .onChange(of: viewModel?.today?.status.rawValue) { _, newValue in
            guard isDraftFullscreenPresented else { return }
            let isStillDraftEditable = newValue == DayStatus.draft.rawValue || newValue == DayStatus.empty.rawValue
            if !isStillDraftEditable {
                isDraftFullscreenPresented = false
            }
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
            .background(Color.backgroundPrimary)
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
                
                // 日期显示
                Text(formatDate(day.dayId))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func killTimeCard(day: DayModel, viewModel: TodayViewModel) -> some View {
        let displayedHour = pendingTodayKillTimeHour ?? day.killTimeHour
        let displayedMinute = pendingTodayKillTimeMinute ?? day.killTimeMinute
        let hasPendingChange = displayedHour != day.killTimeHour || displayedMinute != day.killTimeMinute

        WeekCard(accentColor: .accentOrange) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.accentOrange)
                    Text(String(localized: "killtime.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                
                KillTimeEditor(
                    hour: displayedHour,
                    minute: displayedMinute,
                    isEditable: day.status == .draft || day.status == .execute,
                    onChange: { hour, minute in
                        pendingTodayKillTimeHour = hour
                        pendingTodayKillTimeMinute = minute
                    }
                )

                if day.status == .draft || day.status == .execute, hasPendingChange {
                    HStack(spacing: WeekSpacing.sm) {
                        WeekButton("取消", style: .outline) {
                            pendingTodayKillTimeHour = nil
                            pendingTodayKillTimeMinute = nil
                        }
                        Spacer(minLength: 0)
                        WeekButton("确认修改", style: .primary) {
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
                        }
                    }
                    .frame(maxWidth: .infinity)
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
            draftTaskEditorMode = .create
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
                        draftTaskEditorMode = .create
                    },
                    onEditTask: { task in
                        draftTaskEditorMode = .edit(task)
                    },
                    onPostponeTask: { task in
                        taskForPostpone = task
                    },
                    showsFullscreenButton: false
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
                    
                    Text(focusTask.title)
                        .font(.titleMedium)
                        .foregroundColor(.white)
                        .onTapGesture {
                            selectedTaskForDetail = focusTask
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
        
        // 冻结任务
        if !day.frozenTasks.isEmpty {
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
                    
                    FrozenZoneView(tasks: day.frozenTasks, onTapTask: { task in
                        selectedTaskForDetail = task
                    }, onPostponeTask: { task in
                        taskForPostpone = task
                    })
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
        // 过期提示卡片
        WeekCard(accentColor: .taskDDL) {
            VStack(spacing: WeekSpacing.md) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.taskDDL)
                    Text(String(localized: "expired.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                
                HStack {
                    Text(String(localized: "expired.count"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("\(day.expiredCount)")
                        .font(.titleMedium)
                        .foregroundColor(.taskDDL)
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
                    
                    CompleteZoneView(tasks: day.completedTasks)
                }
            }
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
    private var floatingStartButtonOverlay: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.backgroundPrimary.opacity(0),
                    Color.backgroundPrimary
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 32)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                WeekButton(
                    "准备开始",
                    icon: "play.circle.fill",
                    style: .primary
                ) {
                    startFlowCoordinator.present()
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("todayFloatingStartButton")
            }
            .padding(.horizontal, WeekSpacing.base)
            .padding(.top, WeekSpacing.sm)
            .padding(.bottom, WeekSpacing.sm)
            .background(Color.backgroundPrimary)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func draftTaskEditorSheet(mode: DraftTaskEditorMode) -> some View {
        switch mode {
        case .create:
            TaskEditorSheet(
                title: String(localized: "draft.add_title"),
                initialType: userSettings.defaultTaskType,
                onSave: { title, description, type, steps, attachments in
                    guard let viewModel else { return }
                    do {
                        try viewModel.addTask(
                            title: title,
                            description: description,
                            type: type,
                            steps: steps,
                            attachments: attachments
                        )
                        draftTaskEditorMode = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            )
        case .edit(let task):
            TaskEditorSheet(
                title: String(localized: "draft.edit_title"),
                initialTitle: task.title,
                initialDescription: task.taskDescription,
                initialType: task.taskType,
                initialSteps: task.steps,
                initialAttachments: task.attachments,
                onSave: { title, description, type, steps, attachments in
                    guard let viewModel else { return }
                    do {
                        try viewModel.updateTask(
                            task,
                            title: title,
                            description: description,
                            type: type,
                            steps: steps,
                            attachments: attachments
                        )
                        draftTaskEditorMode = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            )
        }
    }
    
    private func formatDate(_ dayId: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayId) else { return dayId }
        
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

        VStack(alignment: .leading, spacing: WeekSpacing.lg) {
            if startFlowCoordinator.step == .warning {
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
                    startFlowSummaryItem(
                        icon: "checklist",
                        title: "草稿任务",
                        value: "\(draftCount) 项"
                    )
                    startFlowSummaryItem(
                        icon: "clock.fill",
                        title: "截止时间",
                        value: String(format: "%02d:%02d", killTimeHour, killTimeMinute)
                    )
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
                    WeekButton("我再想想", style: .outline) {
                        startFlowStamp = nil
                        startFlowCoordinator.cancel()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("startFlowSecondaryButton")

                    WeekButton("直接进入", style: .primary) {
                        startFlowStamp = viewModel.pickStartRitualStamp()
                        startFlowCoordinator.chooseDirectEnter()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("startFlowPrimaryButton")
                }
            } else {
                VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                    Text("今日思想钢印")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textSecondary)

                    if let quote = startFlowStamp?.text, quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Text("“\(quote)”")
                            .font(.bodyLarge.weight(.medium))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("给自己一个清晰而坚定的开始。")
                            .font(.bodyLarge.weight(.medium))
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(WeekSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: WeekRadius.medium))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("思想钢印内容")
                .accessibilityIdentifier("startFlowRitualCard")

                Spacer(minLength: WeekSpacing.sm)

                WeekButton("确认开始", style: .primary) {
                    do {
                        try viewModel.startDay()
                        startFlowStamp = nil
                        startFlowCoordinator.cancel()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("startFlowPrimaryButton")
            }
        }
        .padding(WeekSpacing.base)
        .background(Color.backgroundPrimary)
    }

    private func startFlowSummaryItem(icon: String, title: String, value: String) -> some View {
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

// MARK: - Task Creator Sheet
private struct DraftFullscreenEditorView: View {
    let day: DayModel
    let viewModel: TodayViewModel
    let sourceRect: CGRect
    let onAddTask: () -> Void
    let onEditTask: (TaskItem) -> Void
    let onPostponeTask: (TaskItem) -> Void
    let onClose: () -> Void

    @State private var revealProgress: CGFloat = 0
    @State private var appearOffsetY: CGFloat = 44
    @State private var dragOffsetY: CGFloat = 0
    @State private var topEditMode: EditMode = .inactive

    var body: some View {
        GeometryReader { proxy in
            let origin = animationOrigin(in: proxy)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let entryOffsetX = (origin.x - center.x) * (1 - revealProgress)
            let offsetY = appearOffsetY + dragOffsetY
            let scale = 0.94 + 0.06 * revealProgress

            ZStack(alignment: .top) {
                Color.backgroundPrimary
                    .opacity(Double(0.88 + 0.12 * revealProgress))
                    .ignoresSafeArea()

                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: WeekSpacing.base) {
                            daySummaryCard
                            DraftEditorView(
                                day: day,
                                viewModel: viewModel,
                                onAddTask: onAddTask,
                                onEditTask: onEditTask,
                                onPostponeTask: onPostponeTask,
                                showsFullscreenButton: false,
                                onFullscreenTap: nil,
                                showsHeaderControls: false,
                                showsDraftHint: false,
                                externalEditMode: $topEditMode
                            )
                        }
                        .padding(.horizontal, WeekSpacing.base)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + WeekSpacing.xl)
                    }
                    .background(Color.backgroundPrimary)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                dismissAnimated()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .frame(width: 36, height: 36)
                                    .background(Color.backgroundSecondary, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("draftFullscreenExitButton")
                            .accessibilityLabel("退出全屏")
                        }

                        ToolbarItem(placement: .principal) {
                            Text(day.dayId)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                        }

                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                onAddTask()
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.title3.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.weekyiiPrimary)
                            .accessibilityIdentifier("draftFullscreenAddButton")

                            Button(topEditMode == .active ? "完成" : "编辑") {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                    topEditMode = topEditMode == .active ? .inactive : .active
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.weekyiiPrimary)
                            .accessibilityIdentifier("draftFullscreenEditButton")
                        }
                    }
                }
                .environment(\.editMode, $topEditMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .scaleEffect(scale)
                .offset(x: entryOffsetX, y: offsetY)
                .opacity(Double(revealProgress))
                .shadow(color: WeekShadow.medium.color.opacity(0.22), radius: 16, x: 0, y: 8)
            }
            .gesture(dismissGesture)
            .onAppear {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    revealProgress = 1
                    appearOffsetY = 0
                }
            }
        }
        .ignoresSafeArea()
    }

    private var daySummaryCard: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                Text("\(day.date, format: Date.FormatStyle().year().month().day()) \(weekdayText(for: day.date))")
                    .font(.titleSmall)
                    .foregroundStyle(Color.textPrimary)
                StatusBadge(status: day.status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func weekdayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                dragOffsetY = value.translation.height
                revealProgress = max(0.82, 1 - value.translation.height / 1200)
            }
            .onEnded { value in
                if value.translation.height > 140 || value.predictedEndTranslation.height > 220 {
                    dismissAnimated()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        dragOffsetY = 0
                        revealProgress = 1
                    }
                }
            }
    }

    private func dismissAnimated() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            dragOffsetY = 520
            revealProgress = 0.96
            appearOffsetY = 28
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onClose()
        }
    }

    private func animationOrigin(in proxy: GeometryProxy) -> CGPoint {
        guard sourceRect != .zero else {
            return CGPoint(x: proxy.size.width * 0.82, y: proxy.size.height * 0.18)
        }
        return CGPoint(x: sourceRect.midX, y: sourceRect.midY)
    }
}
