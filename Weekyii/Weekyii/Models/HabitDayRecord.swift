import Foundation
import SwiftData

enum HabitDayRecordStatus: String, Codable, CaseIterable {
    case pending
    case completed
    case missed

    var displayName: String {
        switch self {
        case .pending: return String(localized: "habit.record.status.pending", defaultValue: "待完成")
        case .completed: return String(localized: "habit.record.status.completed", defaultValue: "已完成")
        case .missed: return String(localized: "habit.record.status.missed", defaultValue: "中断")
        }
    }
}

@Model
final class HabitDayRecord {
    var id: UUID = UUID()
    /// YYYY-MM-DD，与 DayModel.dayId / Date.dayId 同格式。
    var dayId: String = ""
    var statusRaw: String = HabitDayRecordStatus.pending.rawValue
    /// 记录创建时刻（= 物化时刻）。
    var createdAt: Date = Date()
    var completedAt: Date?
    var habit: HabitModel?

    init(dayId: String, createdAt: Date = Date()) {
        self.dayId = dayId
        self.createdAt = createdAt
    }

    var status: HabitDayRecordStatus {
        get { HabitDayRecordStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}
