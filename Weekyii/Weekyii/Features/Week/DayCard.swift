import SwiftUI

// MARK: - DayCard - 日期卡片组件

struct DayCard: View {
    let day: DayModel
    
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
                
                // 进度环(仅在有任务时显示)
                if day.status != .empty {
                    MiniProgressRing(progress: completionRate, size: 36)
                }
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.lg)
        }
    }
    
    private var weekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day.dayId) else {
            return ""
        }
        
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day.dayId) else {
            return ""
        }
        
        formatter.dateFormat = "d"
        return formatter.string(from: date)
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
