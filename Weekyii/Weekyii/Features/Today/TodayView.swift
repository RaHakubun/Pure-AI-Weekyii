import SwiftUI
import SwiftData

private enum TodaySection: Int {
    case today
    case week
}

struct TodayView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(UserSettings.self) private var userSettings

    @State private var viewModel: TodayViewModel?
    @State private var showingTaskCreator = false
    @State private var errorMessage: String?
    @State private var selectedSection: TodaySection = .today
    

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel, let day = viewModel.today {
                    content(for: day, viewModel: viewModel)
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
                    notificationService: .shared,
                    appState: appState,
                    userSettings: userSettings
                )
                viewModel = model
            }
            viewModel?.refresh()
            viewModel?.seedDraftTasksForUITestsIfNeeded()
        }
    }

    @ViewBuilder
    private func content(for day: DayModel, viewModel: TodayViewModel) -> some View {
        TodayWeekSwitcher(
            selectedSection: $selectedSection,
            todayContent: { todayContent(day: day, viewModel: viewModel) },
            weekContent: { WeekOverviewContentView() }
        )
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
                    hour: day.killTimeHour,
                    minute: day.killTimeMinute,
                    isEditable: day.status == .draft || day.status == .execute,
                    onChange: { hour, minute in
                        do {
                            try viewModel.changeKillTime(hour: hour, minute: minute)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
            }
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
            showingTaskCreator = true
        }
        .sheet(isPresented: $showingTaskCreator, onDismiss: {
            viewModel.refresh()
        }) {
            TaskEditorSheet(
                title: String(localized: "draft.add_title"),
                onSave: { title, description, type, steps, attachments in
                    do {
                        try viewModel.addTask(title: title, description: description, type: type, steps: steps, attachments: attachments)
                        showingTaskCreator = false
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            )
        }
    }
    
    // MARK: - Draft State
    
    @ViewBuilder
    private func draftStateContent(day: DayModel, viewModel: TodayViewModel) -> some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                DraftEditorView(day: day, viewModel: viewModel)
            }
        }
        
        WeekButton(
            String(localized: "action.start"),
            icon: "play.circle.fill",
            style: .primary,
            isEnabled: !day.sortedDraftTasks.isEmpty
        ) {
            do {
                try viewModel.startDay()
            } catch {
                errorMessage = error.localizedDescription
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
                    
                    FrozenZoneView(tasks: day.frozenTasks)
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
    
}

private struct TodayWeekSwitcher<TodayContent: View, WeekContent: View>: View {
    @Binding var selectedSection: TodaySection
    let todayContent: TodayContent
    let weekContent: WeekContent

    @GestureState private var dragTranslation: CGFloat = 0
    @GestureState private var isDragging = false

    init(
        selectedSection: Binding<TodaySection>,
        @ViewBuilder todayContent: () -> TodayContent,
        @ViewBuilder weekContent: () -> WeekContent
    ) {
        self._selectedSection = selectedSection
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
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .updating($isDragging) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = true
            }
            .onEnded { value in
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
