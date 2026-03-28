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
                    // 周标题
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.weekyiiPrimary)
                        Text(week.relativeWeekLabel())
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                    
                    // 日期范围
                    HStack(spacing: WeekSpacing.xs) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text(formatDateRange())
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }
                    
                    Divider()
                    
                    HStack(alignment: .center, spacing: WeekSpacing.md) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(String(localized: "pending.week.outlook.title", defaultValue: "周预报"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                tonePill
                                Spacer(minLength: 0)
                            }

                            Text(outlook.headline)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            HStack(spacing: 6) {
                                typeMetric(icon: TaskType.regular.monthMarkerIconName, value: outlook.typeCounts.regular, tint: .taskRegular)
                                typeMetric(icon: TaskType.ddl.monthMarkerIconName, value: outlook.typeCounts.ddl, tint: .taskDDL)
                                typeMetric(icon: TaskType.leisure.monthMarkerIconName, value: outlook.typeCounts.leisure, tint: .taskLeisure)
                                Spacer(minLength: 0)
                            }

                            advicePill
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        WeekLoadSparklineView(series: outlook.dayLoadSeries, tint: toneColor)
                            .frame(width: 58, height: 50)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
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
            return .red
        }
    }

    private var tonePill: some View {
        Text(outlook.tone.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(toneColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(toneColor.opacity(colorScheme == .dark ? 0.22 : 0.14), in: .rect(cornerRadius: 6))
    }

    private var advicePill: some View {
        HStack(spacing: 4) {
            Image(systemName: "lightbulb.max.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text(outlook.advice)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.backgroundTertiary.opacity(colorScheme == .dark ? 0.55 : 0.75), in: .rect(cornerRadius: 6))
    }

    private func typeMetric(icon: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(colorScheme == .dark ? 0.18 : 0.12), in: .rect(cornerRadius: 6))
    }

    private var forecastPanelFill: Color {
        toneColor.opacity(colorScheme == .dark ? 0.14 : 0.08)
    }

    private var forecastPanelBorder: Color {
        toneColor.opacity(colorScheme == .dark ? 0.30 : 0.20)
    }
}

private struct WeekLoadSparklineView: View {
    let series: [Double]
    let tint: Color

    private var normalizedSeries: [Double] {
        let maxValue = max(series.max() ?? 0, 1)
        return series.map { max($0 / maxValue, 0.16) }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(Array(normalizedSeries.enumerated()), id: \.offset) { index, ratio in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barTint(at: index))
                    .frame(width: 4, height: 32 * ratio)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(Color.backgroundPrimary.opacity(0.72), in: .rect(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var peakIndex: Int? {
        guard let maxValue = series.max(), maxValue > 0 else { return nil }
        return series.firstIndex(of: maxValue)
    }

    private func barTint(at index: Int) -> Color {
        guard let peakIndex else {
            return .textTertiary.opacity(0.26)
        }
        if index == peakIndex {
            return tint.opacity(0.90)
        }
        if abs(index - peakIndex) == 1 {
            return tint.opacity(0.45)
        }
        return .textTertiary.opacity(0.24)
    }
}

// MARK: - Preview

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let startDate = calendar.date(byAdding: .day, value: 7, to: today)!
    let endDate = calendar.date(byAdding: .day, value: 13, to: today)!
    
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
        .padding()
        .background(Color.backgroundPrimary)
}
