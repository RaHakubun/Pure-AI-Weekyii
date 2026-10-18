import SwiftUI
import SwiftData

/// Per-day facts the Past month calendar can mark. Derived on read from
/// existing `DayModel` fields; never written back.
struct PastMonthDaySummary: Equatable {
    let dayId: String
    let completedCount: Int
    let expiredCount: Int
    let hasRecord: Bool
    let failure: PastDayFailureKind?
}

/// Which markers the Past month calendar draws. Every flag is an independent,
/// device-local preference in `UserSettings`; none of it lives in SwiftData
/// or travels through iCloud sync.
struct PastMonthMarkerOptions: Equatable {
    /// Frowning face on days that ended with unfinished tasks.
    var showsUnfinishedFace: Bool
    /// Muted face on days that expired without ever being started.
    var showsNotStartedFace: Bool
    /// Completed-task count badge at the date's top-right corner.
    var showsCompletedCount: Bool
    /// Dot for any day that has a plan, execution or completion record.
    var showsRecordDot: Bool
    /// Flame for days with expired tasks (same condition as the unfinished face).
    var showsExpiredFlame: Bool

    static let `default` = PastMonthMarkerOptions(
        showsUnfinishedFace: true,
        showsNotStartedFace: false,
        showsCompletedCount: false,
        showsRecordDot: false,
        showsExpiredFlame: false
    )

    var enabledCount: Int {
        [showsUnfinishedFace, showsNotStartedFace, showsCompletedCount, showsRecordDot, showsExpiredFlame]
            .filter { $0 }
            .count
    }

    var isEmpty: Bool { enabledCount == 0 }

    func showsFace(for kind: PastDayFailureKind) -> Bool {
        switch kind {
        case .unfinished: return showsUnfinishedFace
        case .notStarted: return showsNotStartedFace
        }
    }

    /// Short value for the Settings root row.
    var summaryText: String {
        if isEmpty {
            return String(localized: "settings.past.markers.summary.none", defaultValue: "不显示")
        }
        if self == .default {
            return String(localized: "settings.past.markers.summary.default", defaultValue: "失败提醒")
        }
        return String(
            format: String(localized: "settings.past.markers.summary.count", defaultValue: "显示 %lld 项"),
            enabledCount
        )
    }
}

enum PastDayFailureKind: Equatable {
    /// Started (or reached kill time) with tasks still open: `expiredCount > 0`.
    case unfinished
    /// Expired without ever being started. Often produced by habit drafts the
    /// app materialized on its own, so its marker is off by default.
    case notStarted
}

/// Read-only interpretation of the state machine's persisted day outcome.
/// It derives everything from existing fields (`status`, `expiredCount`,
/// `initiatedAt`) and never writes back, so it stays correct when sync or
/// invariant repair later settles a day as completed.
enum PastDayFailureRule {
    static func kind(for day: DayModel, todayId: String, includeNotStarted: Bool) -> PastDayFailureKind? {
        kind(
            dayId: day.dayId,
            status: day.status,
            expiredCount: day.expiredCount,
            initiatedAt: day.initiatedAt,
            todayId: todayId,
            includeNotStarted: includeNotStarted
        )
    }

    static func kind(
        dayId: String,
        status: DayStatus,
        expiredCount: Int,
        initiatedAt: Date?,
        todayId: String,
        includeNotStarted: Bool
    ) -> PastDayFailureKind? {
        guard !dayId.isEmpty, dayId <= todayId else { return nil }
        // An open day has not reached its kill time yet; its outcome is undecided.
        guard status != .draft && status != .execute else { return nil }
        if expiredCount > 0 {
            return .unfinished
        }
        if includeNotStarted, status == .expired, initiatedAt == nil {
            return .notStarted
        }
        return nil
    }
}

struct PastView: View {
    @EnvironmentObject private var userSettings: UserSettings
    @Query(sort: \WeekModel.startDate, order: .reverse) private var allWeeks: [WeekModel]
    @Query(sort: \DayModel.date, order: .reverse) private var allDays: [DayModel]
    @State private var selectedMonth = Date()
    @State private var selectedDate = Date()
    @State private var showsMonthAnalytics = false
    private let analyticsService = PastAnalyticsService()
    private let calendar = Calendar(identifier: .iso8601)

