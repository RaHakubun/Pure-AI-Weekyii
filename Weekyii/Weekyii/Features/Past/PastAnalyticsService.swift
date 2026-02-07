import Foundation

/// DayPeriod: 一天中的时段
enum DayPeriod: String, CaseIterable {
    case morning = "morning"      // 5:00 - 12:00
    case afternoon = "afternoon"  // 12:00 - 18:00
    case evening = "evening"      // 18:00 - 24:00
    case night = "night"          // 0:00 - 5:00
    
    var localizedName: String {
        switch self {
        case .morning: return String(localized: "period.morning")
        case .afternoon: return String(localized: "period.afternoon")
        case .evening: return String(localized: "period.evening")
        case .night: return String(localized: "period.night")
        }
    }
    
    static func from(hour: Int) -> DayPeriod {
        switch hour {
        case 5..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<24: return .evening
        default: return .night
        }
    }
}

/// 过去统计分析服务
@MainActor
final class PastAnalyticsService {
    private let calendar = Calendar(identifier: .iso8601)
    
    // MARK: - 辅助计算
    
    /// 计算任务耗时
    private func taskDuration(_ task: TaskItem) -> TimeInterval? {
        guard let start = task.startedAt, let end = task.endedAt else { return nil }
        return end.timeIntervalSince(start)
    }
    
    /// 获取任务开始时段
    private func taskStartPeriod(_ task: TaskItem) -> DayPeriod? {
        guard let start = task.startedAt else { return nil }
        let hour = Calendar.current.component(.hour, from: start)
        return DayPeriod.from(hour: hour)
    }
    
    // MARK: - 时间效率
    
    /// 平均任务耗时（秒）
    func averageTaskDuration(tasks: [TaskItem]) -> TimeInterval {
        let durations = tasks.compactMap { taskDuration($0) }
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }
    
    /// 总专注时长（秒）
    func totalFocusDuration(tasks: [TaskItem]) -> TimeInterval {
        tasks.compactMap { taskDuration($0) }.reduce(0, +)
    }
    
    /// 各时段完成任务统计
    func taskCountByPeriod(tasks: [TaskItem]) -> [DayPeriod: Int] {
        var counts: [DayPeriod: Int] = [:]
        for period in DayPeriod.allCases {
            counts[period] = 0
        }
        for task in tasks {
            if let period = taskStartPeriod(task) {
                counts[period, default: 0] += 1
            }
        }
        return counts
    }
    
    /// 最高效时段
    func mostProductivePeriod(tasks: [TaskItem]) -> DayPeriod? {
        let counts = taskCountByPeriod(tasks: tasks)
        return counts.max(by: { $0.value < $1.value })?.key
    }
    
    // MARK: - 完成率
    
    /// 总体完成率
    func overallCompletionRate(days: [DayModel]) -> Double {
        let totalCompleted = days.reduce(0) { $0 + $1.completedTasks.count }
        let totalExpired = days.reduce(0) { $0 + $1.expiredCount }
        let total = totalCompleted + totalExpired
        guard total > 0 else { return 0 }
        return Double(totalCompleted) / Double(total)
    }
    
    // MARK: - 汇总数据结构
    
    struct OverviewStats {
        let totalCompletedTasks: Int
        let totalExpiredTasks: Int
        let completionRate: Double
        let totalFocusHours: Double
        let averageTaskMinutes: Double
        let totalStartedDays: Int
    }
    
    /// 获取概览统计
    func getOverviewStats(days: [DayModel]) -> OverviewStats {
        let startedDays = days.filter {
            $0.status == .execute || $0.status == .completed || $0.status == .expired
        }
        let totalCompleted = startedDays.reduce(0) { $0 + $1.completedTasks.count }
        let totalExpired = startedDays.reduce(0) { $0 + $1.expiredCount }
        let completedTasks = startedDays.flatMap { $0.completedTasks }
        let totalFocusSeconds = totalFocusDuration(tasks: completedTasks)
        let averageTaskMinutes = completedTasks.isEmpty ? 0 : averageTaskDuration(tasks: completedTasks) / 60
        
        return OverviewStats(
            totalCompletedTasks: totalCompleted,
            totalExpiredTasks: totalExpired,
            completionRate: overallCompletionRate(days: startedDays),
            totalFocusHours: totalFocusSeconds / 3600,
            averageTaskMinutes: averageTaskMinutes,
            totalStartedDays: startedDays.count
        )
    }
    
    // MARK: - 图表数据
    
    /// 获取当前周每日任务数据（用于柱状图）
    func getWeekTrendData(days: [DayModel], weekStart: Date) -> [DayTaskDataPoint] {
        let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
        let dayMap = Dictionary(
            days.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        return (0..<7).compactMap { dayOffset -> DayTaskDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { return nil }
            let dateStart = calendar.startOfDay(for: date)
            let dayLabel = weekdayLabels[dayOffset]
            let day = dayMap[dateStart]
            
            return DayTaskDataPoint(
                dayLabel: dayLabel,
                date: date,
                completedCount: day?.completedTasks.count ?? 0,
                expiredCount: day?.expiredCount ?? 0
            )
        }
    }
    
    /// 获取指定月份每日任务数据（用于月趋势图）
    func getMonthTrendData(days: [DayModel], month: Date) -> [DayTaskDataPoint] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }
        let dayMap = Dictionary(
            days.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        return dayRange.compactMap { dayIndex -> DayTaskDataPoint? in
            let offset = dayIndex - 1
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { return nil }
            let dateStart = calendar.startOfDay(for: date)
            let day = dayMap[dateStart]
            
            return DayTaskDataPoint(
                dayLabel: "\(dayIndex)",
                date: date,
                completedCount: day?.completedTasks.count ?? 0,
                expiredCount: day?.expiredCount ?? 0
            )
        }
    }
    
    /// 获取日热力图数据（按范围）
    func getHeatmapData(days: [DayModel], startDate: Date, endDate: Date) -> [DayHeatmapDataPoint] {
        let dayMap = Dictionary(
            days.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        
        var data: [DayHeatmapDataPoint] = []
        var current = start
        while current <= end {
            if let day = dayMap[current] {
                let isExpired = day.status == .expired
                let completedCount = day.completedTasks.count
                let total = completedCount + day.expiredCount
                let rate: Double? = total > 0 ? Double(completedCount) / Double(total) : nil
                
                let status = HeatmapStatus.from(
                    completionRate: day.status == .completed || day.status == .execute || day.status == .expired ? rate : nil,
                    isExpired: isExpired
                )
                data.append(DayHeatmapDataPoint(date: current, status: status))
            } else {
                data.append(DayHeatmapDataPoint(date: current, status: .empty))
            }
            
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        
        return data
    }
}
