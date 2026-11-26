import SwiftUI
import Charts

// MARK: - PendingWeekCard - 未来周卡片

struct PendingWeekCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var displayMode: OutlookDisplayMode = .highlights
    @ScaledMetric(relativeTo: .caption) private var outlookBodyMinHeight: CGFloat = 78

    private enum OutlookDisplayMode: Hashable {
        case highlights, trend
    }
    let week: WeekModel
    let outlook: PendingViewModel.WeekOutlookSnapshot

    init(week: WeekModel, outlook: PendingViewModel.WeekOutlookSnapshot) {
        self.week = week
        self.outlook = outlook
    }

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()
    
    var body: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                // Navigation and the segmented control are siblings, not nested buttons.
                NavigationLink {
                    PendingWeekDetailView(week: week)
                } label: {
                    HStack(spacing: WeekSpacing.xs) {
                        CatCoveredSymbol(systemName: "calendar", pointSize: 13)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textTertiary)
                        Text(week.relativeWeekLabel())
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                        Text(formatDateRange())
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pendingWeekCard_\(week.weekId)")

                HStack(alignment: .top, spacing: WeekSpacing.sm) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(toneColor)
                        .frame(width: 3)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        forecastHeader

                        // Empty weeks retain their existing compact message and height.
                        if outlook.hasTasks {
                            // Keep each card's choice transient and independent.
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    modePicker
                                    Spacer(minLength: 4)
                                    taskTotal
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    modePicker
                                    taskTotal
                                }
                            }
                        }

                        NavigationLink {
                            PendingWeekDetailView(week: week)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                // Lay out both states together so switching does not move the next card.
                                // The hidden state contributes its natural height, including at large type sizes.
                                if outlook.hasTasks {
                                    ZStack(alignment: .topLeading) {
                                        highlightContent
                                            .opacity(displayMode == .highlights ? 1 : 0)
                                            .accessibilityHidden(displayMode != .highlights)
                                        WeekOutlookTrend(days: outlook.days, tint: toneColor)
                                            .opacity(displayMode == .trend ? 1 : 0)
                                            .accessibilityHidden(displayMode != .trend)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: outlookBodyMinHeight, alignment: .topLeading)
                                } else {
                                    highlightContent
                                }

                                HStack(spacing: 3) {
                                    Image(systemName: "lightbulb")
                                        .font(.system(size: 9, weight: .regular))
                                        .foregroundStyle(Color.textTertiary)
                                    Text(WeekOutlookText.hint(outlook.hint, days: outlook.days))
                                        .font(.caption2)
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pendingWeekOutlookContent_\(week.weekId)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(forecastPanelFill, in: .rect(cornerRadius: WeekRadius.scaled(10)))
                .overlay(
                    RoundedRectangle(cornerRadius: WeekRadius.scaled(10))
                        .stroke(forecastPanelBorder, lineWidth: 1)
                        .allowsHitTesting(false)
                )
            }
        }
    }

    private var forecastHeader: some View {
        HStack(spacing: 5) {
            Text(outlook.tone.displayName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(toneColor)
            Text(WeekOutlookText.title)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Spacer(minLength: 4)
            HStack(spacing: WeekSpacing.sm) {
                typeCountItem(icon: TaskType.regular.monthMarkerIconName,
                              value: outlook.typeCounts.regular, tint: .taskRegular)
                typeCountItem(icon: TaskType.ddl.monthMarkerIconName,
                              value: outlook.typeCounts.ddl, tint: .taskDDL)
                typeCountItem(icon: TaskType.leisure.monthMarkerIconName,
                              value: outlook.typeCounts.leisure, tint: .taskLeisure)
            }
        }
    }

    private var modePicker: some View {
        Picker(String(localized: "pending.week.outlook.displayMode", defaultValue: "周预报视图"), selection: $displayMode) {
            Text(String(localized: "pending.week.outlook.highlights", defaultValue: "重点"))
                .tag(OutlookDisplayMode.highlights)
            Text(String(localized: "pending.week.outlook.trend", defaultValue: "轨迹"))
                .tag(OutlookDisplayMode.trend)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 150)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pendingWeekOutlookPicker_\(week.weekId)")
    }

    private var taskTotal: some View {
        Text(String(format: String(localized: "pending.week.outlook.total", defaultValue: "%lld 项任务"), Int64(outlook.days.reduce(0) { $0 + $1.taskCount })))
            .font(.caption2)
            .foregroundStyle(Color.textTertiary)
            .lineLimit(1)
    }

    @ViewBuilder private var highlightContent: some View {
        if !outlook.hasTasks {
            Text(WeekOutlookText.emptyWeek)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        } else if outlook.keyTasks.isEmpty {
            Text(WeekOutlookText.noKeyTasks)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(outlook.keyTasks) { task in
                    keyTaskRow(task)
                }
                if let more = WeekOutlookText.hiddenKeyTasks(
                    total: outlook.hiddenKeyTaskCount,
                    deadlines: outlook.hiddenDeadlineCount
                ) {
                    Text(more)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.leading, weekdayColumnWidth + 6)
                }
            }
        }
    }

    private func formatDateRange() -> String {
        let sortedDays = week.days.sorted(by: { $0.date < $1.date })
        guard let firstDay = sortedDays.first,
              let lastDay = sortedDays.last else {
            return ""
        }
        let start = Self.monthDayFormatter.string(from: firstDay.date)
        let end = Self.monthDayFormatter.string(from: lastDay.date)
        return "\(start) - \(end)"
    }

    // 唯一主强调色，按 tone 决定
    private var toneColor: Color {
        switch outlook.tone {
        case .relaxed:
            return .accentGreen
        case .steady:
            return .weekyiiPrimary
        case .frontLooseBackTight:
            return .accentOrange
        case .midweekCongestion:
            return .accentOrange
        case .deadlineRush:
            return .taskDDL
        case .overloadWarning:
            // 用 taskDDL 替代 .red，避免高饱和红色噪音；
            // taskDDL 在各主题下已调校为柔和锈橙，可读性更好
            return .taskDDL
        }
    }

    // 面板背景：极低透明度，仅用于区域感知，不传递情绪色
    private var forecastPanelFill: Color {
        colorScheme == .dark
            ? Color.backgroundTertiary.opacity(0.6)
            : Color.backgroundTertiary.opacity(0.5)
    }

    // 面板边框：中性，不带 tone 色
    private var forecastPanelBorder: Color {
        colorScheme == .dark
            ? Color.textTertiary.opacity(0.18)
            : Color.textTertiary.opacity(0.12)
    }

    /// Weekday column of the key task rows; scales with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var weekdayColumnWidth: CGFloat = 30

    // 重点任务行：星期 + 类型图标 + 标题（截断）+ 原因标签
    private func keyTaskRow(_ task: PendingViewModel.WeekOutlookKeyTask) -> some View {
        let reasonColor = reasonTint(task.reason)
        return HStack(spacing: 6) {
            Text(PendingViewModel.weekdayLabel(for: task.date))
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .frame(width: weekdayColumnWidth, alignment: .leading)
            Image(systemName: task.baseKind.monthMarkerIconName)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(task.baseKind.color.opacity(0.9))
            Text(task.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(WeekOutlookText.reason(task.reason))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(reasonColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 88)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(reasonColor.opacity(0.35), lineWidth: 1)
                )
                .layoutPriority(1)
        }
    }

    private func reasonTint(_ reason: PendingViewModel.WeekOutlookKeyTask.Reason) -> Color {
        switch reason {
        case .deadline:
            return .taskDDL
        case .projectDue:
            return .accentOrange
        case .project, .steps:
            return .textSecondary
        }
    }

    // 任务数量行：图标用任务色，数字用次要文字色，无背景胶囊
    private func typeCountItem(icon: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint.opacity(0.85))
            Text("\(value)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textSecondary)
        }
    }
}