    /// Week list or month calendar. Stored in `UserSettings` (device-local), so
    /// the last chosen view is restored after the app restarts.
    private var displayMode: WeekBrowseMode {
        get { userSettings.pastBrowseMode }
        nonmutating set { userSettings.pastBrowseMode = newValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                    MonthPickerView(month: $selectedMonth, restriction: .pastOnly)

                    monthReviewCard

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

    /// Days the calendar may mark or open: this month, up to and including
    /// today, regardless of week status. The current week and today (once past
    /// kill time) therefore show up immediately, while the review statistics
    /// above keep using archived weeks only via `monthDays`. Matching on
    /// `dayId` keeps the calendar aligned with the anchored Weekyii time zone.
    private var calendarScopedDays: [DayModel] {
        let range = monthRange
        let lowerId = range.lowerBound.dayId
        let upperId = min(range.upperBound.dayId, Date().dayId)
        return allDays.filter { $0.dayId >= lowerId && $0.dayId <= upperId }
    }

    private var monthSummaries: [String: PastMonthDaySummary] {
        let todayId = Date().dayId
        var result: [String: PastMonthDaySummary] = [:]
        for day in calendarScopedDays {
            let completedCount = day.completedTasks.count
            let expiredCount = day.expiredCount
            result[day.dayId] = PastMonthDaySummary(
                dayId: day.dayId,
                completedCount: completedCount,
                expiredCount: expiredCount,
                hasRecord: completedCount > 0 || expiredCount > 0 || day.status != .empty,
                failure: PastDayFailureRule.kind(for: day, todayId: todayId, includeNotStarted: true)
            )
        }
        return result
    }

    private var selectedDay: DayModel? {
        let targetId = calendar.startOfDay(for: selectedDate).dayId
        return calendarScopedDays.first(where: { $0.dayId == targetId })
    }

    private var selectedDaySummary: PastMonthDaySummary? {
        let targetId = calendar.startOfDay(for: selectedDate).dayId
        return monthSummaries[targetId]
    }

    private var monthStats: PastAnalyticsService.OverviewStats? {
        let stats = analyticsService.getOverviewStats(days: monthDays)
        return stats.totalStartedDays > 0 ? stats : nil
    }

    private var previousMonthStats: PastAnalyticsService.OverviewStats? {
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) else { return nil }
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: previousMonth)) ?? previousMonth
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: -1, to: next) ?? start
        let days = allDays.filter { day in
            guard day.week?.status == .past else { return false }
            let date = calendar.startOfDay(for: day.date)
            return date >= calendar.startOfDay(for: start) && date <= calendar.startOfDay(for: end)
        }
        let stats = analyticsService.getOverviewStats(days: days)
        return stats.totalStartedDays > 0 ? stats : nil
    }

    private var monthComparisonText: String? {
        guard let current = monthStats, let previous = previousMonthStats else { return nil }
        let delta = current.completionRate - previous.completionRate
        if abs(delta) < 0.005 {
            return "完成率与上月持平"
        }
        let value = abs(delta).formatted(.percent.precision(.fractionLength(0)))
        return delta > 0 ? "完成率较上月提升 \(value)" : "完成率较上月下降 \(value)"
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
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: displayMode == .weekList ? "calendar" : "list.bullet.rectangle")
                Text(displayMode == .weekList ? "月历" : "周列表")
            }
            .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel(
            displayMode == .weekList
                ? String(localized: "past.switch.month", defaultValue: "切换到月视图")
                : String(localized: "past.switch.week", defaultValue: "切换到周列表")
        )
    }

    private var monthOverview: some View {
        VStack(spacing: WeekSpacing.md) {
            pastSurface {
                PastMonthCalendarView(
                    selectedDate: $selectedDate,
                    selectedMonth: $selectedMonth,
                    summaries: monthSummaries,
                    markerOptions: userSettings.pastMonthMarkerOptions
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

        return pastSurface {
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
            pastSurface {
                HStack {
                    VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                        Text("趋势与洞察")
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

                Text("完成任务保留详情；过期任务仅保留数量。")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
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

    private var monthReviewCard: some View {
        pastSurface {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("本月回顾")
                            .font(.titleSmall)
                            .foregroundStyle(Color.textPrimary)
                        Text(selectedMonth, format: Date.FormatStyle().year().month(.wide))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(Color.weekyiiPrimary)
                }

                if let stats = monthStats {
                    HStack(spacing: WeekSpacing.lg) {
                        reviewMetric("完成", value: "\(stats.totalCompletedTasks)", color: .accentGreen)
                        reviewMetric("完成率", value: stats.completionRate.formatted(.percent.precision(.fractionLength(0))), color: .weekyiiPrimary)
                        reviewMetric("专注", value: String(format: "%.1fh", stats.totalFocusHours), color: .weekyiiPrimaryLight)
                        reviewMetric("活跃", value: "\(stats.totalStartedDays)天", color: .weekyiiPrimary)
                    }

                    if let monthComparisonText {
                        Label(monthComparisonText, systemImage: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    Text("这个月还没有可以回顾的记录。")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func reviewMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.bodyMedium.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 保留过去页既有卡片与信息顺序，只统一其表面材质、圆角、边界和阴影。
    private func pastSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(WeekSpacing.base)
            .background(Color.backgroundSecondary)
            .clipShape(.rect(cornerRadius: WeekRadius.xlarge))
            .overlay {
                RoundedRectangle(cornerRadius: WeekRadius.xlarge, style: .continuous)
                    .stroke(Color.backgroundTertiary.opacity(0.55), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: WeekShadow.light.color, radius: 14, x: 0, y: 5)
    }

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
    let markerOptions: PastMonthMarkerOptions

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
        VStack(spacing: WeekSpacing.sm) {
            weekdayHeader

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(calendarDays) { day in
                    dayCell(day)
                }
            }

            legend
        }
    }

    private var legend: some View {
        PastMarkerLegend(options: markerOptions)
            .padding(.top, WeekSpacing.xs)
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
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day.date)
        let today = calendar.startOfDay(for: Date())
        let isFutureDate = calendar.startOfDay(for: day.date) > today
        let isInteractive = day.isCurrentMonth && !isFutureDate
        let summary = isInteractive ? summaries[dayId] : nil
        let highlight: PastCalendarDayLabel.Highlight = !isInteractive
            ? .none
            : (isSelected ? .selected : (isToday ? .today : .none))

        Button {
            guard isInteractive else { return }
            withAnimation(.snappy(duration: 0.22)) {
                selectedDate = day.date
            }
        } label: {
            PastCalendarDayLabel(
                dayNumber: calendar.component(.day, from: day.date),
                numberColor: dayNumberColor(
                    day: day,
                    isSelected: isSelected,
                    isToday: isToday,
                    isFutureDate: isFutureDate
                ),
                isEmphasized: isToday,
                highlight: highlight,
                summary: summary,
                options: markerOptions
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: day.date, summary: summary))
            .accessibilityAddTraits(isSelected && isInteractive ? .isSelected : [])
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
    }

    /// VoiceOver reads only what is visible, so the spoken markers always
    /// match the user's own display choices.
    private func accessibilityLabel(for date: Date, summary: PastMonthDaySummary?) -> String {
        var parts = [date.formatted(Date.FormatStyle().month().day())]
        guard let summary else { return parts[0] }
        if let failure = summary.failure, markerOptions.showsFace(for: failure) {
            parts.append(failure.legendText)
        }
        if markerOptions.showsCompletedCount && summary.completedCount > 0 {
            parts.append(String(
                format: String(localized: "past.month.a11y.completed_count", defaultValue: "完成 %lld 项"),
                summary.completedCount
            ))
        }
        if markerOptions.showsRecordDot && summary.hasRecord {
            parts.append(String(localized: "past.month.legend.record", defaultValue: "有记录"))
        }
        if markerOptions.showsExpiredFlame && summary.expiredCount > 0 {
            parts.append(String(
                format: String(localized: "past.month.a11y.expired_count", defaultValue: "过期 %lld 项"),
                summary.expiredCount
            ))
        }
        return parts.joined(separator: ", ")
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
}

extension PastDayFailureKind {
    var legendText: String {
        switch self {
        case .unfinished:
            return String(localized: "past.month.legend.failed", defaultValue: "没完成的一天")
        case .notStarted:
            return String(localized: "past.month.legend.not_started", defaultValue: "未启动")
        }
    }
}

/// One calendar day: the number with its selection/today frame plus every
/// marker the options allow. Shared by the Past calendar and the Settings
/// preview so the preview is always exactly what the calendar will draw.
struct PastCalendarDayLabel: View {
    enum Highlight {
        case none
        case selected
        case today
    }

    let dayNumber: Int
    let numberColor: Color
    let isEmphasized: Bool
    let highlight: Highlight
    let summary: PastMonthDaySummary?
    let options: PastMonthMarkerOptions

    private var visibleFace: PastDayFailureKind? {
        guard let failure = summary?.failure, options.showsFace(for: failure) else { return nil }
        return failure
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    switch highlight {
                    case .selected:
                        RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                            .fill(Color.weekyiiPrimary)
                    case .today:
                        RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                            .stroke(Color.weekyiiPrimary, lineWidth: 1.5)
                    case .none:
                        EmptyView()
                    }

                    Text("\(dayNumber)")
                        .font(.body)
                        .fontWeight(isEmphasized ? .semibold : .regular)
                        .foregroundStyle(numberColor)
                }
                .frame(width: 38, height: 40)

                if options.showsCompletedCount, let count = summary?.completedCount, count > 0 {
                    PastCompletedCountBadge(count: count)
                        .offset(x: 5, y: -4)
                }
            }

            // Fixed height: toggling markers in Settings never shifts the grid.
            HStack(spacing: 3) {
                if options.showsRecordDot, summary?.hasRecord == true {
                    PastRecordDotMark()
                }
                if options.showsExpiredFlame, (summary?.expiredCount ?? 0) > 0 {
                    PastExpiredFlameMark()
                }
                if let visibleFace {
                    PastFailureFaceMark(kind: visibleFace)
                        .frame(width: 13, height: 13)
                }
            }
            .frame(height: 13)
        }
        // Keep each marker visually attached to its own date rather than
        // floating toward the next row.
        .padding(.bottom, WeekSpacing.xs)
    }
}

struct PastCompletedCountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.accentGreen, in: Capsule())
    }
}

struct PastRecordDotMark: View {
    var body: some View {
        Circle()
            .fill(Color.accentGreen)
            .frame(width: 6, height: 6)
    }
}

struct PastExpiredFlameMark: View {
    var size: CGFloat = 8

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: size))
            .foregroundStyle(Color.taskDDL)
    }
}

