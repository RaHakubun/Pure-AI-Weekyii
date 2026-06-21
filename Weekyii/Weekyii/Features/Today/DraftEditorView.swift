import SwiftUI

struct DraftEditorView: View {
    enum PresentationMode {
        case draft
        case flexibleExecution
    }

    let day: DayModel
    let viewModel: TodayViewModel
    var presentationMode: PresentationMode = .draft
    let onAddTask: () -> Void
    let onEditTask: (TaskItem) -> Void
    let onPostponeTask: (TaskItem) -> Void
    var onToggleLock: (() -> Void)? = nil

    @State private var errorMessage: String?
    @State private var localEditMode: EditMode = .inactive

    private var isEditing: Bool {
        localEditMode == .active
    }

    private var tasks: [TaskItem] {
        presentationMode == .draft ? day.sortedDraftTasks : day.frozenTasks
    }

    private var canEdit: Bool {
        switch presentationMode {
        case .draft:
            return day.status == .draft || day.status == .empty
        case .flexibleExecution:
            return day.status == .execute
                && day.executionMode == .flexible
                && day.isDraftZoneUnlocked
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            header
            guidance
            taskList
        }
        .environment(\.editMode, $localEditMode)
        .alert(String(localized: "alert.title"), isPresented: Binding(get: {
            errorMessage != nil
        }, set: { newValue in
            if !newValue { errorMessage = nil }
        })) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: canEdit) { _, editable in
            if !editable {
                localEditMode = .inactive
            }
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text(presentationMode == .draft ? String(localized: "draft.title") : "草稿区")
                .font(.titleSmall)
                .foregroundColor(.textPrimary)
            Spacer()
            Text("\(tasks.count)")
                .font(.titleSmall)
                .foregroundColor(.weekyiiPrimary)

            if presentationMode == .flexibleExecution {
                temperatureToggle
            }

            actionButton(
                systemName: "plus",
                accessibilityLabel: "新增任务",
                accessibilityIdentifier: "draftAddButton",
                isEnabled: canEdit,
                action: onAddTask
            )

            actionButton(
                systemName: isEditing ? "checkmark" : "pencil",
                accessibilityLabel: isEditing ? "完成编辑" : "编辑草稿",
                accessibilityIdentifier: "draftEditButton",
                isEnabled: canEdit
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    localEditMode = isEditing ? .inactive : .active
                }
            }
        }
    }

    private var temperatureToggle: some View {
        let isThawed = day.isDraftZoneUnlocked
        let coldColor = Color(red: 0.15, green: 0.58, blue: 0.78)
        let warmColor = Color(red: 0.94, green: 0.43, blue: 0.20)
        let stateColor = isThawed ? warmColor : coldColor

        return Button {
            onToggleLock?()
        } label: {
            ZStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 36, height: 36)
                    .shadow(
                        color: stateColor.opacity(0.28),
                        radius: 4,
                        y: 2
                    )

                Image(systemName: isThawed ? "flame.fill" : "snowflake")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityIdentifier(
                        isThawed
                            ? "executionQueueThawedIcon"
                            : "executionQueueFrozenIcon"
                    )
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.status != .execute)
        .accessibilityLabel(isThawed ? "冻结草稿区" : "解冻草稿区")
        .accessibilityValue(isThawed ? "解冻" : "冻结")
        .accessibilityHint("在冻结和解冻状态之间切换")
        .accessibilityIdentifier("executionQueueLockButton")
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isThawed)
    }

    @ViewBuilder
    private var guidance: some View {
        switch presentationMode {
        case .draft:
            if day.status == .draft {
                Text("点击任务可编辑；进入编辑模式后可删除并拖拽排序。")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        case .flexibleExecution:
            Text(day.isDraftZoneUnlocked
                 ? "草稿区已解冻，可新增、编辑、删除、排序，并与当前专注任务交换。"
                 : "草稿区已冻结，解冻后可调整待执行任务。")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
    }

    @ViewBuilder
    private var taskList: some View {
        if tasks.isEmpty {
            Text(presentationMode == .draft ? String(localized: "draft.empty") : "暂无待执行任务。")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .padding(.vertical, WeekSpacing.lg)
        } else {
            List {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    rowView(task: task, index: index)
                        .listRowInsets(EdgeInsets(
                            top: WeekSpacing.xs,
                            leading: WeekSpacing.xs,
                            bottom: WeekSpacing.xs,
                            trailing: WeekSpacing.xs
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                                .fill(Color.backgroundSecondary)
                        )
                }
                .onMove(perform: moveTasks)
                .onDelete(perform: deleteTasks)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.backgroundSecondary.opacity(0.65))
            .frame(height: CGFloat(max(1, tasks.count)) * 82)
        }
    }

    @ViewBuilder
    private func rowView(task: TaskItem, index: Int) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            Button {
                onEditTask(task)
            } label: {
                TaskRowView(
                    task: task,
                    titleAccessibilityIdentifier: "draftTaskTitle_\(index)",
                    showsProjectOrigin: true,
                    renderContext: .reorderList
                )
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .contextMenu {
                if canEdit {
                    Button("后移任务", systemImage: "calendar.badge.clock") {
                        onPostponeTask(task)
                    }
                }
            }

            if isEditing {
                VStack(spacing: WeekSpacing.xs) {
                    Button {
                        moveTask(from: index, to: max(index - 1, 0))
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .accessibilityIdentifier("draftMoveUp_\(index)")

                    Button {
                        moveTask(from: index, to: index + 2)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderless)
                    .disabled(index >= tasks.count - 1)
                    .accessibilityIdentifier("draftMoveDown_\(index)")
                }
                .foregroundColor(.weekyiiPrimary)
            }
        }
        .padding(.vertical, 2)
    }

    private func moveTasks(from source: IndexSet, to destination: Int) {
        do {
            switch presentationMode {
            case .draft:
                try viewModel.moveDraftTasks(from: source, to: destination)
            case .flexibleExecution:
                try viewModel.moveExecutionTasks(from: source, to: destination)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTasks(at offsets: IndexSet) {
        do {
            switch presentationMode {
            case .draft:
                try viewModel.deleteTasks(at: offsets)
            case .flexibleExecution:
                try viewModel.deleteExecutionTasks(at: offsets)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveTask(from sourceIndex: Int, to destination: Int) {
        moveTasks(from: IndexSet(integer: sourceIndex), to: destination)
    }

    private func actionButton(
        systemName: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isEnabled ? Color.weekyiiPrimary : Color.textSecondary.opacity(0.55))
                )
                .shadow(
                    color: (isEnabled ? Color.weekyiiPrimary : Color.textSecondary).opacity(0.22),
                    radius: 4,
                    y: 2
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
