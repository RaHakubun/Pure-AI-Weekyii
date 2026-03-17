import SwiftUI

struct DraftEditorView: View {
    let day: DayModel
    let viewModel: TodayViewModel
    let onAddTask: () -> Void
    let onEditTask: (TaskItem) -> Void
    let onPostponeTask: (TaskItem) -> Void
    var showsFullscreenButton: Bool = false
    var onFullscreenTap: ((CGRect) -> Void)?
    var showsHeaderControls: Bool = true
    var showsDraftHint: Bool = true
    var externalEditMode: Binding<EditMode>?

    @State private var errorMessage: String?
    @State private var localEditMode: EditMode = .inactive
    @State private var fullscreenButtonFrame: CGRect = .zero

    private var editModeBinding: Binding<EditMode> {
        externalEditMode ?? $localEditMode
    }

    private var isEditing: Bool {
        editModeBinding.wrappedValue == .active
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            if showsHeaderControls {
                HStack {
                    Text(String(localized: "draft.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("\(day.sortedDraftTasks.count)")
                        .font(.titleSmall)
                        .foregroundColor(.weekyiiPrimary)
                    Button {
                        onAddTask()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(day.status == .draft || day.status == .empty ? Color.weekyiiPrimary : Color.textSecondary)
                    }
                    .disabled(!(day.status == .draft || day.status == .empty))
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("新增任务")
                    .accessibilityIdentifier("draftAddButton")
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            editModeBinding.wrappedValue = isEditing ? .inactive : .active
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(day.status == .draft || day.status == .empty ? Color.weekyiiPrimary : Color.textSecondary)
                    }
                    .disabled(!(day.status == .draft || day.status == .empty))
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel(isEditing ? "完成编辑" : "编辑草稿")
                    .accessibilityIdentifier("draftEditButton")

                    if showsFullscreenButton && (day.status == .draft || day.status == .empty) {
                        Button {
                            onFullscreenTap?(fullscreenButtonFrame)
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.weekyiiPrimary)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(
                                                key: FullscreenButtonFramePreferenceKey.self,
                                                value: proxy.frame(in: .global)
                                            )
                                    }
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .accessibilityLabel("草稿全屏")
                        .accessibilityIdentifier("draftFullscreenButton")
                    }
                }
            }

            if showsDraftHint && day.status == .draft {
                Text("点击任务可编辑；进入编辑模式后可删除并拖拽排序。")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            if day.sortedDraftTasks.isEmpty {
                Text(String(localized: "draft.empty"))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, WeekSpacing.lg)
            } else {
                List {
                    ForEach(Array(day.sortedDraftTasks.enumerated()), id: \.element.id) { index, task in
                        rowView(task: task, index: index)
                            .listRowInsets(EdgeInsets(top: WeekSpacing.xs, leading: 0, bottom: WeekSpacing.xs, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        do {
                            try viewModel.moveDraftTasks(from: source, to: destination)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .onDelete { offsets in
                        do {
                            try viewModel.deleteTasks(at: offsets)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(max(1, day.sortedDraftTasks.count)) * 82)
            }
        }
        .environment(\.editMode, editModeBinding)
        .onPreferenceChange(FullscreenButtonFramePreferenceKey.self) { frame in
            fullscreenButtonFrame = frame
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

    @ViewBuilder
    private func rowView(task: TaskItem, index: Int) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            Button(action: {
                onEditTask(task)
            }) {
                TaskRowView(task: task, titleAccessibilityIdentifier: "draftTaskTitle_\(index)")
            }
            .buttonStyle(.plain)
            .disabled(!(day.status == .draft || day.status == .empty))
            .contextMenu {
                Button("后移任务", systemImage: "calendar.badge.clock") {
                    onPostponeTask(task)
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
                    .disabled(index >= day.sortedDraftTasks.count - 1)
                    .accessibilityIdentifier("draftMoveDown_\(index)")
                }
                .foregroundColor(.weekyiiPrimary)
            }
        }
        .padding(.vertical, 2)
    }

    private func moveTask(from sourceIndex: Int, to destination: Int) {
        do {
            try viewModel.moveDraftTasks(from: IndexSet(integer: sourceIndex), to: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FullscreenButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}
