import SwiftData
import SwiftUI

// MARK: - Habit Detail View - 习惯详情页

struct HabitDetailView: View {
    let habit: HabitModel
    let viewModel: HabitViewModel

    @State private var showingEditor = false
    @State private var showingDeleteConfirm = false
    @State private var alertMessage: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                identitySection(stats: stats)
                actionSection(stats: stats)
                statisticsCard(stats: stats)
                HabitHistorySection(habit: habit, startsOnText: startsOnText)
            }
            .padding(.horizontal, WeekSpacing.base)
            .padding(.vertical, WeekSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("habitDetailView")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditor = true
                    } label: {
                        Label(String(localized: "action.edit"), systemImage: "pencil")
                    }
                    .accessibilityIdentifier("habitDetailEditButton")

                    Button {
                        toggleActive()
                    } label: {
                        Label(
                            habit.isActive
                                ? String(localized: "habit.action.archive", defaultValue: "停用")
                                : String(localized: "habit.action.restore", defaultValue: "恢复"),
                            systemImage: habit.isActive ? "archivebox" : "arrow.uturn.backward"
                        )
                    }
                    .accessibilityIdentifier("habitDetailArchiveButton")

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label(String(localized: "habit.detail.delete", defaultValue: "删除习惯"), systemImage: "trash")
                    }
                    .accessibilityIdentifier("habitDetailDeleteButton")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Color.textPrimary)
                }
                .accessibilityIdentifier("habitDetailMenu")
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            viewModel.refresh()
        }) {
            HabitEditorSheet(viewModel: viewModel, habit: habit)
        }
        .confirmationDialog(
            String(localized: "habit.detail.delete", defaultValue: "删除习惯"),
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "habit.detail.delete", defaultValue: "删除习惯"), role: .destructive) {
                deleteHabit()
            }
            Button(String(localized: "action.cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "habit.detail.delete_confirm", defaultValue: "删除后未开始日期中的该习惯任务会被移除，已开始的日期仅解除关联；全部打卡记录与统计将一并删除。"))
        }
        .onAppear {
            viewModel.refresh()
        }
        .refreshOnStateTransitions(using: appState) {
            viewModel.refresh()
            if habit.isDeleted { dismiss() }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let newValue { alertMessage = newValue }
        }
        .alert(String(localized: "alert.title"), isPresented: Binding(get: {
            alertMessage != nil
        }, set: { newValue in
            if !newValue { alertMessage = nil }
        })) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Identity

    private var stats: HabitStatistics {
        viewModel.statistics(for: habit)
    }

    private func identitySection(stats: HabitStatistics) -> some View {
        WeekCard(accentColor: habit.habitColor) {
            HStack(alignment: .top, spacing: WeekSpacing.md) {
                Image(systemName: habit.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(habit.habitColor)
                    .frame(width: 58, height: 58)
                    .background(habit.habitColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(habit.name)
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    Text("\(habit.category.displayName) · \(habit.scheduleSummary)")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)

                    if habit.startDate != nil {
                        Text(startsOnText)
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                HabitTodayStatusChip(status: stats.todayStatus)
            }
        }
    }


    // MARK: - Actions

    @ViewBuilder
    private func actionSection(stats: HabitStatistics) -> some View {
        if stats.todayStatus != .notScheduled && !stats.hasTodayTask {
            Button {
                addToday()
            } label: {
                HStack(spacing: WeekSpacing.xs) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(String(localized: "habit.detail.add_today", defaultValue: "加入今日"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WeekSpacing.md)
                .background(Color.accentGreen)
                .clipShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityIdentifier("habitDetailAddTodayButton")
        }
    }

    // MARK: - Statistics

    private func statisticsCard(stats: HabitStatistics) -> some View {
        WeekCard(accentColor: habit.habitColor) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                Text(String(localized: "habit.stats.title", defaultValue: "统计"))
                    .font(.titleSmall)
                    .foregroundColor(.textPrimary)

                HStack(spacing: 0) {
                    statColumn(
                        title: String(localized: "habit.stats.current_streak", defaultValue: "当前连续"),
                        value: "\(stats.currentStreak)"
                    )
                    Divider().frame(height: 36)
                    statColumn(
                        title: String(localized: "habit.stats.longest_streak", defaultValue: "最长连续"),
                        value: "\(stats.longestStreak)"
                    )
                    Divider().frame(height: 36)
                    statColumn(
                        title: String(localized: "habit.stats.completion_rate", defaultValue: "完成率"),
                        value: stats.completionRatePercent.map { "\($0)%" }
                            ?? String(localized: "habit.stats.placeholder", defaultValue: "—")
                    )
                    Divider().frame(height: 36)
                    statColumn(
                        title: String(localized: "habit.stats.total_completed", defaultValue: "累计完成"),
                        value: "\(stats.completedCount)"
                    )
                }
                .animation(.snappy(duration: 0.25), value: stats)
            }
        }
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(habit.habitColor)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }


    // MARK: - Helpers

    private var startsOnText: String {
        guard let startDate = habit.startDate else { return "" }
        return String(
            format: String(localized: "habit.timeline.starts_on %@", defaultValue: "将于 %@ 开始"),
            locale: Locale.current,
            startDate.formatted(date: .abbreviated, time: .omitted)
        )
    }

    // MARK: - Actions

    private func addToday() {
        do {
            let outcome = try viewModel.assignToday(habit)
            switch outcome {
            case .created:
                break
            case .alreadyExists:
                alertMessage = String(
                    localized: "habit.detail.add_today.result.exists",
                    defaultValue: "今日已存在该习惯任务"
                )
            case .dayLocked:
                alertMessage = String(localized: "habit.error.day_locked", defaultValue: "日期已锁定")
            case .pastKillTime:
                alertMessage = String(
                    localized: "habit.error.past_kill_time",
                    defaultValue: "已过今日截止时间，明天会自动加入"
                )
            case .notScheduledToday:
                alertMessage = String(
                    localized: "habit.error.not_scheduled_today",
                    defaultValue: "今天不在该习惯的重复计划内"
                )
            case .failed:
                break
            }
        } catch {
            if viewModel.errorMessage == nil {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func toggleActive() {
        do {
            try viewModel.setActive(habit, !habit.isActive)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deleteHabit() {
        do {
            try viewModel.deleteHabit(habit)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

// MARK: - Habit History

/// One compact card: a small week / month / year switch, a calendar of dots and
/// a single summary line. Built on `HabitStatisticsCalculator.timeline`;
/// nothing new is stored.
private struct HabitHistorySection: View {
    let habit: HabitModel
    let startsOnText: String

    enum Range: String, CaseIterable, Identifiable {
        case week, month, year
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: return String(localized: "habit.history.range.week", defaultValue: "周")
            case .month: return String(localized: "habit.history.range.month", defaultValue: "月")
            case .year: return String(localized: "habit.history.range.year", defaultValue: "年")
            }
        }
        var component: Calendar.Component {
            switch self {
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            }
        }
    }

    enum DayState {
        case completed, missed, pending, upcoming, rest
    }

    @State private var range: Range = .month
    @State private var offset = 0

    private var calendar: Calendar { WeekyiiTimeZone.calendar }
    private var today: Date { Date().startOfDay }

    var body: some View {
        let nodes = HabitStatisticsCalculator.timeline(for: habit)
        let byDay = Dictionary(nodes.map { ($0.dayId, $0) }, uniquingKeysWith: { first, _ in first })

        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HStack {
                Text(String(localized: "habit.history.title", defaultValue: "历史"))
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: WeekSpacing.md)
                if !nodes.isEmpty, habit.scheduleKind != .once {
                    Picker(String(localized: "habit.history.range", defaultValue: "范围"), selection: $range) {
                        ForEach(Range.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 132)
                    .onChange(of: range) { _, _ in offset = 0 }
                }
            }

            if nodes.isEmpty {
                Text(startsOnText)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WeekSpacing.md)
            } else if habit.scheduleKind == .once {
                onceRow(nodes[0])
            } else {
                periodHeader
                switch range {
                case .week: weekDots(byDay: byDay)
                case .month: monthDots(days: monthDays(of: periodStart), byDay: byDay, dot: 22, spacing: 10)
                case .year: yearGrid(byDay: byDay)
                }
                Divider()
                summaryLine(byDay: byDay)
            }
        }
        .padding(WeekSpacing.lg)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous)
                .stroke(Color.backgroundTertiary, lineWidth: 1)
        )
    }

    // MARK: Pieces

    private var periodHeader: some View {
        HStack {
            arrow("chevron.left", enabled: offset > minOffset) { offset -= 1 }
            Spacer()
            Text(periodTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            arrow("chevron.right", enabled: offset < 0) { offset += 1 }
        }
    }

    private func arrow(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.textSecondary : Color.textTertiary.opacity(0.4))
        .disabled(!enabled)
    }

    private func weekDots(byDay: [String: HabitTimelineNode]) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                let date = periodStart.addingDays(index).startOfDay
                VStack(spacing: 8) {
                    Text(WeekyiiWeekday.localizedSymbol(for: date.isoWeekday))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    dot(date: date, byDay: byDay, size: 26)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthDots(days: [Date], byDay: [String: HabitTimelineNode], dot size: CGFloat, spacing: CGFloat) -> some View {
        let leading = (days.first?.isoWeekday ?? 1) - 1
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(1...7, id: \.self) { weekday in
                Text(WeekyiiWeekday.localizedSymbol(for: weekday))
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            ForEach(0..<leading, id: \.self) { index in
                Color.clear.frame(height: size).id("lead-\(index)")
            }
            ForEach(days, id: \.self) { date in
                dot(date: date, byDay: byDay, size: size)
            }
        }
    }

    /// Twelve small months, 4 × 3. Tapping a month opens it in the month view.
    private func yearGrid(byDay: [String: HabitTimelineNode]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: WeekSpacing.sm), count: 4)
        return LazyVGrid(columns: columns, spacing: WeekSpacing.md) {
            ForEach(0..<12, id: \.self) { index in
                let monthStart = calendar.date(byAdding: .month, value: index, to: periodStart) ?? periodStart
                Button {
                    jumpToMonth(monthStart)
                } label: {
                    miniMonth(monthStart, byDay: byDay)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func miniMonth(_ monthStart: Date, byDay: [String: HabitTimelineNode]) -> some View {
        let days = monthDays(of: monthStart)
        let leading = (days.first?.isoWeekday ?? 1) - 1
        // Fixed 7pt dots with 2pt gaps: a compact square calendar per month
        // that leaves clear air between neighbouring months.
        let cell: CGFloat = 7
        let columns = Array(repeating: GridItem(.fixed(cell), spacing: 2), count: 7)
        return VStack(alignment: .leading, spacing: 5) {
            Text(monthStart.formatted(.dateTime.month(.abbreviated)))
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textSecondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
                ForEach(0..<leading, id: \.self) { index in
                    Color.clear.frame(width: cell, height: cell).id("mini-lead-\(index)")
                }
                ForEach(days, id: \.self) { date in
                    Mark(state: state(of: date, byDay: byDay), tint: habit.habitColor, isMini: true)
                        .frame(width: cell, height: cell)
                }
                // Six week-rows for every month so the blocks line up.
                ForEach(0..<max(42 - leading - days.count, 0), id: \.self) { index in
                    Color.clear.frame(width: cell, height: cell).id("mini-trail-\(index)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Only today's dot carries its date, so the calendar stays clean.
    private func dot(date: Date, byDay: [String: HabitTimelineNode], size: CGFloat) -> some View {
        let dayState = state(of: date, byDay: byDay)
        let isToday = date.dayId == today.dayId
        let restSize: CGFloat = 6
        return ZStack {
            Mark(state: dayState, tint: habit.habitColor)
                .frame(width: dayState == .rest ? restSize : size, height: dayState == .rest ? restSize : size)
            if isToday {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(dayState == .completed ? .white : Color.weekyiiPrimary)
            }
        }
        .frame(width: size, height: size)
    }

    private func summaryLine(byDay: [String: HabitTimelineNode]) -> some View {
        let nodes = periodDays().compactMap { byDay[$0.dayId] }
        let done = nodes.filter { $0.state == .completed }.count
        let missed = nodes.filter { $0.state == .missed }.count
        return HStack {
            Text(String(
                format: String(localized: "habit.history.summary.done", defaultValue: "完成 %1$lld / %2$lld"),
                locale: Locale.current,
                Int64(done),
                Int64(nodes.count)
            ))
            .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(String(
                format: String(localized: "habit.history.summary.missed", defaultValue: "中断 %lld"),
                locale: Locale.current,
                Int64(missed)
            ))
            .foregroundStyle(Color.taskDDL)
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func onceRow(_ node: HabitTimelineNode) -> some View {
        HStack {
            Text(node.date.formatted(.dateTime.year().month().day().weekday()))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Mark(state: dayState(node.state), tint: habit.habitColor)
                .frame(width: 22, height: 22)
        }
    }

    // MARK: Period math

    private var periodStart: Date {
        let anchor: Date
        switch range {
        case .week:
            anchor = today.startOfWeek
        case .month:
            anchor = calendar.dateInterval(of: .month, for: today)?.start ?? today
        case .year:
            anchor = calendar.dateInterval(of: .year, for: today)?.start ?? today
        }
        return calendar.date(byAdding: range.component, value: offset, to: anchor)?.startOfDay ?? anchor
    }

    /// The earliest period that still contains the habit's start day.
    private var minOffset: Int {
        guard let start = habit.startDate?.startOfDay else { return 0 }
        let value: Int?
        switch range {
        case .week:
            value = calendar.dateComponents([.weekOfYear], from: today.startOfWeek, to: start.startOfWeek).weekOfYear
        case .month:
            let current = calendar.dateInterval(of: .month, for: today)?.start ?? today
            let first = calendar.dateInterval(of: .month, for: start)?.start ?? start
            value = calendar.dateComponents([.month], from: current, to: first).month
        case .year:
            value = calendar.component(.year, from: start) - calendar.component(.year, from: today)
        }
        return min(value ?? 0, 0)
    }

    private func periodDays() -> [Date] {
        guard let interval = calendar.dateInterval(of: range.component, for: periodStart) else { return [] }
        return days(in: interval)
    }

    private func monthDays(of date: Date) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        return days(in: interval)
    }

    private func days(in interval: DateInterval) -> [Date] {
        var days: [Date] = []
        var cursor = interval.start.startOfDay
        while cursor < interval.end {
            days.append(cursor)
            cursor = cursor.addingDays(1).startOfDay
        }
        return days
    }

    private func jumpToMonth(_ monthStart: Date) {
        let current = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let months = calendar.dateComponents([.month], from: current, to: monthStart).month ?? 0
        range = .month
        // Changing `range` resets the offset; apply the target afterwards.
        DispatchQueue.main.async {
            offset = min(months, 0)
        }
    }

    private var periodTitle: String {
        switch range {
        case .week:
            return periodStart.formatted(.dateTime.month().day()) + " – " + periodStart.addingDays(6).formatted(.dateTime.month().day())
        case .month:
            return periodStart.formatted(.dateTime.year().month())
        case .year:
            return periodStart.formatted(.dateTime.year())
        }
    }

    // MARK: State

    private func state(of date: Date, byDay: [String: HabitTimelineNode]) -> DayState {
        if let node = byDay[date.dayId] {
            return dayState(node.state)
        }
        if date > today, let start = habit.startDate?.startOfDay, date >= start, habit.isScheduled(on: date) {
            return .upcoming
        }
        return .rest
    }

    private func dayState(_ state: HabitTimelineNodeState) -> DayState {
        switch state {
        case .completed: return .completed
        case .missed: return .missed
        case .pending: return .pending
        }
    }

    /// A single day as a dot.
    struct Mark: View {
        let state: DayState
        let tint: Color
        /// Tiny year-view cells: hairline strokes and dashes don't survive at
        /// that size, so outlines become soft fills.
        var isMini = false

        var body: some View {
            switch state {
            case .completed:
                Circle().fill(tint)
            case .missed:
                Circle().fill(Color.taskDDL.opacity(0.4))
            case .pending:
                if isMini {
                    Circle().fill(Color.weekyiiPrimary)
                } else {
                    Circle().strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [3, 2.5]))
                }
            case .upcoming:
                Circle().fill(tint.opacity(0.14))
            case .rest:
                Circle().fill(Color.backgroundTertiary.opacity(isMini ? 0.55 : 1))
                    .scaleEffect(isMini ? 0.6 : 1)
            }
        }
    }
}
