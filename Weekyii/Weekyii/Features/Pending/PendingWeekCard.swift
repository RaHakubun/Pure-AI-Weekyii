import SwiftUI

// MARK: - PendingWeekCard - 未来周卡片

struct PendingWeekCard: View {
    let week: WeekModel
    
    var body: some View {
        NavigationLink {
            // TODO: 周详情视图
            Text("Week Detail: \(week.weekId)")
        } label: {
            WeekCard {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    // 周标题
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.weekyiiPrimary)
                        Text(week.weekId)
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                    
                    // 日期范围
                    HStack(spacing: WeekSpacing.xs) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text(formatDateRange())
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }
                    
                    Divider()
                    
                    // 天数统计
                    HStack {
                        VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                            Text(String(localized: "pending.days_count"))
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Text("\(week.days.count)")
                                .font(.titleMedium)
                                .foregroundColor(.weekyiiPrimary)
                        }
                        
                        Spacer()
                        
                        // 状态标识
                        Image(systemName: "clock.badge")
                            .font(.system(size: 32))
                            .foregroundColor(.weekyiiPrimary.opacity(0.3))
                    }
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private func formatDateRange() -> String {
        let sortedDays = week.days.sorted(by: { $0.date < $1.date })
        guard let firstDay = sortedDays.first,
              let lastDay = sortedDays.last else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let start = formatter.string(from: firstDay.date)
        let end = formatter.string(from: lastDay.date)
        
        return "\(start) - \(end)"
    }
}

// MARK: - Preview

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let startDate = calendar.date(byAdding: .day, value: 7, to: today)!
    let endDate = calendar.date(byAdding: .day, value: 13, to: today)!
    
    PendingWeekCard(week: WeekModel(weekId: "2026-W06", startDate: startDate, endDate: endDate, status: .pending))
        .padding()
        .background(Color.backgroundPrimary)
}
