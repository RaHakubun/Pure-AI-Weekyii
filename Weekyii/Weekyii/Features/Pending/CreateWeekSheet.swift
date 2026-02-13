import SwiftUI

struct CreateWeekSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var selectedMonth = Date()
    @State private var selectedWeekId: String?
    @State private var selectedMode: Mode = .date
    @State private var createdDay: DayModel?
    @State private var createdWeek: WeekModel?
    @State private var errorMessage: String?
    private let calendar = Calendar(identifier: .iso8601)

    let viewModel: PendingViewModel

    enum Mode: String, CaseIterable {
        case date
        case weekId
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "pending.create.mode"))) {
                    Picker(String(localized: "pending.create.mode"), selection: $selectedMode) {
                        Text(String(localized: "pending.create.by_date")).tag(Mode.date)
                        Text(String(localized: "pending.create.by_week")).tag(Mode.weekId)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedMode == .date {
                    Section(header: Text(String(localized: "pending.create.date"))) {
                        DatePicker(String(localized: "pending.create.date"), selection: $selectedDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                    }
                } else {
                    weekSelectionSection
                }
            }
            .navigationTitle(String(localized: "pending.create.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.create")) {
                        if selectedMode == .date {
                            guard let week = viewModel.createWeek(containing: selectedDate) else {
                                errorMessage = viewModel.errorMessage ?? String(localized: "error.operation_failed_retry")
                                return
                            }
                            guard let day = viewModel.day(in: week, for: selectedDate) else {
                                errorMessage = String(localized: "error.operation_failed_retry")
                                return
                            }
                            createdDay = day
                        } else {
                            guard let selectedWeekId else {
                                errorMessage = "请选择周"
                                return
                            }
                            guard let week = viewModel.createWeek(weekId: selectedWeekId) else {
                                errorMessage = viewModel.errorMessage ?? String(localized: "error.operation_failed_retry")
                                return
                            }
                            createdWeek = week
                        }
                    }
                    .disabled(selectedMode == .weekId && selectedWeekId == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                }
            }
            .navigationDestination(item: $createdDay) { day in
                DayDetailView(day: day)
            }
            .navigationDestination(item: $createdWeek) { week in
                PendingWeekDetailView(week: week)
            }
            .alert(String(localized: "alert.title"), isPresented: Binding(get: {
                errorMessage != nil
            }, set: { newValue in
                if !newValue { errorMessage = nil }
            })) {
                Button(String(localized: "action.ok"), role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var weekSelectionSection: some View {
        Section(header: Text(String(localized: "pending.create.week_id"))) {
            weekMonthHeader

            let options = viewModel.weekOptions(in: selectedMonth)
            ForEach(options) { option in
                Button {
                    guard option.isPast == false, option.isExisting == false else { return }
                    selectedWeekId = option.weekId
                } label: {
                    HStack(spacing: WeekSpacing.sm) {
                        VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                            Text(formattedRange(start: option.startDate, end: option.endDate))
                                .font(.bodyMedium)
                                .foregroundColor(option.isPast ? .textTertiary : .textPrimary)
                            Text(option.weekId)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        if option.isExisting {
                            statusBadge(text: "已创建", color: .accentGreen)
                        } else if option.isPast {
                            statusBadge(text: "不可创建", color: .textTertiary)
                        } else {
                            statusBadge(text: "可创建", color: .weekyiiPrimary)
                        }

                        if selectedWeekId == option.weekId {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.weekyiiPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(option.isPast || option.isExisting)
            }
        }
    }

    private var weekMonthHeader: some View {
        HStack(spacing: 16) {
            Button {
                selectedMonth = previousMonth(from: selectedMonth)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoPreviousMonth)
            .opacity(canGoPreviousMonth ? 1 : 0.3)

            Text(selectedMonth, format: Date.FormatStyle().year().month())
                .font(.headline)
                .frame(maxWidth: .infinity)

            Button {
                selectedMonth = nextMonth(from: selectedMonth)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }

    private var canGoPreviousMonth: Bool {
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let selectedMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        return selectedMonthStart > currentMonthStart
    }

    private func previousMonth(from date: Date) -> Date {
        calendar.date(byAdding: .month, value: -1, to: date) ?? date
    }

    private func nextMonth(from date: Date) -> Date {
        calendar.date(byAdding: .month, value: 1, to: date) ?? date
    }

    private func formattedRange(start: Date, end: Date) -> String {
        "\(start.formatted(Date.FormatStyle().month().day())) - \(end.formatted(Date.FormatStyle().month().day()))"
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, WeekSpacing.sm)
            .padding(.vertical, WeekSpacing.xxs)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
