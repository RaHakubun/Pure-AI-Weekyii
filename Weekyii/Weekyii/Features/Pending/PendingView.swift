import SwiftUI
import SwiftData

private enum PendingDisplayMode {
    case weekList
    case month
}

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
    @State private var displayMode: PendingDisplayMode = .weekList
    @State private var selectedWeekID: String?
    @State private var monthSummaries: [String: PendingViewModel.MonthDaySummary] = [:]
    @State private var planningExtensionsViewModel: ExtensionsViewModel?
    private let calendar = Calendar(identifier: .iso8601)

    var body: some View {
        NavigationStack {
            pendingBody
            .accessibilityIdentifier("pendingWorkspaceContent")
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
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
        }
        .refreshOnStateTransitions(using: appState) {
            viewModel?.refresh()
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

            if displayMode == .weekList, layoutMetrics.layoutClass == .wide, !weeks.isEmpty {
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

    private func selectedWeek(in weeks: [WeekModel]) -> WeekModel? {
        weeks.first(where: { $0.weekId == selectedWeekID }) ?? weeks.first
    }

    private var switchModeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                displayMode = displayMode == .weekList ? .month : .weekList
            }
        } label: {
            Image(systemName: displayMode == .weekList ? "calendar" : "rectangle.grid.1x2")
        }
        .accessibilityLabel(
            displayMode == .weekList
                ? String(localized: "pending.switch.month", defaultValue: "切换到月视图")
                : String(localized: "pending.switch.week", defaultValue: "切换到周列表")
        )
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
        .accessibilityLabel(String(localized: "pending.add_week"))
        .accessibilityIdentifier("pendingToolbarAddButton")
    }

    private func presentMonthTaskAddEditor() {
        guard let viewModel else { return }
        guard !isSelectedDatePast else {
            errorMessage = "过去日期不可添加任务"
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
                    selectedDayDetailCard
                        .frame(width: layoutMetrics.auxiliaryColumnWidth)
                }
            } else {
                VStack(spacing: WeekSpacing.md) {
                    monthCalendarCard
                    selectedDayDetailCard
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
        let dayId = calendar.startOfDay(for: selectedDate).dayId
        let summary = monthSummaries[dayId]
        let taskCount = summary?.taskCount ?? 0
        let ddlCount = summary?.ddlCount ?? 0
        let title = selectedDate.formatted(Date.FormatStyle().month().day().weekday(.abbreviated))
        let day = viewModel?.dayRecord(on: selectedDate)
        let tasks = day.flatMap { viewModel?.tasksForDisplay(in: $0) } ?? []

        return WeekCard(accentColor: day?.status.color ?? .weekyiiPrimary) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        Text(String(localized: "pending.month.selected", defaultValue: "已选日期"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text(title)
                            .font(.titleMedium)
                            .foregroundColor(.textPrimary)
                    }

                    Spacer()

                    if let day {
                        StatusBadge(status: day.status)
                    }
                }

                HStack(spacing: WeekSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "pending.month.task_count", defaultValue: "任务"))
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                        Text("\(taskCount)")
                            .font(.headline)
                            .foregroundColor(.accentGreen)
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localized: "pending.month.ddl_count", defaultValue: "DDL"))
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                        Text("\(ddlCount)")
                            .font(.headline)
                            .foregroundColor(.taskDDL)
                    }
                }

                if isSelectedDatePast {
                    Text("过去日期仅可查看，不可新增。")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

                if day == nil {
                    Text("该日期暂无任务记录。")
                        .font(.bodyMedium)
                        .foregroundColor(.textTertiary)
                } else if tasks.isEmpty {
                    Text("该日期暂无任务。")
                        .font(.bodyMedium)
                        .foregroundColor(.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            Button {
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
                            } label: {
                                OrderedTaskRow(
                                    task: task,
                                    index: index,
                                    accessibilityIdentifier: "pendingMonthTask_\(index)"
                                )
                            }
                            .buttonStyle(.plain)

                            if index < tasks.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.horizontal, WeekSpacing.md)
                    .background(Color.backgroundPrimary.opacity(0.55))
                    .clipShape(.rect(cornerRadius: WeekRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: WeekRadius.medium)
                            .stroke(Color.backgroundTertiary, lineWidth: 1)
                    )
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "calendar.badge.plus")
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
        // .id 确保月份切换时整个列表整体替换而非逐个 diff，消除跨月卡片的残留动画。
        VStack(spacing: WeekSpacing.md) {
            // 统计信息
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
            }
            
            // 周卡片列表
            ForEach(weeks) { week in
                PendingWeekCard(
                    week: week,
                    outlook: viewModel?.weekOutlook(for: week) ?? PendingViewModel.buildWeekOutlook(for: week),
                    onSelect: usesInlineSelection ? {
                        selectedWeekID = week.weekId
                    } : nil
                )
                .overlay {
                    if usesInlineSelection, selectedWeekID == week.weekId {
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
        VStack(spacing: WeekSpacing.md) {
            weekdayHeader
            LazyVGrid(columns: columns, spacing: WeekSpacing.xs) {
                ForEach(calendarDays) { day in
                    dayCell(day)
                }
            }
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

        Button {
            guard day.isCurrentMonth, !isPastDate else { return }
            selectedDate = day.date
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected && day.isCurrentMonth && !isPastDate {
                        Circle()
                            .fill(Color.weekyiiPrimary)
                            .frame(width: 34, height: 34)
                    } else if isToday && day.isCurrentMonth && !isPastDate {
                        Circle()
                            .stroke(Color.weekyiiPrimary, lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                    }

                    Text("\(dayNumber)")
                        .font(.body)
                        .fontWeight(isToday ? .semibold : .regular)
                        .foregroundStyle(
                            dayNumberColor(
                                day: day,
                                isSelected: isSelected,
                                isToday: isToday,
                                isPastDate: isPastDate
                            )
                        )
                }
                .frame(width: 36, height: 36)

                HStack(spacing: 3) {
                    if day.isCurrentMonth && !isPastDate && showRegular && regularCount > 0 {
                        Circle()
                            .fill(Color.accentGreen)
                            .frame(width: 6, height: 6)
                    }
                    if day.isCurrentMonth && !isPastDate && showDDL && ddlCount > 0 {
                        Image(systemName: TaskType.ddl.monthMarkerIconName)
                            .font(.system(size: 8))
                            .foregroundStyle(Color.taskDDL)
                    }
                    if day.isCurrentMonth && !isPastDate && showLeisure && leisureCount > 0 {
                        Image(systemName: TaskType.leisure.monthMarkerIconName)
                            .font(.system(size: 8))
                            .foregroundStyle(Color.taskLeisure)
                    }
                }
                .frame(height: 12)
            }
        }
        .buttonStyle(.plain)
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
    }

    private func dayNumberColor(day: PendingCalendarDay, isSelected: Bool, isToday: Bool, isPastDate: Bool) -> Color {
        if !day.isCurrentMonth {
            return .textTertiary.opacity(0.3)
        }
        if isPastDate {
            return .textTertiary.opacity(0.55)
        }
        if isSelected {
            return .white
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
