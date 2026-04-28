import SwiftUI
import SwiftData

private enum PastDisplayMode {
    case weekList
    case month
}

private struct PastMonthDaySummary: Equatable {
    let dayId: String
    let completedCount: Int
    let expiredCount: Int
    let hasRecord: Bool
}

struct PastView: View {
    @Query(sort: \WeekModel.startDate, order: .reverse) private var allWeeks: [WeekModel]
    @Query(sort: \DayModel.date, order: .reverse) private var allDays: [DayModel]
    @State private var selectedMonth = Date()
    @State private var selectedDate = Date()
    @State private var displayMode: PastDisplayMode = .weekList
    @State private var showsMonthAnalytics = true
    private let analyticsService = PastAnalyticsService()
    private let calendar = Calendar(identifier: .iso8601)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                    MonthPickerView(month: $selectedMonth, restriction: .pastOnly)

                    if displayMode == .weekList {
                        let weeks = weeksInSelectedMonth
                        if weeks.isEmpty {
                            emptyStateView
                        } else {
                            weeksList(weeks: weeks)
                        }
                    } else {
                        monthOverview
                    }

                    analyticsSection
                }
                .weekPadding(WeekSpacing.base)
            }
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WeekLogo(size: .small, animated: false)
                }
                ToolbarItem(placement: .topBarLeading) {
                    switchModeButton
                }
            }
        }
        .onAppear {
            normalizeSelectedDateForMonth()
        }
        .onChange(of: selectedMonth) { _, _ in
            normalizeSelectedDateForMonth()
        }
    }

    private var monthRange: ClosedRange<Date> {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? monthStart
        return calendar.startOfDay(for: monthStart)...calendar.startOfDay(for: monthEnd)
    }

    private var monthDays: [DayModel] {
        let range = monthRange
        return allDays.filter { day in
            guard let weekStatus = day.week?.status, weekStatus == .past else { return false }
            let date = calendar.startOfDay(for: day.date)
            return date >= range.lowerBound && date <= range.upperBound
        }
    }

    private var monthSummaries: [String: PastMonthDaySummary] {
        var result: [String: PastMonthDaySummary] = [:]
        for day in monthDays {
            let completedCount = day.completedTasks.count
            let expiredCount = day.expiredCount
            result[day.dayId] = PastMonthDaySummary(
                dayId: day.dayId,
                completedCount: completedCount,
                expiredCount: expiredCount,
                hasRecord: completedCount > 0 || expiredCount > 0 || day.status != .empty
            )
        }
        return result
    }

    private var selectedDay: DayModel? {
        let targetId = calendar.startOfDay(for: selectedDate).dayId
        return monthDays.first(where: { $0.dayId == targetId })
    }

    private var selectedDaySummary: PastMonthDaySummary? {
        let targetId = calendar.startOfDay(for: selectedDate).dayId
        return monthSummaries[targetId]
    }

    private var monthStats: PastAnalyticsService.OverviewStats? {
        let stats = analyticsService.getOverviewStats(days: monthDays)
        return stats.totalStartedDays > 0 ? stats : nil
    }

    private var monthTrendData: [DayTaskDataPoint] {
        let totalTasks = monthDays.reduce(0) { $0 + $1.completedTasks.count + $1.expiredCount }
        guard totalTasks > 0 else { return [] }
        return analyticsService.getMonthTrendData(days: monthDays, month: selectedMonth)
    }

    private var monthHeatmapData: [DayHeatmapDataPoint] {
        let totalTasks = monthDays.reduce(0) { $0 + $1.completedTasks.count + $1.expiredCount }
        guard totalTasks > 0 else { return [] }
        return analyticsService.getHeatmapData(days: monthDays, startDate: monthRange.lowerBound, endDate: monthRange.upperBound)
    }

    private var weeksInSelectedMonth: [WeekModel] {
        let range = monthRange
        return allWeeks.filter { week in
            week.status == .past && week.startDate <= range.upperBound && week.endDate >= range.lowerBound
        }.sorted { $0.startDate < $1.startDate }
    }

    private var switchModeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                displayMode = displayMode == .weekList ? .month : .weekList
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.backgroundSecondary)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.weekyiiPrimary.opacity(0.22), lineWidth: 1)
                Image(systemName: displayMode == .weekList ? "calendar" : "rectangle.grid.1x2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.weekyiiPrimary)
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            displayMode == .weekList
                ? String(localized: "past.switch.month", defaultValue: "切换到月视图")
                : String(localized: "past.switch.week", defaultValue: "切换到周列表")
        )
    }

    private var monthOverview: some View {
        VStack(spacing: WeekSpacing.md) {
            WeekCard {
                PastMonthCalendarView(
                    selectedDate: $selectedDate,
                    selectedMonth: $selectedMonth,
                    summaries: monthSummaries
                )
            }

            selectedDayDetailCard
        }
    }

    private var selectedDayDetailCard: some View {
        let title = selectedDate.formatted(Date.FormatStyle().month().day().weekday(.abbreviated))
        let completedCount = selectedDaySummary?.completedCount ?? 0
        let expiredCount = selectedDaySummary?.expiredCount ?? 0
        let tasks = selectedDay?.completedTasks ?? []

        return WeekCard(accentColor: selectedDay?.status.color ?? .weekyiiPrimary) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        Text(String(localized: "past.month.selected", defaultValue: "已选日期"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text(title)
                            .font(.titleMedium)
                            .foregroundColor(.textPrimary)
                    }

                    Spacer()

                    if let selectedDay {
                        StatusBadge(status: selectedDay.status)
                    }
                }

                HStack(spacing: WeekSpacing.md) {
                    statBlock(
                        title: String(localized: "past.completed"),
                        value: completedCount,
                        color: .accentGreen
                    )

                    statBlock(
                        title: String(localized: "past.expired"),
                        value: expiredCount,
                        color: .taskDDL
                    )
                }

                if selectedDay == nil || (tasks.isEmpty && expiredCount == 0) {
                    Text(String(localized: "past.week.no_records"))
                        .font(.bodyMedium)
                        .foregroundColor(.textTertiary)
                } else {
                    if !tasks.isEmpty {
                        VStack(spacing: WeekSpacing.sm) {
                            ForEach(tasks) { task in
                                TaskRowView(task: task)
                            }
                        }
                    }

                    if expiredCount > 0 {
                        Text(String(format: String(localized: "past.week.expired_count"), expiredCount))
                            .font(.caption)
                            .foregroundColor(.taskDDL)
                    }
                }
            }
        }
    }

    private func statBlock(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
            Text("\(value)")
                .font(.titleMedium)
                .foregroundColor(color)
        }
    }

    private var analyticsSection: some View {
        VStack(spacing: WeekSpacing.md) {
            WeekCard {
                HStack {
                    VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                        Text(String(localized: "past.analytics.title", defaultValue: "过去分析"))
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)
                        Text(String(localized: "past.analytics.subtitle", defaultValue: "趋势、热力与效率统计"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsMonthAnalytics.toggle()
                        }
                    } label: {
                        Image(systemName: showsMonthAnalytics ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.weekyiiGradient)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        showsMonthAnalytics
                            ? String(localized: "past.analytics.collapse", defaultValue: "收起分析")
                            : String(localized: "past.analytics.expand", defaultValue: "展开分析")
                    )
                }
            }

            if showsMonthAnalytics {
                if let stats = monthStats {
                    PastStatsOverview(stats: stats)
                }
                MonthTrendChart(dataPoints: monthTrendData, month: selectedMonth)
                ContributionHeatmap(data: monthHeatmapData, dateRange: monthRange)
            }
        }
    }

    private func normalizeSelectedDateForMonth() {
        let selectedMonthKey = calendar.dateComponents([.year, .month], from: selectedMonth)
        let selectedDateKey = calendar.dateComponents([.year, .month], from: selectedDate)
        let today = calendar.startOfDay(for: Date())
        let monthStart = calendar.date(from: selectedMonthKey) ?? selectedMonth
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? monthStart
        let targetDate = min(today, monthEnd)

        if selectedMonthKey != selectedDateKey || selectedDate > targetDate {
            selectedDate = targetDate
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.weekyiiGradient)
                
                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "past.empty.title"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                    
                    Text(String(localized: "past.empty.subtitle"))
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
        VStack(spacing: WeekSpacing.md) {
            WeekCard(accentColor: .accentGreen) {
                HStack {
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        Text(String(localized: "past.total_weeks"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text("\(weeks.count)")
                            .font(.titleLarge)
                            .foregroundColor(.accentGreen)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.accentGreen.opacity(0.3))
                }
            }

            ForEach(weeks) { week in
                PastWeekCard(week: week)
            }
        }
    }
}

