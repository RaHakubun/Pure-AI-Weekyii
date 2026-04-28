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

                if userSettings.selectedTheme == .sunset {
                    SunsetStatusIllustration()
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: WeekRadius.medium)
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                        )
                } else if userSettings.selectedTheme == .lotr {
                    LotrStatusIllustration()
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: WeekRadius.medium)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
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
                    
                    Text(focusTask.title)
                        .font(.titleMedium)
                        .foregroundColor(.white)
                        .onTapGesture {
                            selectedTaskForDetail = focusTask
                        }

                    TaskProjectOriginBadge(
                        project: focusTask.project,
                        isOnDarkBackground: true
                    )
                    
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
                    
                    FrozenZoneView(
                        tasks: day.frozenTasks,
                        showsProjectOrigin: true,
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
        let killTimeText = String(format: "%02d:%02d", killTimeHour, killTimeMinute)

        VStack(alignment: .leading, spacing: WeekSpacing.base) {
            if startFlowCoordinator.step == .warning {
                StartFlowWarningStepView(
                    draftCount: draftCount,
                    killTimeText: killTimeText,
                    onCancel: {
                        startFlowStamp = nil
                        startFlowCoordinator.cancel()
                    },
                    onContinue: {
                        startFlowStamp = viewModel.pickStartRitualStamp()
                        startFlowCoordinator.chooseDirectEnter()
                    }
                )
            } else {
                StartFlowRitualStepView(
                    stamp: startFlowStamp,
                    onConfirm: {
                        do {
                            try viewModel.startDay()
                            startFlowStamp = nil
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
                SunsetWaterReflectionBackground()
                    .transition(.opacity)
            } else if userSettings.selectedTheme == .lotr {
                LotrRainNightBackground()
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
        VStack(alignment: .leading, spacing: WeekSpacing.base) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                    Text("阶段 2/2 · 思想钢印")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textSecondary)
                    Text("把注意力收束到唯一入口，然后开始今天。")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(alignment: .top, spacing: WeekSpacing.md) {
                    if let blob = stamp?.imageBlob, let uiImage = UIImage(data: blob) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                                    .stroke(Color.backgroundTertiary, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                        Text("今日思想钢印")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textSecondary)

                        ScrollView(showsIndicators: false) {
                            Text(contentText)
                                .font(.bodyLarge.weight(.medium))
                                .foregroundColor(quoteText == nil ? .textSecondary : .textPrimary)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(WeekSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                    .stroke(Color.backgroundTertiary.opacity(0.9), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("思想钢印内容")
            .accessibilityIdentifier("startFlowRitualCard")

            VStack(spacing: WeekSpacing.sm) {
                WeekButton("确认开始", style: .primary, action: onConfirm)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("startFlowPrimaryButton")
            }
            .padding(.top, WeekSpacing.xs)
            .padding(.bottom, WeekSpacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var contentText: String {
        if let quoteText {
            return "“\(quoteText)”"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var sunDrift = false

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
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                    sunDrift = true
                }
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
        guard !reduceMotion else { return base }
        return base + (sunDrift ? 5 : -5)
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
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0)) { timeline in
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

private struct SunsetStatusIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let sunX = size.width * 0.382
            let sunY = size.height * 0.31 + (drift ? 1.3 : -1.3)
            let horizonY = size.height * 0.58

            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: "#3E201E"), Color(hex: "#562922"), Color(hex: "#6A2F27")]
                        : [Color(hex: "#F8D0BA"), Color(hex: "#F19F79"), Color(hex: "#E0715D")],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: colorScheme == .dark ? "#1D2937" : "#8FB2CA"),
                                Color(hex: colorScheme == .dark ? "#111C2A" : "#5E88A6")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: size.height * 0.42)
                    .offset(y: horizonY)

                // 水平线
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.24))
                    .frame(height: 1.0)
                    .position(x: size.width * 0.5, y: horizonY)

                // 不对称地平线体块（右侧）
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 20, bottomLeading: 2, bottomTrailing: 0, topTrailing: 0))
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.34 : 0.16))
                    .frame(width: size.width * 0.34, height: size.height * 0.22)
                    .position(x: size.width * 0.84, y: horizonY - 2)
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.12))
                            .frame(width: size.width * 0.20, height: 1)
                            .offset(x: -10, y: 0)
                    }

                // 太阳本体（偏红，扁平拟物，无漫反射光晕）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: colorScheme == .dark ? "#F46A5F" : "#EE5A4E"),
                                Color(hex: colorScheme == .dark ? "#D8473F" : "#C63B35")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.26), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .scaleEffect(0.68)
                            .offset(y: -8)
                    )
                    .frame(width: 52, height: 52)
                    .position(x: sunX, y: sunY)

                // 主倒影体块（不居中，略向右偏）
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#F36A5D").opacity(colorScheme == .dark ? 0.46 : 0.54),
                                Color(hex: "#D64A42").opacity(colorScheme == .dark ? 0.34 : 0.42),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 64, height: size.height * 0.52)
                    .scaleEffect(x: 1.05, y: 1.0, anchor: .top)
                    .position(x: sunX + 12, y: size.height * 0.77)

                // 非对称水纹
                stylizedRipples(size: size, horizonY: horizonY, sunX: sunX)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 5.8).repeatForever(autoreverses: true)) {
                    drift = true
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func stylizedRipples(size: CGSize, horizonY: CGFloat, sunX: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 20.0)) { timeline in
            Canvas { context, canvasSize in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let bandCount = 8
                let verticalStep = max((canvasSize.height - horizonY) / CGFloat(bandCount + 1), 6.0)

                for i in 0..<bandCount {
                    let p = CGFloat(i) / CGFloat(max(bandCount - 1, 1))
                    let y = horizonY + CGFloat(i + 1) * verticalStep + CGFloat(i % 2 == 0 ? -1.5 : 0.8)
                    let baseWidth = canvasSize.width * (0.14 + p * 0.44)
                    let wobble = CGFloat(sin(t * 0.52 + Double(i) * 0.95)) * (reduceMotion ? 0.8 : 2.6)
                    let centerX = sunX + 10 + wobble + CGFloat(i) * 0.7
                    let height = max(0.9, 1.8 - p * 0.9)
                    let alpha = max(0.05, 0.27 - Double(p) * 0.17)

                    let rect = CGRect(
                        x: centerX - baseWidth / 2,
                        y: y,
                        width: baseWidth,
                        height: height
                    )
                    let path = Path(roundedRect: rect, cornerRadius: height)
                    context.fill(path, with: .color(Color(hex: "#FFD2AE").opacity(alpha)))
                    context.stroke(
                        path,
                        with: .color(Color.white.opacity(alpha * 0.42)),
                        style: StrokeStyle(lineWidth: 0.45)
                    )
                }
            }
            .blendMode(.screen)
        }
    }
}

