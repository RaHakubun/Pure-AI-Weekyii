import SwiftUI
import SwiftData

// MARK: - WeekStatCard - 周统计卡片

struct WeekStatCard: View {
    @Environment(\.modelContext) private var modelContext
    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    private let weekId: String
    private let startDate: Date
    private let endDate: Date

    init(week: WeekModel) {
        // Capture immutable snapshot values only.
        self.weekId = week.weekId
        self.startDate = week.startDate
        self.endDate = week.endDate
    }
    
    var body: some View {
        let completedCount = completedDaysCount
        let completionRate = Double(completedCount) / 7.0

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
                        Text("\(completedCount)/7")
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
        let descriptor = FetchDescriptor<DayModel>(
            predicate: #Predicate { day in
                day.date >= startDate &&
                day.date <= endDate
            }
        )
        let days = (try? modelContext.fetch(descriptor)) ?? []
        return days.reduce(0) { partial, day in
            partial + (day.status == .completed ? 1 : 0)
        }
    }
    
    private func formatDateRange() -> String {
        let start = Self.monthDayFormatter.string(from: startDate)
        let end = Self.monthDayFormatter.string(from: endDate)
        
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
