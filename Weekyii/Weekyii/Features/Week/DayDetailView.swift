import SwiftUI
import SwiftData

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    let day: DayModel

    @State private var showingAddSheet = false
    @State private var editingTask: TaskItem?
    @State private var errorMessage: String?

    private var isEditable: Bool {
        let calendar = Calendar(identifier: .iso8601)
        let today = calendar.startOfDay(for: TimeProvider().today)
        let targetDay = calendar.startOfDay(for: day.date)
        return targetDay >= today && (day.status == .empty || day.status == .draft)
    }

    private var isEditingDraft: Bool {
        (editMode?.wrappedValue.isEditing ?? false) && isEditable
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                switch day.status {
                case .empty:
                    EmptyStateView(
                        title: String(localized: "day.empty.title"),
                        subtitle: String(localized: "day.empty.subtitle"),
                        systemImage: "square.and.pencil"
                    )
                    .weekyiiCard()
                case .draft:
                    draftSection
                case .execute:
                    FocusZoneView(task: day.focusTask)
                        .weekyiiCard()
                    FrozenZoneView(tasks: day.frozenTasks)
                        .weekyiiCard()
                    CompleteZoneView(tasks: day.completedTasks)
                        .weekyiiCard()
                case .completed:
                    CompleteZoneView(tasks: day.completedTasks)
                        .weekyiiCard()
                case .expired:
                    CompleteZoneView(tasks: day.completedTasks)
                        .weekyiiCard()
                    expiredSection
                }
            }
            .padding()
        }
        .navigationTitle(day.dayId)
        .toolbar {
            if isEditable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            TaskEditorSheet(
                title: String(localized: "draft.add_title"),
                onSave: { title, description, type, steps, attachments in
                    do {
                        try addTask(title: title, description: description, type: type, steps: steps, attachments: attachments)
                        showingAddSheet = false
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            )
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(
                title: String(localized: "draft.edit_title"),
                initialTitle: task.title,
                initialDescription: task.taskDescription,
                initialType: task.taskType,
                initialSteps: task.steps,
                initialAttachments: task.attachments,
                onSave: { title, description, type, steps, attachments in
                    do {
                        try updateTask(task, title: title, description: description, type: type, steps: steps, attachments: attachments)
                        editingTask = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            )
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.date, format: Date.FormatStyle().weekday(.abbreviated).month().day().year())
                .font(.headline)
            StatusBadge(status: day.status)
        }
        .weekyiiCard()
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if day.sortedDraftTasks.isEmpty {
                EmptyStateView(
                    title: String(localized: "day.empty.title"),
                    subtitle: String(localized: "day.empty.subtitle"),
                    systemImage: "square.and.pencil"
                )
                .weekyiiCard()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(day.sortedDraftTasks.enumerated()), id: \.element.id) { index, task in
                        HStack(spacing: WeekSpacing.sm) {
                            Button(action: { editingTask = task }) {
                                TaskRowView(task: task, showsProjectOrigin: true)
                            }
                            .buttonStyle(.plain)
                            .disabled(!isEditable || isEditingDraft)

                            if isEditingDraft {
                                HStack(spacing: WeekSpacing.xs) {
                                    Button(action: {
                                        do {
                                            try moveDraftTasks(from: IndexSet(integer: index), to: index - 1)
                                        } catch {
                                            errorMessage = error.localizedDescription
                                        }
                                    }) {
                                        Image(systemName: "arrow.up")
                                    }
                                    .disabled(index == 0)

                                    Button(action: {
                                        do {
                                            try moveDraftTasks(from: IndexSet(integer: index), to: index + 2)
                                        } catch {
                                            errorMessage = error.localizedDescription
                                        }
                                    }) {
                                        Image(systemName: "arrow.down")
                                    }
                                    .disabled(index == day.sortedDraftTasks.count - 1)

                                    Button(role: .destructive, action: {
                                        do {
                                            try deleteTasks(at: IndexSet(integer: index))
                                        } catch {
                                            errorMessage = error.localizedDescription
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                    }
                                }
                                .foregroundColor(.accentOrange)
                                .font(.caption)
                                .padding(.trailing, WeekSpacing.sm)
                            }
                        }
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(WeekRadius.medium)
            }
        }
    }

    private var expiredSection: some View {
        HStack {
            Text(String(localized: "expired.count"))
            Spacer()
            Text("\(day.expiredCount)")
                .fontWeight(.semibold)
        }
        .weekyiiCard()
    }

    private func addTask(title: String, description: String, type: TaskType, steps: [TaskStep], attachments: [TaskAttachment]) throws {
        guard isEditable else { throw WeekyiiError.cannotEditStartedDay }
        if day.status == .empty {
            day.status = .draft
        }
        let order = (day.sortedDraftTasks.last?.order ?? 0) + 1
        let task = TaskItem(
            title: title,
            taskDescription: description,
            taskType: type,
            order: order,
            zone: .draft
        )
        task.steps = normalizedStepCopies(from: steps)
        task.attachments = attachments
        day.tasks.append(task)
        try modelContext.save()
    }

    private func updateTask(_ task: TaskItem, title: String, description: String, type: TaskType, steps: [TaskStep], attachments: [TaskAttachment]) throws {
        guard isEditable else { throw WeekyiiError.cannotEditStartedDay }
        task.title = title
        task.taskDescription = description
        task.taskType = type
        replaceSteps(for: task, with: steps)
        task.attachments = attachments
        try modelContext.save()
    }

    private func deleteTasks(at offsets: IndexSet) throws {
        guard isEditable else { throw WeekyiiError.cannotEditStartedDay }
        let tasks = day.sortedDraftTasks
        let tasksToDelete = offsets.compactMap { index in
            tasks.indices.contains(index) ? tasks[index] : nil
        }
        day.tasks.removeAll { task in
            tasksToDelete.contains { $0.id == task.id }
        }
        for task in tasksToDelete {
            modelContext.delete(task)
        }
        renumberDraftTasks()
        try modelContext.save()
    }

    private func moveDraftTasks(from source: IndexSet, to destination: Int) throws {
        guard isEditable else { throw WeekyiiError.cannotEditStartedDay }
        var tasks = day.sortedDraftTasks
        tasks.move(fromOffsets: source, toOffset: destination)
        for (index, task) in tasks.enumerated() {
            task.order = index + 1
        }
        try modelContext.save()
    }

    private func renumberDraftTasks() {
        let sorted = day.sortedDraftTasks
        for (index, task) in sorted.enumerated() {
            task.order = index + 1
        }
    }

    private func replaceSteps(for task: TaskItem, with steps: [TaskStep]) {
        task.steps.forEach { modelContext.delete($0) }
        task.steps = normalizedStepCopies(from: steps)
    }

    private func normalizedStepCopies(from steps: [TaskStep]) -> [TaskStep] {
        steps
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
            .enumerated()
            .map { index, step in
                TaskStep(
                    title: step.title,
                    isCompleted: step.isCompleted,
                    sortOrder: index
                )
            }
    }
}
