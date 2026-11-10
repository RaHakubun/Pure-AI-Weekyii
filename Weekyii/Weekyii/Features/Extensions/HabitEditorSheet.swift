import SwiftUI

// MARK: - Habit Editor Sheet - 习惯编辑表单

struct HabitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: HabitViewModel
    let habitToEdit: HabitModel?

    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var category: HabitCategory
    @State private var scheduleKind: HabitScheduleKind
    @State private var selectedWeekdays: Set<Int>
    @State private var selectedMonthDays: Set<Int>
    @State private var startDate: Date
    @State private var nameError: String?
    @State private var scheduleError: String?

    static let iconOptions = [
        "repeat.circle.fill", "figure.walk", "figure.run", "figure.mind.and.body",
        "dumbbell.fill", "book.fill", "pencil.and.outline", "brain.head.profile",
        "leaf.fill", "drop.fill", "moon.stars.fill", "sun.max.fill",
        "heart.fill", "fork.knife", "music.note", "cup.and.saucer.fill"
    ]

    static let colorOptions = [
        "#34C759", "#F08A3C", "#D05C3E", "#8C6AD9",
        "#2F7E79", "#3FA67A", "#D97A6C", "#5AC8FA"
    ]

    init(viewModel: HabitViewModel, habit: HabitModel? = nil) {
        self.viewModel = viewModel
        self.habitToEdit = habit
        _name = State(initialValue: habit?.name ?? "")
        _selectedIcon = State(initialValue: habit?.iconName ?? "repeat.circle.fill")
        _selectedColor = State(initialValue: habit?.colorHex ?? "#34C759")
        _category = State(initialValue: habit?.category ?? .health)
        _scheduleKind = State(initialValue: habit?.scheduleKind ?? .weekly)
        _selectedWeekdays = State(initialValue: habit?.scheduleWeekdays ?? [1, 2, 3, 4, 5])
        _selectedMonthDays = State(initialValue: habit?.scheduleMonthDays ?? [])
        _startDate = State(initialValue: habit?.startDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                    nameCard
                    iconCard
                    colorCard
                    categoryCard
                    scheduleCard
                    startDateCard
                    footerNotes
                }
                .weekPadding(WeekSpacing.base)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle(
                habitToEdit == nil
                    ? String(localized: "habit.editor.create_title", defaultValue: "新建习惯")
                    : String(localized: "habit.editor.edit_title", defaultValue: "编辑习惯")
            )
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("habitEditorSheet")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        habitToEdit == nil
                            ? String(localized: "action.create")
                            : String(localized: "action.save")
                    ) {
                        save()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Name

    private var nameCard: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                Text(String(localized: "habit.editor.name", defaultValue: "名称"))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)

                TextField(String(localized: "habit.editor.name_placeholder", defaultValue: "例如：冥想、跑步"), text: $name)
                    .font(.bodyLarge)
                    .padding(WeekSpacing.md)
                    .background(Color.backgroundTertiary)
                    .clipShape(.rect(cornerRadius: WeekRadius.small))

                if let nameError {
                    Text(nameError)
                        .font(.caption)
                        .foregroundColor(.taskDDL)
                }
            }
        }
    }

    // MARK: - Icon

    private var iconCard: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                Text(String(localized: "habit.editor.icon", defaultValue: "图标"))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: WeekSpacing.sm) {
                    ForEach(Self.iconOptions, id: \.self) { icon in
                        ZStack {
                            RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous)
                                .fill(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.15) : Color.backgroundTertiary)
                                .frame(height: 36)
                            Image(systemName: icon)
                                .font(.system(size: 15))
                                .foregroundColor(selectedIcon == icon ? Color(hex: selectedColor) : .textTertiary)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous)
                                .stroke(selectedIcon == icon ? Color(hex: selectedColor) : .clear, lineWidth: 1.5)
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedIcon = icon
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Color

    private var colorCard: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                Text(String(localized: "habit.editor.color", defaultValue: "颜色"))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: WeekSpacing.sm) {
                    ForEach(Self.colorOptions, id: \.self) { hex in
                        ZStack {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)

                            if selectedColor == hex {
                                Circle()
                                    .stroke(Color.textPrimary, lineWidth: 2.5)
                                    .scaleEffect(1.25)
                                    .frame(width: 32, height: 32)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedColor = hex
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Category

    private var categoryCard: some View {
        WeekCard {
            HStack {
                Text(String(localized: "habit.editor.category", defaultValue: "分类"))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)

                Spacer()

                Picker("", selection: $category) {
                    ForEach(HabitCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color(hex: selectedColor))
            }
        }
    }

    // MARK: - Schedule

    private var scheduleCard: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                Text(String(localized: "habit.editor.schedule", defaultValue: "重复"))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)

                Picker("", selection: $scheduleKind) {
                    ForEach(HabitScheduleKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Color(hex: selectedColor))

                switch scheduleKind {
                case .weekly:
                    weekdaySelector
                case .monthly:
                    monthDaySelector
                case .once:
                    EmptyView()
                }

                if let scheduleError {
                    Text(scheduleError)
                        .font(.caption)
                        .foregroundColor(.taskDDL)
                }
            }
        }
    }

    private var weekdaySelector: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HStack(spacing: WeekSpacing.sm) {
                ForEach(1...7, id: \.self) { weekday in
                    Button {
                        toggleWeekday(weekday)
                    } label: {
                        Text(WeekyiiWeekday.localizedSymbol(for: weekday))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedWeekdays.contains(weekday) ? .white : .textSecondary)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(
                                    selectedWeekdays.contains(weekday)
                                        ? Color(hex: selectedColor)
                                        : Color.backgroundTertiary
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: WeekSpacing.sm) {
                weekdayPreset(String(localized: "habit.schedule.everyday", defaultValue: "每天"), days: Set(1...7))
                weekdayPreset(String(localized: "habit.schedule.weekdays", defaultValue: "工作日"), days: [1, 2, 3, 4, 5])
                weekdayPreset(String(localized: "habit.schedule.weekend", defaultValue: "周末"), days: [6, 7])
            }
        }
    }

    private func weekdayPreset(_ title: String, days: Set<Int>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedWeekdays = days
            }
        } label: {
            Text(title)
                .font(.caption)
                .foregroundColor(selectedWeekdays == days ? .white : .textSecondary)
                .padding(.horizontal, WeekSpacing.md)
                .padding(.vertical, WeekSpacing.xs + 2)
                .background(
                    Capsule().fill(
                        selectedWeekdays == days
                            ? Color(hex: selectedColor)
                            : Color.backgroundTertiary
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var monthDaySelector: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: WeekSpacing.sm) {
            ForEach(1...31, id: \.self) { day in
                Button {
                    toggleMonthDay(day)
                } label: {
                    Text("\(day)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(selectedMonthDays.contains(day) ? .white : .textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous)
                                .fill(
                                    selectedMonthDays.contains(day)
                                        ? Color(hex: selectedColor)
                                        : Color.backgroundTertiary
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Start Date

    private var startDateCard: some View {
        WeekCard {
            DatePicker(
                String(localized: "habit.editor.start_date", defaultValue: "开始日期"),
                selection: $startDate,
                in: startDateRange,
                displayedComponents: .date
            )
            .font(.bodyMedium)
            .tint(Color(hex: selectedColor))
        }
    }

    private var startDateRange: PartialRangeFrom<Date> {
        // 编辑既有习惯时范围必须包含原始开始日，否则 DatePicker 会因越界选择异常。
        if let originalStart = habitToEdit?.startDate, originalStart < Date() {
            return originalStart...
        }
        return Date()...
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerNotes: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            Text(String(localized: "habit.editor.footer", defaultValue: "习惯在当天首次打开 App 时加入草稿区；已开始或已过截止时间的日期不会写入。"))
                .font(.caption2)
                .foregroundColor(.textTertiary)

            if scheduleKind == .monthly {
                Text(String(localized: "habit.editor.monthly_footer", defaultValue: "所选日期在当月不存在时（如 2 月 31 日），该月跳过。"))
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }

            if habitToEdit != nil {
                Text(String(localized: "habit.editor.plan_change_hint", defaultValue: "修改重复计划后会自动重估今日任务。"))
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }
        }
    }

    // MARK: - Actions

    private func toggleWeekday(_ weekday: Int) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedWeekdays.contains(weekday) {
                selectedWeekdays.remove(weekday)
            } else {
                selectedWeekdays.insert(weekday)
            }
        }
    }

    private func toggleMonthDay(_ day: Int) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedMonthDays.contains(day) {
                selectedMonthDays.remove(day)
            } else {
                selectedMonthDays.insert(day)
            }
        }
    }

    private func save() {
        nameError = nil
        scheduleError = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            nameError = HabitError.nameEmpty.errorDescription
            return
        }
        let scheduleHasSelection: Bool
        switch scheduleKind {
        case .weekly: scheduleHasSelection = !selectedWeekdays.isEmpty
        case .monthly: scheduleHasSelection = !selectedMonthDays.isEmpty
        case .once: scheduleHasSelection = true
        }
        guard scheduleHasSelection else {
            scheduleError = HabitError.scheduleEmpty.errorDescription
            return
        }

        do {
            if let habitToEdit {
                try viewModel.updateHabit(
                    habitToEdit,
                    name: trimmedName,
                    iconName: selectedIcon,
                    colorHex: selectedColor,
                    category: category,
                    scheduleKind: scheduleKind,
                    scheduleWeekdays: selectedWeekdays,
                    scheduleMonthDays: selectedMonthDays,
                    startDate: startDate
                )
            } else {
                try viewModel.createHabit(
                    name: trimmedName,
                    iconName: selectedIcon,
                    colorHex: selectedColor,
                    category: category,
                    scheduleKind: scheduleKind,
                    scheduleWeekdays: selectedWeekdays,
                    scheduleMonthDays: selectedMonthDays,
                    startDate: startDate
                )
            }
            dismiss()
        } catch let error as HabitError {
            if error == .scheduleEmpty {
                scheduleError = error.errorDescription
            } else {
                nameError = error.errorDescription
            }
        } catch {
            nameError = error.localizedDescription
        }
    }
}