/// Lists only the markers the user turned on, in the same order they are
/// configured in Settings. Hidden entirely when nothing is shown.
struct PastMarkerLegend: View {
    let options: PastMonthMarkerOptions

    var body: some View {
        if !options.isEmpty {
            FlowLayout(spacing: WeekSpacing.lg, lineSpacing: WeekSpacing.xs) {
                if options.showsUnfinishedFace {
                    item(text: PastDayFailureKind.unfinished.legendText) {
                        PastFailureFaceMark(kind: .unfinished).frame(width: 11, height: 11)
                    }
                }
                if options.showsNotStartedFace {
                    item(text: PastDayFailureKind.notStarted.legendText) {
                        PastFailureFaceMark(kind: .notStarted).frame(width: 11, height: 11)
                    }
                }
                if options.showsCompletedCount {
                    item(text: String(localized: "past.month.legend.completed_count", defaultValue: "完成数量")) {
                        PastCompletedCountBadge(count: 3)
                    }
                }
                if options.showsRecordDot {
                    item(text: String(localized: "past.month.legend.record", defaultValue: "有记录")) {
                        PastRecordDotMark()
                    }
                }
                if options.showsExpiredFlame {
                    item(text: String(localized: "past.month.legend.expired", defaultValue: "有过期")) {
                        PastExpiredFlameMark(size: 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func item<Mark: View>(text: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 4) {
            mark()
            Text(text)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        }
    }
}

/// Small frowning face drawn with shapes so it follows the theme's DDL tint
/// (SF Symbols has no sad face). Not-started days use a muted outline.
struct PastFailureFaceMark: View {
    let kind: PastDayFailureKind

    private var tint: Color {
        kind == .unfinished ? .taskDDL : .textTertiary
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let line = max(size * 0.1, 1)
            ZStack {
                Circle()
                    .fill(kind == .unfinished ? tint.opacity(0.18) : Color.clear)
                Circle()
                    .stroke(tint, lineWidth: line)
                HStack(spacing: size * 0.22) {
                    Circle().fill(tint).frame(width: size * 0.13, height: size * 0.13)
                    Circle().fill(tint).frame(width: size * 0.13, height: size * 0.13)
                }
                .offset(y: -size * 0.1)
                PastFrownShape()
                    .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: size * 0.42, height: size * 0.16)
                    .offset(y: size * 0.2)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

private struct PastFrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6)
        )
        return path
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
