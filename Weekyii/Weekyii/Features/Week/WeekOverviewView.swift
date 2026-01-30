import SwiftUI
import SwiftData

struct WeekOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WeekViewModel?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let week = viewModel?.presentWeek {
                    VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                        // 周统计卡片
                        WeekStatCard(week: week)
                        
                        // 日期网格
                        LazyVGrid(columns: columns, spacing: WeekSpacing.md) {
                            ForEach(week.days.sorted(by: { $0.date < $1.date })) { day in
                                NavigationLink {
                                    DayDetailView(day: day)
                                } label: {
                                    DayCard(day: day)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
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
                    HStack(spacing: WeekSpacing.sm) {
                        WeekLogo(size: .small, animated: false)
                        if let week = viewModel?.presentWeek {
                            Text(week.weekId)
                                .font(.titleSmall)
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = WeekViewModel(modelContext: modelContext, timeProvider: TimeProvider())
            }
            viewModel?.refresh()
        }
    }
}
