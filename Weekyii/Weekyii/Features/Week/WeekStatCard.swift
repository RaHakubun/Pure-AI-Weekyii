import SwiftUI

// MARK: - WeekStatCard - 周统计卡片

struct WeekStatCard: View {
    let week: WeekModel
    
    var body: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                // 日期范围
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.weekyiiPrimary)
                    Text(formatDateRange())
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                
                // 完成进度
                HStack {
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        Text(String(localized: "week.completed_days"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text("\(completedDaysCount)/7")
                            .font(.titleMedium)
                            .foregroundColor(.accentGreen)
                    }
                    
                    Spacer()
                    
                    // 进度条
                    VStack(alignment: .trailing, spacing: WeekSpacing.xs) {
                        Text("\(Int(completionRate * 100))%")
                            .font(.captionBold)
                            .foregroundColor(.weekyiiPrimary)
                        ProgressBar(progress: completionRate, height: 8)
                            .frame(width: 120)
                    }
                }
            }
        }
    }
    
    private var completedDaysCount: Int {
        week.days.filter { $0.status == .completed }.count
    }
    
    private var completionRate: Double {
        Double(completedDaysCount) / 7.0
    }
    
    private func formatDateRange() -> String {
        let sortedDays = week.days.sorted(by: { $0.date < $1.date })
        guard let firstDay = sortedDays.first,
              let lastDay = sortedDays.last else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        guard let startDate = formatter.date(from: firstDay.dayId),
              let endDate = formatter.date(from: lastDay.dayId) else {
            return ""
        }
        
        formatter.dateFormat = "M月d日"
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        
        return "\(start) - \(end)"
    }
}

// MARK: - Preview

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let startDate = calendar.date(byAdding: .day, value: -3, to: today)!
    let endDate = calendar.date(byAdding: .day, value: 3, to: today)!
    
    WeekStatCard(week: WeekModel(weekId: "2026-W05", startDate: startDate, endDate: endDate, status: .pending))
        .padding()
        .background(Color.backgroundPrimary)
}
