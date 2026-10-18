import SwiftUI

// MARK: - PendingWeekCard - 未来周卡片

struct PendingWeekCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let week: WeekModel
    let outlook: PendingViewModel.WeekOutlookSnapshot

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()
    
    var body: some View {
        NavigationLink {
            PendingWeekDetailView(week: week)
        } label: {
            WeekCard {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    // 周标题行：图标中性化，仅周标签用主色，右侧显示日期范围
                    HStack(spacing: WeekSpacing.xs) {
                        Image(systemName: "calendar")
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

                    // 周预报信息区：中性面板背景，仅左侧竖线用 tone 色做强调
                    HStack(alignment: .top, spacing: WeekSpacing.sm) {
                        // 左侧 tone 色竖线（唯一高饱和色块，宽度仅 3pt）
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(toneColor)
                            .frame(width: 3)
                            .padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 6) {
                            // 层1：tone 标签 + 三类任务数量
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
                                                  value: outlook.typeCounts.regular,
                                                  tint: .taskRegular)
                                    typeCountItem(icon: TaskType.ddl.monthMarkerIconName,
                                                  value: outlook.typeCounts.ddl,
                                                  tint: .taskDDL)
                                    typeCountItem(icon: TaskType.leisure.monthMarkerIconName,
                                                  value: outlook.typeCounts.leisure,
                                                  tint: .taskLeisure)
                                }
                            }

                            // 层2：本周重点任务（不点进详情就能看到要提前准备的事）
                            if !outlook.hasTasks {
                                Text(WeekOutlookText.emptyWeek)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                            } else if outlook.keyTasks.isEmpty {
                                Text(WeekOutlookText.noKeyTasks)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
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
                                            .lineLimit(1)
                                            .padding(.leading, weekdayColumnWidth + 6)
                                    }
                                }
                            }

                            // 层3：七天分布（统一刻度，周与周之间可直接比较）
                            if outlook.hasTasks {
                                WeekOutlookDayStrip(days: outlook.days, tint: toneColor)
                            }

                            // 层4：根据实际数据生成的一句建议
                            HStack(spacing: 3) {
                                Image(systemName: "lightbulb")
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundStyle(Color.textTertiary)
                                Text(WeekOutlookText.hint(outlook.hint, days: outlook.days))
                                    .font(.caption2)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(forecastPanelFill, in: .rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(forecastPanelBorder, lineWidth: 1)
                    )
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityIdentifier("pendingWeekCard_\(week.weekId)")
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

// MARK: - Day strip（七天分布，统一刻度）

private struct WeekOutlookDayStrip: View {
    let days: [PendingViewModel.WeekOutlookDay]
    let tint: Color

    /// Same scale for every week: this many tasks fills a bar, so a light week
    /// looks light next to a busy one.
    static let fullScaleTaskCount = 10
    private let barAreaHeight: CGFloat = 26

    private var peakCount: Int { days.map(\.taskCount).max() ?? 0 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 2) {
                    VStack(spacing: 2) {
                        if day.deadlineCount > 0 {
                            // DDL 标记
                            Circle()
                                .fill(Color.taskDDL)
                                .frame(width: 4, height: 4)
                        }
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barColor(for: day))
                            .frame(maxWidth: 26)
                            .frame(height: barHeight(for: day))
                    }
                    .frame(height: barAreaHeight + 6, alignment: .bottom)
                    Text(PendingViewModel.narrowWeekdayLabel(for: day.date))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        // 重点任务与建议句已用文字表达，分布条仅作视觉辅助
        .accessibilityHidden(true)
    }

    private func barHeight(for day: PendingViewModel.WeekOutlookDay) -> CGFloat {
        guard day.taskCount > 0 else { return 2 }
        let ratio = min(Double(day.taskCount) / Double(Self.fullScaleTaskCount), 1)
        return max(4, barAreaHeight * CGFloat(ratio))
    }

    private func barColor(for day: PendingViewModel.WeekOutlookDay) -> Color {
        if day.taskCount == 0 {
            return .textTertiary.opacity(0.18)
        }
        if day.taskCount == peakCount {
            return tint.opacity(0.88)
        }
        return .textTertiary.opacity(0.45)
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
