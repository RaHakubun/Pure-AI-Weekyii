import SwiftUI
import SwiftData

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let day: DayModel

    @State private var showingAddSheet = false
    @State private var editingTask: TaskItem?
    @State private var errorMessage: String?

    private var isEditable: Bool {
        let today = TimeProvider().today
        return day.date >= today && (day.status == .empty || day.status == .draft)
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
                initialTitle: "",
                initialType: .regular
            ) { title, type in
                do {
                    try addTask(title: title, type: type)
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
            ) { title, type in
                do {
                    try updateTask(task, title: title, type: type)
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
            Text(String(localized: "draft.title"))
                .font(.headline)

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
                        .disabled(!isEditable)
                    }
                    .onDelete { offsets in
                        do {
                            try deleteTasks(at: offsets)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .onMove { source, destination in
                        do {
                            try moveDraftTasks(from: source, to: destination)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 120)
            }
        }
        .weekyiiCard()
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

    private func addTask(title: String, type: TaskType) throws {
        guard isEditable else { throw WeekyiiError.cannotEditStartedDay }
        if day.status == .empty {
            day.status = .draft
        }
        let order = (day.sortedDraftTasks.last?.order ?? 0) + 1
        let task = TaskItem(title: title, taskType: type, order: order, zone: .draft)
        task.day = day
        day.tasks.append(task)
        try? modelContext.save()
    }

    private func updateTask(_ task: TaskItem, title: String, type: TaskType) throws {
        guard isEditable else { throw WeekyiiError.cannotEditStartedDay }
        task.title = title
        task.taskType = type
        try? modelContext.save()
    }

    private func deleteTasks(at offsets: IndexSet) throws {
        guard isEditable else { throw WeekyiiError.cannotEditStartedDay }
        let tasks = day.sortedDraftTasks
        for index in offsets {
            let task = tasks[index]
            modelContext.delete(task)
        }
        renumberDraftTasks()
        try? modelContext.save()
    }

    private func moveDraftTasks(from source: IndexSet, to destination: Int) throws {
        guard isEditable else { throw WeekyiiError.cannotEditStartedDay }
        var tasks = day.sortedDraftTasks
        tasks.move(fromOffsets: source, toOffset: destination)
        for (index, task) in tasks.enumerated() {
            task.order = index + 1
        }
        try? modelContext.save()
    }

    private func renumberDraftTasks() {
        let sorted = day.sortedDraftTasks
        for (index, task) in sorted.enumerated() {
            task.order = index + 1
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
