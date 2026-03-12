import SwiftUI
import SwiftData

// MARK: - PendingWeekDetailView - 未来周详情页

struct PendingWeekDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    let week: WeekModel

    @State private var selectedDayId: String = ""
    @State private var viewModel: PendingViewModel?
    @State private var showingAddSheet = false
    @State private var editingTask: TaskItem?
    @State private var deletingTask: TaskItem?
    @State private var errorMessage: String?

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

    private var isSelectedDayEditable: Bool {
        guard let selectedDay, let viewModel else { return false }
        return viewModel.canEdit(selectedDay)
    }

    private var isEditingDraft: Bool {
        (editMode?.wrappedValue.isEditing ?? false) && isSelectedDayEditable
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
        .toolbar { draftToolbar }
        .onAppear {
            if viewModel == nil {
                viewModel = PendingViewModel(modelContext: modelContext)
            }
            initializeDaySelectionIfNeeded()
        }
        .sheet(isPresented: $showingAddSheet) {
            if let selectedDay {
                TaskEditorSheet(
                    title: String(localized: "draft.add_title"),
                    onSave: { title, description, type, steps, attachments in
                        guard let viewModel else { return }
                        do {
                            try viewModel.addDraftTask(
                                to: selectedDay,
                                title: title,
                                description: description,
                                type: type,
                                steps: steps,
                                attachments: attachments
                            )
                            showingAddSheet = false
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
            }
        }
        .sheet(item: $editingTask) { task in
            if let selectedDay {
                TaskEditorSheet(
                    title: String(localized: "draft.edit_title"),
                    initialTitle: task.title,
                    initialDescription: task.taskDescription,
                    initialType: task.taskType,
                    initialSteps: task.steps,
                    initialAttachments: task.attachments,
                    onSave: { title, description, type, steps, attachments in
                        guard let viewModel else { return }
                        do {
                            try viewModel.updateDraftTask(
                                task,
                                in: selectedDay,
                                title: title,
                                description: description,
                                type: type,
                                steps: steps,
                                attachments: attachments
                            )
                            editingTask = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
            }
        }
        .confirmationDialog(
            String(localized: "project.task.delete.confirm"),
            isPresented: Binding(
                get: { deletingTask != nil },
                set: { if !$0 { deletingTask = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "project.task.delete.action"), role: .destructive) {
                confirmDeleteSelectedTask()
            }

            Button(String(localized: "action.cancel"), role: .cancel) {
                deletingTask = nil
            }
        } message: {
            Text(String(localized: "project.task.delete.message"))
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

    @ToolbarContentBuilder
    private var draftToolbar: some ToolbarContent {
        if isSelectedDayEditable {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditingDraft ? String(localized: "action.done") : String(localized: "action.edit")) {
                    editMode?.wrappedValue = isEditingDraft ? .inactive : .active
                }
                .accessibilityIdentifier("pendingDraftEditButton")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityIdentifier("pendingDraftAddButton")
            }
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
                if isEditingDraft {
                    editMode?.wrappedValue = .inactive
                }
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
                    emptyDraftState
                } else if isSelectedDayEditable {
                    PendingEditableDraftTaskList(
                        tasks: displayTasks,
                        isEditingDraft: isEditingDraft,
                        onTaskTap: { task in
                            if !isEditingDraft {
                                editingTask = task
                            }
                        },
                        onMoveUp: { index in
                            do {
                                try viewModel?.moveDraftTasks(in: day, from: IndexSet(integer: index), to: index - 1)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        },
                        onMoveDown: { index in
                            do {
                                try viewModel?.moveDraftTasks(in: day, from: IndexSet(integer: index), to: index + 2)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        },
                        onDelete: { index in
                            guard displayTasks.indices.contains(index) else { return }
                            deletingTask = displayTasks[index]
                        }
                    )
                } else {
                    readOnlyTaskList(displayTasks)
                }
            }
        }
    }

    private var emptyDraftState: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            Text(String(localized: "pending.week.add_tasks"))
                .font(.bodyMedium)
                .foregroundColor(.textTertiary)

            if isSelectedDayEditable {
                Button {
                    showingAddSheet = true
                } label: {
                    Label(String(localized: "action.add"), systemImage: "plus.circle.fill")
                        .font(.bodyMedium.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.weekyiiPrimary)
                .accessibilityIdentifier("pendingDraftInlineAddButton")
            }
        }
    }

    private func readOnlyTaskList(_ tasks: [TaskItem]) -> some View {
        VStack(spacing: WeekSpacing.sm) {
            ForEach(tasks, id: \.id) { task in
                TaskRowView(task: task)
            }
        }
    }

    private var draftDaysCount: Int {
        week.days.filter { $0.status == .draft }.count
    }

    private var emptyDaysCount: Int {
        week.days.filter { $0.status == .empty }.count
    }

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

    private func confirmDeleteSelectedTask() {
        guard let deletingTask, let selectedDay else { return }
        let currentDraftTasks = selectedDay.sortedDraftTasks
        guard let index = currentDraftTasks.firstIndex(where: { $0.id == deletingTask.id }) else {
            self.deletingTask = nil
            return
        }

        do {
            try viewModel?.deleteDraftTasks(in: selectedDay, at: IndexSet(integer: index))
            self.deletingTask = nil
        } catch {
            self.deletingTask = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct PendingEditableDraftTaskList: View {
    let tasks: [TaskItem]
    let isEditingDraft: Bool
    let onTaskTap: (TaskItem) -> Void
    let onMoveUp: (Int) -> Void
    let onMoveDown: (Int) -> Void
    let onDelete: (Int) -> Void

    var body: some View {
        let indices = Array(tasks.indices)
        VStack(spacing: WeekSpacing.sm) {
            SwiftUI.ForEach<[Int], Int, PendingEditableDraftTaskRow>(indices, id: \.self) { index in
                PendingEditableDraftTaskRow(
                    index: index,
                    task: tasks[index],
                    taskCount: tasks.count,
                    isEditingDraft: isEditingDraft,
                    onTaskTap: { onTaskTap(tasks[index]) },
                    onMoveUp: { onMoveUp(index) },
                    onMoveDown: { onMoveDown(index) },
                    onDelete: { onDelete(index) }
                )
            }
        }
    }
}

private struct PendingEditableDraftTaskRow: View {
    let index: Int
    let task: TaskItem
    let taskCount: Int
    let isEditingDraft: Bool
    let onTaskTap: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: WeekSpacing.sm) {
            Button {
                onTaskTap()
            } label: {
                TaskRowView(task: task)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(isEditingDraft)
            .accessibilityIdentifier("pendingDraftTask_\(index)")

            if isEditingDraft {
                HStack(spacing: WeekSpacing.xs) {
                    Button {
                        onMoveUp()
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(index == 0)

                    Button {
                        onMoveDown()
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(index == taskCount - 1)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityIdentifier("pendingDraftDeleteButton_\(index)")
                }
                .foregroundStyle(Color.accentOrange)
                .font(.caption)
                .padding(.trailing, WeekSpacing.sm)
            }
        }
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let startDate = calendar.date(byAdding: .day, value: 7, to: today)!
    let endDate = calendar.date(byAdding: .day, value: 13, to: today)!

    NavigationStack {
        PendingWeekDetailView(week: WeekModel(weekId: "2026-W06", startDate: startDate, endDate: endDate, status: .pending))
    }
}
