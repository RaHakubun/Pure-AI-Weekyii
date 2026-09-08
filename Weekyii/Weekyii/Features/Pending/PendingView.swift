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
    @State private var monthSummaries: [String: PendingViewModel.MonthDaySummary] = [:]
    private let calendar = Calendar(identifier: .iso8601)

    var body: some View {
        NavigationStack {
            ScrollView {
                if let viewModel {
                    VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                        if displayMode == .weekList {
                            MonthPickerView(month: $selectedMonth, restriction: .futureOnly)

                            let weeks = viewModel.weeks(in: selectedMonth)
                            if weeks.isEmpty {
                                emptyStateView
                            } else {
                                weeksList(weeks: weeks)
                            }
                        } else {
                            monthOverview
                        }
                    }
                    .weekPadding(WeekSpacing.base)
                } else {
                    ProgressView()
                }
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
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
            viewModel?.refresh()
            viewModel?.seedPendingWeekForUITestsIfNeeded()
            refreshMonthSummaries()
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

    private var switchModeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                displayMode = displayMode == .weekList ? .month : .weekList
            }
        } label: {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: displayMode == .weekList ? "calendar" : "list.bullet.rectangle")
                Text(displayMode == .weekList ? "月历" : "周列表")
            }
            .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel(
            displayMode == .weekList
                ? String(localized: "pending.switch.month", defaultValue: "切换到月视图")
                : String(localized: "pending.switch.week", defaultValue: "切换到周列表")
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
                : "为所选日期添加任务"
        )
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
        VStack(spacing: WeekSpacing.md) {
            MonthPickerView(month: $selectedMonth, restriction: .futureOnly)

            monthCalendarSurface

            selectedDaySurface
        }
    }

    private var monthCalendarSurface: some View {
        pendingMonthSurface {
            PendingMonthCalendarView(
                selectedDate: $selectedDate,
                selectedMonth: $selectedMonth,
                summaries: monthSummaries,
                showRegular: settings.pendingMonthShowRegular,
                showDDL: settings.pendingMonthShowDDL,
                showLeisure: settings.pendingMonthShowLeisure
            )
            // 月份变化时强制重建日历格视图树，消除 LazyVGrid cell 跨月复用时的 identity 错乱。
            .id(calendar.dateComponents([.year, .month], from: selectedMonth))
        }
    }

    private var selectedDaySurface: some View {
        pendingMonthSurface {
            selectedDayDetailCard
        }
    }

    /// 与「过去」月视图保持相同的独立卡片排版，仅承载「未来」自己的内容和交互。
    private func pendingMonthSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(WeekSpacing.base)
            .background(Color.backgroundSecondary)
            .clipShape(.rect(cornerRadius: WeekRadius.xlarge))
            .overlay {
                RoundedRectangle(cornerRadius: WeekRadius.xlarge, style: .continuous)
                    .stroke(Color.backgroundTertiary.opacity(0.55), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: WeekShadow.light.color,
                radius: 14,
                x: 0,
                y: 5
            )
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
    
    private func weeksList(weeks: [WeekModel]) -> some View {
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
                    outlook: viewModel?.weekOutlook(for: week) ?? PendingViewModel.buildWeekOutlook(for: week)
                )
            }
        }
        // 月份切换时整体重建，避免跨月卡片复用时的 identity 错乱与残留动画。
        .id(calendar.dateComponents([.year, .month], from: selectedMonth))
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
                Text("\(selectedDate.formatted(Date.FormatStyle().weekday(.abbreviated)))安排")
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
                Text("\(tasks.count) 项")
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
                        title: "步骤",
                        value: "\(stepCount)",
                        icon: "checklist",
                        color: .weekyiiPrimary
                    )
                }

                let projectCount = Set(tasks.compactMap { $0.project?.id }).count
                if projectCount > 0 {
                    summaryChip(
                        title: "项目",
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
            Text("过去日期仅可查看，不可新增。")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }

        if day == nil {
            emptyState("这一天还没有安排")
        } else if tasks.isEmpty {
            emptyState("这一天还没有安排")
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
            Image(systemName: "calendar")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.textTertiary)

            VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                Text(message)
                    .font(.bodyMedium.weight(.medium))
                    .foregroundStyle(Color.textSecondary)

                if !isSelectedDatePast {
                    Text("使用上方“添加”为这一天创建任务")
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
                        Label("\(task.steps.count) 个步骤", systemImage: "checklist")
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
        VStack(spacing: WeekSpacing.xs) {
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 0) {
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

                VStack(spacing: 3) {
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

                    HStack(spacing: 3) {
                        if day.isCurrentMonth && !isPastDate && showsRegularMarker {
                            Circle()
                                .fill(isSelected ? Color.white : Color.accentGreen)
                                .frame(width: 5, height: 5)
                        }
                        if day.isCurrentMonth && !isPastDate && showsDDLMarker {
                            Image(systemName: TaskType.ddl.monthMarkerIconName)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(isSelected ? Color.white : Color.taskDDL)
                        }
                        if day.isCurrentMonth && !isPastDate && showsLeisureMarker {
                            Image(systemName: TaskType.leisure.monthMarkerIconName)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(isSelected ? Color.white : Color.taskLeisure)
                        }
                    }
                    .frame(height: 7)
                    .opacity(hasVisibleMarker ? 1 : 0)
                }
            }
            .frame(width: 38, height: 40)
            .frame(maxWidth: .infinity)
            .shadow(
                color: isSelected ? Color.weekyiiPrimary.opacity(0.18) : Color.clear,
                radius: 6,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pendingMonthDay_\(dayId)")
        .disabled(!day.isCurrentMonth || isPastDate)
        .accessibilityLabel(
            calendarDayAccessibilityLabel(
                dayNumber: dayNumber,
                regularCount: regularCount,
                ddlCount: ddlCount,
                leisureCount: leisureCount
            )
        )
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
        if regularCount > 0 { parts.append("常规 \(regularCount)") }
        if ddlCount > 0 { parts.append("DDL \(ddlCount)") }
        if leisureCount > 0 { parts.append("休闲 \(leisureCount)") }
        return parts.joined(separator: "，")
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
