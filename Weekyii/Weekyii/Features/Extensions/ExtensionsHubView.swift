import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

struct SuspendedCountdownPreset {
    static let defaultOptions = [1, 2, 3, 5, 7, 10, 30]

    /// Presets plus the user's configured default, so the default is always selectable.
    static func options(includingDefault defaultDays: Int) -> [Int] {
        let normalized = max(1, defaultDays)
        guard !defaultOptions.contains(normalized) else { return defaultOptions }
        return (defaultOptions + [normalized]).sorted()
    }
}

// MARK: - Extensions Hub View (New Architecture)

struct ExtensionsHubView: View {
    let animationsActive: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: UserSettings
    @State private var viewModel: ExtensionsViewModel?
    @State private var mindStampViewModel: MindStampViewModel?
    @State private var habitViewModel: HabitViewModel?
    @State private var errorMessage: String?
    /// 上方瓦片区块的自然高度，用于计算项目卡可拉伸的富余空间。
    @State private var upperSectionHeight: CGFloat = 0

    /// Module tiles only rotate when the user left auto-rotation on.
    private var moduleTilesActive: Bool {
        animationsActive && settings.moduleTileRotationEnabled
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let viewportHeight = geo.size.height
                ScrollView {
                    VStack(spacing: WeekSpacing.md) {
                        if let mindStampViewModel, let viewModel, let habitViewModel {
                            VStack(spacing: WeekSpacing.md) {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: WeekSpacing.md),
                                        GridItem(.flexible())
                                    ],
                                    spacing: WeekSpacing.md
                                ) {
                                    MindStampsModulePreview(viewModel: mindStampViewModel, animationsActive: moduleTilesActive)
                                    SuspendedTasksModulePreview(viewModel: viewModel, animationsActive: moduleTilesActive)
                                }

                                HabitsModulePreview(viewModel: habitViewModel, animationsActive: moduleTilesActive)
                            }
                            .background(GeometryReader { proxy in
                                Color.clear.preference(
                                    key: HubUpperSectionHeightKey.self,
                                    value: proxy.size.height
                                )
                            })
                            .onPreferenceChange(HubUpperSectionHeightKey.self) { newValue in
                                upperSectionHeight = newValue
                            }

                            ProjectsModulePreview(
                                viewModel: viewModel,
                                animationsActive: moduleTilesActive,
                                fillHeight: max(
                                    0,
                                    viewportHeight
                                        - upperSectionHeight
                                        - WeekSpacing.md      // 与上方区块的间距
                                        - WeekSpacing.md * 2  // 纵向 padding
                                )
                            )
                        }
                    }
                    .padding(.horizontal, WeekSpacing.base)
                    .padding(.vertical, WeekSpacing.md)
                    .frame(minHeight: viewportHeight, alignment: .top)
                }
                .scrollIndicators(.hidden)
            }
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WeekLogo(size: .small, animated: false)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ExtensionsViewModel(modelContext: modelContext)
            }
            if mindStampViewModel == nil {
                mindStampViewModel = MindStampViewModel(modelContext: modelContext)
            }
            if habitViewModel == nil {
                habitViewModel = HabitViewModel(
                    modelContext: modelContext,
                    appState: appState
                )
            }
            viewModel?.refresh()
            mindStampViewModel?.refresh()
            habitViewModel?.refresh()
        }
        .refreshOnStateTransitions(using: appState) {
            viewModel?.refresh()
            mindStampViewModel?.refresh()
            habitViewModel?.refresh()
        }
        .onChange(of: viewModel?.errorMessage) { _, newValue in
            if let newValue { errorMessage = newValue }
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
}

// MARK: - Suspended Tasks Module Preview

private struct SuspendedTasksModulePreview: View {
    let viewModel: ExtensionsViewModel
    let animationsActive: Bool