private struct PastWeekCard: View {
    let week: WeekModel

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    var body: some View {
        NavigationLink {
            PastWeekDetailView(week: week)
        } label: {
            WeekCard {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    HStack {
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundColor(.weekyiiPrimary)
                        Text(week.relativeWeekLabel(referenceDate: Date()))
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }

                    HStack(spacing: WeekSpacing.xs) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text(formatDateRange())
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }

                    Divider()

                    HStack(spacing: WeekSpacing.lg) {
                        statBlock(
                            title: String(localized: "past.completed"),
                            value: week.completedTasksCount,
                            color: .accentGreen
                        )

                        statBlock(
                            title: String(localized: "past.expired"),
                            value: week.expiredTasksCount,
                            color: .taskDDL
                        )

                        Spacer()

                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.accentGreen.opacity(0.3))
                    }
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func statBlock(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
            Text("\(value)")
                .font(.titleMedium)
                .foregroundColor(color)
        }
    }

    private func formatDateRange() -> String {
        let sortedDays = week.days.sorted { $0.date < $1.date }
        guard let first = sortedDays.first, let last = sortedDays.last else { return "" }
        let start = Self.monthDayFormatter.string(from: first.date)
        let end = Self.monthDayFormatter.string(from: last.date)
        return "\(start) - \(end)"
    }
}

