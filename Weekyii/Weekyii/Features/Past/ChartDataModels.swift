import Foundation

// MARK: - 图表数据模型

/// 每日任务数据点（用于柱状图）
struct DayTaskDataPoint: Identifiable {
    let id = UUID()
    let dayLabel: String       // "一", "二"... 或 "Mon", "Tue"...
    let date: Date
    let completedCount: Int
    let expiredCount: Int
    
    var totalCount: Int { completedCount + expiredCount }
}

/// 日热力图数据
struct DayHeatmapDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let status: HeatmapStatus
}

/// 热力图状态
enum HeatmapStatus {
    case empty           // 未启动 - 灰色
    case lowCompletion   // 完成率 < 50% - 浅绿
    case midCompletion   // 完成率 50-80% - 中绿
    case highCompletion  // 完成率 > 80% - 深绿
    case expired         // 过期 - 红色
    
    static func from(completionRate: Double?, isExpired: Bool) -> HeatmapStatus {
        if isExpired { return .expired }
        guard let rate = completionRate else { return .empty }
        if rate < 0.5 { return .lowCompletion }
        if rate < 0.8 { return .midCompletion }
        return .highCompletion
    }
}
