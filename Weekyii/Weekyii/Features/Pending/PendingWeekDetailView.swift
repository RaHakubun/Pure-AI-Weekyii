import SwiftUI

// MARK: - PendingWeekDetailView - 未来周详情页

struct PendingWeekDetailView: View {
    let week: WeekModel
    @State private var selectedDayId: String = ""
    private let calendar = Calendar(identifier: .iso8601)

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

    private var sortedDays: [DayModel] {
        week.days.sorted { $0.date < $1.date }
    }

    private var selectedDay: DayModel? {
        sortedDays.first(where: { $0.dayId == selectedDayId }) ?? sortedDays.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                overviewAndDayPickerCard

                if let selectedDay {
                    selectedDayDetailCard(selectedDay)
                }
            }
            .weekPadding(WeekSpacing.base)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle(week.relativeWeekLabel())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            initializeDaySelectionIfNeeded()
        }
    }

    // MARK: - Overview + Day Picker Card

    private var overviewAndDayPickerCard: some View {
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

                Divider()
                    .padding(.vertical, WeekSpacing.xxs)

                HStack(alignment: .firstTextBaseline, spacing: WeekSpacing.sm) {
                    Text(String(localized: "pending.timeline.title"))
                        .font(.bodyMedium.weight(.semibold))
                        .foregroundColor(.textPrimary)

                    Spacer()

                    if let selectedDay {
                        Text(Self.monthDayWeekdayFormatter.string(from: selectedDay.date))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }

                dayPickerStrip
            }
        }
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

    private var dayPickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WeekSpacing.sm) {
                ForEach(sortedDays) { day in
                    dayPickerChip(day)
                }
            }
            .padding(.horizontal, WeekSpacing.xs)
            .padding(.vertical, WeekSpacing.xs)
        }
        .background(Color.backgroundTertiary.opacity(0.5))
        .clipShape(.rect(cornerRadius: WeekRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium)
                .stroke(Color.backgroundTertiary, lineWidth: 1)
        )
    }

    private func dayPickerChip(_ day: DayModel) -> some View {
        let isSelected = day.dayId == selectedDay?.dayId
        let hasAnyTasks = !tasksForDisplay(in: day).isEmpty

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedDayId = day.dayId
            }
        } label: {
            VStack(spacing: WeekSpacing.xxs) {
                Text(weekdaySymbol(for: day.date))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? .white : .textPrimary)

                Text(Self.monthDayFormatter.string(from: day.date))
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .textSecondary)

                Circle()
                    .fill(hasAnyTasks ? (isSelected ? .white : .taskDDL) : .clear)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 60, height: 70)
            .background(isSelected ? Color.weekyiiPrimary : Color.backgroundSecondary)
            .clipShape(.rect(cornerRadius: WeekRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.medium)
                    .stroke(isSelected ? Color.weekyiiPrimary : Color.backgroundTertiary, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func selectedDayDetailCard(_ day: DayModel) -> some View {
        let displayTasks = tasksForDisplay(in: day)

        return WeekCard(accentColor: day.status.color) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(alignment: .center, spacing: WeekSpacing.sm) {
                    Text(Self.monthDayWeekdayFormatter.string(from: day.date))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    StatusBadge(status: day.status)
                }

                HStack(spacing: WeekSpacing.xs) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text(String(format: String(localized: "project.tasks.count"), Int64(displayTasks.count)))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }

                if displayTasks.isEmpty {
                    Text(String(localized: "pending.week.add_tasks"))
                        .font(.bodyMedium)
                        .foregroundColor(.textTertiary)
                } else {
                    VStack(spacing: WeekSpacing.sm) {
                        ForEach(displayTasks) { task in
                            TaskRowView(task: task)
                        }
                    }
                }
            }
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

    private func initializeDaySelectionIfNeeded() {
        guard !sortedDays.isEmpty else { return }
        if sortedDays.contains(where: { $0.dayId == selectedDayId }) {
            return
        }
        if let firstDraft = sortedDays.first(where: { $0.status == .draft }) {
            selectedDayId = firstDraft.dayId
        } else if let firstDay = sortedDays.first {
            selectedDayId = firstDay.dayId
        }
    }

    private func weekdaySymbol(for date: Date) -> String {
        let weekdayIndex = calendar.component(.weekday, from: date) - 1
        let symbols = calendar.veryShortWeekdaySymbols
        if symbols.indices.contains(weekdayIndex) {
            return symbols[weekdayIndex]
        }
        return ""
    }

    private func tasksForDisplay(in day: DayModel) -> [TaskItem] {
        day.tasks.sorted { lhs, rhs in
            if lhs.zone == rhs.zone {
                if lhs.zone == .complete {
                    return lhs.completedOrder < rhs.completedOrder
                }
                return lhs.order < rhs.order
            }
            return zonePriority(lhs.zone) < zonePriority(rhs.zone)
        }
    }

    private func zonePriority(_ zone: TaskZone) -> Int {
        switch zone {
        case .draft: return 0
        case .focus: return 1
        case .frozen: return 2
        case .complete: return 3
        }
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