private struct PastMonthCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var selectedMonth: Date
    let summaries: [String: PastMonthDaySummary]

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

    private var calendarDays: [PastCalendarDay] {
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingOffset = firstWeekday - 1

        var days: [PastCalendarDay] = []
        if leadingOffset > 0 {
            for i in (1...leadingOffset).reversed() {
                guard let date = calendar.date(byAdding: .day, value: -i, to: monthStart) else { continue }
                days.append(PastCalendarDay(date: date, isCurrentMonth: false))
            }
        }

        var cursor = monthStart
        while cursor < monthEnd {
            days.append(PastCalendarDay(date: cursor, isCurrentMonth: true))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? monthEnd
        }

        let remainder = days.count % 7
        if remainder > 0 {
            let trailing = 7 - remainder
            for i in 0..<trailing {
                guard let date = calendar.date(byAdding: .day, value: i, to: monthEnd) else { continue }
                days.append(PastCalendarDay(date: date, isCurrentMonth: false))
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

            HStack(spacing: WeekSpacing.lg) {
                legendItem(
                    color: .accentGreen,
                    icon: nil,
                    text: String(localized: "past.month.legend.completed", defaultValue: "有完成")
                )
                legendItem(
                    color: .taskDDL,
                    icon: "flame.fill",
                    text: String(localized: "past.month.legend.expired", defaultValue: "有过期")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    private func dayCell(_ day: PastCalendarDay) -> some View {
        let dayId = day.date.dayId
        let summary = summaries[dayId]
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day.date)
        let today = calendar.startOfDay(for: Date())
        let isFutureDate = calendar.startOfDay(for: day.date) > today
        let dayNumber = calendar.component(.day, from: day.date)
        let completedCount = summary?.completedCount ?? 0
        let expiredCount = summary?.expiredCount ?? 0
        let hasRecord = summary?.hasRecord ?? false

        Button {
            guard day.isCurrentMonth, !isFutureDate else { return }
            selectedDate = day.date
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if isSelected && day.isCurrentMonth && !isFutureDate {
                            Circle()
                                .fill(Color.weekyiiPrimary)
                                .frame(width: 34, height: 34)
                        } else if isToday && day.isCurrentMonth && !isFutureDate {
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
                                    isFutureDate: isFutureDate
                                )
                            )
                    }
                    .frame(width: 36, height: 36)

                    if day.isCurrentMonth && completedCount > 0 && !isFutureDate {
                        Text(completedCount > 99 ? "99+" : "\(completedCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentGreen, in: Capsule())
                            .offset(x: 5, y: -4)
                    }
                }

                HStack(spacing: 3) {
                    if day.isCurrentMonth && hasRecord && !isFutureDate {
                        Circle()
                            .fill(Color.accentGreen)
                            .frame(width: 6, height: 6)
                    }
                    if day.isCurrentMonth && expiredCount > 0 && !isFutureDate {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.taskDDL)
                    }
                }
                .frame(height: 10)
            }
        }
        .buttonStyle(.plain)
        .disabled(!day.isCurrentMonth || isFutureDate)
    }

    private func dayNumberColor(day: PastCalendarDay, isSelected: Bool, isToday: Bool, isFutureDate: Bool) -> Color {
        if !day.isCurrentMonth {
            return .textTertiary.opacity(0.3)
        }
        if isFutureDate {
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
                .foregroundColor(.textSecondary)
        }
    }
}

