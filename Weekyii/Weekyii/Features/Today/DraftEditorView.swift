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
    /// 每行实测高度。`List` 没有固有高度，只能用测量值给它一个恰好的框，
    /// 否则固定的估算高度会在最后一行下面留一条露出底色的空带。
    @State private var rowHeights: [Int: CGFloat] = [:]

    /// 首帧还没量到行高时的估值，只为让 `List` 先把行摆出来。
    private static let estimatedRowHeight: CGFloat = 48
    private static let rowVerticalInset = WeekSpacing.xs

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
            ThemedSectionTitle(title: presentationMode == .draft ? String(localized: "draft.title") : String(localized: "zone.draft"))
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
                    .weekSoftShadow(
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
                            top: Self.rowVerticalInset,
                            leading: WeekSpacing.xs,
                            bottom: Self.rowVerticalInset,
                            trailing: WeekSpacing.xs
                        ))
                        .listRowSeparator(.hidden)
                        // 行底下不再垫一块圆角矩形：任务行本身就是纸上的一行，
                        // 由行内的皮肤压一条脚线，列表只负责排版。
                        .listRowBackground(Color.clear)
                }
                .onMove(perform: moveTasks)
                .onDelete(perform: deleteTasks)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: taskListHeight)
            .onPreferenceChange(DraftRowHeightKey.self) { rowHeights = $0 }
        }
    }

    /// 行高由行自己量出来，`List` 的框正好等于所有行加行距，不多留一个像素。
    private var taskListHeight: CGFloat {
        let perRowInsets = Self.rowVerticalInset * 2
        return tasks.indices.reduce(CGFloat.zero) { total, index in
            total + (rowHeights[index] ?? Self.estimatedRowHeight) + perRowInsets
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
                    showsHabitOrigin: true,
                    renderContext: .reorderList
                )
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityIdentifier("draftTaskButton_\(index)")
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
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DraftRowHeightKey.self,
                    value: [index: proxy.size.height]
                )
            }
        )
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
                .foregroundStyle(isEnabled ? Color.weekyiiOnPrimary : Color.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isEnabled ? Color.weekyiiPrimary : Color.textSecondary.opacity(0.55))
                )
                .weekSoftShadow(
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

/// 草稿行实测高度（按行下标）。`List` 没有固有高度，只能靠行自己上报，
/// 让外框正好等于内容，底部不再留一条空带。
private struct DraftRowHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
