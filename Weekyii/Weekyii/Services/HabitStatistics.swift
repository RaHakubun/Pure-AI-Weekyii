import Foundation

enum HabitTodayStatus: Equatable {
    case completed
    case pending
    case notGenerated
    case notScheduled
}

/// 时间线节点状态（决策 D4：详情页为每个习惯维护一条完整历史时间线）。
enum HabitTimelineNodeState: Equatable {
    case completed
    case missed        // 显示为「中断」
    case pending       // 仅今天
    case unrecorded    // 计划内无记录（D2 跳过口径），与 missed 视觉可区分
}

struct HabitTimelineNode: Equatable, Identifiable {
    let dayId: String
    let date: Date
    let state: HabitTimelineNodeState
    let completedAt: Date?

    var id: String { dayId }
}

struct HabitStatistics: Equatable {
    let currentStreak: Int
    let longestStreak: Int
    let completedCount: Int
    let missedCount: Int
    let totalRecordedCount: Int
    let todayStatus: HabitTodayStatus

    var completionRate: Double? {
        totalRecordedCount == 0 ? nil : Double(completedCount) / Double(totalRecordedCount)
    }

    var completionRatePercent: Int? {
        completionRate.map { Int(($0 * 100).rounded()) }
    }
}

@MainActor
enum HabitStatisticsCalculator {
    static func statistics(for habit: HabitModel, today: Date = Date()) -> HabitStatistics {
        let map = recordStatusMap(for: habit)
        let todayStart = today.startOfDay
        return HabitStatistics(
            currentStreak: currentStreak(habit: habit, todayStart: todayStart, map: map),
            longestStreak: longestStreak(habit: habit, todayStart: todayStart, map: map),
            completedCount: map.values.filter { $0 == .completed }.count,
            missedCount: map.values.filter { $0 == .missed }.count,
            totalRecordedCount: map.values.filter { $0 != .pending }.count,
            todayStatus: todayStatus(habit: habit, todayStart: todayStart, map: map)
        )
    }

    /// 完整历史时间线（决策 D4）：startDay → today 的全部计划日，倒序。
    /// 纯推导，不新增落盘字段；非计划日不产生节点。
    static func timeline(for habit: HabitModel, today: Date = Date()) -> [HabitTimelineNode] {
        guard habit.hasSchedule, let start = habit.startDate?.startOfDay else { return [] }
        let map = recordStatusMap(for: habit)
        let completedTimes = completedAtMap(for: habit)

        let calendar = Calendar(identifier: .iso8601)
        let startDay = start.startOfDay
        var nodes: [HabitTimelineNode] = []
        var cursor = today.startOfDay
        var scanned = 0
        while cursor >= startDay, scanned < 3660 {
            scanned += 1
            if habit.isScheduled(on: cursor) {
                let state: HabitTimelineNodeState
                switch map[cursor.dayId] {
                case .completed: state = .completed
                case .missed: state = .missed
                case .pending: state = .pending
                case nil: state = .unrecorded
                }
                nodes.append(HabitTimelineNode(
                    dayId: cursor.dayId,
                    date: cursor,
                    state: state,
                    completedAt: completedTimes[cursor.dayId]
                ))
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return nodes
    }

    /// 同日多条 completed 记录（多设备合并）取最早打卡时刻。
    private static func completedAtMap(for habit: HabitModel) -> [String: Date] {
        var map: [String: Date] = [:]
        for record in habit.records where HabitDayRecordStatus(rawValue: record.statusRaw) == .completed {
            guard let completedAt = record.completedAt else { continue }
            if let existing = map[record.dayId] {
                map[record.dayId] = min(existing, completedAt)
            } else {
                map[record.dayId] = completedAt
            }
        }
        return map
    }

    /// 同日多条记录（CloudKit 多设备合并）取"最有利"状态：completed > missed > pending。
    static func recordStatusMap(for habit: HabitModel) -> [String: HabitDayRecordStatus] {
        var map: [String: HabitDayRecordStatus] = [:]
        for record in habit.records {
            let status = HabitDayRecordStatus(rawValue: record.statusRaw) ?? .pending
            guard let existing = map[record.dayId] else {
                map[record.dayId] = status
                continue
            }
            map[record.dayId] = Self.rank(status) > Self.rank(existing) ? status : existing
        }
        return map
    }

    static func currentStreak(
        habit: HabitModel,
        today: Date = Date(),
        map: [String: HabitDayRecordStatus]? = nil
    ) -> Int {
        let todayStart = today.startOfDay
        return currentStreak(habit: habit, todayStart: todayStart, map: map ?? recordStatusMap(for: habit))
    }

    static func longestStreak(
        habit: HabitModel,
        today: Date = Date(),
        map: [String: HabitDayRecordStatus]? = nil
    ) -> Int {
        longestStreak(habit: habit, todayStart: today.startOfDay, map: map ?? recordStatusMap(for: habit))
    }

    // MARK: - 内部

    private static func rank(_ status: HabitDayRecordStatus) -> Int {
        switch status {
        case .completed: return 2
        case .missed: return 1
        case .pending: return 0
        }
    }

    private static func currentStreak(
        habit: HabitModel,
        todayStart: Date,
        map: [String: HabitDayRecordStatus]
    ) -> Int {
        guard habit.hasSchedule, let start = habit.startDate?.startOfDay else { return 0 }

        let calendar = Calendar(identifier: .iso8601)
        let startDay = start.startOfDay
        var streak = 0
        for offset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { break }
            let dayStart = date.startOfDay
            if dayStart < startDay { break }
            guard habit.isScheduled(on: dayStart) else { continue }

            switch map[dayStart.dayId] {
            case .completed: streak += 1
            case .missed: return streak
            case .pending, nil: continue      // 今天宽限；未记录日跳过（决策 D2）
            }
        }
        return streak
    }

    private static func longestStreak(
        habit: HabitModel,
        todayStart: Date,
        map: [String: HabitDayRecordStatus]
    ) -> Int {
        guard habit.hasSchedule, let start = habit.startDate?.startOfDay else { return 0 }

        var longest = 0
        var run = 0
        var cursor = start.startOfDay
        var guardCounter = 0
        while cursor <= todayStart, guardCounter < 3660 {
            if habit.isScheduled(on: cursor) {
                switch map[cursor.dayId] {
                case .completed:
                    run += 1
                    longest = max(longest, run)
                case .missed:
                    run = 0
                case .pending, nil:
                    break
                }
            }
            cursor = cursor.addingDays(1)
            guardCounter += 1
        }
        return longest
    }

    private static func todayStatus(
        habit: HabitModel,
        todayStart: Date,
        map: [String: HabitDayRecordStatus]
    ) -> HabitTodayStatus {
        guard habit.isActive,
              let start = habit.startDate,
              todayStart >= start.startOfDay,
              habit.isScheduled(on: todayStart) else { return .notScheduled }

        switch map[todayStart.dayId] {
        case .completed: return .completed
        case .pending: return .pending
        case .missed: return .notGenerated
        case nil: return .notGenerated
        }
    }
}
