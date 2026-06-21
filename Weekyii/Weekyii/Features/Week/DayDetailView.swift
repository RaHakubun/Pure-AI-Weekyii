import SwiftUI
import SwiftData

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let day: DayModel

    @State private var showingAddSheet = false
    @State private var editingTask: TaskItem?
    @State private var errorMessage: String?
    @State private var isEditingDraftTasks = false

    private var isEditable: Bool {
        let calendar = Calendar(identifier: .iso8601)
        let today = calendar.startOfDay(for: TimeProvider().today)
        let targetDay = calendar.startOfDay(for: day.date)
        return targetDay >= today && (day.status == .empty || day.status == .draft)
    }

    private var isEditingDraft: Bool {
        isEditingDraftTasks && isEditable
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
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
            .padding(.horizontal, WeekSpacing.base)
            .padding(.top, WeekSpacing.sm)
            .padding(.bottom, 100)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("日程详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditable {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增任务")
                    .accessibilityIdentifier("dayDetailAddButton")

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingDraftTasks.toggle()
                        }
                    } label: {
                        Image(systemName: isEditingDraft ? "checkmark" : "pencil")
                    }
                    .accessibilityLabel(isEditingDraft ? "完成编辑" : "编辑任务")
                    .accessibilityIdentifier("dayDetailEditButton")
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
        WeekCard(accentColor: day.status.color, shadow: .light) {
            HStack(alignment: .center, spacing: WeekSpacing.lg) {
                VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                    Text(day.date, format: Date.FormatStyle().year().month(.wide))
                        .font(.captionBold)
                        .foregroundStyle(Color.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: WeekSpacing.sm) {
                        Text(day.date, format: Date.FormatStyle().day())
                            .font(.system(size: 38, weight: .bold, design: .serif))
                            .foregroundStyle(Color.textPrimary)

                        Text(day.date, format: Date.FormatStyle().weekday(.wide))
                            .font(.titleSmall)
                            .foregroundStyle(Color.textPrimary)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: WeekSpacing.sm) {
                    StatusBadge(status: day.status)

                    HStack(spacing: WeekSpacing.md) {
                        headerMetric(value: totalTaskCount, label: "任务")
                        headerMetric(value: day.completedTasks.count, label: "完成")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dayDetailSummary")
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                    Text("草稿任务")
                        .font(.titleSmall)
                        .foregroundStyle(Color.textPrimary)

                    Text(isEditingDraft ? "调整顺序或删除任务" : "按当前顺序执行，共 \(day.sortedDraftTasks.count) 项")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 0)

                Text("\(day.sortedDraftTasks.count)")
                    .font(.bodyMedium.weight(.bold))
                    .foregroundStyle(Color.weekyiiPrimary)
                    .frame(minWidth: 32, minHeight: 32)
                    .background(Color.weekyiiPrimary.opacity(0.10), in: Circle())
            }

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
                                OrderedTaskRow(
                                    task: task,
                                    index: index,
                                    showsChevron: !isEditingDraft,
                                    accessibilityIdentifier: "dayDetailTaskRow_\(index)"
                                )
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
                                            .frame(width: 34, height: 34)
                                            .background(Color.backgroundTertiary, in: Circle())
                                    }
                                    .disabled(index == 0)
                                    .accessibilityLabel("上移")

                                    Button(action: {
                                        do {
                                            try moveDraftTasks(from: IndexSet(integer: index), to: index + 2)
                                        } catch {
                                            errorMessage = error.localizedDescription
                                        }
                                    }) {
                                        Image(systemName: "arrow.down")
                                            .frame(width: 34, height: 34)
                                            .background(Color.backgroundTertiary, in: Circle())
                                    }
                                    .disabled(index == day.sortedDraftTasks.count - 1)
                                    .accessibilityLabel("下移")

                                    Button(role: .destructive, action: {
                                        do {
                                            try deleteTasks(at: IndexSet(integer: index))
                                        } catch {
                                            errorMessage = error.localizedDescription
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .frame(width: 34, height: 34)
                                            .background(Color.taskDDL.opacity(0.10), in: Circle())
                                    }
                                    .accessibilityLabel("删除")
                                }
                                .foregroundStyle(Color.weekyiiPrimary)
                                .font(.caption.weight(.semibold))
                            }
                        }

                        if index < day.sortedDraftTasks.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.horizontal, WeekSpacing.md)
                .background(Color.backgroundSecondary)
                .clipShape(.rect(cornerRadius: WeekRadius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: WeekRadius.large)
                        .stroke(Color.backgroundTertiary, lineWidth: 1)
                )
                .shadow(
                    color: WeekShadow.light.color,
                    radius: WeekShadow.light.radius,
                    x: WeekShadow.light.x,
                    y: WeekShadow.light.y
                )
                .accessibilityIdentifier("dayDetailDraftList")
            }
        }
    }

    private func headerMetric(value: Int, label: String) -> some View {
        VStack(spacing: WeekSpacing.xxs) {
            Text("\(value)")
                .font(.bodyLarge.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.captionSmall)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(minWidth: 34)
    }

    private var totalTaskCount: Int {
        day.tasks.count + day.expiredCount
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
