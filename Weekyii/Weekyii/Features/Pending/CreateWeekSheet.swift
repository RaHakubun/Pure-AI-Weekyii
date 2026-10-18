import SwiftUI

struct CreateWeekSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date
    @State private var selectedMonth: Date
    @State private var selectedWeekId: String?
    @State private var selectedMode: Mode
    @State private var createdDay: DayModel?
    @State private var createdWeek: WeekModel?
    @State private var errorMessage: String?
    private let calendar = Calendar(identifier: .iso8601)

    let viewModel: PendingViewModel

    enum Mode: String, CaseIterable {
        case date
        case weekId
    }

    init(
        viewModel: PendingViewModel,
        initialDate: Date? = nil,
        initialMonth: Date? = nil,
        initialMode: Mode? = nil
    ) {
        self.viewModel = viewModel

        let fallbackDate = Date()
        let resolvedDate = initialDate ?? fallbackDate
        let resolvedMonth = initialMonth ?? resolvedDate

        _selectedDate = State(initialValue: resolvedDate)
        _selectedMonth = State(initialValue: resolvedMonth)
        _selectedMode = State(initialValue: initialMode ?? .date)
        _selectedWeekId = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "pending.create.mode"))) {
                    Picker(String(localized: "pending.create.mode"), selection: $selectedMode) {
                        Text(String(localized: "pending.create.by_date")).tag(Mode.date)
                        Text(String(localized: "pending.create.by_week")).tag(Mode.weekId)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedMode == .date {
                    Section(header: Text(String(localized: "pending.create.date"))) {
                        CustomCalendarView(
                            selectedDate: $selectedDate,
                            selectedMonth: $selectedMonth,
                            viewModel: viewModel
                        )
                    }
                } else {
                    weekSelectionSection
                }
            }
            .navigationTitle(String(localized: "pending.create.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.create")) {
                        if selectedMode == .date {
                            guard let week = viewModel.createWeek(containing: selectedDate) else {
                                errorMessage = viewModel.errorMessage ?? String(localized: "error.operation_failed_retry")
                                return
                            }
                            guard let day = viewModel.day(in: week, for: selectedDate) else {
                                errorMessage = String(localized: "error.operation_failed_retry")
                                return
                            }
                            createdDay = day
                        } else {
                            guard let selectedWeekId else {
                                errorMessage = "请选择周"
                                return
                            }
                            guard let week = viewModel.createWeek(weekId: selectedWeekId) else {
                                errorMessage = viewModel.errorMessage ?? String(localized: "error.operation_failed_retry")
                                return
                            }
                            createdWeek = week
                        }
                    }
                    .disabled(selectedMode == .weekId && selectedWeekId == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                }
            }
            .navigationDestination(item: $createdDay) { day in
                DayDetailView(day: day)
            }
            .navigationDestination(item: $createdWeek) { week in
                PendingWeekDetailView(week: week)
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

    private var weekSelectionSection: some View {
        Section(header: Text(String(localized: "pending.create.week_id"))) {
            weekMonthHeader

            let options = viewModel.weekOptions(in: selectedMonth)
            ForEach(options) { option in
                Button {
                    guard option.isPast == false, option.isExisting == false else { return }
                    selectedWeekId = option.weekId
                } label: {
                    HStack(spacing: WeekSpacing.sm) {
                        VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                            Text(formattedRange(start: option.startDate, end: option.endDate))
                                .font(.bodyMedium)
                                .foregroundColor(option.isPast ? .textTertiary : .textPrimary)
                            Text(option.weekId)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        if option.isExisting {
                            statusBadge(text: "已创建", color: .accentGreen)
                        } else if option.isPast {
                            statusBadge(text: "不可创建", color: .textTertiary)
                        } else {
                            statusBadge(text: "可创建", color: .weekyiiPrimary)
                        }

                        if selectedWeekId == option.weekId {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.weekyiiPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(option.isPast || option.isExisting)
            }
        }
    }

    private var weekMonthHeader: some View {
        HStack(spacing: 16) {
            Button {
                selectedMonth = previousMonth(from: selectedMonth)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoPreviousMonth)
            .opacity(canGoPreviousMonth ? 1 : 0.3)

            Text(selectedMonth, format: Date.FormatStyle().year().month())
                .font(.headline)
                .frame(maxWidth: .infinity)

            Button {
                selectedMonth = nextMonth(from: selectedMonth)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }

    private var canGoPreviousMonth: Bool {
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let selectedMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        return selectedMonthStart > currentMonthStart
    }

    private func previousMonth(from date: Date) -> Date {
        calendar.date(byAdding: .month, value: -1, to: date) ?? date
    }

    private func nextMonth(from date: Date) -> Date {
        calendar.date(byAdding: .month, value: 1, to: date) ?? date
    }

    private func formattedRange(start: Date, end: Date) -> String {
        "\(start.formatted(Date.FormatStyle().month().day())) - \(end.formatted(Date.FormatStyle().month().day()))"
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, WeekSpacing.sm)
            .padding(.vertical, WeekSpacing.xxs)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Custom Calendar View

private struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var selectedMonth: Date
    let viewModel: PendingViewModel

    @EnvironmentObject private var settings: UserSettings
    @State private var cachedTaskDates: Set<String> = []
    @State private var cachedDDLDates: Set<String> = []

    private let calendar = Calendar(identifier: .iso8601)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    // 星期标题（周日开始）
    private let weekdaySymbols: [String] = {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale.current
        let symbols = cal.shortWeekdaySymbols  // [Sun, Mon, Tue, ...]
        return symbols
    }()

    /// 当月第一天
    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
    }

    /// 当月年月标签
    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: monthStart)
    }

    /// 生成日历格子中的所有日期（含前后填充）
    private var calendarDays: [CalendarDay] {
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        // 当月第一天是周几 (1=Sun, 2=Mon, ..., 7=Sat)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        // 需要在前面填充的天数（周日=1 起始，所以偏移 = firstWeekday - 1）
        let leadingOffset = firstWeekday - 1

        var days: [CalendarDay] = []

        // 前置填充（上个月的尾数日期）
        if leadingOffset > 0 {
            for i in (1...leadingOffset).reversed() {
                guard let date = calendar.date(byAdding: .day, value: -i, to: monthStart) else { continue }
                days.append(CalendarDay(date: date, isCurrentMonth: false))
            }
        }

        // 当月所有日期
        var cursor = monthStart
        while cursor < monthEnd {
            days.append(CalendarDay(date: cursor, isCurrentMonth: true))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? monthEnd
        }

        // 后置填充（补满最后一行到 7 的倍数）
        let remainder = days.count % 7
        if remainder > 0 {
            let trailingCount = 7 - remainder
            for i in 0..<trailingCount {
                guard let date = calendar.date(byAdding: .day, value: i, to: monthEnd) else { continue }
                days.append(CalendarDay(date: date, isCurrentMonth: false))
            }
        }

        return days
    }

    var body: some View {
        VStack(spacing: WeekSpacing.md) {
            // 月份导航
            calendarHeader

            // 星期标题行
            weekdayHeader

            // 日期网格
            LazyVGrid(columns: columns, spacing: WeekSpacing.xs) {
                ForEach(calendarDays) { day in
                    dayCellView(day)
                }
            }
        }
        .padding(.vertical, WeekSpacing.sm)
        .onAppear {
            refreshIndicators()
        }
        .onChange(of: selectedMonth) { _, _ in
            refreshIndicators()
        }
    }

    private func refreshIndicators() {
        cachedTaskDates = viewModel.datesWithTasks(in: selectedMonth)
        cachedDDLDates = viewModel.datesWithDDL(in: selectedMonth)
    }

    // MARK: - Month Header

    private var calendarHeader: some View {
        HStack {
            Button {
                selectedMonth = monthLabel == "" ? selectedMonth : (calendar.date(byAdding: .month, value: 0, to: selectedMonth) ?? selectedMonth)
            } label: {
                HStack(spacing: 4) {
                    Text(monthLabel)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: WeekSpacing.lg) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .foregroundColor(.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundColor(.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Weekday Header

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

    // MARK: - Day Cell

    @ViewBuilder
    private func dayCellView(_ day: CalendarDay) -> some View {
        let dayNumber = calendar.component(.day, from: day.date)
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day.date)
        let dayIdStr = day.date.dayId
        let hasTasks = cachedTaskDates.contains(dayIdStr)
        let hasDDL = cachedDDLDates.contains(dayIdStr)

        Button {
            if day.isCurrentMonth {
                selectedDate = day.date
            }
        } label: {
            VStack(spacing: 2) {
                // 日期数字
                ZStack {
                    if isSelected && day.isCurrentMonth {
                        Circle()
                            .fill(Color.weekyiiPrimary)
                            .frame(width: 34, height: 34)
                    } else if isToday && day.isCurrentMonth {
                        Circle()
                            .stroke(Color.weekyiiPrimary, lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                    }

                    Text("\(dayNumber)")
                        .font(.body)
                        .fontWeight(isToday ? .semibold : .regular)
                        .foregroundColor(dayTextColor(day: day, isSelected: isSelected, isToday: isToday))
                }
                .frame(width: 36, height: 36)

                // 指示器区域（遵循「我的 > 未来月视图」设置项）
                HStack(spacing: 3) {
                    if day.isCurrentMonth && settings.pendingMonthShowRegular && hasTasks {
                        Circle()
                            .fill(Color.accentGreen)
                            .frame(width: 6, height: 6)
                    }
                    if day.isCurrentMonth && settings.pendingMonthShowDDL && hasDDL {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.taskDDL)
                    }
                }
                .frame(height: 10)
            }
        }
        .buttonStyle(.plain)
        .disabled(!day.isCurrentMonth)
    }

    private func dayTextColor(day: CalendarDay, isSelected: Bool, isToday: Bool) -> Color {
        if !day.isCurrentMonth {
            return .textTertiary.opacity(0.3)
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

// MARK: - Calendar Day Model

private struct CalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool
    var id: String { date.dayId + (isCurrentMonth ? "_cur" : "_oth") }
}