    var body: some View {
        NavigationLink {
            SuspendedTasksFullView(viewModel: viewModel)
        } label: {
            LiveModuleTile(
                items: viewModel.hubSuspendedTasks(),
                initialDelay: .seconds(4.0),
                isActive: animationsActive,
                accessibilityIdentifier: "extensionsSuspendedLiveTile",
                aspectRatio: 1,
                tint: { _ in Color.suspendedModuleTint },
                emptyTint: .suspendedModuleTint
            ) { task in
                SuspendedTaskLiveTile(task: task, totalCount: viewModel.suspendedTasks.count)
            } emptyContent: {
                HubEmptyTile(
                    title: String(localized: "extensions.module.suspended.title"),
                    message: String(localized: "extensions.hub.suspended.empty"),
                    icon: "hourglass.circle.fill",
                    tint: .suspendedModuleTint
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("extensionsSuspendedSeeAllButton")
    }
}

// MARK: - Habits Module Preview

private struct HabitsModulePreview: View {
    let viewModel: HabitViewModel
    let animationsActive: Bool

    private var todayProgress: (completed: Int, scheduled: Int) {
        var completed = 0
        var scheduled = 0
        for habit in viewModel.activeHabits {
            let status = viewModel.statistics(for: habit).todayStatus
            guard status != .notScheduled else { continue }
            scheduled += 1
            if status == .completed { completed += 1 }
        }
        return (completed, scheduled)
    }

    var body: some View {
        let progress = todayProgress
        NavigationLink {
            HabitsFullView(viewModel: viewModel)
        } label: {
            LiveModuleTile(
                items: viewModel.activeHabits,
                initialDelay: .seconds(3.2),
                isActive: animationsActive,
                accessibilityIdentifier: "extensionsHabitsLiveTile",
                minHeight: 132,
                tint: { $0.habitColor },
                emptyTint: .accentGreen
            ) { habit in
                HabitLiveTile(
                    habit: habit,
                    habitCount: viewModel.activeHabits.count,
                    completedToday: progress.completed,
                    scheduledToday: progress.scheduled
                )
            } emptyContent: {
                HabitEmptyLiveTile(
                    title: String(localized: "extensions.module.habits.title", defaultValue: "习惯追踪"),
                    message: String(localized: "extensions.hub.habits.empty", defaultValue: "还没有习惯，点击创建"),
                    icon: "repeat.circle.fill",
                    tint: .accentGreen
                )
                .accessibilityIdentifier("extensionsHabitsEmptyTile")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("extensionsHabitsSeeAllButton")
    }
}

private struct HabitLiveTile: View {
    let habit: HabitModel
    let habitCount: Int
    let completedToday: Int
    let scheduledToday: Int

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HubTileHeader(
                title: String(localized: "extensions.module.habits.title", defaultValue: "习惯追踪"),
                icon: "repeat.circle.fill",
                tint: habit.habitColor,
                trailing: "\(completedToday)/\(scheduledToday)"
            )

            HStack(alignment: .center, spacing: WeekSpacing.md) {
                Image(systemName: habit.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(habit.habitColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text(habit.scheduleSummary)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: WeekSpacing.sm)

                VStack(alignment: .trailing, spacing: 4) {
                    if habitCount > 1 {
                        Text(
                            String(
                                format: String(localized: "extensions.hub.habits.more", defaultValue: "还有 %lld 个习惯"),
                                locale: Locale.current,
                                Int64(habitCount - 1)
                            )
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    }

                    Label(
                        String(localized: "extensions.hub.empty.tap_to_see_all"),
                        systemImage: "chevron.right"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(WeekSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Projects Module Preview

private struct ProjectsModulePreview: View {
    let viewModel: ExtensionsViewModel
    let animationsActive: Bool
    /// 视口剩余可拉伸高度；瓦片只吃富余空间，绝不低于自身内容高度。
    var fillHeight: CGFloat = 0

    var body: some View {
        NavigationLink {
            ProjectsFullView(viewModel: viewModel)
        } label: {
            LiveModuleTile(
                items: viewModel.hubProjectSnapshots(),
                initialDelay: .seconds(5.6),
                isActive: animationsActive,
                accessibilityIdentifier: "extensionsProjectsLiveTile",
                minHeight: max(172, fillHeight),
                stretches: true,
                tint: { Color.weekyiiEmphasis(hex: $0.colorHex) },
                emptyTint: .weekyiiPrimary
            ) { snapshot in
                ProjectFocusLiveTile(
                    snapshot: snapshot,
                    projectCount: viewModel.activeProjects().count
                )
            } emptyContent: {
                ProjectEmptyLiveTile()
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("extensionsProjectsSeeAllButton")
    }
}

// MARK: - Suspended Tasks Full View

private struct SuspendedTasksFullView: View {
    private struct TaskGroups {
        var dueSoon: [SuspendedTaskItem] = []
        var later: [SuspendedTaskItem] = []
    }

    @State private var viewModel: ExtensionsViewModel
    @State private var showingCreateSheet = false
    @State private var editingTask: SuspendedTaskItem?
    @State private var deletingTask: SuspendedTaskItem?
    @State private var assigningTask: SuspendedTaskItem?
    @State private var errorMessage: String?
    @Environment(\.taskTypePresentationCatalog) private var taskTypeCatalog
    @EnvironmentObject private var settings: UserSettings

    init(viewModel: ExtensionsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var stats: (total: Int, dueSoon: Int, dueToday: Int) {
        viewModel.suspendedTaskStats()
    }

    private var taskGroups: TaskGroups {
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        let upperBound = today.addingDays(7)
        return viewModel.suspendedTasks.reduce(into: TaskGroups()) { groups, task in
            let deadline = Calendar(identifier: .iso8601).startOfDay(for: task.decisionDeadline)
            if deadline >= today && deadline <= upperBound {
                groups.dueSoon.append(task)
            } else {
                groups.later.append(task)
            }
        }
    }

    var body: some View {
        let groups = taskGroups
        ScrollView {
            VStack(spacing: WeekSpacing.md) {
                guidanceCard
                statsCard

                if viewModel.suspendedTasks.isEmpty {
                    emptyState
                } else {
                    if !groups.dueSoon.isEmpty {
                        section(title: "即将到期", tasks: groups.dueSoon)
                    }
                    if !groups.later.isEmpty {
                        section(title: "其他悬置", tasks: groups.later)
                    }

                    footerCreateButton
                }
            }
            .padding(.horizontal, WeekSpacing.base)
            .padding(.vertical, WeekSpacing.md)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("悬置箱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新增") {
                    showingCreateSheet = true
                }
                .accessibilityIdentifier("suspendedCreateButton")
            }
        }
        .onAppear {
            viewModel.refresh()
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let newValue { errorMessage = newValue }
        }
        .sheet(isPresented: $showingCreateSheet, onDismiss: {
            viewModel.refresh(rebuildProjectSnapshots: false)
        }) {
            SuspendedTaskEditorSheet(
                title: "新增悬置任务",
                initialCountdownDays: settings.suspendedDefaultCountdownDays
            ) { title, description, type, typeIdRaw, countdownDays, steps, attachments in
                _ = viewModel.createSuspendedTask(
                    title: title,
                    description: description,
                    type: type,
                    taskTypeIdRaw: typeIdRaw,
                    countdownDays: countdownDays,
                    steps: steps,
                    attachments: attachments
                )
            }
        }
        .sheet(item: $editingTask, onDismiss: {
            viewModel.refresh(rebuildProjectSnapshots: false)
        }) { task in
            SuspendedTaskEditorSheet(
                title: "编辑悬置任务",
                initialTitle: task.title,
                initialDescription: task.taskDescription,
                initialType: task.taskType,
                initialTypeIdRaw: task.taskTypeIdRaw,
                initialCountdownDays: task.preferredCountdownDays,
                initialSteps: task.steps,
                initialAttachments: task.attachments
            ) { title, description, type, typeIdRaw, countdownDays, steps, attachments in
                viewModel.updateSuspendedTask(
                    task,
                    title: title,
                    description: description,
                    type: type,
                    taskTypeIdRaw: typeIdRaw,
                    countdownDays: countdownDays,
                    steps: steps,
                    attachments: attachments
                )
            }
        }
        .sheet(item: $assigningTask, onDismiss: {
            viewModel.refresh()
        }) { task in
            SuspendedTaskAssignSheet(taskTitle: task.title) { targetDate in
                viewModel.assignSuspendedTask(task, to: targetDate)
            }
        }
        .confirmationDialog(
            "删除悬置任务",
            isPresented: Binding(
                get: { deletingTask != nil },
                set: { if !$0 { deletingTask = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let task = deletingTask {
                Button("删除", role: .destructive) {
                    viewModel.deleteSuspendedTask(task)
                    deletingTask = nil
                }
            }
            Button("取消", role: .cancel) {
                deletingTask = nil
            }
        } message: {
            Text("悬置箱不是回收站。删除后不会保留后路。")
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

    private var guidanceCard: some View {
        WeekCard(accentColor: .suspendedModuleTint) {
            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                Text("在这里记录任务思绪")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                Text("暂存未分配日期的任务。到期前可续期、分配或删除。")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsCard: some View {
        WeekCard(accentColor: .suspendedModuleTint) {
            HStack(spacing: WeekSpacing.sm) {
                statColumn(value: "\(stats.total)", label: "总数")
                statColumn(value: "\(stats.dueSoon)", label: "7天内到期")
                statColumn(value: "\(stats.dueToday)", label: "今日到期")
            }
        }
    }

    private var emptyState: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.md) {
                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.suspendedModuleTint)

                Text("把暂时无法承诺到特定日期的任务放这里。")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)

                Button("新增悬置任务") {
                    showingCreateSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.suspendedModuleTint)
                .accessibilityIdentifier("suspendedEmptyCreateButton")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WeekSpacing.xl)
        }
    }

    private var footerCreateButton: some View {
        Button("新增悬置任务") {
            showingCreateSheet = true
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, WeekSpacing.xl)
        .padding(.vertical, WeekSpacing.md)
        .background(Color.suspendedModuleGradient)
        .clipShape(Capsule())
        .shadow(color: Color.suspendedModuleTint.opacity(0.25), radius: 6, x: 0, y: 3)
        .accessibilityIdentifier("suspendedFooterCreateButton")
        .padding(.top, WeekSpacing.md)
        .padding(.bottom, WeekSpacing.xl)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(.suspendedModuleTint)
            Text(label)
                .font(.caption2)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(title: String, tasks: [SuspendedTaskItem]) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            Text(title)
                .font(.titleSmall)
                .foregroundColor(.textPrimary)

            ForEach(tasks) { task in
                suspendedTaskCard(task)
            }
        }
    }

    private func suspendedTaskCard(_ task: SuspendedTaskItem) -> some View {
        let taskType = taskTypeCatalog.resolve(idRaw: task.taskTypeIdRaw, fallback: task.taskType)

        return VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HStack(alignment: .top, spacing: WeekSpacing.sm) {
                Image(systemName: taskType.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(taskType.color)
                    .frame(width: 32, height: 32)
                    .background(taskType.color.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    if !task.taskDescription.isEmpty {
                        Text(task.taskDescription)
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                suspendedCountdownBadge(task)
            }

            suspendedMetaRow(task)

            HStack(spacing: WeekSpacing.sm) {
                Spacer()

                Menu {
                    Button("分配到某天", systemImage: "calendar.badge.plus") {
                        assigningTask = task
                    }
                    Button("编辑", systemImage: "pencil") {
                        editingTask = task
                    }
                    Button("续期 10 天", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                        viewModel.extendSuspendedTask(task, by: 10)
                    }
                    Button("续期 30 天", systemImage: "clock.badge") {
                        viewModel.extendSuspendedTask(task, by: 30)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.textSecondary)
                }
                .accessibilityIdentifier("suspendedTaskMenuButton_\(task.id.uuidString)")

                Button {
                    deletingTask = task
                } label: {
                    Image(systemName: "trash.circle")
                        .font(.title3)
                        .foregroundColor(.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("suspendedDeleteButton_\(task.id.uuidString)")
            }
        }
        .padding(WeekSpacing.md)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium))
    }

    private func suspendedMetaRow(_ task: SuspendedTaskItem) -> some View {
        let taskType = taskTypeCatalog.resolve(idRaw: task.taskTypeIdRaw, fallback: task.taskType)

        return HStack(spacing: 6) {
            Text(taskType.name)
                .font(.caption2.weight(.semibold))
                .foregroundColor(taskType.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(taskType.color.opacity(0.12))
                .clipShape(Capsule())

            Text("·")
                .font(.caption)
                .foregroundColor(.textTertiary)

            Text(SuspendedTaskMetaFormatter.deadlineText(remainingDays: task.remainingDays()))
                .font(.caption)
                .foregroundColor(.textSecondary)

            Text("·")
                .font(.caption)
                .foregroundColor(.textTertiary)

            Label(SuspendedTaskMetaFormatter.stepsText(count: task.steps.count), systemImage: "list.bullet")
                .font(.caption)
                .foregroundColor(.textSecondary)

            Text("·")
                .font(.caption)
                .foregroundColor(.textTertiary)

            Label(SuspendedTaskMetaFormatter.attachmentsText(count: task.attachments.count), systemImage: "paperclip")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }
}

private struct SuspendedTaskEditorSheet: View {
    let title: String
    let initialTitle: String
    let initialDescription: String
    let initialType: TaskType
    let initialTypeIdRaw: String
    let initialCountdownDays: Int
    let initialSteps: [TaskStep]
    let initialAttachments: [TaskAttachment]
    let onSave: (String, String, TaskType, String, Int, [TaskStep], [TaskAttachment]) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: UserSettings
    @Query(sort: \TaskTypeDefinition.sortOrder) private var taskTypeDefinitions: [TaskTypeDefinition]
    @State private var taskTitle: String
    @State private var taskDescription: String
    @State private var taskType: TaskType
    @State private var taskTypeIdRaw: String
    @State private var countdownDays: Int
    @State private var stepDrafts: [SuspendedStepDraft]
    @State private var attachments: [TaskAttachment]
    @State private var newStepTitle: String = ""
    @FocusState private var isStepInputFocused: Bool
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imagePreviewItem: ImagePreviewItem?

    init(
        title: String,
        initialTitle: String = "",
        initialDescription: String = "",
        initialType: TaskType = .regular,
        initialTypeIdRaw: String? = nil,
        initialCountdownDays: Int = 10,
        initialSteps: [TaskStep] = [],
        initialAttachments: [TaskAttachment] = [],
        onSave: @escaping (String, String, TaskType, String, Int, [TaskStep], [TaskAttachment]) -> Void
    ) {
        self.title = title
        self.initialTitle = initialTitle
        self.initialDescription = initialDescription
        self.initialType = initialType
        self.initialTypeIdRaw = initialTypeIdRaw ?? initialType.rawValue
        self.initialCountdownDays = initialCountdownDays
        self.initialSteps = initialSteps
        self.initialAttachments = initialAttachments
        self.onSave = onSave
        _taskTitle = State(initialValue: initialTitle)
        _taskDescription = State(initialValue: initialDescription)
        _taskType = State(initialValue: initialType)
        _taskTypeIdRaw = State(initialValue: initialTypeIdRaw ?? initialType.rawValue)
        _countdownDays = State(initialValue: initialCountdownDays)
        _stepDrafts = State(
            initialValue: initialSteps
                .sorted {
                    if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                    return $0.createdAt < $1.createdAt
                }
                .enumerated()
                .map { index, step in
                    SuspendedStepDraft(
                        id: UUID(),
                        title: step.title,
                        isCompleted: step.isCompleted,
                        sortOrder: index
                    )
                }
        )
        _attachments = State(initialValue: initialAttachments)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WeekSpacing.lg) {
                    WeekCard(accentColor: .suspendedModuleTint) {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            Text("在这里记录未决定具体时限的任务")
                                .font(.titleSmall)
                                .foregroundColor(.textPrimary)
                            Text("暂时不属于任何一天、须在倒计时内再次决策。")
                                .font(.bodySmall)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    WeekCard(accentColor: selectedTaskTypeColor) {
                        VStack(alignment: .leading, spacing: WeekSpacing.md) {
                            TextField("输入任务名称", text: $taskTitle)
                                .font(.titleSmall)
                                .padding(WeekSpacing.md)
                                .background(Color.backgroundTertiary)
                                .cornerRadius(WeekRadius.medium)
                                .accessibilityIdentifier("suspendedTaskTitleField")

                            TextField("输入任务描述", text: $taskDescription, axis: .vertical)
                                .font(.bodyMedium)
                                .lineLimit(3...5)
                                .padding(WeekSpacing.md)
                                .background(Color.backgroundTertiary)
                                .cornerRadius(WeekRadius.medium)

                            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                                Text("任务类型")
                                    .font(.captionBold)
                                    .foregroundColor(.textSecondary)
                                ScrollView(.horizontal) {
                                    HStack(spacing: WeekSpacing.xs) {
                                        ForEach(availableTaskTypeDefinitions, id: \.idRaw) { definition in
                                            suspendedTypeChip(definition)
                                        }
                                    }
                                }
                                .scrollIndicators(.hidden)
                            }
                        }
                    }

                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.md) {
                            Text("步骤")
                                .font(.titleSmall)
                                .foregroundColor(.textPrimary)

                            if stepDrafts.isEmpty {
                                Text("暂无步骤")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            } else {
                                VStack(spacing: WeekSpacing.sm) {
                                    ForEach(stepDrafts) { draft in
                                        stepRow(for: draft.id)
                                    }
                                }
                            }

                            HStack(spacing: WeekSpacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentGreen)
                                TextField("新增步骤", text: $newStepTitle)
                                    .focused($isStepInputFocused)
                                    .onSubmit { addNewStep() }
                                if !newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Button("添加") {
                                        addNewStep()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.accentGreen)
                                }
                            }
                        }
                    }

                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.md) {
                            Text("附件")
                                .font(.titleSmall)
                                .foregroundColor(.textPrimary)

                            let columns = [
                                GridItem(.adaptive(minimum: 92), spacing: WeekSpacing.sm)
                            ]
                            LazyVGrid(columns: columns, spacing: WeekSpacing.sm) {
                                ForEach(attachments, id: \.id) { attachment in
                                    attachmentTile(attachment)
                                }
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    RoundedRectangle(cornerRadius: WeekRadius.medium)
                                        .fill(Color.suspendedModuleTintLight.opacity(0.22))
                                        .frame(height: 96)
                                        .overlay {
                                            VStack(spacing: 6) {
                                                Image(systemName: "plus.square.fill")
                                                    .font(.title2)
                                                    .foregroundColor(.suspendedModuleTint)
                                                Text("添加")
                                                    .font(.captionBold)
                                                    .foregroundColor(.suspendedModuleTint)
                                            }
                                        }
                                }
                                .onChange(of: selectedPhoto) { _, newItem in
                                    loadPhoto(newItem)
                                }
                            }
                        }
                    }

                    WeekCard(accentColor: .suspendedModuleTint) {
                        VStack(alignment: .leading, spacing: WeekSpacing.md) {
                            Text("倒计时")
                                .font(.titleSmall)
                                .foregroundColor(.textPrimary)

                            let presets = SuspendedCountdownPreset.options(includingDefault: countdownDays)
                            let columns = [GridItem(.adaptive(minimum: 62), spacing: WeekSpacing.sm)]
                            LazyVGrid(columns: columns, spacing: WeekSpacing.sm) {
                                ForEach(presets, id: \.self) { value in
                                    presetChip(label: "\(value)天", days: value)
                                }
                            }

                            Stepper(value: $countdownDays, in: 1...120) {
                                Text("倒计时 \(countdownDays) 天")
                                    .font(.bodyMedium)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }
                }
                .padding(WeekSpacing.base)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        normalizeStepOrder()
                        let normalizedSteps = stepDrafts
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .map { draft in
                                TaskStep(
                                    title: draft.title,
                                    isCompleted: draft.isCompleted,
                                    sortOrder: draft.sortOrder,
                                    createdAt: draft.createdAt
                                )
                            }
                        onSave(
                            taskTitle,
                            taskDescription,
                            taskType,
                            taskTypeIdRaw,
                            countdownDays,
                            normalizedSteps,
                            attachments
                        )
                        dismiss()
                    }
                    .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || countdownDays <= 0)
                    .accessibilityIdentifier("suspendedTaskSaveButton")
                }
            }
        }
        .fullScreenCover(item: $imagePreviewItem) { item in
            ImageViewerScreen(image: item.image)
        }
    }

    private var availableTaskTypeDefinitions: [TaskTypeDefinition] {
        let active = taskTypeDefinitions.filter { !$0.isArchived }
        if active.isEmpty { return TaskTypeDefinition.builtInDefinitions() }
        if active.contains(where: { $0.idRaw == taskTypeIdRaw }) { return active }
        if let selected = taskTypeDefinitions.first(where: { $0.idRaw == taskTypeIdRaw }) { return active + [selected] }
        return active
    }

    private var selectedTaskTypeColor: Color {
        taskTypeDefinitions.first { $0.idRaw == taskTypeIdRaw }?.color ?? taskType.color
    }

    private func suspendedTypeChip(_ definition: TaskTypeDefinition) -> some View {
        let isSelected = taskTypeIdRaw == definition.idRaw
        return Button {
            taskType = definition.baseKind
            taskTypeIdRaw = definition.idRaw
        } label: {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: definition.iconName)
                    .font(.caption)
                Text(definition.name)
                    .font(.captionBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundColor(isSelected ? definition.color : .textSecondary)
            .frame(minWidth: 78, minHeight: 36)
            .padding(.horizontal, 8)
            .background(isSelected ? definition.color.opacity(0.15) : Color.backgroundTertiary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? definition.color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func presetChip(label: String, days: Int) -> some View {
        let isSelected = countdownDays == days
        return Button(label) {
            countdownDays = days
        }
        .font(.captionBold)
        .foregroundColor(isSelected ? .white : .suspendedModuleTint)
        .padding(.horizontal, WeekSpacing.md)
        .padding(.vertical, WeekSpacing.sm)
        .background(isSelected ? Color.suspendedModuleTint : Color.suspendedModuleTint.opacity(0.12))
        .clipShape(Capsule())
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func stepRow(for stepID: UUID) -> some View {
        if let index = stepDrafts.firstIndex(where: { $0.id == stepID }) {
            let binding = $stepDrafts[index]
            HStack(spacing: WeekSpacing.sm) {
                Button {
                    binding.isCompleted.wrappedValue.toggle()
                } label: {
                    Image(systemName: binding.isCompleted.wrappedValue ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(binding.isCompleted.wrappedValue ? .accentGreen : .textTertiary)
                }
                .buttonStyle(.plain)

                TextField("步骤内容", text: binding.title, axis: .vertical)
                    .font(.bodyMedium)
                    .lineLimit(1...6)

                Spacer()

                HStack(spacing: WeekSpacing.xs) {
                    Button {
                        guard index > 0 else { return }
                        stepDrafts.swapAt(index, index - 1)
                        normalizeStepOrder()
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(index == 0)

                    Button {
                        guard index < stepDrafts.count - 1 else { return }
                        stepDrafts.swapAt(index, index + 1)
                        normalizeStepOrder()
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(index == stepDrafts.count - 1)

                    Button {
                        stepDrafts.remove(at: index)
                        normalizeStepOrder()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.suspendedModuleTint)
                }
                .font(.caption)
            }
            .padding(WeekSpacing.sm)
            .background(Color.backgroundTertiary)
            .cornerRadius(WeekRadius.medium)
        }
    }

    private func addNewStep() {
        let normalized = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let step = SuspendedStepDraft(id: UUID(), title: normalized, isCompleted: false, sortOrder: stepDrafts.count)
        stepDrafts.append(step)
        normalizeStepOrder()
        newStepTitle = ""
        isStepInputFocused = true
    }

    private func normalizeStepOrder() {
        for index in stepDrafts.indices {
            stepDrafts[index].sortOrder = index
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        item.loadTransferable(type: Data.self) { result in
            guard case .success(let data) = result, let data else { return }
            let attachment = TaskAttachment(data: data, fileName: "image.jpg", fileType: "image/jpeg")
            DispatchQueue.main.async {
                attachments.append(attachment)
            }
        }
    }

    private func deleteAttachment(_ attachment: TaskAttachment) {
        if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
            attachments.remove(at: index)
        }
    }

    @ViewBuilder
    private func attachmentTile(_ attachment: TaskAttachment) -> some View {
        let fileLabel = attachment.fileName.isEmpty ? "附件" : attachment.fileName

        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: WeekRadius.medium)
                .fill(Color.suspendedModuleTintLight.opacity(0.16))
                .frame(height: 96)
                .overlay(alignment: .bottomLeading) {
                    Text(fileLabel)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(2)
                        .foregroundColor(.textPrimary)
                        .padding(8)
                }

            if let data = attachment.data {
                AttachmentThumbnail(data: data)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
            }

            Button {
                deleteAttachment(attachment)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .offset(x: 6, y: -6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let data = attachment.data, let previewImage = UIImage(data: data) else { return }
            imagePreviewItem = ImagePreviewItem(image: previewImage)
        }
    }
}

private struct SuspendedStepDraft: Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    /// Carried across from the persisted step so that saving an untouched step
    /// does not look like a content change to the sync layer.
    var createdAt: Date = Date()
}

private struct SuspendedTaskAssignSheet: View {
    let taskTitle: String
    let onAssign: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var targetDate = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: WeekSpacing.lg) {
                WeekCard(accentColor: .suspendedModuleTint) {
                    VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                        Text(taskTitle)
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)
                        Text("把这项悬置任务真正落到某一天。若那一天或所属周不存在，系统会自动补齐。")
                            .font(.bodySmall)
                            .foregroundColor(.textSecondary)
                    }
                }

                DatePicker(
                    "目标日期",
                    selection: $targetDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .background(Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium))

                Spacer()
            }
            .padding(WeekSpacing.base)
            .background(Color.backgroundPrimary)
            .navigationTitle("分配到某天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认分配") {
                        onAssign(targetDate)
                        dismiss()
                    }
                }
            }
        }
    }
}

private func suspendedDeadlineLabel(for task: SuspendedTaskItem) -> String {
    SuspendedTaskMetaFormatter.deadlineText(remainingDays: task.remainingDays())
}

private func suspendedCountdownBadge(_ task: SuspendedTaskItem) -> some View {
    let days = task.remainingDays()
    let color: Color = days <= 1 ? .red : (days <= 7 ? .accentOrange : .accentGreen)

    return Text(days <= 0 ? "到期" : "D-\(days)")
        .font(.captionBold)
        .foregroundColor(color)
        .padding(.horizontal, WeekSpacing.sm)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
}

enum SuspendedTaskMetaFormatter {
    static func deadlineText(remainingDays: Int) -> String {
        if remainingDays < 0 {
            // Reachable once the suspended box is configured to keep overdue
            // tasks instead of deleting them at the deadline.
            return String(
                format: String(localized: "suspended.deadline.overdue", defaultValue: "已逾期 %d 天"),
                abs(remainingDays)
            )
        }
        if remainingDays == 0 {
            return "今日到期"
        }
        return "\(remainingDays) 天后到期"
    }

    static func stepsText(count: Int) -> String {
        "\(count) 步骤"
    }

    static func attachmentsText(count: Int) -> String {
        "\(count) 附件"
    }
}

// MARK: - Mind Stamps Module Preview

private struct MindStampsModulePreview: View {
    let viewModel: MindStampViewModel
    let animationsActive: Bool

    var body: some View {
        NavigationLink {
            MindStampsFullView(viewModel: viewModel)
        } label: {
            LiveModuleTile(
                items: viewModel.stamps,
                initialDelay: .seconds(2.4),
                isActive: animationsActive,
                accessibilityIdentifier: "extensionsMindStampsLiveTile",
                aspectRatio: 1,
                tint: { _ in Color.accentPink },
                emptyTint: .accentPink
            ) { stamp in
                MindStampLiveTile(stamp: stamp, totalCount: viewModel.stamps.count)
            } emptyContent: {
                HubEmptyTile(
                    title: String(localized: "extensions.module.mindstamps.title"),
                    message: String(localized: "extensions.hub.mindstamps.empty"),
                    icon: "bandage.fill",
                    tint: .accentPink
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("extensionsMindStampsSeeAllButton")
    }
}

// MARK: - Live Hub Tile Faces

extension ProjectTileSnapshot: Identifiable {
    var id: UUID { projectID }
}

/// 上报 hub 上方区块（2×2 瓦片 + 习惯卡）的自然高度，供项目卡计算可拉伸的富余空间。
private struct HubUpperSectionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HubEmptyTile: View {
    let title: String
    let message: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HubTileHeader(title: title, icon: icon, tint: tint, trailing: "")
            Spacer(minLength: 0)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            Text(String(localized: "extensions.hub.empty.tap_to_see_all"))
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(WeekSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HabitEmptyLiveTile: View {
    let title: String
    let message: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HubTileHeader(title: title, icon: icon, tint: tint, trailing: "")

            HStack(alignment: .center, spacing: WeekSpacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(tint.opacity(0.7))
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: 0)
                Label(
                    String(localized: "extensions.hub.empty.tap_to_see_all"),
                    systemImage: "chevron.right"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(WeekSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MindStampLiveTile: View {
    let stamp: MindStampItem
    let totalCount: Int

    private var image: UIImage? {
        guard let blob = stamp.imageBlob else { return nil }
        return UIImage(data: blob)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.accentPink.opacity(0.08)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)

                    LinearGradient(
                        colors: [.black.opacity(0.02), .black.opacity(0.58)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                    HubTileHeader(
                        title: String(localized: "extensions.module.mindstamps.title"),
                        icon: "bandage.fill",
                        tint: image == nil ? .accentPink : .white,
                        trailing: "\(totalCount)"
                    )

                    Spacer(minLength: 0)

                    Text(stamp.text.isEmpty ? String(localized: "extensions.hub.mindstamps.image_only") : stamp.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(image == nil ? Color.textPrimary : .white)
                        .lineLimit(image == nil ? 3 : 2)
                        .multilineTextAlignment(.leading)

                    Text(stamp.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(image == nil ? Color.textTertiary : .white.opacity(0.82))
                }
                .padding(WeekSpacing.md)
            }
        }
    }
}

private struct SuspendedTaskLiveTile: View {
    let task: SuspendedTaskItem
    let totalCount: Int
    private let calendar = Calendar(identifier: .iso8601)

    private var deadline: Date { calendar.startOfDay(for: task.decisionDeadline) }
    private var today: Date { calendar.startOfDay(for: Date()) }

    private var deadlineLabel: String {
        if deadline < today { return String(localized: "extensions.hub.suspended.deadline.overdue") }
        if calendar.isDate(deadline, inSameDayAs: today) { return String(localized: "extensions.hub.suspended.deadline.today") }
        let days = calendar.dateComponents([.day], from: today, to: deadline).day ?? 0
        if days <= 7 {
            return String(
                format: String(localized: "extensions.hub.suspended.deadline.days"),
                locale: Locale.current,
                Int64(days)
            )
        }
        return String(
            format: String(localized: "extensions.hub.suspended.deadline.date"),
            locale: Locale.current,
            deadline.formatted(.dateTime.month().day())
        )
    }

    private var deadlineColor: Color {
        deadline <= today ? .taskDDL : .suspendedModuleTint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HubTileHeader(
                title: String(localized: "extensions.module.suspended.title"),
                icon: "hourglass.circle.fill",
                tint: .suspendedModuleTint,
                trailing: String(
                    format: String(localized: "extensions.hub.suspended.count"),
                    locale: Locale.current,
                    Int64(totalCount)
                )
            )

            Spacer(minLength: 0)

            Text(task.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: WeekSpacing.xs) {
                Label(task.taskType.displayName, systemImage: task.taskType.iconName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(task.taskType.color)
                Spacer(minLength: 0)
            }

            Text(deadlineLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(deadlineColor)
        }
        .padding(WeekSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProjectFocusLiveTile: View {
    let snapshot: ProjectTileSnapshot
    let projectCount: Int

    /// 焦点卡在浅色卡片上呈现，项目色只作前景与描边，过亮的色系需压暗后才可读。
    private var projectColor: Color { Color.weekyiiEmphasis(hex: snapshot.colorHex) }
    private var progressPercent: Int { Int((snapshot.progress * 100).rounded()) }

    var body: some View {
        tileContent
            .padding(WeekSpacing.md)
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HStack(spacing: WeekSpacing.sm) {
                Image(systemName: snapshot.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(projectColor)
                    .frame(width: 34, height: 34)
                    .background(projectColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "extensions.module.projects.title"))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(snapshot.name)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: WeekSpacing.sm)

                Text(String(localized: "extensions.module.see_all"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(projectColor)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(projectColor)
            }

            HStack(alignment: .center, spacing: WeekSpacing.md) {
                ZStack {
                    Circle()
                        .stroke(projectColor.opacity(0.12), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(max(snapshot.progress, 0), 1))
                        .stroke(projectColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text("\(progressPercent)%")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(projectColor)
                            .contentTransition(.numericText())
                        Text(String(localized: "extensions.hub.projects.progress_label", defaultValue: "完成"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                    if let nextTaskDate = snapshot.nextTaskDate {
                        HStack(spacing: WeekSpacing.xs) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Text(nextTaskDate, format: .dateTime.month().day())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(projectColor)
                            Text(String(localized: "extensions.hub.projects.deadline_label", defaultValue: "截止"))
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }

                    Text(
                        String(
                            format: String(localized: "extensions.hub.projects.active_count"),
                            locale: Locale.current,
                            Int64(projectCount)
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                Text(String(localized: "extensions.hub.projects.next_step"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)

                Text(snapshot.nextTaskTitle ?? String(localized: "extensions.hub.projects.no_next_task"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        snapshot.nextTaskTitle != nil ? Color.textPrimary : Color.textTertiary
                    )
                    .lineLimit(2)
            }
            .padding(WeekSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(projectColor.opacity(0.06), in: RoundedRectangle(cornerRadius: WeekRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous)
                    .stroke(projectColor.opacity(0.14), lineWidth: 1)
            )

            VStack(spacing: WeekSpacing.sm) {
                HStack(spacing: WeekSpacing.sm) {
                    hubStatTile(
                        title: String(localized: "project.stat.total"),
                        value: snapshot.totalCount,
                        tint: .textPrimary
                    )
                    hubStatTile(
                        title: String(localized: "project.stat.completed"),
                        value: snapshot.completedCount,
                        tint: .accentGreen
                    )
                }
                HStack(spacing: WeekSpacing.sm) {
                    hubStatTile(
                        title: String(localized: "project.stat.remaining"),
                        value: snapshot.remainingCount,
                        tint: projectColor
                    )
                    hubStatTile(
                        title: String(localized: "project.stat.expired"),
                        value: snapshot.expiredCount,
                        tint: .taskDDL
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 统计瓦片吃掉卡片拉伸的富余高度：空白有多少它长多少，卡内永不留无规划的空区。
    private func hubStatTile(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Text("\(value)")
                .font(.titleSmall)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(WeekSpacing.sm)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: WeekRadius.small))
    }
}

private struct ProjectEmptyLiveTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HubTileHeader(
                title: String(localized: "extensions.module.projects.title"),
                icon: "folder.fill",
                tint: .weekyiiPrimary,
                trailing: String(localized: "extensions.module.see_all")
            )
            HStack(alignment: .center, spacing: WeekSpacing.sm) {
                Image(systemName: "folder.badge.plus")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.weekyiiPrimary.opacity(0.45))
                Text(String(localized: "extensions.hub.projects.empty"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: 0)
                Label(
                    String(localized: "extensions.hub.projects.tap_to_see_all"),
                    systemImage: "chevron.right"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(WeekSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


private struct HubTileHeader: View {
    let title: String
    let icon: String
    let tint: Color
    let trailing: String

    var body: some View {
        HStack(spacing: WeekSpacing.xs) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Spacer(minLength: 0)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
    }
}

private struct ProjectHubProgressRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.14), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(width: 48, height: 48)
    }
}

// MARK: - Projects Full View (Wrapped Existing)

private struct ProjectsFullView: View {
    private enum ProjectFilter: String, CaseIterable, Identifiable {
        case current
        case completed
        case archived

        var id: String { rawValue }
        var title: String {
            switch self {
            case .current: "进行中"
            case .completed: "已完成"
            case .archived: "已归档"
            }
        }
    }

    private enum BoardMetrics {
        static let columnSpacing: CGFloat = 6
        static let rowSpacing: CGFloat = 6
        static let horizontalPadding: CGFloat = 16
        static let footerSpacing: CGFloat = 32
    }

    @EnvironmentObject private var settings: UserSettings
    @State private var viewModel: ExtensionsViewModel
    @State private var showingCreateSheet = false
    @State private var tileProjects: [ProjectModel] = []
    @State private var isEditingTiles = false
    @State private var draggingProjectID: UUID?
    @State private var deletingProject: ProjectModel?
    @State private var errorMessage: String?
    @State private var selectedFilter: ProjectFilter = .current

    init(viewModel: ExtensionsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .accessibilityIdentifier("projectsFullView")
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(String(localized: "extensions.tab.projects"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editToolbar }
            .sheet(isPresented: $showingCreateSheet, onDismiss: {
                viewModel.refresh()
            }) {
                CreateProjectSheet(viewModel: viewModel)
            }
            .onAppear {
                syncTileProjectsFromModel(force: true)
            }
            .onChange(of: viewModel.projects.map(\.id)) { _, _ in
                syncTileProjectsFromModel(force: draggingProjectID == nil)
            }
            .onChange(of: viewModel.projects.map(\.status)) { _, _ in
                syncTileProjectsFromModel(force: draggingProjectID == nil)
            }
            .onChange(of: selectedFilter) { _, _ in
                isEditingTiles = false
                draggingProjectID = nil
                syncTileProjectsFromModel(force: true)
            }
            .confirmationDialog(
                String(localized: "project.delete.confirm"),
                isPresented: Binding(
                    get: { deletingProject != nil },
                    set: { if !$0 { deletingProject = nil } }
                ),
                titleVisibility: .visible
            ) {
                deleteDialogActions
            } message: {
                Text(String(localized: "project.delete.choice.message"))
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                if let newValue { errorMessage = newValue }
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

    private var content: some View {
        ScrollView {
            VStack(spacing: WeekSpacing.md) {
                if viewModel.projects.isEmpty {
                    emptyStateView
                } else {
                    Picker("项目状态", selection: $selectedFilter) {
                        ForEach(ProjectFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    if tileProjects.isEmpty {
                        WeekCard {
                            VStack(spacing: WeekSpacing.sm) {
                                Image(systemName: selectedFilter == .archived ? "archivebox" : "tray")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color.textTertiary)
                                Text("这里还没有\(selectedFilter.title)的项目")
                                    .font(.bodyMedium)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, WeekSpacing.lg)
                        }
                    } else {
                        if isEditingTiles {
                            Text(String(localized: "project.tiles.edit_hint"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }

                        ProjectTileGridLayout(
                            columns: settings.effectiveBoardColumnCount,
                            columnSpacing: BoardMetrics.columnSpacing,
                            rowSpacing: BoardMetrics.rowSpacing
                        ) {
                            ForEach(tileProjects) { project in
                                tileView(for: project)
                                    .layoutValue(key: TileColSpanLayoutKey.self, value: project.tileSize.colSpan)
                                    .layoutValue(key: TileRowSpanLayoutKey.self, value: project.tileSize.rowSpan)
                            }
                        }
                        .animation(draggingProjectID == nil ? .interactiveSpring(response: 0.22, dampingFraction: 0.88) : nil, value: tileProjects.map(\.id))
                        .animation(draggingProjectID == nil ? .interactiveSpring(response: 0.22, dampingFraction: 0.88) : nil, value: tileProjects.map(\.tileSizeRaw))
                        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.9), value: isEditingTiles)
                        .transaction { transaction in
                            if draggingProjectID != nil {
                                transaction.animation = nil
                            }
                        }
                    }

                    if selectedFilter == .current {
                        Button {
                            showingCreateSheet = true
                        } label: {
                            HStack(spacing: WeekSpacing.xs) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                Text(String(localized: "project.add"))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, WeekSpacing.xl)
                            .padding(.vertical, WeekSpacing.md)
                            .background(Color.weekyiiGradient)
                            .clipShape(Capsule())
                            .shadow(color: Color.weekyiiPrimary.opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                        .accessibilityIdentifier("projectsFooterCreateButton")
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.top, BoardMetrics.footerSpacing)
                        .padding(.bottom, BoardMetrics.footerSpacing)
                    }
                }
            }
            .padding(.horizontal, BoardMetrics.horizontalPadding)
            .padding(.top, WeekSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        if !tileProjects.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditingTiles ? String(localized: "action.done") : String(localized: "action.edit")) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        isEditingTiles.toggle()
                        if !isEditingTiles {
                            draggingProjectID = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var deleteDialogActions: some View {
        if let project = deletingProject {
            Button(String(localized: "project.delete.choice.only_project"), role: .destructive) {
                viewModel.deleteProject(project, includeTasks: false)
                deletingProject = nil
            }
            Button(String(localized: "project.delete.choice.with_tasks"), role: .destructive) {
                viewModel.deleteProject(project, includeTasks: true)
                deletingProject = nil
            }
        }
        Button(String(localized: "action.cancel"), role: .cancel) {
            deletingProject = nil
        }
    }

    private func syncTileProjectsFromModel(force: Bool) {
        guard force else { return }
        tileProjects = viewModel.sortedProjectsForBoard().filter { project in
            switch selectedFilter {
            case .current:
                project.status == .planning || project.status == .active
            case .completed:
                project.status == .completed
            case .archived:
                project.status == .archived
            }
        }
    }

    @ViewBuilder
    private func tileView(for project: ProjectModel) -> some View {
        let snapshot = snapshotForTile(project)
        let isCompactTile = project.tileSize == .mini || project.tileSize == .small
        let overlayPadding: CGFloat = isCompactTile ? 3 : 6
        let deleteButtonSize: CGFloat = isCompactTile ? 14 : 20
        let resizeIconSize: CGFloat = isCompactTile ? 9 : 12
        let resizeButtonPadding: CGFloat = isCompactTile ? 5 : 8
        let isDraggingTile = draggingProjectID == project.id
        let isCompactBoard = settings.effectiveBoardColumnCount >= 5

        if isEditingTiles {
            ProjectMetroTileView(
                snapshot: snapshot,
                tileSize: project.tileSize,
                statusText: project.status.displayName,
                isEditing: true,
                isDragging: isDraggingTile,
                isCompactBoard: isCompactBoard
            )
            .overlay(alignment: .topTrailing) {
                Button {
                    deletingProject = project
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: deleteButtonSize, weight: .bold))
                        .foregroundStyle(.white, .red)
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                }
                .padding(overlayPadding)
                .buttonStyle(.plain)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        viewModel.cycleTileSize(for: project)
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: resizeIconSize, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(resizeButtonPadding)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .padding(overlayPadding)
                .buttonStyle(.plain)
            }
            .contentShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
            .opacity(isDraggingTile ? 0.86 : 1)
            .onDrag {
                draggingProjectID = project.id
                return NSItemProvider(object: NSString(string: project.id.uuidString))
            } preview: {
                Color.clear
                    .frame(width: 1, height: 1)
            }
            .onDrop(
                of: [UTType.text.identifier],
                delegate: ProjectTileDropDelegate(
                    targetProjectID: project.id,
                    projects: $tileProjects,
                    draggingProjectID: $draggingProjectID
                ) { orderedIDs in
                    viewModel.updateTileOrder(with: orderedIDs)
                }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        isEditingTiles = true
                    }
                }
            )
        } else {
            NavigationLink(destination: ProjectDetailView(project: project, viewModel: viewModel)) {
                ProjectMetroTileView(
                    snapshot: snapshot,
                    tileSize: project.tileSize,
                    statusText: project.status.displayName,
                    isEditing: false,
                    isDragging: false,
                    isCompactBoard: isCompactBoard
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        isEditingTiles = true
                    }
                }
            )
        }
    }

    private func snapshotForTile(_ project: ProjectModel) -> ProjectTileSnapshot {
        viewModel.tileSnapshotsByProjectID[project.id] ?? ProjectTileSnapshot(
            projectID: project.id,
            name: project.name,
            icon: project.icon,
            colorHex: project.color,
            progress: project.progress,
            completedCount: project.completedTaskCount,
            totalCount: project.totalTaskCount,
            remainingCount: max(project.totalTaskCount - project.completedTaskCount, 0),
            expiredCount: project.expiredTaskCount,
            nextTaskTitle: nil,
            nextTaskDate: nil
        )
    }

    private var emptyStateView: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.weekyiiGradient)

                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "project.empty.title"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)

                    Text(String(localized: "project.empty.subtitle"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showingCreateSheet = true
                } label: {
                    HStack(spacing: WeekSpacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text(String(localized: "project.add"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, WeekSpacing.xl)
                    .padding(.vertical, WeekSpacing.md)
                    .background(Color.weekyiiGradient)
                    .clipShape(Capsule())
                    .shadow(color: Color.weekyiiPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .accessibilityIdentifier("projectsEmptyCreateButton")
                .buttonStyle(ScaleButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectsEmptyState")
    }
}

private struct ProjectMetroTileView: View {
    let snapshot: ProjectTileSnapshot
    let tileSize: ProjectTileSize
    let statusText: String
    let isEditing: Bool
    let isDragging: Bool
    let isCompactBoard: Bool

    /// 磁贴底色：过暗的项目色在渲染时抬到亮度下限之上，存储值不动。
    private var projectColor: Color { Color.weekyiiTileSurface(hex: snapshot.colorHex) }

    /// 磁贴唯一墨色。深浅层次只靠同一墨色的透明度分级，避免一屏内白字与黑字混排。
    private var tileInk: Color { .weekyiiTileInk }

    /// 空项目：一个任务都还没有。计数徽标在此状态下会画成 "✓ 0"，读起来像"全部完成"，
    /// 所以空项目一律不渲染计数，只留一条低强度说明。
    private var isEmptyProject: Bool { snapshot.totalCount == 0 }

    /// 窗口右端跟随最晚待办日延伸，因此可能出现的“计划”是快照的固有语义；
    /// 只有确实存在未来列时才需要图例，避免纯历史窗口多占一行说明。
    private var trendFutureStartIndex: Int? {
        let today = Calendar.current.startOfDay(for: Date())
        guard let lastHistory = snapshot.trend.lastIndex(where: { $0.day <= today }),
              lastHistory + 1 < snapshot.trend.count else { return nil }
        return lastHistory + 1
    }

    var body: some View {
        let presentation = ProjectTilePresentation(
            snapshot: snapshot,
            size: tileSize,
            isEditing: isEditing,
            liveTick: 0,
            isCompactBoard: isCompactBoard
        )

        tileContent(presentation: presentation)
        .padding(.top, presentation.contentInsets.top)
        .padding(.leading, presentation.contentInsets.leading)
        .padding(.bottom, presentation.contentInsets.bottom)
        .padding(.trailing, presentation.contentInsets.trailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .stroke(isEditing ? tileInk.opacity(0.18) : tileInk.opacity(0.10), lineWidth: isEditing ? 1.5 : 1)
        )
        .shadow(
            color: .black.opacity(isDragging ? 0.16 : 0.10),
            radius: isDragging ? 8 : 5,
            x: 0,
            y: isDragging ? 4 : 3
        )
        .scaleEffect(scaleValue)
    }

    @ViewBuilder
    private func tileContent(presentation: ProjectTilePresentation) -> some View {
        switch tileSize {
        case .mini:
            miniTileBody(presentation: presentation)
        case .small:
            smallTileBody(presentation: presentation)
        case .medium:
            mediumTileBody(presentation: presentation)
        case .wide:
            wideTileBody(presentation: presentation)
        }
    }

    private var tileBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    projectColor.opacity(0.95),
                    projectColor.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    .white.opacity(isEditing ? 0.10 : 0.14),
                    .white.opacity(0.02),
                    .black.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .fill(.white.opacity(0.05))
                .padding(1)
        }
    }

    private func miniTileBody(presentation: ProjectTilePresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            tileIconBadge(size: 10)

            Spacer(minLength: 0)

            compactPrimaryPanel(for: presentation.livePanel)

            if presentation.showsTitle {
                Text(snapshot.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(tileInk.opacity(0.92))
                    .lineLimit(presentation.titleLineLimit)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func smallTileBody(presentation: ProjectTilePresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: WeekSpacing.xs) {
                tileIconBadge(size: 9)

                if presentation.showsTitle {
                    Text(snapshot.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(tileInk.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                compactPrimaryPanel(for: presentation.livePanel)
            }

            Spacer(minLength: 0)

            if presentation.showsProgressBar {
                tileProgressBar(height: 4)
            }

            if presentation.secondaryContent == .microStatsStrip, !isEmptyProject {
                smallStatsStrip
            }
        }
    }

    private func mediumTileBody(presentation: ProjectTilePresentation) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            tileHeader(
                presentation: presentation,
                titleFontSize: isEditing ? 15 : 17,
                titleWeight: .bold
            )

            Spacer(minLength: 0)

            mediumPrimaryPanel(presentation: presentation)
                .foregroundStyle(tileInk)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.28), value: presentation.livePanel)

            if presentation.showsProgressBar {
                tileProgressBar(height: 5)
            }

            if presentation.secondaryContent == .compactPills, !isEmptyProject {
                mediumPillRow(panel: presentation.livePanel)
            }

            if !isEditing {
                Spacer(minLength: 0)
            }
        }
    }

    private func wideTileBody(presentation: ProjectTilePresentation) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            tileHeader(
                presentation: presentation,
                titleFontSize: isEditing ? 15 : 16,
                titleWeight: .bold,
                showsTrendLegend: presentation.showsTrendChart && trendFutureStartIndex != nil
            )

            if presentation.showsTrendChart {
                trendChart(
                    minHeight: presentation.trendChartMinHeight,
                    maxHeight: presentation.trendChartMaxHeight
                )
            }

            if presentation.taskRowCount > 0, !snapshot.upcomingTasks.isEmpty {
                tileTaskList(limit: presentation.taskRowCount)
            } else if presentation.secondaryContent == .compactPills {
                wideFallbackPanel(presentation: presentation)
            } else if isEmptyProject {
                // 窄板上的 wide 会让位给图表，空项目时整块就只剩标题；补一条低强度说明。
                emptyStatePanel(titleSize: 13, hintSize: 9)
            }

            Spacer(minLength: 0)
        }
    }

    private func tileHeader(
        presentation: ProjectTilePresentation,
        titleFontSize: CGFloat,
        titleWeight: Font.Weight,
        showsTrendLegend: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: WeekSpacing.xs) {
            tileIconBadge(size: 11)

            if presentation.showsTitle {
                Text(snapshot.name)
                    .font(.system(size: titleFontSize, weight: titleWeight, design: .rounded))
                    .foregroundStyle(tileInk)
                    .lineLimit(presentation.titleLineLimit)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsTrendLegend {
                trendLegend
            }

            if presentation.showsStatusChip {
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tileInk.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.96), in: Capsule())
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
    }

    private func tileIconBadge(size: CGFloat) -> some View {
        Image(systemName: snapshot.icon)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tileInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(tileInk.opacity(0.08), in: Capsule())
    }

    /// 空项目的说明文案。"什么都没有"是一条低价值信息，不该占用满级视觉权重。
    private func emptyStatePanel(titleSize: CGFloat, hintSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "project.tasks.empty"))
                .font(.system(size: titleSize, weight: .medium, design: .rounded))
                .foregroundStyle(tileInk.opacity(0.50))
            if !isEditing {
                Text(String(localized: "project.tile.empty.hint"))
                    .font(.system(size: hintSize, weight: .medium, design: .rounded))
                    .foregroundStyle(tileInk.opacity(0.35))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func compactPrimaryPanel(for panel: ProjectTileLivePanel) -> some View {
        switch panel {
        case .progress:
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(Int(snapshot.progress * 100))")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(tileInk)
        case .metrics, .nextTask:
            if isEmptyProject {
                // 空项目画 "✓ 0" 会被读成"全部完成"，改成无完成语义的占位符。
                Image(systemName: "circle.dashed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tileInk.opacity(0.45))
                    .accessibilityLabel(Text(String(localized: "project.tasks.empty")))
            } else {
                HStack(spacing: 4) {
                    Image(systemName: snapshot.remainingCount > 0 ? "clock.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tileInk.opacity(snapshot.remainingCount > 0 ? 0.9 : 0.7))
                    Text("\(snapshot.remainingCount > 0 ? snapshot.remainingCount : snapshot.completedCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(tileInk)
                }
            }
        }
    }

    @ViewBuilder
    private func mediumPrimaryPanel(presentation: ProjectTilePresentation) -> some View {
        switch presentation.livePanel {
        case .progress:
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(Int(snapshot.progress * 100))")
                    .font(.system(size: presentation.primaryNumberFontSize, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: presentation.primaryNumberFontSize * 0.375, weight: .semibold))
            }
        case .metrics:
            if !isEditing {
                emptyStatePanel(titleSize: 15, hintSize: 10)
            }
        case .nextTask:
            nextTaskPanel(
                showsDate: presentation.showsNextTaskDate,
                titleFontSize: 17,
                secondaryFontSize: 12
            )
        }
    }

    private func mediumPillRow(panel: ProjectTileLivePanel) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            metricPill(icon: "checkmark.circle.fill", value: snapshot.completedCount, tint: tileInk.opacity(0.72))
            metricPill(
                icon: panel == .progress ? "list.bullet" : "clock.fill",
                value: panel == .progress ? snapshot.totalCount : snapshot.remainingCount,
                tint: tileInk.opacity(0.92)
            )
        }
    }

    @ViewBuilder
    private func wideFallbackPanel(presentation: ProjectTilePresentation) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            switch presentation.livePanel {
            case .nextTask:
                nextTaskPanel(
                    showsDate: presentation.showsNextTaskDate,
                    titleFontSize: 14,
                    secondaryFontSize: 10
                )
            case .progress:
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(Int(snapshot.progress * 100))")
                        .font(.system(size: presentation.primaryNumberFontSize, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.system(size: 14, weight: .semibold))
                }
            case .metrics:
                emptyStatePanel(titleSize: 14, hintSize: 10)
            }

            if !isEmptyProject {
                wideStatsStrip
            }
        }
        .foregroundStyle(tileInk)
    }

    private var trendLegend: some View {
        HStack(spacing: 5) {
            trendLegendItem(filled: true, title: String(localized: "project.tile.legend.completed"))
            trendLegendItem(filled: false, title: String(localized: "project.tile.legend.planned"))
        }
        .fixedSize()
    }

    private func trendLegendItem(filled: Bool, title: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(filled ? tileInk.opacity(0.92) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .stroke(tileInk.opacity(filled ? 0 : 0.5), lineWidth: 1)
                )
                .frame(width: 6, height: 6)

            Text(title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(tileInk.opacity(0.70))
        }
    }

    private func trendChart(minHeight: CGFloat, maxHeight: CGFloat) -> some View {
        let points = snapshot.trend
        let last = points.count - 1
        // 今天及其左侧是"已发生"：实心柱=完成，叠在半空槽位上的实心淡柱=该日仍欠的待办。
        // 今天右侧是"计划"：空心槽位 + 半透明柱。
        let lastHistoryIndex = (trendFutureStartIndex.map { $0 - 1 }) ?? last
        let peak = max(points.map { $0.completed + $0.planned }.max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        let barHeight: (Int) -> CGFloat = { value in
                            proxy.size.height * CGFloat(value) / CGFloat(peak)
                        }

                        ZStack(alignment: .bottom) {
                            if index <= lastHistoryIndex {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(tileInk.opacity(0.10))
                            } else {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .stroke(tileInk.opacity(0.22), lineWidth: 1)
                            }

                            VStack(spacing: 0) {
                                if point.planned > 0 {
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(tileInk.opacity(index <= lastHistoryIndex ? 0.40 : 0.28))
                                        .frame(height: max(2, barHeight(point.planned)))
                                }

                                if point.completed > 0 {
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(tileInk.opacity(0.92))
                                        .frame(height: max(3, barHeight(point.completed)))
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)

            Rectangle()
                .fill(tileInk.opacity(0.24))
                .frame(height: 1)

            HStack(spacing: 3) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let showsLabel = index == last || (last - index) % 3 == 0
                    let isBoundary = index == lastHistoryIndex

                    Text(showsLabel ? point.day.formatted(.dateTime.day()) : " ")
                        .font(.system(size: 8, weight: isBoundary ? .bold : .medium, design: .rounded))
                        .foregroundStyle(tileInk.opacity(isBoundary ? 0.95 : 0.62))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func tileTaskList(limit: Int) -> some View {
        let rows = Array(snapshot.upcomingTasks.prefix(limit))
        let hiddenCount = max(snapshot.remainingCount - rows.count, 0)

        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 5) {
                    Circle()
                        .fill(tileInk.opacity(entry.isOverdue ? 1 : 0.55))
                        .frame(width: 4, height: 4)

                    Text(entry.title)
                        .font(.system(size: 11, weight: entry.isOverdue ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(tileInk.opacity(0.94))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let date = entry.date {
                        Text(date, format: .dateTime.month().day())
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(tileInk.opacity(entry.isOverdue ? 0.95 : 0.70))
                    }
                }
            }

            if hiddenCount > 0 || snapshot.expiredCount > 0 {
                HStack(spacing: WeekSpacing.xs) {
                    if hiddenCount > 0 {
                        Text(String(format: String(localized: "project.card.more"), hiddenCount))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(tileInk.opacity(0.62))
                    }

                    if snapshot.expiredCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8, weight: .semibold))
                            Text("\(snapshot.expiredCount)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(tileInk)
                    }
                }
            }
        }
    }

    private func tileProgressBar(height: CGFloat) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tileInk.opacity(0.14))

                Capsule()
                    .fill(tileInk.opacity(0.90))
                    .frame(width: proxy.size.width * CGFloat(min(max(snapshot.progress, 0), 1)))
            }
        }
        .frame(height: height)
    }

    private func nextTaskPanel(showsDate: Bool, titleFontSize: CGFloat, secondaryFontSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.nextTaskTitle ?? String(localized: "project.tasks.empty"))
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .lineLimit(2)

            if showsDate, let date = snapshot.nextTaskDate {
                Text(date, format: .dateTime.month().day())
                    .font(.system(size: secondaryFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(tileInk.opacity(0.84))
            }
        }
    }

    private var smallStatsStrip: some View {
        HStack(spacing: WeekSpacing.xs) {
            metricPill(icon: "checkmark.circle.fill", value: snapshot.completedCount, tint: tileInk.opacity(0.72))
            metricPill(icon: "list.bullet", value: snapshot.totalCount, tint: tileInk.opacity(0.92))
        }
    }

    private var wideStatsStrip: some View {
        HStack(spacing: WeekSpacing.xs) {
            metricPill(icon: "checkmark.circle.fill", value: snapshot.completedCount, tint: tileInk.opacity(0.72))
            metricPill(icon: "clock.fill", value: snapshot.remainingCount, tint: tileInk.opacity(0.92))
            if snapshot.expiredCount > 0 {
                metricPill(icon: "exclamationmark.triangle.fill", value: snapshot.expiredCount, tint: tileInk)
            }
        }
    }

    private func metricPill(icon: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text("\(value)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tileInk.opacity(0.10), in: Capsule())
    }

    private var scaleValue: CGFloat {
        if isDragging { return 1.05 }
        if isEditing { return 0.97 }
        return 1.0
    }
}

private struct TileColSpanLayoutKey: LayoutValueKey {
    nonisolated static let defaultValue = 1
}

private struct TileRowSpanLayoutKey: LayoutValueKey {
    nonisolated static let defaultValue = 1
}

private struct ProjectTileGridLayout: Layout {
    let columns: Int
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let arranged = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: arranged.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in arranged.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], totalHeight: CGFloat) {
        let safeColumns = max(columns, 1)
        let totalSpacing = columnSpacing * CGFloat(max(safeColumns - 1, 0))
        let cell = max((width - totalSpacing) / CGFloat(safeColumns), 1)

        var occupancy: [[Bool]] = []
        var frames: [CGRect] = Array(repeating: .zero, count: subviews.count)
        var maxUsedRow = 0

        func ensureRows(_ count: Int) {
            while occupancy.count < count {
                occupancy.append(Array(repeating: false, count: safeColumns))
            }
        }

        func canPlace(row: Int, col: Int, colSpan: Int, rowSpan: Int) -> Bool {
            guard col + colSpan <= safeColumns else { return false }
            ensureRows(row + rowSpan)
            for r in row..<(row + rowSpan) {
                for c in col..<(col + colSpan) where occupancy[r][c] {
                    return false
                }
            }
            return true
        }

        func occupy(row: Int, col: Int, colSpan: Int, rowSpan: Int) {
            for r in row..<(row + rowSpan) {
                for c in col..<(col + colSpan) {
                    occupancy[r][c] = true
                }
            }
        }

        for (index, subview) in subviews.enumerated() {
            let colSpan = max(1, min(safeColumns, subview[TileColSpanLayoutKey.self]))
            let rowSpan = max(1, subview[TileRowSpanLayoutKey.self])
            var row = 0
            var placed = false

            while !placed {
                ensureRows(row + rowSpan)
                for col in 0...(safeColumns - colSpan) {
                    if canPlace(row: row, col: col, colSpan: colSpan, rowSpan: rowSpan) {
                        occupy(row: row, col: col, colSpan: colSpan, rowSpan: rowSpan)
                        let x = CGFloat(col) * (cell + columnSpacing)
                        let y = CGFloat(row) * (cell + rowSpacing)
                        let width = CGFloat(colSpan) * cell + CGFloat(colSpan - 1) * columnSpacing
                        let height = CGFloat(rowSpan) * cell + CGFloat(rowSpan - 1) * rowSpacing
                        frames[index] = CGRect(x: x, y: y, width: width, height: height)
                        maxUsedRow = max(maxUsedRow, row + rowSpan)
                        placed = true
                        break
                    }
                }
                if !placed {
                    row += 1
                }
            }
        }

        let totalHeight = CGFloat(maxUsedRow) * cell + CGFloat(max(maxUsedRow - 1, 0)) * rowSpacing
        return (frames, totalHeight)
    }
}

private struct ProjectTileDropDelegate: DropDelegate {
    let targetProjectID: UUID
    @Binding var projects: [ProjectModel]
    @Binding var draggingProjectID: UUID?
    let didReorder: ([UUID]) -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggingProjectID,
            draggingProjectID != targetProjectID,
            let from = projects.firstIndex(where: { $0.id == draggingProjectID }),
            let to = projects.firstIndex(where: { $0.id == targetProjectID })
        else {
            return
        }

        projects.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: to > from ? to + 1 : to
        )
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggingProjectID != nil else { return false }
        didReorder(projects.map(\.id))
        draggingProjectID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Mind Stamps Full View (Wrapped Existing)

private struct MindStampsFullView: View {
    @State var viewModel: MindStampViewModel
    @State private var showingEditor = false

    init(viewModel: MindStampViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WeekSpacing.md) {
                if viewModel.stamps.isEmpty {
                    emptyState
                } else {
                    MindStampListView(viewModel: viewModel)
                }
            }
            .padding(.horizontal, WeekSpacing.base)
            .padding(.top, WeekSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "extensions.tab.mindstamps"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentPink)
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel(String(localized: "mindstamp.add"))
                .accessibilityIdentifier("mindstampsToolbarCreateButton")
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            viewModel.refresh()
        }) {
            MindStampEditorSheet(viewModel: viewModel)
        }
    }

    private var emptyState: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "bandage.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentPink)

                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "mindstamp.empty.title"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)

                    Text(String(localized: "mindstamp.empty.subtitle"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Text("右上角点 + 新建呆胶布")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, WeekSpacing.md)
                    .padding(.vertical, WeekSpacing.xs)
                    .background(Color.backgroundTertiary)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("mindstampEmptyCreateHint")
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
    }
}
