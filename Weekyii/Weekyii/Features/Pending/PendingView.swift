import SwiftUI
import SwiftData

struct PendingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PendingViewModel?
    @State private var selectedMonth = Date()
    @State private var showingCreateSheet = false

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
                                title: String(localized: "pending.empty.title"),
                                subtitle: String(localized: "pending.empty.subtitle"),
                                systemImage: "calendar.badge.plus"
                            )
                            .weekyiiCard()
                            .padding()
                        } else {
                            VStack(spacing: 12) {
                                ForEach(weeks) { week in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(String(localized: "pending.week")) \(week.weekId)")
                                            .font(.headline)

                                        ForEach(week.days.sorted(by: { $0.date < $1.date })) { day in
                                            NavigationLink {
                                                DayDetailView(day: day)
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
            .navigationTitle(String(localized: "pending.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                if let viewModel {
                    CreateWeekSheet(viewModel: viewModel)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = PendingViewModel(modelContext: modelContext)
            }
            viewModel?.refresh()
        }
    }
}
