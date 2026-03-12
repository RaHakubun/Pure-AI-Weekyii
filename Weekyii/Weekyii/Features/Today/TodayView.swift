import SwiftUI
import SwiftData

// 导入子视图组件和状态管理
// 所有组件都在同一个模块中，不需要单独导入

// 枚举和结构体
enum TodaySection: Int {
    case today
    case week
}

enum DraftTaskEditorMode: Identifiable {
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

struct TodayView: View {
    private let floatingStartOverlayReserveHeight: CGFloat = 120

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userSettings: UserSettings

    @StateObject private var state: TodayViewState

    // 初始化
    init() {
        _state = StateObject(wrappedValue: TodayViewState())
    }

    // 带参数的初始化 - 仅用于测试
    init(modelContext: ModelContext, appState: AppState, userSettings: UserSettings) {
        _state = StateObject(wrappedValue: TodayViewState(modelContext: modelContext, appState: appState, userSettings: userSettings))
    }
    

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = state.viewModel {
                    if let day = viewModel.today {
                        content(for: day, viewModel: viewModel)
                    } else if let message = viewModel.errorMessage {
                        loadingErrorView(message: message) {
                            state.refresh()
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
                state.errorMessage != nil
            }, set: { newValue in
                if !newValue { state.errorMessage = nil }
            })) {
                Button(String(localized: "action.ok"), role: .cancel) { }
            } message: {
                Text(state.errorMessage ?? "")
            }
        }
        .onAppear {
            // 确保使用正确的modelContext
            if state.viewModel == nil || state.viewModel?.today == nil {
                state.updateDependencies(modelContext: modelContext, appState: appState, userSettings: userSettings)
            }
        }
        .onChange(of: userSettings.defaultKillTimeHour) { _, _ in
            state.refresh()
        }
        .onChange(of: userSettings.defaultKillTimeMinute) { _, _ in
            state.refresh()
        }
        .refreshOnStateTransitions(using: appState) {
            state.refresh()
        }
        .onChange(of: state.viewModel?.errorMessage) { _, newValue in
            if let newValue {
                state.errorMessage = newValue
            }
        }
        .sheet(item: $state.selectedTaskForDetail) {
            task in
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
        .sheet(item: $state.draftTaskEditorMode) {
            mode in
            draftTaskEditorSheet(mode: mode)
        }
        .sheet(isPresented: $state.startFlowCoordinator.isPresented) {
            if let viewModel = state.viewModel {
                StartFlowSheet(
                    viewModel: viewModel,
                    coordinator: $state.startFlowCoordinator,
                    startStamp: $state.startFlowStamp,
                    onError: { state.errorMessage = $0 }
                )
                    .presentationDetents([.fraction(0.5), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.backgroundPrimary)
            }
        }
        .sheet(item: $state.taskForPostpone) {
            task in
            PostponeTaskSheet(taskTitle: task.title) { targetDate in
                state.stagePostponeRequest(for: task, targetDate: targetDate)
            }
        }
        .alert("确认后移任务", isPresented: $state.showingPostponeConfirm) {
            Button(String(localized: "action.cancel"), role: .cancel) {
                state.clearPendingPostponeContext()
            }
            Button("确认后移") {
                state.confirmPostponeRequest()
            }
        } message: {
            Text(state.postponeConfirmMessage)
        }
        .alert("目标周尚未创建", isPresented: $state.showingPostponeWeekCreationConfirm) {
            Button(String(localized: "action.cancel"), role: .cancel) {
                state.clearPendingPostponeContext()
            }
            Button("创建并移动", role: .destructive) {
                state.confirmPostponeWithWeekCreation()
            }
        } message: {
            Text(state.postponeCreateWeekConfirmMessage)
        }
        .alert(
            state.todayKillTimeConfirmTitle,
            isPresented: $state.showingTodayKillTimeConfirm
        ) {
            Button(String(localized: "action.cancel"), role: .cancel) { }
            Button("确认") {
                state.applyPendingTodayKillTime()
            }
        } message: {
            Text(state.todayKillTimeConfirmMessage)
        }
    }

    @ViewBuilder
    private func content(for day: DayModel, viewModel: TodayViewModel) -> some View {
        TodayWeekSwitcher(selectedSection: $state.selectedSection, isPagingEnabled: false) {
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
                TodayStatusCard(day: day, daysStartedCount: appState.daysStartedCount)

                // 任务流区域
                TaskFlowSection(
                    day: day,
                    viewModel: viewModel,
                    onAddTask: { state.draftTaskEditorMode = .create },
                    onEditTask: { task in state.draftTaskEditorMode = .edit(task) },
                    onPostponeTask: { task in state.taskForPostpone = task },
                    onSelectTask: { task in state.selectedTaskForDetail = task }
                )

                // 截止时间（放在最后）
                KillTimeCard(
                    day: day,
                    viewModel: viewModel,
                    pendingHour: state.pendingTodayKillTimeHour,
                    pendingMinute: state.pendingTodayKillTimeMinute,
                    onPendingChange: { hour, minute in
                        state.pendingTodayKillTimeHour = hour
                        state.pendingTodayKillTimeMinute = minute
                    },
                    onConfirmChange: { state.confirmKillTimeChange() },
                    showingConfirm: state.showingTodayKillTimeConfirm,
                    confirmMode: state.todayKillTimeConfirmMode
                )
            }
            .weekPadding(WeekSpacing.base)
            .padding(.bottom, shouldShowFloatingStartButton(for: day) ? floatingStartOverlayReserveHeight : 0)
        }
        .overlay(alignment: .bottom) {
            if shouldShowFloatingStartButton(for: day) {
                FloatingStartButton {
                    state.startFlowCoordinator.present()
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
    private func draftTaskEditorSheet(mode: DraftTaskEditorMode) -> some View {
        switch mode {
        case .create:
            TaskEditorSheet(
                title: String(localized: "draft.add_title"),
                initialType: userSettings.defaultTaskType,
                onSave: { title, description, type, steps, attachments in
                    guard let viewModel = state.viewModel else { return }
                    do {
                        try viewModel.addTask(
                            title: title,
                            description: description,
                            type: type,
                            steps: steps,
                            attachments: attachments
                        )
                        state.draftTaskEditorMode = nil
                    } catch {
                        state.errorMessage = error.localizedDescription
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
                    guard let viewModel = state.viewModel else { return }
                    do {
                        try viewModel.updateTask(
                            task,
                            title: title,
                            description: description,
                            type: type,
                            steps: steps,
                            attachments: attachments
                        )
                        state.draftTaskEditorMode = nil
                    } catch {
                        state.errorMessage = error.localizedDescription
                    }
                }
            )
        }
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
