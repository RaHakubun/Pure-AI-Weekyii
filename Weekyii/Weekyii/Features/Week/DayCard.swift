import SwiftUI

// MARK: - DayCard - 日期卡片组件

struct DayCard: View {
    let day: DayModel
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

                // 统一占位，避免不同状态造成卡片高度跳变
                Group {
                    if day.status != .empty {
                        MiniProgressRing(progress: completionRate, size: WeekLayoutMetrics.dayCardRingSize)
                    } else {
                        Circle()
                            .stroke(Color.backgroundTertiary, lineWidth: 3)
                            .frame(width: WeekLayoutMetrics.dayCardRingSize, height: WeekLayoutMetrics.dayCardRingSize)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.lg)
        }
        .frame(maxWidth: .infinity, minHeight: WeekLayoutMetrics.dayCardMinHeight, alignment: .top)
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

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let day1 = calendar.date(byAdding: .day, value: -2, to: today)!
    let day2 = calendar.date(byAdding: .day, value: -1, to: today)!
    
    HStack(spacing: 12) {
        DayCard(day: DayModel(dayId: "2026-01-27", date: day1, status: .completed))
        DayCard(day: DayModel(dayId: "2026-01-28", date: day2, status: .execute))
        DayCard(day: DayModel(dayId: "2026-01-29", date: today, status: .empty))
    }
    .padding()
    .background(Color.backgroundPrimary)
}
