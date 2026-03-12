import SwiftUI

struct DraftEditorView: View {
    let day: DayModel
    let viewModel: TodayViewModel
    let onAddTask: () -> Void
    let onEditTask: (TaskItem) -> Void
    let onPostponeTask: (TaskItem) -> Void

    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

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
                Button(String(localized: "action.add")) {
                    onAddTask()
                }
                .disabled(!(day.status == .draft || day.status == .empty))
                .foregroundColor(.weekyiiPrimary)
                .font(.bodyMedium.weight(.semibold))
                .accessibilityIdentifier("draftAddButton")
                EditButton()
                    .disabled(!(day.status == .draft || day.status == .empty))
                    .accessibilityIdentifier("draftEditButton")
            }

            if day.status == .draft {
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
                .frame(minHeight: CGFloat(max(1, day.sortedDraftTasks.count)) * 68)
            }
        }
        .environment(\.editMode, $editMode)
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

            if editMode == .active {
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
