import SwiftUI

/// GitHub 风格的日贡献热力图
struct ContributionHeatmap: View {
    let data: [DayHeatmapDataPoint]
    let weeksToShow: Int
    let dateRange: ClosedRange<Date>?
    
    init(data: [DayHeatmapDataPoint], weeksToShow: Int = 12) {
        self.data = data
        self.weeksToShow = weeksToShow
        self.dateRange = nil
    }
    
    init(data: [DayHeatmapDataPoint], dateRange: ClosedRange<Date>) {
        self.data = data
        self.weeksToShow = 0
        self.dateRange = dateRange
    }
    
    private let calendar = Calendar(identifier: .iso8601)
    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 3
    
    var body: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                // 标题
                HStack {
                    Image(systemName: "square.grid.3x3.fill")
                        .foregroundColor(.accentGreen)
                    Text(String(localized: "stats.heatmap.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                
                if data.isEmpty {
                    Text(String(localized: "stats.heatmap.empty"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, WeekSpacing.lg)
                } else {
                    VStack(alignment: .leading, spacing: cellSpacing) {
                        // 星期标签
                        HStack(spacing: cellSpacing) {
                            ForEach(weekdayLabels, id: \.self) { label in
                                Text(label)
                                    .font(.system(size: 9))
                                    .foregroundColor(.textTertiary)
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                        
                        // 热力图主体
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: cellSpacing) {
                                ForEach(weekColumns, id: \.self) { weekStart in
                                    VStack(spacing: cellSpacing) {
                                        ForEach(daysInWeek(starting: weekStart), id: \.self) { date in
                                            HeatmapCell(
                                                status: statusFor(date: date),
                                                size: cellSize
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 图例
                        HStack(spacing: WeekSpacing.md) {
                            Spacer()
                            legendItem(String(localized: "stats.heatmap.less"), color: statusColor(.lowCompletion))
                            legendItem("", color: statusColor(.midCompletion))
                            legendItem(String(localized: "stats.heatmap.more"), color: statusColor(.highCompletion))
                        }
                    }
                }
            }
        }
    }
    
    private var weekdayLabels: [String] {
        ["一", "二", "三", "四", "五", "六", "日"]
    }
    
    private var weekColumns: [Date] {
        if let dateRange {
            let start = calendar.startOfDay(for: dateRange.lowerBound)
            let end = calendar.startOfDay(for: dateRange.upperBound)
            guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)),
                  let endOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: end)) else {
                return []
            }
            
            var weeks: [Date] = []
            var current = startOfWeek
            while current <= endOfWeek {
                weeks.append(current)
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: current) else { break }
                current = next
            }
            return weeks
        }
        
        let today = calendar.startOfDay(for: Date())
        guard let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return []
        }
        
        var weeks: [Date] = []
        for i in (0..<weeksToShow).reversed() {
            if let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: startOfThisWeek) {
                weeks.append(weekStart)
            }
        }
        return weeks
    }
    
    private func daysInWeek(starting weekStart: Date) -> [Date] {
        (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }
    
    private func statusFor(date: Date) -> HeatmapStatus {
        let dayStart = calendar.startOfDay(for: date)
        if let dateRange {
            if dayStart < calendar.startOfDay(for: dateRange.lowerBound) || dayStart > calendar.startOfDay(for: dateRange.upperBound) {
                return .empty
            }
        }
        return data.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.status ?? .empty
    }
    
    private func statusColor(_ status: HeatmapStatus) -> Color {
        switch status {
        case .empty: return Color.textTertiary.opacity(0.2)
        case .lowCompletion: return Color.accentGreen.opacity(0.3)
        case .midCompletion: return Color.accentGreen.opacity(0.6)
        case .highCompletion: return Color.accentGreen
        case .expired: return Color.taskDDL.opacity(0.7)
        }
    }
    
    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            if !label.isEmpty {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }
        }
    }
}

// MARK: - 热力图格子

private struct HeatmapCell: View {
    let status: HeatmapStatus
    let size: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: size, height: size)
    }
    
    private var color: Color {
        switch status {
        case .empty: return Color.textTertiary.opacity(0.2)
        case .lowCompletion: return Color.accentGreen.opacity(0.3)
        case .midCompletion: return Color.accentGreen.opacity(0.6)
        case .highCompletion: return Color.accentGreen
        case .expired: return Color.taskDDL.opacity(0.7)
        }
    }
}

// MARK: - Preview

#Preview {
    let calendar = Calendar(identifier: .iso8601)
    let today = Date()
    
    // 生成过去 84 天的模拟数据
    let mockData: [DayHeatmapDataPoint] = (0..<84).compactMap { dayOffset in
        guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { return nil }
        let random = Double.random(in: 0...1)
        let status: HeatmapStatus
        if random < 0.2 {
            status = .empty
        } else if random < 0.4 {
            status = .lowCompletion
        } else if random < 0.6 {
            status = .midCompletion
        } else if random < 0.9 {
            status = .highCompletion
        } else {
            status = .expired
        }
        return DayHeatmapDataPoint(date: date, status: status)
    }
    
    return ContributionHeatmap(data: mockData)
        .padding()
        .background(Color.backgroundPrimary)
}
