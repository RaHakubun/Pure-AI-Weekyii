import SwiftUI

struct DraftEditorView: View {
    let day: DayModel
    let viewModel: TodayViewModel

    @State private var showingAddSheet = false
    @State private var editingTask: TaskItem?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "draft.title"))
                    .font(.headline)
                Spacer()
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus.circle")
                }
                .disabled(!(day.status == .draft || day.status == .empty))
            }

            if day.sortedDraftTasks.isEmpty {
                Text(String(localized: "draft.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                .frame(minHeight: 120)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            TaskEditorSheet(
                title: String(localized: "draft.add_title"),
                initialTitle: "",
                initialType: .regular
            ) { title, type in
                do {
                    try viewModel.addTask(title: title, type: type)
                    showingAddSheet = false
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(
                title: String(localized: "draft.edit_title"),
                initialTitle: task.title,
                initialType: task.taskType
            ) { newTitle, newType in
                do {
                    try viewModel.updateTask(task, title: newTitle, type: newType)
                    editingTask = nil
                } catch {
                    errorMessage = error.localizedDescription
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

private struct TaskEditorSheet: View {
    let title: String
    @State var initialTitle: String
    @State var initialType: TaskType
    var onSave: (String, TaskType) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "task.title"))) {
                    TextField(String(localized: "task.title.placeholder"), text: $initialTitle)
                }

                Section(header: Text(String(localized: "task.type"))) {
                    Picker(String(localized: "task.type"), selection: $initialType) {
                        ForEach(TaskType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.save")) {
                        onSave(initialTitle, initialType)
                    }
                    .disabled(initialTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
