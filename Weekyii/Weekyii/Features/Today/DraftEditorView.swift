import SwiftUI

struct DraftEditorView: View {
    let day: DayModel
    let viewModel: TodayViewModel

    @State private var showingAddSheet = false
    @State private var editingTask: TaskItem?
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HStack {
                Text(String(localized: "draft.title"))
                    .font(.titleSmall)
                    .foregroundColor(.textPrimary)
                Spacer()
                EditButton()
                    .disabled(!(day.status == .draft || day.status == .empty))
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
                List {
                    ForEach(day.sortedDraftTasks) { task in
                        Button(action: { editingTask = task }) {
                            TaskRowView(task: task)
                        }
                        .disabled(!(day.status == .draft || day.status == .empty))
                    }
                    .onDelete { offsets in
                        do {
                            try viewModel.deleteTasks(at: offsets)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .onMove { source, destination in
                        do {
                            try viewModel.moveDraftTasks(from: source, to: destination)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(min(day.sortedDraftTasks.count, 8)) * 60)
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
}