// MARK: - Seven-day task trend

private struct WeekOutlookTrend: View {
    let days: [PendingViewModel.WeekOutlookDay]
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var chartHeight: CGFloat = 62

    private var chartMaximum: Double {
        let maximum = days.map(\.taskCount).max() ?? 0
        return Double(max(1, maximum)) * 1.45
    }

    private var showCountRows: Bool {
        dynamicTypeSize.isAccessibilitySize || days.contains { $0.taskCount > 999 }
    }

    private var peak: PendingViewModel.WeekOutlookDay? {
        let maximum = days.map(\.taskCount).max() ?? 0
        return maximum > 0 ? days.first { $0.taskCount == maximum } : nil
    }

    private var spokenSummary: String {
        days.map { day in
            String(format: String(localized: "pending.week.outlook.dayCount", defaultValue: "%1$@，%2$lld 项任务"),
                   PendingViewModel.weekdayLabel(for: day.date), Int64(day.taskCount))
        }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(String(localized: "pending.week.outlook.trendSummary", defaultValue: "七天任务轨迹"))
                Spacer(minLength: 4)
                if let peak {
                    Text(String(format: String(localized: "pending.week.outlook.peak", defaultValue: "%1$@最多 · %2$lld 项"),
                                PendingViewModel.weekdayLabel(for: peak.date), Int64(peak.taskCount)))
                }
            }
            .font(.caption2)
            .foregroundStyle(Color.textTertiary)
            .lineLimit(1)
            .accessibilityHidden(true)

