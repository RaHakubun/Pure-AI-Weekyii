import SwiftUI
import SwiftData

private struct PendingMonthAddTarget: Identifiable {
    let id: String
    let day: DayModel
}

private struct PendingMonthEditTarget: Identifiable {
    let id: String
    let day: DayModel
    let task: TaskItem
}

struct PendingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    @Environment(\.workspaceSelectionStore) private var workspaceSelectionStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: UserSettings
    @State private var viewModel: PendingViewModel?
    @State private var selectedMonth = Date()
    @State private var selectedDate = Date()
    @State private var showingCreateSheet = false
    @State private var monthAddTarget: PendingMonthAddTarget?
    @State private var monthEditTarget: PendingMonthEditTarget?
    @State private var selectedTaskForDetail: TaskItem?
    @State private var errorMessage: String?
    @State private var selectedWeekID: String?
    @State private var monthSummaries: [String: PendingViewModel.MonthDaySummary] = [:]
    @State private var planningExtensionsViewModel: ExtensionsViewModel?
    private let calendar = Calendar(identifier: .iso8601)

    /// Week list or month calendar. Stored in `UserSettings` (device-local), so
    /// the last chosen view is restored after the app restarts.
    private var displayMode: WeekBrowseMode {
        get { settings.pendingBrowseMode }
        nonmutating set { settings.pendingBrowseMode = newValue }
    }

    var body: some View {
        NavigationStack {
            pendingBody
            .accessibilityIdentifier("pendingWorkspaceContent")
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WeekLogo(size: .small, animated: false)
                }
                ToolbarItem(placement: .topBarLeading) {
                    switchModeButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    addWeekButton
                }
            }
            .sheet(isPresented: $showingCreateSheet, onDismiss: {
                viewModel?.refresh()
                refreshMonthSummaries()
            }) {
                if let viewModel {
                    CreateWeekSheet(
                        viewModel: viewModel,
                        initialDate: createSheetInitialDate,
                        initialMonth: selectedMonth,
                        initialMode: displayMode == .month ? .date : nil
                    )
                }
            }
            .sheet(item: $monthAddTarget, onDismiss: {
                refreshMonthSummaries()
            }) { target in
                TaskEditorSheet(
                    title: String(localized: "draft.add_title"),
                    initialType: settings.defaultTaskType,
                    initialTypeIdRaw: settings.defaultTaskTypeIdRaw,
                    onSave: { _, _, _, _, _ in },
                    onSaveWithTypeId: { title, description, type, typeIdRaw, steps, attachments in
                        guard let viewModel else { return }
                        do {
                            try viewModel.addDraftTask(
                                to: target.day,
                                title: title,
                                description: description,
                                type: type,
                                taskTypeIdRaw: typeIdRaw,
                                steps: steps,
                                attachments: attachments
                            )
                            monthAddTarget = nil
                            refreshMonthSummaries()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
            }
            .sheet(item: $monthEditTarget, onDismiss: {
                refreshMonthSummaries()
            }) { target in
                TaskEditorSheet(
                    title: String(localized: "draft.edit_title"),
                    initialTitle: target.task.title,
                    initialDescription: target.task.taskDescription,
                    initialType: target.task.taskType,
                    initialTypeIdRaw: target.task.taskTypeIdRaw,
                    initialSteps: target.task.steps,
                    initialAttachments: target.task.attachments,
                    onSave: { _, _, _, _, _ in },
                    onSaveWithTypeId: { title, description, type, typeIdRaw, steps, attachments in
                        guard let viewModel else { return }
                        do {
                            try viewModel.updateDraftTask(
                                target.task,
                                in: target.day,
                                title: title,
                                description: description,
                                type: type,
                                taskTypeIdRaw: typeIdRaw,
                                steps: steps,
                                attachments: attachments
                            )
                            monthEditTarget = nil
                            refreshMonthSummaries()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
            }
            .sheet(item: $selectedTaskForDetail) { task in
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
        .onAppear {
            if viewModel == nil {
                viewModel = PendingViewModel(modelContext: modelContext)
            }
            if planningExtensionsViewModel == nil {
                planningExtensionsViewModel = ExtensionsViewModel(modelContext: modelContext)
            }
            viewModel?.refresh()
            planningExtensionsViewModel?.refresh(rebuildProjectSnapshots: false)
            viewModel?.seedPendingWeekForUITestsIfNeeded()
            refreshMonthSummaries()
            normalizeSelectedWeek()
            initializeWorkspaceSelectionIfNeeded()
        }
        .refreshOnStateTransitions(using: appState) {
            viewModel?.refresh()
            refreshMonthSummaries()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceDataDidChange)) { _ in
            viewModel?.refresh()
            planningExtensionsViewModel?.refresh(rebuildProjectSnapshots: false)
            refreshMonthSummaries()
        }
        .onChange(of: selectedMonth) { _, _ in
            // 在同一个无动画事务中完成 selectedDate 归位和 monthSummaries 刷新，
            // 避免两者分两帧更新导致 selectedDayDetailCard 在中间帧读到不一致数据而闪烁。
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                normalizeSelectedDateForMonth()
                refreshMonthSummaries()
                normalizeSelectedWeek()
            }
        }
        .onChange(of: selectedDate) { _, date in
            workspaceSelectionStore?.select(.date(date), for: .pending)
        }
        .onChange(of: viewModel?.errorMessage) { _, newValue in
            if let newValue {
                errorMessage = newValue
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

    @ViewBuilder
    private var pendingBody: some View {
        if let viewModel {
            let weeks = viewModel.weeks(in: selectedMonth)

            if displayMode == .weekList, layoutMetrics.layoutClass == .wide, workspaceSelectionStore == nil, !weeks.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                                MonthPickerView(month: $selectedMonth, restriction: .futureOnly)
                                weeksList(weeks: weeks, usesInlineSelection: true)
                            }
                            .padding(layoutMetrics.pageHorizontalPadding)
                        }
                        .frame(minWidth: 330, idealWidth: 370, maxWidth: 420)

                        Divider()

                        if let selectedWeek = selectedWeek(in: weeks) {
                            PendingWeekDetailView(week: selectedWeek)
                                .id(selectedWeek.weekId)
                        } else {
                            inlineSelectionPlaceholder
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                        MonthPickerView(month: $selectedMonth, restriction: .futureOnly)

                        if displayMode == .weekList {
                            if weeks.isEmpty {
                                emptyStateView
                            } else {
                                weeksList(weeks: weeks)
                            }
                        } else {
                            monthOverview
                        }
                    }
                    .padding(.horizontal, layoutMetrics.pageHorizontalPadding)
                    .padding(.vertical, WeekSpacing.base)
                    .weekReadableContent()
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var createSheetInitialDate: Date {
        let today = calendar.startOfDay(for: Date())
        let selected = calendar.startOfDay(for: selectedDate)
        return selected >= today ? selected : today
    }

    private var isSelectedDatePast: Bool {
        calendar.startOfDay(for: selectedDate) < calendar.startOfDay(for: Date())
    }

    private func refreshMonthSummaries() {
        guard let viewModel else {
            monthSummaries = [:]
            return
        }
        monthSummaries = viewModel.monthDaySummaries(in: selectedMonth)
    }

    private func normalizeSelectedDateForMonth() {
        let selectedMonthKey = calendar.dateComponents([.year, .month], from: selectedMonth)
        let selectedDateKey = calendar.dateComponents([.year, .month], from: selectedDate)
        guard selectedMonthKey != selectedDateKey else { return }

        let monthStart = calendar.date(from: selectedMonthKey) ?? selectedMonth
        let today = calendar.startOfDay(for: Date())
        if calendar.isDate(monthStart, equalTo: today, toGranularity: .month) {
            selectedDate = today
        } else {
            selectedDate = monthStart
        }
    }

    private func normalizeSelectedWeek() {
        guard let viewModel else {
            selectedWeekID = nil
            return
        }
        let weeks = viewModel.weeks(in: selectedMonth)
        guard !weeks.isEmpty else {
            selectedWeekID = nil
            return
        }
        if !weeks.contains(where: { $0.weekId == selectedWeekID }) {
            selectedWeekID = weeks.first?.weekId
        }
    }

    /// The calendar and the right inspector must start from the same future
    /// date. Prefer the nearest planned day, then the nearest empty future
    /// day when the user has created a week but has not filled it yet.
    private func initializeWorkspaceSelectionIfNeeded() {
        guard let workspaceSelectionStore,
              workspaceSelectionStore.selection(for: .pending) == nil,
              let viewModel else {
            return
        }

        let futureDays = viewModel.pendingWeeks
            .flatMap(\.days)
            .filter { $0.date > calendar.startOfDay(for: Date()) }
            .sorted { $0.date < $1.date }
        guard let target = futureDays.first(where: { !$0.tasks.isEmpty }) ?? futureDays.first else {
            return
        }

        selectedMonth = target.date
        selectedDate = target.date
        workspaceSelectionStore.select(.date(target.date), for: .pending)
    }

    private func selectedWeek(in weeks: [WeekModel]) -> WeekModel? {
        weeks.first(where: { $0.weekId == selectedWeekID }) ?? weeks.first
    }

    private var switchModeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                displayMode = displayMode == .weekList ? .month : .weekList
            }
        } label: {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: displayMode == .weekList ? "calendar" : "list.bullet.rectangle")
                Text(
                    displayMode == .weekList
                        ? String(localized: "pending.month.toggle_month")
                        : String(localized: "pending.month.toggle_week")
                )
            }
            .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel(
            displayMode == .weekList
                ? String(localized: "pending.switch.month")
                : String(localized: "pending.switch.week")
        )
        .accessibilityIdentifier("pendingSwitchToMonthButton")
    }

    private var addWeekButton: some View {
        Button {
            if displayMode == .weekList {
                showingCreateSheet = true
            } else {
                presentMonthTaskAddEditor()
            }
        } label: {
            Image(systemName: "plus")
        }
        .disabled(displayMode == .month && isSelectedDatePast)
        .opacity(displayMode == .month && isSelectedDatePast ? 0.45 : 1.0)
        .accessibilityLabel(
            displayMode == .weekList
                ? String(localized: "pending.add_week")
                : String(localized: "pending.month.add_selected_date")
        )
        .accessibilityIdentifier("pendingToolbarAddButton")
    }

    private func presentMonthTaskAddEditor() {
        guard let viewModel else { return }
        guard !isSelectedDatePast else {
            errorMessage = String(localized: "pending.month.past_date_unavailable")
            return
        }

        guard let day = viewModel.resolveEditableDayForMonthAdd(on: selectedDate) else {
            errorMessage = viewModel.errorMessage ?? String(localized: "error.operation_failed_retry")
            return
        }
        monthAddTarget = PendingMonthAddTarget(id: day.dayId, day: day)
    }

    private var monthOverview: some View {
        Group {
            if layoutMetrics.layoutClass.supportsTwoColumns {
                HStack(alignment: .top, spacing: WeekSpacing.xl) {
                    monthCalendarCard
                        .frame(maxWidth: .infinity, alignment: .top)
                    if workspaceSelectionStore == nil {
                        selectedDayDetailCard
                            .frame(width: layoutMetrics.auxiliaryColumnWidth)
                    }
                }
            } else {
                VStack(spacing: WeekSpacing.md) {
                    monthCalendarCard
                    if workspaceSelectionStore == nil {
                        selectedDayDetailCard
                    }
                }
            }
        }
    }

    private var monthCalendarCard: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                if layoutMetrics.layoutClass.supportsSidebar {
                    Label("从悬置箱拖动任务，悬停“未来”后放到具体日期", systemImage: "hand.draw")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.weekyiiPrimary)
                }

                PendingMonthCalendarView(
                    selectedDate: $selectedDate,
                    selectedMonth: $selectedMonth,
                    summaries: monthSummaries,
                    showRegular: settings.pendingMonthShowRegular,
                    showDDL: settings.pendingMonthShowDDL,
                    showLeisure: settings.pendingMonthShowLeisure,
                    onDropSuspendedTask: assignSuspendedTaskPayload
                )
                // 月份变化时强制重建日历格视图树，消除 LazyVGrid cell 跨月复用时的 identity 错乱。
                .id(calendar.dateComponents([.year, .month], from: selectedMonth))
            }
        }
    }

    private func assignSuspendedTaskPayload(_ payload: String, to date: Date) -> Bool {
        let prefix = "weekyii:suspended:"
        guard payload.hasPrefix(prefix),
              let id = UUID(uuidString: String(payload.dropFirst(prefix.count))),
              let planningExtensionsViewModel,
              let task = planningExtensionsViewModel.suspendedTasks.first(where: { $0.id == id })
        else {
            return false
        }

        planningExtensionsViewModel.assignSuspendedTask(task, to: date)
        if let message = planningExtensionsViewModel.errorMessage {
            errorMessage = message
            return false
        }

        viewModel?.refresh()
        refreshMonthSummaries()
        return true
    }

    private var selectedDayDetailCard: some View {
        let day = viewModel?.dayRecord(on: selectedDate)
        let tasks = day.flatMap { viewModel?.tasksForDisplay(in: $0) } ?? []

        return PendingSelectedDaySection(
            selectedDate: selectedDate,
            day: day,
            tasks: tasks,
            isSelectedDatePast: isSelectedDatePast,
            onTaskTap: { task in
                guard let day, let viewModel else {
                    selectedTaskForDetail = task
                    return
                }
                if viewModel.canEdit(day), task.zone == .draft {
                    monthEditTarget = PendingMonthEditTarget(
                        id: task.id.uuidString,
                        day: day,
                        task: task
                    )
                } else {
                    selectedTaskForDetail = task
                }
            }
        )
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                CatCoveredSymbol(systemName: "calendar.badge.plus", pointSize: 60)
                    .font(.system(size: 60))
                    .foregroundStyle(Color.weekyiiGradient)
                
                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "pending.empty.title"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                    
                    Text(String(localized: "pending.empty.subtitle"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
    }
    
    // MARK: - Weeks List
    
    private func weeksList(weeks: [WeekModel], usesInlineSelection: Bool = false) -> some View {
        let usesWorkspaceSelection = workspaceSelectionStore != nil
        // .id 确保月份切换时整个列表整体替换而非逐个 diff，消除跨月卡片的残留动画。
        return VStack(spacing: WeekSpacing.md) {
            // 统计信息
            if workspaceSelectionStore == nil {
                WeekCard(accentColor: .accentOrange) {
                    HStack {
                        VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                            Text(String(localized: "pending.total_weeks"))
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Text("\(weeks.count)")
                                .font(.titleLarge)
                                .foregroundColor(.accentOrange)
                        }

                        Spacer()

                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 40))
                            .foregroundColor(.accentOrange.opacity(0.3))
                    }
                    
                    Spacer()
                    
                    CatCoveredSymbol(systemName: "calendar.badge.clock", pointSize: 40)
                        .font(.system(size: 40))
                        .foregroundColor(.accentOrange.opacity(0.3))
                }
            }
            
            // 周卡片列表
            ForEach(weeks) { week in
                PendingWeekCard(
                    week: week,
                    outlook: viewModel?.weekOutlook(for: week) ?? PendingViewModel.buildWeekOutlook(for: week),
                    onSelect: usesInlineSelection || usesWorkspaceSelection ? {
                        selectedWeekID = week.weekId
                        workspaceSelectionStore?.select(.week(week.weekId), for: .pending)
                    } : nil
                )
                .overlay {
                    if (usesInlineSelection || usesWorkspaceSelection), selectedWeekID == week.weekId {
                        RoundedRectangle(cornerRadius: WeekRadius.large)
                            .stroke(Color.weekyiiPrimary, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        // 月份切换时整体重建，避免跨月卡片复用时的 identity 错乱与残留动画。
        .id(calendar.dateComponents([.year, .month], from: selectedMonth))
    }

    private var inlineSelectionPlaceholder: some View {
        VStack(spacing: WeekSpacing.md) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(Color.weekyiiGradient)
            Text("选择未来周")
                .font(.titleMedium)
                .foregroundColor(.textPrimary)
            Text("在左侧选择一周，查看七天任务与时间安排。")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(WeekSpacing.xl)
    }
}

private struct PendingSelectedDaySection: View {
    let selectedDate: Date
    let day: DayModel?
    let tasks: [TaskItem]
    let isSelectedDatePast: Bool
    let onTaskTap: (TaskItem) -> Void
    @Environment(\.taskTypePresentationCatalog) private var taskTypeCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            header
            if !tasks.isEmpty {
                selectedDaySummary
            }
            taskContent
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pendingSelectedDaySection")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: WeekSpacing.md) {
            VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                Text(
                    String(
                        format: String(localized: "pending.month.schedule"),
                        locale: Locale.current,
                        selectedDate.formatted(Date.FormatStyle().weekday(.abbreviated))
                    )
                )
                    .font(.titleMedium.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: WeekSpacing.xs) {
                    Text(selectedDate, format: Date.FormatStyle().month().day())

                    if let day, day.status != .empty {
                        Text("·")
                        Text(day.status.displayName)
                            .foregroundStyle(day.status.color)
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            }

            Spacer(minLength: WeekSpacing.sm)

            if !tasks.isEmpty {
                Text(
                    String(
                        format: String(localized: "pending.month.task_count"),
                        locale: Locale.current,
                        Int64(tasks.count)
                    )
                )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.weekyiiPrimary)
                    .monospacedDigit()
                    .padding(.horizontal, WeekSpacing.sm)
                    .padding(.vertical, WeekSpacing.xs)
                    .background(Color.weekyiiPrimary.opacity(0.10), in: Capsule())
                    .accessibilityIdentifier("pendingSelectedDayTaskCount")
            }

        }
    }

    private var selectedDaySummary: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WeekSpacing.sm) {
                ForEach(typeSummaries) { summary in
                    summaryChip(
                        title: summary.name,
                        value: "\(summary.count)",
                        icon: summary.iconName,
                        color: summary.color
                    )
                }

                let stepCount = tasks.reduce(0) { $0 + $1.steps.count }
                if stepCount > 0 {
                    summaryChip(
                        title: String(localized: "pending.month.steps"),
                        value: "\(stepCount)",
                        icon: "checklist",
                        color: .weekyiiPrimary
                    )
                }

                let projectCount = Set(tasks.compactMap { $0.project?.id }).count
                if projectCount > 0 {
                    summaryChip(
                        title: String(localized: "pending.month.projects"),
                        value: "\(projectCount)",
                        icon: "folder.fill",
                        color: .accentOrange
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pendingSelectedDayTypeSummary")
    }

    private var typeSummaries: [PendingDayTypeSummary] {
        var result: [PendingDayTypeSummary] = []
        var indicesByID: [String: Int] = [:]

        for task in tasks {
            let id = task.taskTypeIdRaw.isEmpty ? task.taskType.rawValue : task.taskTypeIdRaw
            if let index = indicesByID[id] {
                result[index].count += 1
                continue
            }

            let presentation = taskTypeCatalog.resolve(idRaw: id, fallback: task.taskType)
            indicesByID[id] = result.count
            result.append(
                PendingDayTypeSummary(
                    id: id,
                    name: presentation.name,
                    iconName: presentation.iconName,
                    color: presentation.color,
                    count: 1
                )
            )
        }

        return result
    }

    private func summaryChip(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: WeekSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))

            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()

            Text(title)
                .font(.caption)
        }
        .foregroundStyle(color)
        .padding(.horizontal, WeekSpacing.md)
        .padding(.vertical, WeekSpacing.sm)
        .background(color.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(0.16), lineWidth: 0.75)
        }
    }

    @ViewBuilder
    private var taskContent: some View {
        if isSelectedDatePast {
            Text(String(localized: "pending.month.past_read_only"))
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }

        if day == nil {
            emptyState(String(localized: "pending.month.empty_day"))
        } else if tasks.isEmpty {
            emptyState(String(localized: "pending.month.empty_day"))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    Button {
                        onTaskTap(task)
                    } label: {
                        PendingDayTaskRow(
                            task: task,
                            index: index,
                            accessibilityIdentifier: "pendingMonthTask_\(index)"
                        )
                    }
                    .buttonStyle(.plain)

                    if index < tasks.count - 1 {
                        Divider()
                            .overlay(Color.backgroundTertiary.opacity(0.75))
                            .padding(.leading, 48)
                    }
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        HStack(alignment: .top, spacing: WeekSpacing.sm) {
            CatCoveredSymbol(systemName: "calendar", pointSize: 17)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.textTertiary)

            VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                Text(message)
                    .font(.bodyMedium.weight(.medium))
                    .foregroundStyle(Color.textSecondary)

                if !isSelectedDatePast {
                    Text(String(localized: "pending.month.empty_hint"))
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, WeekSpacing.base)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.backgroundTertiary.opacity(0.55))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pendingMonthEmptyState")
    }
}

