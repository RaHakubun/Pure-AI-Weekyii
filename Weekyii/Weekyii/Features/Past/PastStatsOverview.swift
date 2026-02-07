import SwiftUI

/// 过去统计概览卡片组
struct PastStatsOverview: View {
    let stats: PastAnalyticsService.OverviewStats
    
    var body: some View {
        WeekCard {
            HStack(spacing: WeekSpacing.sm) {
                CompactStat(
                    title: String(localized: "stats.completed"),
                    value: "\(stats.totalCompletedTasks)",
                    icon: "checkmark.circle.fill",
                    color: .accentGreen
                )
                
                CompactStat(
                    title: String(localized: "stats.completion_rate"),
                    value: String(format: "%.0f%%", stats.completionRate * 100),
                    icon: "chart.pie.fill",
                    color: .weekyiiPrimary
                )
                
                CompactStat(
                    title: String(localized: "stats.focus_hours"),
                    value: formatHours(stats.totalFocusHours),
                    icon: "flame.fill",
                    color: .taskDDL
                )
            }
        }
    }
    
    private func formatHours(_ hours: Double) -> String {
        if hours < 1 {
            return String(format: "%.0f分钟", hours * 60)
        } else if hours < 10 {
            return String(format: "%.1f小时", hours)
        } else {
            return String(format: "%.0f小时", hours)
        }
    }
}

// MARK: - 单个统计卡片

private struct CompactStat: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            
            Text(value)
                .font(.bodyLarge.weight(.semibold))
                .foregroundColor(.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    PastStatsOverview(stats: .init(
        totalCompletedTasks: 42,
        totalExpiredTasks: 8,
        completionRate: 0.84,
        totalFocusHours: 23.5,
        averageTaskMinutes: 28,
        totalStartedDays: 30
    ))
    .padding()
    .background(Color.backgroundPrimary)
}
