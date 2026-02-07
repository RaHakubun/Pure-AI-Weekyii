import SwiftUI
import Charts

/// 每周任务柱状图 - 每天一根柱子，顶部红色表示过期任务
struct WeekTrendChart: View {
    let dataPoints: [DayTaskDataPoint]
    
    var body: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                // 标题
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.weekyiiPrimary)
                    Text(String(localized: "stats.trend.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                    
                    Spacer()
                    
                    // 周总结
                    if !dataPoints.isEmpty {
                        WeekSummaryBadge(
                            completed: dataPoints.reduce(0) { $0 + $1.completedCount },
                            expired: dataPoints.reduce(0) { $0 + $1.expiredCount }
                        )
                    }
                }
                
                if dataPoints.isEmpty {
                    Text(String(localized: "stats.trend.empty"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, WeekSpacing.lg)
                } else {
                    // 柱状图
                    Chart(dataPoints) { point in
                        // 完成任务 - 绿色
                        BarMark(
                            x: .value("Day", point.dayLabel),
                            y: .value("Completed", point.completedCount)
                        )
                        .foregroundStyle(Color.accentGreen.gradient)
                        .cornerRadius(4, style: .continuous)
                        
                        // 过期任务 - 红色（堆叠在上面）
                        if point.expiredCount > 0 {
                            BarMark(
                                x: .value("Day", point.dayLabel),
                                y: .value("Expired", point.expiredCount)
                            )
                            .foregroundStyle(Color.taskDDL.gradient)
                            .cornerRadius(4, style: .continuous)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel {
                                if let count = value.as(Int.self) {
                                    Text("\(count)")
                                        .font(.caption2)
                                        .foregroundColor(.textTertiary)
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(Color.textTertiary.opacity(0.3))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel()
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(height: 160)
                    
                    // 图例
                    HStack(spacing: WeekSpacing.md) {
                        Spacer()
                        legendItem(String(localized: "stats.legend.completed"), color: .accentGreen)
                        legendItem(String(localized: "stats.legend.expired"), color: .taskDDL)
                    }
                }
            }
        }
    }
    
    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .foregroundColor(.textTertiary)
        }
    }
}

// MARK: - 月趋势图

struct MonthTrendChart: View {
    let dataPoints: [DayTaskDataPoint]
    let month: Date
    private let calendar = Calendar(identifier: .iso8601)
    
    var body: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.weekyiiPrimary)
                    Text("月趋势")
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                    
                    Spacer()
                    
                    if !dataPoints.isEmpty {
                        let completed = dataPoints.reduce(0) { $0 + $1.completedCount }
                        let expired = dataPoints.reduce(0) { $0 + $1.expiredCount }
                        WeekSummaryBadge(completed: completed, expired: expired)
                    }
                }
                
                if dataPoints.isEmpty {
                    Text(String(localized: "stats.trend.empty"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, WeekSpacing.lg)
                } else {
                    Chart(dataPoints) { point in
                        BarMark(
                            x: .value("Day", point.dayLabel),
                            y: .value("Completed", point.completedCount)
                        )
                        .foregroundStyle(Color.accentGreen.gradient)
                        .cornerRadius(4, style: .continuous)
                        
                        if point.expiredCount > 0 {
                            BarMark(
                                x: .value("Day", point.dayLabel),
                                y: .value("Expired", point.expiredCount)
                            )
                            .foregroundStyle(Color.taskDDL.gradient)
                            .cornerRadius(4, style: .continuous)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel {
                                if let count = value.as(Int.self) {
                                    Text("\(count)")
                                        .font(.caption2)
                                        .foregroundColor(.textTertiary)
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(Color.textTertiary.opacity(0.3))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: xAxisLabels) { value in
                            AxisValueLabel()
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(height: 180)
                    
                    HStack(spacing: WeekSpacing.md) {
                        Spacer()
                        legendItem(String(localized: "stats.legend.completed"), color: .accentGreen)
                        legendItem(String(localized: "stats.legend.expired"), color: .taskDDL)
                    }
                }
            }
        }
    }
    
    private var xAxisLabels: [String] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }
        
        let lastDay = dayRange.count
        let keyDays = Set([1, 5, 10, 15, 20, 25, lastDay])
        return dayRange.compactMap { dayIndex in
            keyDays.contains(dayIndex) ? "\(dayIndex)" : nil
        }
    }
    
    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .foregroundColor(.textTertiary)
        }
    }
}

// MARK: - 周总结徽章

struct WeekSummaryBadge: View {
    let completed: Int
    let expired: Int
    
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.accentGreen)
                Text("\(completed)")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            
            if expired > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.taskDDL)
                    Text("\(expired)")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.backgroundSecondary.opacity(0.5))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    WeekTrendChart(dataPoints: [
        DayTaskDataPoint(dayLabel: "一", date: Date(), completedCount: 5, expiredCount: 1),
        DayTaskDataPoint(dayLabel: "二", date: Date(), completedCount: 4, expiredCount: 0),
        DayTaskDataPoint(dayLabel: "三", date: Date(), completedCount: 6, expiredCount: 2),
        DayTaskDataPoint(dayLabel: "四", date: Date(), completedCount: 3, expiredCount: 0),
        DayTaskDataPoint(dayLabel: "五", date: Date(), completedCount: 7, expiredCount: 1),
        DayTaskDataPoint(dayLabel: "六", date: Date(), completedCount: 2, expiredCount: 0),
        DayTaskDataPoint(dayLabel: "日", date: Date(), completedCount: 0, expiredCount: 0),
    ])
    .padding()
    .background(Color.backgroundPrimary)
}
