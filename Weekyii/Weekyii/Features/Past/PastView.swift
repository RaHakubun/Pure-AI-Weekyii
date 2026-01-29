import SwiftUI
import SwiftData

struct PastView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PastViewModel?
    @State private var selectedMonth = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                MonthPickerView(month: $selectedMonth)
                    .padding(.horizontal)

                ScrollView {
                    if let viewModel {
                        let weeks = viewModel.weeks(in: selectedMonth)
                        if weeks.isEmpty {
                            EmptyStateView(
                                title: String(localized: "past.empty.title"),
                                subtitle: String(localized: "past.empty.subtitle"),
                                systemImage: "clock.arrow.circlepath"
                            )
                            .weekyiiCard()
                            .padding()
                        } else {
                            VStack(spacing: 12) {
                                ForEach(weeks) { week in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("\(String(localized: "past.week")) \(week.weekId)")
                                                .font(.headline)
                                            Spacer()
                                            Text("\(String(localized: "past.completed")): \(week.completedTasksCount)")
                                                .font(.caption)
                                            Text("\(String(localized: "past.expired")): \(week.expiredTasksCount)")
                                                .font(.caption)
                                        }

                                        ForEach(week.days.sorted(by: { $0.date < $1.date })) { day in
                                            NavigationLink {
                                                PastDayDetailView(day: day)
                                            } label: {
                                                HStack {
                                                    Text(day.date, format: Date.FormatStyle().weekday(.abbreviated).month().day())
                                                    Spacer()
                                                    StatusBadge(status: day.status)
                                                }
                                                .padding(.vertical, 6)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .weekyiiCard()
                                }
                            }
                            .padding()
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .navigationTitle(String(localized: "past.title"))
        }
        .onAppear {
            if viewModel == nil {
                viewModel = PastViewModel(modelContext: modelContext)
            }
            viewModel?.refresh()
        }
    }
}
