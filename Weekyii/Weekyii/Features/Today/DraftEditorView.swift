import SwiftUI

struct DraftEditorView: View {
    let day: DayModel
    let viewModel: TodayViewModel

    @State private var showingAddSheet = false
    @State private var editingTask: TaskItem?
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

    private var isEditing: Bool {
        editMode.isEditing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HStack {
                Text(String(localized: "draft.title"))
                    .font(.titleSmall)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(day.sortedDraftTasks.count)")
                    .font(.titleSmall)
                    .foregroundColor(.weekyiiPrimary)
                EditButton()
                    .disabled(!(day.status == .draft || day.status == .empty))
                    .accessibilityIdentifier("draftEditButton")
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundColor(.weekyiiPrimary)
                }
                .disabled(!(day.status == .draft || day.status == .empty))
            }

            if day.sortedDraftTasks.isEmpty {
                Text(String(localized: "draft.empty"))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, WeekSpacing.lg)
            } else {
                LazyVStack(spacing: WeekSpacing.sm) {
                    ForEach(Array(day.sortedDraftTasks.enumerated()), id: \.element.id) { index, task in
                        rowView(task: task, index: index)
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $showingAddSheet) {
            TaskEditorSheet(
                title: String(localized: "draft.add_title"),
                onSave: { title, description, type, steps, attachments in
                    do {
                        try viewModel.addTask(title: title, description: description, type: type, steps: steps, attachments: attachments)
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
                onSave: { newTitle, newDescription, newType, newSteps, newAttachments in
                    do {
                        try viewModel.updateTask(task, title: newTitle, description: newDescription, type: newType, steps: newSteps, attachments: newAttachments)
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

    private var canReorder: Bool {
        isEditing && day.status == .draft
    }

    @ViewBuilder
    private func rowView(task: TaskItem, index: Int) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            Button(action: { editingTask = task }) {
                TaskRowView(task: task, titleAccessibilityIdentifier: "draftTaskTitle_\(index)")
            }
            .buttonStyle(.plain)
            .disabled(!(day.status == .draft || day.status == .empty))

            if isEditing {
                VStack(spacing: WeekSpacing.xs) {
                    dragHandle(task: task, index: index)

                    Button(role: .destructive, action: { deleteTask(task) }) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func dragHandle(task: TaskItem, index: Int) -> some View {
        let isEnabled = canReorder
        return Image(systemName: "line.3.horizontal")
            .font(.caption)
            .foregroundColor(isEnabled ? .textSecondary : .textTertiary)
            .padding(6)
            .background(Color.backgroundTertiary.opacity(0.8), in: Capsule())
            .accessibilityIdentifier("draftDragHandle_\(index)")
            .opacity(isEditing ? 1 : 0)
            .allowsHitTesting(isEditing)
            .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                guard isEnabled else { return }
                if value.translation.height <= -20 {
                    moveTask(id: task.id, direction: -1)
                } else if value.translation.height >= 20 {
                    moveTask(id: task.id, direction: 1)
                }
            })
    }

    private func moveTask(id taskID: UUID, direction: Int) {
        let tasks = day.sortedDraftTasks
        guard let from = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let to = from + direction
        guard to >= 0, to < tasks.count else { return }

        let destination = direction > 0 ? to + 1 : to
        do {
            try viewModel.moveDraftTasks(from: IndexSet(integer: from), to: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTask(_ task: TaskItem) {
        guard let index = day.sortedDraftTasks.firstIndex(where: { $0.id == task.id }) else { return }
        do {
            try viewModel.deleteTasks(at: IndexSet(integer: index))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
