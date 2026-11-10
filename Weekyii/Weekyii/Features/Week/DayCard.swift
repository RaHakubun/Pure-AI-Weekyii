import SwiftUI

// MARK: - DayCard - 日期卡片组件

struct DayCard: View {
    let day: DayModel

    /// 进度槽位的固定直径。
    ///
    /// 空状态也要占住这块高度：`WeekOverviewView` / `WeekOverviewDetailSection`
    /// 用两列 `LazyVGrid` 排布日期卡，而 `LazyVGrid` 只把一行撑到最高 cell 的高度，
    /// **不会**把同行的其他 cell 拉伸。所以只要卡片的 intrinsic height 随状态变化，
    /// 空日期就会比有任务的日期矮一截。
    static let progressRingSize: CGFloat = 36

    private static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
    private static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()
    
    var body: some View {
        WeekCard(accentColor: day.status.color, shadow: .medium) {
            VStack(spacing: WeekSpacing.md) {
                // 星期和日期
                VStack(spacing: WeekSpacing.xxs) {
                    Text(weekdayName)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    
                    Text(dayNumber)
                        .font(.titleLarge)
                        .foregroundColor(.textPrimary)
                }
                
                // 状态指示
                StatusBadge(status: day.status)

                // 进度槽位：七张日期卡共用同一条布局路径，只切换透明度、
                // 不切换分支。卡片高度因此与状态无关，空日期不再矮一截。
                // （空状态本来就没有进度可言，所以环隐藏，但槽位必须留着。）
                MiniProgressRing(progress: completionRate, size: Self.progressRingSize)
                    .opacity(showsProgressRing ? 1 : 0)
                    .accessibilityHidden(!showsProgressRing)
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.lg)
        }
    }

    /// 空状态不画进度环，但**仍然占位**（见 `progressRingSize`）。
    private var showsProgressRing: Bool {
        day.status != .empty
    }
    
    private var weekdayName: String {
        Self.shortWeekdayFormatter.string(from: day.date)
    }
    
    private var dayNumber: String {
        Self.dayNumberFormatter.string(from: day.date)
    }
    
    private var completionRate: Double {
        let totalTasks = day.tasks.count
        guard totalTasks > 0 else { return 0.0 }
        
        let completedTasks = day.completedTasks.count
        return Double(completedTasks) / Double(totalTasks)
    }
}

// MARK: - Preview

#Preview("等高回归 — 空 / 有任务 混排") {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    // 复现截图里的排布：周一空、周二执行中、周三/周四草稿、周五/周六空。
    // 修复前，第一行「空 + 执行中」会明显不等高（差 36pt 环 + 12pt 间距）。
    let days = [
        previewDay(dayId: "d0", date: today, status: .empty, taskCount: 0, completedCount: 0),
        previewDay(dayId: "d1", date: calendar.date(byAdding: .day, value: 1, to: today)!, status: .execute, taskCount: 2, completedCount: 1),
        previewDay(dayId: "d2", date: calendar.date(byAdding: .day, value: 2, to: today)!, status: .draft, taskCount: 2, completedCount: 0),
        previewDay(dayId: "d3", date: calendar.date(byAdding: .day, value: 3, to: today)!, status: .draft, taskCount: 1, completedCount: 0),
        previewDay(dayId: "d4", date: calendar.date(byAdding: .day, value: 4, to: today)!, status: .empty, taskCount: 0, completedCount: 0),
        previewDay(dayId: "d5", date: calendar.date(byAdding: .day, value: 5, to: today)!, status: .empty, taskCount: 0, completedCount: 0),
        previewDay(dayId: "d6", date: calendar.date(byAdding: .day, value: 6, to: today)!, status: .completed, taskCount: 2, completedCount: 2)
    ]

    ScrollView {
        LazyVGrid(columns: columns, spacing: WeekSpacing.md) {
            ForEach(days, id: \.dayId) { day in
                DayCard(day: day)
            }
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}

#Preview("五种状态并排") {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let statuses: [DayStatus] = [.empty, .draft, .execute, .completed, .expired]

    HStack(spacing: 12) {
        ForEach(Array(statuses.enumerated()), id: \.offset) { index, status in
            DayCard(
                day: previewDay(
                    dayId: "status\(index)",
                    date: calendar.date(byAdding: .day, value: index, to: today)!,
                    status: status,
                    taskCount: status == .empty ? 0 : 2,
                    completedCount: status == .completed ? 2 : (status == .execute ? 1 : 0)
                )
            )
        }
    }
    .padding()
    .background(Color.backgroundPrimary)
}

/// 仅用于 Preview：造一个状态与任务数都确定的日期。
private func previewDay(
    dayId: String,
    date: Date,
    status: DayStatus,
    taskCount: Int,
    completedCount: Int
) -> DayModel {
    let day = DayModel(dayId: dayId, date: date, status: status)
    day.tasks = (0..<taskCount).map { index in
        TaskItem(
            title: "任务 \(index + 1)",
            order: index + 1,
            zone: index < completedCount ? .complete : .draft
        )
    }
    return day
}
