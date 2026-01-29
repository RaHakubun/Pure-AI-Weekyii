import SwiftUI
import SwiftData

struct WeekOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WeekViewModel?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let week = viewModel?.presentWeek {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(week.days.sorted(by: { $0.date < $1.date })) { day in
                            NavigationLink {
                                DayDetailView(day: day)
                            } label: {
                                DayCardView(day: day)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "week.title"))
        }
        .onAppear {
            if viewModel == nil {
                viewModel = WeekViewModel(modelContext: modelContext, timeProvider: TimeProvider())
            }
            viewModel?.refresh()
        }
    }
}