private struct LotrRainNightBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var rainDrift = false

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
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 5.8).repeatForever(autoreverses: false)) {
                    rainDrift = true
                }
            }
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
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 24.0)) { timeline in
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

private struct LotrStatusIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let horizonY = size.height * 0.62
            let beaconX = size.width * 0.382

            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: "#0B0D10"), Color(hex: "#14171C"), Color(hex: "#1E232A")]
                        : [Color(hex: "#D9DBE0"), Color(hex: "#C9CCD3"), Color(hex: "#BABEC7")],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: colorScheme == .dark ? "#1A1E24" : "#A3A8B1"),
                                Color(hex: colorScheme == .dark ? "#10141A" : "#8E949F")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: size.height * 0.42)
                    .offset(y: horizonY)

                Path { path in
                    path.move(to: CGPoint(x: -12, y: horizonY + 10))
                    path.addLine(to: CGPoint(x: size.width * 0.24, y: horizonY - 22))
                    path.addLine(to: CGPoint(x: size.width * 0.46, y: horizonY + 6))
                    path.addLine(to: CGPoint(x: size.width * 0.66, y: horizonY - 18))
                    path.addLine(to: CGPoint(x: size.width + 12, y: horizonY + 14))
                    path.addLine(to: CGPoint(x: size.width + 12, y: size.height + 20))
                    path.addLine(to: CGPoint(x: -12, y: size.height + 20))
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(colorScheme == .dark ? 0.66 : 0.34))

                Capsule()
                    .fill(Color(hex: colorScheme == .dark ? "#D5A56A" : "#A67943").opacity(pulse ? 0.88 : 0.64))
                    .frame(width: 4, height: 16)
                    .position(x: beaconX, y: horizonY - 6)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#C99A65").opacity(colorScheme == .dark ? 0.34 : 0.24),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 26, height: 44)
                    .position(x: beaconX + 5, y: horizonY + 14)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .accessibilityHidden(true)
    }
}
