import SwiftUI

struct AddProjectTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: ProjectModel
    let viewModel: ExtensionsViewModel

    @State private var title = ""
    @State private var taskType: TaskType = .regular
    @State private var selectedDates: Set<DateComponents> = []
    @State private var currentMonth = Date()
    @State private var errorMessage: String?

    private let calendar = Calendar(identifier: .iso8601)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                    // 任务名称
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            Text(String(localized: "project.task.name"))
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)
                            TextField(String(localized: "project.task.name.placeholder"), text: $title)
                                .font(.bodyLarge)
                                .padding(WeekSpacing.md)
                                .background(Color.backgroundTertiary)
                                .cornerRadius(WeekRadius.small)
                        }
                    }

                    // 任务类型
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            Text(String(localized: "project.task.type"))
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)

                            HStack(spacing: WeekSpacing.sm) {
                                ForEach(TaskType.allCases, id: \.self) { type in
                                    Button {
                                        taskType = type
                                    } label: {
                                        HStack(spacing: WeekSpacing.xs) {
                                            Image(systemName: type.iconName)
                                                .font(.caption)
                                            Text(type.displayName)
                                                .font(.bodyMedium)
                                        }
                                        .foregroundColor(taskType == type ? .white : type.color)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, WeekSpacing.md)
                                        .padding(.vertical, WeekSpacing.sm)
                                        .background(taskType == type ? type.color : type.color.opacity(0.1))
                                        .cornerRadius(WeekRadius.small)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // 日期选择
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            HStack {
                                Text(String(localized: "project.task.dates"))
                                    .font(.bodyMedium)
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                if !selectedDates.isEmpty {
                                    Text(String(format: String(localized: "project.task.dates.count"), selectedDates.count))
                                        .font(.caption)
                                        .foregroundColor(Color(hex: project.color))
                                }
                            }

                            multiDateCalendar
                        }
                    }

                    // 选中的日期预览
                    if !selectedDates.isEmpty {
                        WeekCard {
                            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                                Text(String(localized: "project.task.selected_dates"))
                                    .font(.bodyMedium)
                                    .foregroundColor(.textSecondary)

                                FlowLayout(spacing: WeekSpacing.xs) {
                                    ForEach(sortedSelectedDates, id: \.self) { dc in
                                        if let date = calendar.date(from: dc) {
                                            Text(date, format: .dateTime.month().day())
                                                .font(.caption)
                                                .foregroundColor(Color(hex: project.color))
                                                .padding(.horizontal, WeekSpacing.sm)
                                                .padding(.vertical, WeekSpacing.xs)
                                                .background(Color(hex: project.color).opacity(0.1))
                                                .clipShape(Capsule())
                                                .onTapGesture {
                                                    selectedDates.remove(dc)
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .weekPadding(WeekSpacing.base)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle(String(localized: "project.task.add.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.create")) {
                        createTasks()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedDates.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                }
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

    private var sortedSelectedDates: [DateComponents] {
        selectedDates.sorted {
            let d1 = calendar.date(from: $0) ?? Date.distantPast
            let d2 = calendar.date(from: $1) ?? Date.distantPast
            return d1 < d2
        }
    }

    private func createTasks() {
        var firstFailureMessage: String?
        for dc in sortedSelectedDates {
            guard let date = calendar.date(from: dc) else { continue }
            let result = viewModel.addTask(
                to: project,
                title: title.trimmingCharacters(in: .whitespaces),
                taskType: taskType,
                on: date
            )
            if result == nil, firstFailureMessage == nil {
                firstFailureMessage = viewModel.errorMessage ?? String(localized: "error.operation_failed_retry")
            }
        }

        if let firstFailureMessage {
            errorMessage = firstFailureMessage
        } else {
            dismiss()
        }
    }

    // MARK: - Multi-Date Calendar

    private var multiDateCalendar: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        let weekdaySymbols: [String] = {
            var cal = Calendar(identifier: .iso8601)
            cal.locale = Locale.current
            return cal.shortWeekdaySymbols
        }()

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingOffset = firstWeekday - 1

        struct CalDay: Identifiable {
            let date: Date
            let isCurrent: Bool
            var id: String { date.dayId + (isCurrent ? "c" : "o") }
        }

        var days: [CalDay] = []
        if leadingOffset > 0 {
            for i in (1...leadingOffset).reversed() {
                guard let d = calendar.date(byAdding: .day, value: -i, to: monthStart) else { continue }
                days.append(CalDay(date: d, isCurrent: false))
            }
        }
        var cursor = monthStart
        while cursor < monthEnd {
            days.append(CalDay(date: cursor, isCurrent: true))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? monthEnd
        }
        let remainder = days.count % 7
        if remainder > 0 {
            for i in 0..<(7 - remainder) {
                guard let d = calendar.date(byAdding: .day, value: i, to: monthEnd) else { continue }
                days.append(CalDay(date: d, isCurrent: false))
            }
        }

        return VStack(spacing: WeekSpacing.sm) {
            // 月份导航
            HStack {
                HStack(spacing: 4) {
                    Text(monthStart, format: .dateTime.year().month())
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                }

                Spacer()

                HStack(spacing: WeekSpacing.lg) {
                    Button {
                        withAnimation { currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(monthStart <= (calendar.date(from: calendar.dateComponents([.year, .month], from: project.startDate)) ?? project.startDate))

                    Button {
                        withAnimation { currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth }
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(monthStart >= (calendar.date(from: calendar.dateComponents([.year, .month], from: project.endDate)) ?? project.endDate))
                }
            }

            // 星期标题
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s).font(.caption).foregroundColor(.textTertiary).frame(maxWidth: .infinity)
                }
            }

            // 日期网格
            LazyVGrid(columns: columns, spacing: WeekSpacing.xs) {
                ForEach(days) { day in
                    let dc = calendar.dateComponents([.year, .month, .day], from: day.date)
                    let isSelected = selectedDates.contains(dc)
                    let dayNum = calendar.component(.day, from: day.date)
                    let isToday = calendar.isDateInToday(day.date)
                    
                    let dayDate = calendar.startOfDay(for: day.date)
                    let today = calendar.startOfDay(for: Date())
                    let projectStart = calendar.startOfDay(for: project.startDate)
                    let projectEnd = calendar.startOfDay(for: project.endDate)
                    let isWithinProject = dayDate >= projectStart && dayDate <= projectEnd
                    let isPast = dayDate < today
                    let isSelectable = day.isCurrent && isWithinProject && !isPast

                    Button {
                        if isSelectable {
                            if isSelected {
                                selectedDates.remove(dc)
                            } else {
                                selectedDates.insert(dc)
                            }
                        }
                    } label: {
                        ZStack {
                            if isSelected && day.isCurrent && isWithinProject {
                                Circle()
                                    .fill(Color(hex: project.color))
                                    .frame(width: 34, height: 34)
                            } else if isToday && day.isCurrent {
                                Circle()
                                    .stroke(Color(hex: project.color), lineWidth: 1.5)
                                    .frame(width: 34, height: 34)
                            }

                            Text("\(dayNum)")
                                .font(.body)
                                .foregroundColor(
                                    (!isSelectable) ? .textTertiary.opacity(0.3) :
                                    isSelected ? .white :
                                    isToday ? Color(hex: project.color) :
                                    .textPrimary
                                )
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSelectable)
                }
            }
        }
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