            Chart {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    AreaMark(x: .value("Day", index), y: .value("Tasks", day.taskCount))
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.01)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", index), y: .value("Tasks", day.taskCount))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Day", index), y: .value("Tasks", day.taskCount))
                        .foregroundStyle(tint)
                        .symbolSize(28)
                        .annotation(position: .top, spacing: 2) {
                            if !showCountRows {
                                Text("\(day.taskCount)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                }
            }
            .chartXScale(domain: -0.5...6.5)
            .chartYScale(domain: 0...chartMaximum)
            .chartXAxis {
                AxisMarks(values: Array(0..<days.count)) { value in
                    AxisValueLabel {
                        if let index = value.as(Int.self), days.indices.contains(index) {
                            Text(PendingViewModel.narrowWeekdayLabel(for: days[index].date))
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(Color.textTertiary.opacity(0.25))
                }
            }
            .frame(height: chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(String(localized: "pending.week.outlook.trendSummary", defaultValue: "七天任务轨迹")))
            .accessibilityValue(Text(spokenSummary))

            // Keep full counts legible for large type and unusually large values.
            if showCountRows {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    HStack {
                        Text(PendingViewModel.weekdayLabel(for: day.date))
                        Spacer()
                        Text("\(day.taskCount)")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    let calendar = Calendar(identifier: .iso8601)
    let startDate = calendar.date(byAdding: .day, value: 7, to: Date().startOfWeek)!
    let endDate = calendar.date(byAdding: .day, value: 6, to: startDate)!
    let dates = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: startDate)! }
    let busyDays = zip(dates, zip([7, 2, 8, 9, 6, 6, 4], [1, 0, 3, 3, 1, 0, 0])).map { date, counts in
        PendingViewModel.WeekOutlookDay(date: date, taskCount: counts.0, deadlineCount: counts.1)
    }
    let busyOutlook = PendingViewModel.WeekOutlookSnapshot(
        tone: .overloadWarning,
        typeCounts: .init(regular: 12, ddl: 8, leisure: 22),
        dayLoadSeries: [8, 2, 11, 12, 7, 6, 4],
        days: busyDays,
        keyTasks: [
            .init(id: UUID(), title: "提交季度经营分析报告终稿", date: dates[2], baseKind: .ddl, reason: .deadline(typeName: nil)),
            .init(id: UUID(), title: "合同审核", date: dates[3], baseKind: .ddl, reason: .deadline(typeName: nil)),
            .init(id: UUID(), title: "官网改版 · 首页上线", date: dates[4], baseKind: .regular, reason: .projectDue)
        ],
        hiddenKeyTaskCount: 6,
        hiddenDeadlineCount: 6,
        hint: PendingViewModel.weekHint(for: busyDays)
    )
    let emptyDays = dates.map { PendingViewModel.WeekOutlookDay(date: $0, taskCount: 0, deadlineCount: 0) }

    VStack(spacing: 16) {
        PendingWeekCard(
            week: WeekModel(weekId: "2026-W07", startDate: startDate, endDate: endDate, status: .pending),
            outlook: busyOutlook
        )

        PendingWeekCard(
            week: WeekModel(weekId: "2026-W08", startDate: startDate, endDate: endDate, status: .pending),
            outlook: .init(
                tone: .relaxed,
                typeCounts: .init(regular: 0, ddl: 0, leisure: 0),
                dayLoadSeries: Array(repeating: 0, count: 7),
                days: emptyDays,
                hint: .noTasks
            )
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}
