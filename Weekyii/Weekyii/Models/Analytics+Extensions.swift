import Foundation

// MARK: - TaskItem 统计扩展

extension TaskItem {
    /// 任务实际耗时（秒）
    var duration: TimeInterval? {
        guard let start = startedAt, let end = endedAt else { return nil }
        return end.timeIntervalSince(start)
    }
    
    /// 任务耗时（分钟）
    var durationMinutes: Double? {
        guard let d = duration else { return nil }
        return d / 60.0
    }
    
    /// 开始时段
    var startPeriod: DayPeriod? {
        guard let start = startedAt else { return nil }
        let hour = Calendar.current.component(.hour, from: start)
        return DayPeriod.from(hour: hour)
    }
    
    /// 格式化耗时字符串
    var durationFormatted: String? {
        guard let d = duration else { return nil }
        let minutes = Int(d / 60)
        if minutes < 60 {
            return "\(minutes)分钟"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)小时\(mins)分钟" : "\(hours)小时"
        }
    }
}

// MARK: - DayModel 统计扩展

extension DayModel {
    /// 当日总专注时长（秒）
    var totalFocusDuration: TimeInterval {
        completedTasks.compactMap { $0.duration }.reduce(0, +)
    }
    
    /// 完成率 (0.0 - 1.0)
    var completionRate: Double {
        let total = completedTasks.count + expiredCount
        guard total > 0 else { return 0 }
        return Double(completedTasks.count) / Double(total)
    }
    
    /// 是否为工作日（周一到周五）
    var isWeekday: Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday >= 2 && weekday <= 6
    }
    
    /// 格式化专注时长
    var focusDurationFormatted: String {
        let minutes = Int(totalFocusDuration / 60)
        if minutes < 60 {
            return "\(minutes)分钟"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)小时\(mins)分钟" : "\(hours)小时"
        }
    }
}

// MARK: - WeekModel 统计扩展

extension WeekModel {
    /// 周完成率 (0.0 - 1.0)
    var completionRate: Double {
        let total = completedTasksCount + expiredTasksCount
        guard total > 0 else { return 0 }
        return Double(completedTasksCount) / Double(total)
    }
    
    /// 周总专注时长（秒）
    var totalFocusDuration: TimeInterval {
        days.reduce(0) { $0 + $1.totalFocusDuration }
    }
}