private struct PendingDayTypeSummary: Identifiable {
    let id: String
    let name: String
    let iconName: String
    let color: Color
    var count: Int
}

private struct PendingDayTaskRow: View {
    let task: TaskItem
    let index: Int
    let accessibilityIdentifier: String
    @Environment(\.taskTypePresentationCatalog) private var taskTypeCatalog

    private var taskType: TaskTypePresentation {
        taskTypeCatalog.resolve(idRaw: task.taskTypeIdRaw, fallback: task.taskType)
    }

    var body: some View {
        HStack(alignment: .top, spacing: WeekSpacing.md) {
            Text(index + 1, format: .number.precision(.integerLength(2)))
                .font(.caption.weight(.bold))
                .foregroundStyle(taskType.color)
                .monospacedDigit()
                .frame(width: 30, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                Text(task.title)
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                HStack(spacing: WeekSpacing.sm) {
                    Label(taskType.name, systemImage: taskType.iconName)
                        .foregroundStyle(taskType.color)

                    if !task.steps.isEmpty {
                        Label(
                            String(
                                format: String(localized: "pending.month.steps_count"),
                                locale: Locale.current,
                                Int64(task.steps.count)
                            ),
                            systemImage: "checklist"
                        )
                            .foregroundStyle(Color.textSecondary)
                    }

                    if let project = task.project {
                        Label(project.name, systemImage: "folder")
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption2.weight(.medium))
            }

            Spacer(minLength: WeekSpacing.xs)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textTertiary.opacity(0.75))
                .padding(.top, 5)
        }
        .padding(.vertical, WeekSpacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct PendingMonthCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var selectedMonth: Date
    let summaries: [String: PendingViewModel.MonthDaySummary]
    let showRegular: Bool
    let showDDL: Bool
    let showLeisure: Bool
    let onDropSuspendedTask: (String, Date) -> Bool

    private let calendar = Calendar(identifier: .iso8601)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private let weekdaySymbols: [String] = {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale.current
        return cal.shortWeekdaySymbols
    }()

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
    }

    private var monthEnd: Date {
        calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
    }

    private var calendarDays: [PendingCalendarDay] {
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingOffset = firstWeekday - 1

        var days: [PendingCalendarDay] = []
        if leadingOffset > 0 {
            for i in (1...leadingOffset).reversed() {
                guard let date = calendar.date(byAdding: .day, value: -i, to: monthStart) else { continue }
                days.append(PendingCalendarDay(date: date, isCurrentMonth: false))
            }
        }

        var cursor = monthStart
        while cursor < monthEnd {
            days.append(PendingCalendarDay(date: cursor, isCurrentMonth: true))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? monthEnd
        }

        let remainder = days.count % 7
        if remainder > 0 {
            let trailing = 7 - remainder
            for i in 0..<trailing {
                guard let date = calendar.date(byAdding: .day, value: i, to: monthEnd) else { continue }
                days.append(PendingCalendarDay(date: date, isCurrentMonth: false))
            }
        }

        return days
    }

    var body: some View {
        // 与「过去」月历保持同一垂直节奏：星期标题、日期格标记行、底部图例。
        // 未来页仍以任务类型表达当天计划，不复用过去页的完成／过期语义。
        VStack(spacing: WeekSpacing.sm) {
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(calendarDays) { day in
                    dayCell(day)
                }
            }

            typeLegend
                .padding(.top, WeekSpacing.xs)
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: PendingCalendarDay) -> some View {
        let dayId = day.date.dayId
        let summary = summaries[dayId]
        let today = calendar.startOfDay(for: Date())
        let isPastDate = calendar.startOfDay(for: day.date) < today
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day.date)
        let dayNumber = calendar.component(.day, from: day.date)
        let regularCount = summary?.regularCount ?? 0
        let ddlCount = summary?.ddlCount ?? 0
        let leisureCount = summary?.leisureCount ?? 0
        let showsRegularMarker = showRegular && regularCount > 0
        let showsDDLMarker = showDDL && ddlCount > 0
        let showsLeisureMarker = showLeisure && leisureCount > 0
        let hasVisibleMarker = showsRegularMarker || showsDDLMarker || showsLeisureMarker

        Button {
            guard day.isCurrentMonth, !isPastDate else { return }
            withAnimation(.snappy(duration: 0.22)) {
                selectedDate = day.date
            }
        } label: {
            // 保留未来任务类型的色彩编码，但把标记独立到日期数字下方，
            // 让日期网格的高度和「过去」页一致。
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                        .fill(
                            dayCellBackground(
                                isSelected: isSelected,
                                isAvailable: day.isCurrentMonth && !isPastDate,
                                hasVisibleMarker: hasVisibleMarker,
                                showsDDLMarker: showsDDLMarker,
                                showsLeisureMarker: showsLeisureMarker
                            )
                        )

                    if isSelected && day.isCurrentMonth && !isPastDate {
                        RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    } else if isToday && day.isCurrentMonth && !isPastDate {
                        RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                            .stroke(Color.weekyiiPrimary, lineWidth: 1.5)
                    }

                    Text("\(dayNumber)")
                        .font(.bodyMedium.weight(isSelected || isToday ? .bold : .medium))
                        .foregroundStyle(
                            dayNumberColor(
                                day: day,
                                isSelected: isSelected,
                                isToday: isToday,
                                isPastDate: isPastDate
                            )
                        )
                }
                .frame(width: 38, height: 40)

                HStack(spacing: 3) {
                    if day.isCurrentMonth && !isPastDate && showsRegularMarker {
                        Circle()
                            .fill(Color.accentGreen)
                            .frame(width: 5, height: 5)
                    }
                    if day.isCurrentMonth && !isPastDate && showsDDLMarker {
                        Image(systemName: TaskType.ddl.monthMarkerIconName)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.taskDDL)
                    }
                    if day.isCurrentMonth && !isPastDate && showsLeisureMarker {
                        Image(systemName: TaskType.leisure.monthMarkerIconName)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.taskLeisure)
                    }
                }
                .frame(height: 10)
                .opacity(hasVisibleMarker ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .weekSoftShadow(
                color: isSelected ? Color.weekyiiPrimary.opacity(0.18) : Color.clear,
                radius: 6,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pendingMonthDay_\(dayId)")
        .disabled(!day.isCurrentMonth || isPastDate)
        .dropDestination(for: String.self) { payloads, _ in
            guard day.isCurrentMonth, !isPastDate else { return false }
            return payloads.contains { payload in
                onDropSuspendedTask(payload, day.date)
            }
        }
        .accessibilityHint(
            day.isCurrentMonth && !isPastDate
                ? "可接收从悬置箱拖来的任务"
                : ""
        )
        .accessibilityLabel(
            calendarDayAccessibilityLabel(
                dayNumber: dayNumber,
                regularCount: regularCount,
                ddlCount: ddlCount,
                leisureCount: leisureCount
            )
        )
    }

    private var typeLegend: some View {
        HStack(spacing: WeekSpacing.lg) {
            if showRegular {
                legendItem(color: .accentGreen, icon: nil, text: String(localized: "pending.month.legend.regular"))
            }
            if showDDL {
                legendItem(color: .taskDDL, icon: TaskType.ddl.monthMarkerIconName, text: "DDL")
            }
            if showLeisure {
                legendItem(
                    color: .taskLeisure,
                    icon: TaskType.leisure.monthMarkerIconName,
                    text: String(localized: "pending.month.legend.leisure")
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("pendingMonthTypeLegend")
    }

    private func legendItem(color: Color, icon: String?, text: String) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func dayCellBackground(
        isSelected: Bool,
        isAvailable: Bool,
        hasVisibleMarker: Bool,
        showsDDLMarker: Bool,
        showsLeisureMarker: Bool
    ) -> Color {
        guard isAvailable else { return .clear }
        if isSelected { return .weekyiiPrimary }
        guard hasVisibleMarker else { return .clear }
        if showsDDLMarker { return .taskDDLBg.opacity(0.78) }
        if showsLeisureMarker { return .taskLeisureBg.opacity(0.78) }
        return .taskRegularBg.opacity(0.78)
    }

    private func calendarDayAccessibilityLabel(
        dayNumber: Int,
        regularCount: Int,
        ddlCount: Int,
        leisureCount: Int
    ) -> String {
        var parts = ["\(dayNumber)"]
        if regularCount > 0 {
            parts.append(
                String(
                    format: String(localized: "pending.month.a11y.regular"),
                    locale: Locale.current,
                    Int64(regularCount)
                )
            )
        }
        if ddlCount > 0 {
            parts.append(
                String(
                    format: String(localized: "pending.month.a11y.ddl"),
                    locale: Locale.current,
                    Int64(ddlCount)
                )
            )
        }
        if leisureCount > 0 {
            parts.append(
                String(
                    format: String(localized: "pending.month.a11y.leisure"),
                    locale: Locale.current,
                    Int64(leisureCount)
                )
            )
        }
        return ListFormatter.localizedString(byJoining: parts)
    }

    private func dayNumberColor(day: PendingCalendarDay, isSelected: Bool, isToday: Bool, isPastDate: Bool) -> Color {
        if !day.isCurrentMonth {
            return .textTertiary.opacity(0.3)
        }
        if isPastDate {
            return .textTertiary.opacity(0.55)
        }
        if isSelected {
            return .weekyiiOnPrimary
        }
        if isToday {
            return .weekyiiPrimary
        }
        return .textPrimary
    }
}

private struct PendingCalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool

    var id: String { date.dayId + (isCurrentMonth ? "_current" : "_adjacent") }
}
