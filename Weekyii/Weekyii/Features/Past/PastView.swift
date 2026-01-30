import SwiftUI
import SwiftData

struct PastView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PastViewModel?
    @State private var selectedMonth = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                if let viewModel {
                    VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                        // 月份选择器（限制只能看过去和当前月份）
                        MonthPickerView(month: $selectedMonth, restriction: .pastOnly)
                        
                        // 周列表
                        let weeks = viewModel.weeks(in: selectedMonth)
                        if weeks.isEmpty {
                            emptyStateView
                        } else {
                            weeksList(weeks: weeks)
                        }
                    }
                    .weekPadding(WeekSpacing.base)
                } else {
                    ProgressView()
                }
            }
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WeekLogo(size: .small, animated: false)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = PastViewModel(modelContext: modelContext)
            }
            viewModel?.refresh()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.weekyiiGradient)
                
                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "past.empty.title"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                    
                    Text(String(localized: "past.empty.subtitle"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
    }
    
    // MARK: - Weeks List
    
    private func weeksList(weeks: [WeekModel]) -> some View {
        VStack(spacing: WeekSpacing.md) {
            // 统计卡片
            WeekCard(accentColor: .accentGreen) {
                HStack {
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        Text(String(localized: "past.total_weeks"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text("\(weeks.count)")
                            .font(.titleLarge)
                            .foregroundColor(.accentGreen)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.accentGreen.opacity(0.3))
                }
            }
            
            // 周卡片列表
            ForEach(weeks) { week in
                pastWeekCard(week: week)
            }
        }
    }
    
    // MARK: - Past Week Card
    
    private func pastWeekCard(week: WeekModel) -> some View {
        NavigationLink {
            PastWeekDetailView(week: week)
        } label: {
            WeekCard {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    // 周标题
                    HStack {
                        Text(week.weekId)
                            .font(.titleSmall)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                    
                    // 完成统计
                    HStack(spacing: WeekSpacing.lg) {
                        VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                            Text(String(localized: "past.completed"))
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Text("\(week.completedTasksCount)")
                                .font(.titleMedium)
                                .foregroundColor(.accentGreen)
                        }
                        
                        VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                            Text(String(localized: "past.expired"))
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Text("\(week.expiredTasksCount)")
                                .font(.titleMedium)
                                .foregroundColor(.taskDDL)
                        }
                    }
                    
                    // 进度条
                    let totalTasks = week.completedTasksCount + week.expiredTasksCount
                    if totalTasks > 0 {
                        let completionRate = Double(week.completedTasksCount) / Double(totalTasks)
                        ProgressBar(progress: completionRate, showPercentage: true)
                    }
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct PastWeekDetailView: View {
    let week: WeekModel
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
        .navigationTitle(week.weekId)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sortedDays: [DayModel] {
        week.days.sorted { $0.date < $1.date }
    }

    private var completedTasksCount: Int {
        week.days.reduce(0) { $0 + $1.completedTasks.count }
    }

    private var expiredTasksCount: Int {
        week.days.reduce(0) { $0 + $1.expiredCount }
    }

    private var startedDaysCount: Int {
        week.days.filter { [.execute, .completed, .expired].contains($0.status) }.count
    }

    private var summaryCard: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                Text(String(localized: "past.week.summary"))
                    .font(.titleSmall)
                    .foregroundColor(.textPrimary)

                Text(formatDateRange())
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)

                HStack(spacing: WeekSpacing.lg) {
                    statBlock(title: String(localized: "past.completed"), value: completedTasksCount, color: .accentGreen)
                    statBlock(title: String(localized: "past.expired"), value: expiredTasksCount, color: .taskDDL)
                    statBlock(title: String(localized: "past.week.started_days"), value: startedDaysCount, color: .weekyiiPrimary)
                }
            }
        }
    }

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

    private func dayCard(_ day: DayModel) -> some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    Text(formatDay(day.date))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    StatusBadge(status: day.status)
                }

                HStack(spacing: WeekSpacing.lg) {
                    statBlock(title: String(localized: "past.completed"), value: day.completedTasks.count, color: .accentGreen)
                    statBlock(title: String(localized: "past.expired"), value: day.expiredCount, color: .taskDDL)
                }

                if day.completedTasks.isEmpty && day.expiredCount == 0 {
                    Text(String(localized: "past.week.no_records"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                } else {
                    if !day.completedTasks.isEmpty {
                        Text(String(localized: "past.week.completed_list"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        VStack(spacing: WeekSpacing.sm) {
                            ForEach(day.completedTasks) { task in
                                TaskRowView(task: task)
                            }
                        }
                    }

                    if day.expiredCount > 0 {
                        Text(String(format: String(localized: "past.week.expired_count"), day.expiredCount))
                            .font(.caption)
                            .foregroundColor(.taskDDL)
                    }
                }
            }
        }
    }

    private func formatDateRange() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let start = formatter.string(from: week.startDate)
        let end = formatter.string(from: week.endDate)
        return "\(start) - \(end)"
    }

    private func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 E"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}