private struct PastCalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool

    var id: String { date.dayId + (isCurrentMonth ? "_current" : "_adjacent") }
}

private struct PastWeekDetailView: View {
    let week: WeekModel
    @State private var selectedDayId: String = ""
    @State private var showsWeekAnalytics = true

    private let calendar = Calendar(identifier: .iso8601)
    private let analyticsService = PastAnalyticsService()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()
    private static let monthDayWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MdE")
        return formatter
    }()

    private var selectedDay: DayModel? {
        sortedDays.first(where: { $0.dayId == selectedDayId }) ?? sortedDays.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                overviewAndDayPickerCard

                if let selectedDay {
                    selectedDayDetailCard(selectedDay)
                }

                weekAnalyticsSection
            }
            .weekPadding(WeekSpacing.base)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle(week.relativeWeekLabel(referenceDate: Date()))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            initializeDaySelectionIfNeeded()
        }
    }

    private var sortedDays: [DayModel] {
        week.days.sorted { $0.date < $1.date }
    }
    
    private var weekRange: ClosedRange<Date> {
        let start = calendar.startOfDay(for: week.startDate)
        let end = calendar.startOfDay(for: week.endDate)
        return start...end
    }
    
    private var weekStats: PastAnalyticsService.OverviewStats? {
        let stats = analyticsService.getOverviewStats(days: week.days)
        return stats.totalStartedDays > 0 ? stats : nil
    }
    
    private var weekTrendData: [DayTaskDataPoint] {
        let totalTasks = week.days.reduce(0) { $0 + $1.completedTasks.count + $1.expiredCount }
        guard totalTasks > 0 else { return [] }
        let weekStart = calendar.startOfDay(for: week.startDate)
        return analyticsService.getWeekTrendData(days: week.days, weekStart: weekStart)
    }
    
    private var weekHeatmapData: [DayHeatmapDataPoint] {
        let totalTasks = week.days.reduce(0) { $0 + $1.completedTasks.count + $1.expiredCount }
        guard totalTasks > 0 else { return [] }
        return analyticsService.getHeatmapData(days: week.days, startDate: weekRange.lowerBound, endDate: weekRange.upperBound)
    }

    private var completedTasksCount: Int {
        week.days.reduce(0) { $0 + $1.completedTasks.count }
    }

    private var expiredTasksCount: Int {
        week.days.reduce(0) { $0 + $1.expiredCount }
    }

    private var startedDaysCount: Int {
        week.days.filter { [.execute, .completed, .expired].contains($0.status) }.count
    }

    private var overviewAndDayPickerCard: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                Text(String(localized: "past.week.summary"))
                    .font(.titleSmall)
                    .foregroundColor(.textPrimary)

                Text(formatDateRange())
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)

                HStack(spacing: WeekSpacing.lg) {
                    statBlock(title: String(localized: "past.completed"), value: completedTasksCount, color: .accentGreen)
                    statBlock(title: String(localized: "past.expired"), value: expiredTasksCount, color: .taskDDL)
                    statBlock(title: String(localized: "past.week.started_days"), value: startedDaysCount, color: .weekyiiPrimary)
                }

                Divider()
                    .padding(.vertical, WeekSpacing.xxs)

                HStack(alignment: .firstTextBaseline, spacing: WeekSpacing.sm) {
                    Text(String(localized: "pending.timeline.title"))
                        .font(.bodyMedium.weight(.semibold))
                        .foregroundColor(.textPrimary)

                    Spacer()

                    if let selectedDay {
                        Text(Self.monthDayWeekdayFormatter.string(from: selectedDay.date))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }

                dayPickerStrip
            }
        }
    }

    private func statBlock(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
            Text("\(value)")
                .font(.titleMedium)
                .foregroundColor(color)
        }
    }

    private var dayPickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WeekSpacing.sm) {
                ForEach(sortedDays) { day in
                    dayPickerChip(day)
                }
            }
            .padding(.horizontal, WeekSpacing.xs)
            .padding(.vertical, WeekSpacing.xs)
        }
        .background(Color.backgroundTertiary.opacity(0.5))
        .clipShape(.rect(cornerRadius: WeekRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium)
                .stroke(Color.backgroundTertiary, lineWidth: 1)
        )
    }

    private func dayPickerChip(_ day: DayModel) -> some View {
        let isSelected = day.dayId == selectedDay?.dayId
        let hasCompleted = !day.completedTasks.isEmpty

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedDayId = day.dayId
            }
        } label: {
            VStack(spacing: WeekSpacing.xxs) {
                Text(weekdaySymbol(for: day.date))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? .white : .textPrimary)

                Text(Self.monthDayFormatter.string(from: day.date))
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .textSecondary)

                HStack(spacing: 3) {
                    Circle()
                        .fill(hasCompleted ? (isSelected ? .white : .accentGreen) : .clear)
                        .frame(width: 6, height: 6)

                    if day.expiredCount > 0 {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(isSelected ? .white : .taskDDL)
                    }
                }
                .frame(height: 10)
            }
            .frame(width: 60, height: 70)
            .background(isSelected ? Color.weekyiiPrimary : Color.backgroundSecondary)
            .clipShape(.rect(cornerRadius: WeekRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.medium)
                    .stroke(isSelected ? Color.weekyiiPrimary : Color.backgroundTertiary, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func selectedDayDetailCard(_ day: DayModel) -> some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    Text(formatDay(day.date))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    StatusBadge(status: day.status)
                }

                HStack(spacing: WeekSpacing.lg) {
                    statBlock(title: String(localized: "past.completed"), value: day.completedTasks.count, color: .accentGreen)
                    statBlock(title: String(localized: "past.expired"), value: day.expiredCount, color: .taskDDL)
                }

                if day.completedTasks.isEmpty && day.expiredCount == 0 {
                    Text(String(localized: "past.week.no_records"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                } else {
                    if !day.completedTasks.isEmpty {
                        Text(String(localized: "past.week.completed_list"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        VStack(spacing: WeekSpacing.sm) {
                            ForEach(day.completedTasks) { task in
                                TaskRowView(task: task)
                            }
                        }
                    }

                    if day.expiredCount > 0 {
                        Text(String(format: String(localized: "past.week.expired_count"), day.expiredCount))
                            .font(.caption)
                            .foregroundColor(.taskDDL)
                    }
                }
            }
        }
    }

    private var weekAnalyticsSection: some View {
        VStack(spacing: WeekSpacing.md) {
            WeekCard {
                HStack {
                    VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                        Text(String(localized: "past.analytics.title", defaultValue: "过去分析"))
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)
                        Text(String(localized: "past.analytics.subtitle", defaultValue: "趋势、热力与效率统计"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsWeekAnalytics.toggle()
                        }
                    } label: {
                        Image(systemName: showsWeekAnalytics ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.weekyiiGradient)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        showsWeekAnalytics
                            ? String(localized: "past.analytics.collapse", defaultValue: "收起分析")
                            : String(localized: "past.analytics.expand", defaultValue: "展开分析")
                    )
                }
            }

            if showsWeekAnalytics {
                if let stats = weekStats {
                    PastStatsOverview(stats: stats)
                }
                WeekTrendChart(dataPoints: weekTrendData)
                ContributionHeatmap(data: weekHeatmapData, dateRange: weekRange)
            }
        }
    }

    private func formatDateRange() -> String {
        let start = Self.monthDayFormatter.string(from: week.startDate)
        let end = Self.monthDayFormatter.string(from: week.endDate)
        return "\(start) - \(end)"
    }

    private func formatDay(_ date: Date) -> String {
        Self.monthDayWeekdayFormatter.string(from: date)
    }

    private func initializeDaySelectionIfNeeded() {
        guard !sortedDays.isEmpty else { return }
        if sortedDays.contains(where: { $0.dayId == selectedDayId }) {
            return
        }
        if let lastRecorded = sortedDays.last(where: { !$0.completedTasks.isEmpty || $0.expiredCount > 0 }) {
            selectedDayId = lastRecorded.dayId
        } else if let firstDay = sortedDays.first {
            selectedDayId = firstDay.dayId
        }
    }

    private func weekdaySymbol(for date: Date) -> String {
        let weekdayIndex = calendar.component(.weekday, from: date) - 1
        let symbols = calendar.veryShortWeekdaySymbols
        if symbols.indices.contains(weekdayIndex) {
            return symbols[weekdayIndex]
        }
        return ""
    }
}
