import SwiftUI

// MARK: - PendingWeekDetailView - 未来周详情页

struct PendingWeekDetailView: View {
    let week: WeekModel
    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()
    private static let monthDayWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MdE")
        return formatter
    }()
    private let calendar = Calendar(identifier: .iso8601)
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                summaryCard
                
                ForEach(sortedDays) { day in
                    dayCard(day)
                }
            }
            .weekPadding(WeekSpacing.base)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle(week.relativeWeekLabel())
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Sorted Days
    
    private var sortedDays: [DayModel] {
        week.days.sorted { $0.date < $1.date }
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                Text(String(localized: "pending.week.summary"))
                    .font(.titleSmall)
                    .foregroundColor(.textPrimary)
                
                Text(formatDateRange())
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                
                HStack(spacing: WeekSpacing.lg) {
                    statBlock(
                        title: String(localized: "pending.week.total_days"),
                        value: week.days.count,
                        color: .weekyiiPrimary
                    )
                    
                    statBlock(
                        title: String(localized: "pending.week.draft_days"),
                        value: draftDaysCount,
                        color: .accentOrange
                    )
                    
                    statBlock(
                        title: String(localized: "pending.week.empty_days"),
                        value: emptyDaysCount,
                        color: .textTertiary
                    )
                }
            }
        }
    }
    
    // MARK: - Day Card
    
    private func dayCard(_ day: DayModel) -> some View {
        NavigationLink {
            DayDetailView(day: day)
        } label: {
            WeekCard {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    HStack {
                        Text(formatDay(day.date))
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        StatusBadge(status: day.status)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                    
                    // 草稿任务统计
                    if day.status == .draft {
                        HStack(spacing: WeekSpacing.xs) {
                            Image(systemName: "doc.text")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Text(String(format: String(localized: "pending.week.draft_tasks_count"), day.sortedDraftTasks.count))
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)
                        }
                        if !day.sortedDraftTasks.isEmpty {
                            Text(String(localized: "draft.title"))
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            VStack(spacing: WeekSpacing.sm) {
                                ForEach(day.sortedDraftTasks) { task in
                                    TaskRowView(task: task)
                                }
                            }
                        } else {
                            Text(String(localized: "draft.empty"))
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)
                        }
                    } else if day.status == .empty {
                        HStack(spacing: WeekSpacing.xs) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                            Text(String(localized: "pending.week.add_tasks"))
                                .font(.bodyMedium)
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Helper Views
    
    private func statBlock(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
            Text("\(value)")
                .font(.titleMedium)
                .foregroundColor(color)
        }
    }
    
    // MARK: - Computed Properties
    
    private var draftDaysCount: Int {
        week.days.filter { $0.status == .draft }.count
    }
    
    private var emptyDaysCount: Int {
        week.days.filter { $0.status == .empty }.count
    }
    
    // MARK: - Formatting
    
    private func formatDateRange() -> String {
        let start = Self.monthDayFormatter.string(from: week.startDate)
        let end = Self.monthDayFormatter.string(from: week.endDate)
        return "\(start) - \(end)"
    }
    
    private func formatDay(_ date: Date) -> String {
        Self.monthDayWeekdayFormatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let startDate = calendar.date(byAdding: .day, value: 7, to: today)!
    let endDate = calendar.date(byAdding: .day, value: 13, to: today)!
    
    NavigationStack {
        PendingWeekDetailView(week: WeekModel(weekId: "2026-W06", startDate: startDate, endDate: endDate, status: .pending))
    }
}
