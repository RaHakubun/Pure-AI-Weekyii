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

                        VStack(alignment: .leading, spacing: 5) {
                            // 层1：tone 标签（文字胶囊，无背景色块）
                            HStack(spacing: 5) {
                                Text(outlook.tone.displayName)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(toneColor)
                                Text(String(localized: "pending.week.outlook.title", defaultValue: "周预报"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.textTertiary)
                                Spacer(minLength: 0)
                            }

                            // 层2：headline（一句话预期，最醒目的文字层）
                            Text(outlook.headline)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            // 层3a：三类任务数量（图标 + 数字，无彩色背景，仅图标用任务色）
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
                                Spacer(minLength: 0)
                            }

                            // 层3b：建议文本（文字形式，最低视觉权重）
                            HStack(spacing: 3) {
                                Image(systemName: "lightbulb")
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundStyle(Color.textTertiary)
                                Text(outlook.advice)
                                    .font(.caption2)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // 压力 sparkline：无额外容器背景，融入面板
                        WeekLoadSparklineView(series: outlook.dayLoadSeries, tint: toneColor)
                            .frame(width: 52, height: 52)
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

// MARK: - Sparkline（弱化装饰，突出峰值日）

private struct WeekLoadSparklineView: View {
    let series: [Double]
    let tint: Color

    private var normalizedSeries: [Double] {
        let maxValue = max(series.max() ?? 0, 1)
        return series.map { max($0 / maxValue, 0.12) }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(Array(normalizedSeries.enumerated()), id: \.offset) { index, ratio in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barTint(at: index))
                    .frame(width: 4, height: 36 * ratio)
            }
        }
        // 移除独立容器背景框，直接融入面板；用 padding 保持对齐
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var peakIndex: Int? {
        guard let maxValue = series.max(), maxValue > 0 else { return nil }
        return series.firstIndex(of: maxValue)
    }

    private func barTint(at index: Int) -> Color {
        guard let peakIndex else {
            return .textTertiary.opacity(0.20)
        }
        if index == peakIndex {
            // 峰值柱：用 toneColor，饱和度完整，其余柱极低透明
            return tint.opacity(0.88)
        }
        if abs(index - peakIndex) == 1 {
            return tint.opacity(0.35)
        }
        return .textTertiary.opacity(0.18)
    }
}

// MARK: - Preview

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let startDate = calendar.date(byAdding: .day, value: 7, to: today)!
    let endDate = calendar.date(byAdding: .day, value: 13, to: today)!
    
    VStack(spacing: 16) {
        PendingWeekCard(
            week: WeekModel(weekId: "2026-W06", startDate: startDate, endDate: endDate, status: .pending),
            outlook: .init(
                tone: .frontLooseBackTight,
                headline: "后半周会明显变紧，建议提前启动关键事项",
                advice: "周一周二先清关键任务",
                typeCounts: .init(regular: 8, ddl: 3, leisure: 2),
                peakDays: ["周四", "周五"],
                dayLoadSeries: [1, 2.4, 2, 4, 4.2, 3, 1]
            )
        )

        PendingWeekCard(
            week: WeekModel(weekId: "2026-W07", startDate: startDate, endDate: endDate, status: .pending),
            outlook: .init(
                tone: .overloadWarning,
                headline: "本周负载偏高，高压在周三/周四",
                advice: "建议拆分或减载安排",
                typeCounts: .init(regular: 12, ddl: 5, leisure: 1),
                peakDays: ["周三", "周四"],
                dayLoadSeries: [3, 4, 5.5, 5.2, 4, 2, 1]
            )
        )

        PendingWeekCard(
            week: WeekModel(weekId: "2026-W08", startDate: startDate, endDate: endDate, status: .pending),
            outlook: .init(
                tone: .relaxed,
                headline: "整体负载偏轻，按节奏推进即可",
                advice: "保持节奏并留1天机动",
                typeCounts: .init(regular: 3, ddl: 0, leisure: 2),
                peakDays: [],
                dayLoadSeries: [1, 0.5, 1.2, 0.8, 1, 0.3, 0]
            )
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}
