import Foundation
import SwiftData
import SwiftUI

enum HabitCategory: String, CaseIterable, Codable, Identifiable {
    case health
    case fitness
    case learning
    case mindfulness
    case creativity
    case social
    case productivity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .health: return String(localized: "habit.category.health", defaultValue: "健康")
        case .fitness: return String(localized: "habit.category.fitness", defaultValue: "运动")
        case .learning: return String(localized: "habit.category.learning", defaultValue: "学习")
        case .mindfulness: return String(localized: "habit.category.mindfulness", defaultValue: "正念")
        case .creativity: return String(localized: "habit.category.creativity", defaultValue: "创造")
        case .social: return String(localized: "habit.category.social", defaultValue: "社交")
        case .productivity: return String(localized: "habit.category.productivity", defaultValue: "效率")
        }
    }
}

enum HabitScheduleKind: String, CaseIterable, Codable, Identifiable {
    case weekly
    case monthly
    case once

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return String(localized: "habit.schedule.kind.weekly", defaultValue: "按星期")
        case .monthly: return String(localized: "habit.schedule.kind.monthly", defaultValue: "按月")
        case .once: return String(localized: "habit.schedule.kind.once", defaultValue: "不重复")
        }
    }
}

enum HabitError: LocalizedError, Equatable {
    case nameEmpty
    case scheduleEmpty
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .nameEmpty: return String(localized: "habit.error.name_empty", defaultValue: "习惯名称不能为空")
        case .scheduleEmpty: return String(localized: "habit.error.schedule_empty", defaultValue: "请至少选择一天")
        case .saveFailed: return String(localized: "habit.error.save_failed", defaultValue: "保存失败，请重试")
        }
    }
}

@Model
final class HabitModel {
    var id: UUID = UUID()

    var name: String = ""
    var iconName: String = "repeat.circle.fill"
    var colorHex: String = "#34C759"
    var categoryRaw: String = HabitCategory.health.rawValue

    /// 重复方式：weekly / monthly / once（不重复）。
    var scheduleKindRaw: String = HabitScheduleKind.weekly.rawValue
    /// 按星期位掩码：bit(weekday - 1)，Mon=bit0 ... Sun=bit6。默认周一至周五 = 0b0011111。
    var scheduleWeekdaysRaw: Int = 0b0011111
    /// 按月位掩码：bit(day - 1)，1 日=bit0 ... 31 日=bit30。默认空。
    var scheduleMonthDaysRaw: Int = 0
    /// 生效开始日（YYYY-MM-DD）；此前日期永不生成。
    var startDayId: String = ""
    /// Retained for V8 SwiftData and Archive v1 compatibility only. Never use for materialization or sync decisions.
    var generatedThroughDayId: String = ""

    var isActive: Bool = true
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, originalName: "tasks", inverse: \TaskItem.habit)
    private var taskRecords: [TaskItem]? = []
    @Relationship(deleteRule: .cascade, originalName: "dayLogs", inverse: \HabitDayRecord.habit)
    private var recordEntries: [HabitDayRecord]? = []

    init(
        name: String,
        iconName: String = "repeat.circle.fill",
        colorHex: String = "#34C759",
        category: HabitCategory = .health,
        scheduleKind: HabitScheduleKind = .weekly,
        scheduleWeekdays: Set<Int> = [1, 2, 3, 4, 5],
        scheduleMonthDays: Set<Int> = [],
        startDayId: String,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.categoryRaw = category.rawValue
        self.scheduleKindRaw = scheduleKind.rawValue
        self.scheduleWeekdaysRaw = Self.encode(scheduleWeekdays)
        self.scheduleMonthDaysRaw = Self.encodeMonthDays(scheduleMonthDays)
        self.startDayId = startDayId
        self.sortOrder = sortOrder
    }

    var tasks: [TaskItem] {
        get { taskRecords ?? [] }
        set { taskRecords = newValue }
    }

    var records: [HabitDayRecord] {
        get { recordEntries ?? [] }
        set { recordEntries = newValue }
    }

    func hasProcessed(dayId: String) -> Bool {
        records.contains { $0.dayId == dayId }
    }

    var category: HabitCategory {
        get { HabitCategory(rawValue: categoryRaw) ?? .health }
        set { categoryRaw = newValue.rawValue }
    }

    /// ISO weekday 集合：1 = 周一 ... 7 = 周日。
    var scheduleWeekdays: Set<Int> {
        get { Self.decode(scheduleWeekdaysRaw) }
        set { scheduleWeekdaysRaw = Self.encode(newValue) }
    }

    var scheduleKind: HabitScheduleKind {
        get { HabitScheduleKind(rawValue: scheduleKindRaw) ?? .weekly }
        set { scheduleKindRaw = newValue.rawValue }
    }

    /// 按月集合：1 ... 31。
    var scheduleMonthDays: Set<Int> {
        get { Self.decodeMonthDays(scheduleMonthDaysRaw) }
        set { scheduleMonthDaysRaw = Self.encodeMonthDays(newValue) }
    }

    /// 是否配置了可生成的计划日（`.once` 恒有效）。
    var hasSchedule: Bool {
        switch scheduleKind {
        case .weekly: return !scheduleWeekdays.isEmpty
        case .monthly: return !scheduleMonthDays.isEmpty
        case .once: return true
        }
    }

    var startDate: Date? { WeekyiiDayId.date(from: startDayId) }

    var habitColor: Color { Color(hex: colorHex) }

    var scheduleSummary: String {
        switch scheduleKind {
        case .once:
            guard let startDate else { return "" }
            let formatted = startDate.formatted(.dateTime.month().day())
            return String(localized: "habit.schedule.once %@", defaultValue: "仅 \(formatted) 一次")
        case .monthly:
            let days = scheduleMonthDays.sorted()
            guard !days.isEmpty else { return "" }
            let list = days.map(String.init).joined(separator: "、")
            return String(localized: "habit.schedule.monthly %@", defaultValue: "每月 \(list) 日")
        case .weekly:
            let weekdays = scheduleWeekdays.sorted()
            guard !weekdays.isEmpty else { return "" }
            if weekdays == [1, 2, 3, 4, 5, 6, 7] {
                return String(localized: "habit.schedule.everyday", defaultValue: "每天")
            }
            if weekdays == [1, 2, 3, 4, 5] {
                return String(localized: "habit.schedule.weekdays", defaultValue: "工作日")
            }
            if weekdays == [6, 7] {
                return String(localized: "habit.schedule.weekend", defaultValue: "周末")
            }
            return weekdays
                .map { WeekyiiWeekday.localizedSymbol(for: $0) }
                .joined(separator: " ")
        }
    }

    /// 按重复方式判定某天是否应生成（按月缺日 / 不重复非开始日 → false，均不计入统计与时间线）。
    func isScheduled(on date: Date) -> Bool {
        switch scheduleKind {
        case .weekly:
            return scheduleWeekdays.contains(date.isoWeekday)
        case .monthly:
            return scheduleMonthDays.contains(Calendar(identifier: .iso8601).component(.day, from: date))
        case .once:
            return date.dayId == startDayId
        }
    }

    private static func encode(_ weekdays: Set<Int>) -> Int {
        weekdays.filter { (1...7).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    private static func decode(_ mask: Int) -> Set<Int> {
        Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
    }

    private static func encodeMonthDays(_ days: Set<Int>) -> Int {
        days.filter { (1...31).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    private static func decodeMonthDays(_ mask: Int) -> Set<Int> {
        Set((1...31).filter { mask & (1 << ($0 - 1)) != 0 })
    }
}
