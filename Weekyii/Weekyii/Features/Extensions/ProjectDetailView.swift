import SwiftUI

struct ProjectDetailView: View {
    let project: ProjectModel
    let viewModel: ExtensionsViewModel

    @State private var showingAddTaskSheet = false
    @State private var showingDeleteAlert = false
    @State private var deletingTask: TaskItem?
    @State private var editingTask: TaskItem?
    @State private var animateProgress = false
    @State private var expandedSectionIDs: Set<String> = []
    @State private var seenSectionIDs: Set<String> = []
    @State private var expandedTaskIDs: Set<UUID> = []
    @Environment(\.dismiss) private var dismiss

    private var projectColor: Color { Color(hex: project.color) }
    private var snapshot: ProjectDetailSnapshot { viewModel.projectDetailSnapshot(for: project) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                identitySection
                summarySection
                ledgerSection
            }
            .weekPadding(WeekSpacing.base)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle(snapshot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAddTaskSheet, onDismiss: { viewModel.refresh() }) {
            AddProjectTaskSheet(project: project, viewModel: viewModel)
        }
        .sheet(item: $editingTask, onDismiss: { viewModel.refresh() }) { task in
            TaskEditorSheet(
                title: String(localized: "draft.edit_title"),
                initialTitle: task.title,
                initialDescription: task.taskDescription,
                initialType: task.taskType,
                initialSteps: task.steps,
                initialAttachments: task.attachments
            ) { title, description, type, steps, attachments in
                viewModel.updateProjectTask(
                    task,
                    title: title,
                    description: description,
                    type: type,
                    steps: steps,
                    attachments: attachments
                )
                editingTask = nil
            }
        }
        .confirmationDialog(
            String(localized: "project.delete.confirm"),
            isPresented: $showingDeleteAlert,
            titleVisibility: .visible
        ) {
            Button(String(localized: "project.delete.choice.only_project"), role: .destructive) {
                viewModel.deleteProject(project, includeTasks: false)
                dismiss()
            }
            Button(String(localized: "project.delete.choice.with_tasks"), role: .destructive) {
                viewModel.deleteProject(project, includeTasks: true)
                dismiss()
            }
            Button(String(localized: "action.cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "project.delete.choice.message"))
        }
        .confirmationDialog(
            String(localized: "project.task.delete.confirm"),
            isPresented: Binding(
                get: { deletingTask != nil },
                set: { if !$0 { deletingTask = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "project.task.delete.action"), role: .destructive) {
                if let task = deletingTask {
                    viewModel.deleteProjectTask(task)
                }
                deletingTask = nil
            }
            Button(String(localized: "action.cancel"), role: .cancel) {
                deletingTask = nil
            }
        } message: {
            Text(String(localized: "project.task.delete.message"))
        }
        .onAppear {
            syncExpandedSections(with: snapshot.sections)
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) {
                animateProgress = true
            }
        }
        .onChange(of: snapshot.sections.map(\.id)) { _, _ in
            syncExpandedSections(with: snapshot.sections)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showingAddTaskSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(projectColor)
            }

            Menu {
                if project.status == .active && project.isAllCompleted {
                    Button(String(localized: "project.action.complete")) {
                        viewModel.updateStatus(project, to: .completed)
                    }
                }
                if project.status == .completed {
                    Button(String(localized: "project.action.archive")) {
                        viewModel.updateStatus(project, to: .archived)
                    }
                }
                Divider()
                Button(String(localized: "project.action.delete"), role: .destructive) {
                    showingDeleteAlert = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    private var identitySection: some View {
        WeekCard(useGradient: true, accentColor: projectColor, shadow: .medium) {
            HStack(alignment: .top, spacing: WeekSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 54, height: 54)
                    Image(systemName: snapshot.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                    Text(snapshot.name)
                        .font(.titleLarge)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: WeekSpacing.sm) {
                        Text(snapshot.status.displayName)
                            .font(.captionBold)
                            .foregroundStyle(projectColor)
                            .padding(.horizontal, WeekSpacing.sm)
                            .padding(.vertical, WeekSpacing.xs)
                            .background(Capsule().fill(Color.white))

                        Text(dateRangeText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.88))
                    }

                    if !snapshot.projectDescription.isEmpty {
                        Text(snapshot.projectDescription)
                            .font(.bodyMedium)
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        WeekCard(accentColor: projectColor) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                Text("项目概览")
                    .font(.titleSmall)
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: WeekSpacing.lg) {
                    progressRing

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: WeekSpacing.sm) {
                        metricChip(title: String(localized: "project.stat.total"), value: "\(snapshot.totalCount)", tint: .textPrimary)
                        metricChip(title: String(localized: "project.stat.completed"), value: "\(snapshot.completedCount)", tint: .accentGreen)
                        metricChip(title: String(localized: "project.stat.remaining"), value: "\(snapshot.remainingCount)", tint: projectColor)
                        metricChip(title: String(localized: "project.stat.expired"), value: "\(snapshot.expiredCount)", tint: .taskDDL)
                    }
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: WeekSpacing.sm) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(projectColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("下一步")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        if let title = snapshot.nextTaskTitle {
                            Text(title)
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(2)
                            if let date = snapshot.nextTaskDate {
                                Text(date, format: .dateTime.month().day().weekday(.abbreviated))
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        } else {
                            Text("项目暂无待办")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(projectColor.opacity(0.2), lineWidth: 8)
                .frame(width: 82, height: 82)

            Circle()
                .trim(from: 0, to: animateProgress ? CGFloat(min(snapshot.progress, 1.0)) : 0)
                .stroke(projectColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 82, height: 82)

            VStack(spacing: 0) {
                Text("\(Int(snapshot.progress * 100))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(projectColor)
                    .contentTransition(.numericText())
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func metricChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.titleSmall)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, WeekSpacing.xs)
        .padding(.horizontal, WeekSpacing.sm)
        .background(tint.opacity(0.08))
        .clipShape(.rect(cornerRadius: WeekRadius.small))
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            Text(String(localized: "project.tasks.title"))
                .font(.titleMedium)
                .foregroundStyle(Color.textPrimary)

            if snapshot.sections.isEmpty {
                WeekCard {
                    VStack(spacing: WeekSpacing.md) {
                        Image(systemName: "tray")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.textTertiary)
                        Text(String(localized: "project.tasks.empty"))
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textSecondary)
                        Button {
                            showingAddTaskSheet = true
                        } label: {
                            Text(String(localized: "project.tasks.add_first"))
                                .font(.bodyMedium)
                                .foregroundStyle(projectColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .weekPaddingVertical(WeekSpacing.lg)
                }
            } else {
                ForEach(snapshot.sections) { section in
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.md) {
                            Button {
                                toggleSection(section.id)
                            } label: {
                                HStack {
                                    Text(section.date, format: .dateTime.month().day().weekday(.wide))
                                        .font(.titleSmall)
                                        .foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    Text("\(section.tasks.count)")
                                        .font(.captionBold)
                                        .foregroundStyle(Color.textSecondary)
                                    Image(systemName: expandedSectionIDs.contains(section.id) ? "chevron.up" : "chevron.down")
                                        .font(.captionBold)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)

                            if expandedSectionIDs.contains(section.id) {
                                VStack(spacing: WeekSpacing.sm) {
                                    ForEach(section.tasks) { task in
                                        taskRow(task)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        let isExpired = isTaskExpired(task)

        return VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HStack(alignment: .top, spacing: WeekSpacing.sm) {
                Button {
                    toggleTaskExpansion(task.id)
                } label: {
                    TaskRowView(task: task)
                }
                .buttonStyle(.plain)

                Menu {
                    Button(String(localized: "action.edit")) {
                        editingTask = task
                    }
                    Button(String(localized: "project.task.delete.action"), role: .destructive) {
                        deletingTask = task
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 32, height: 32)
                }
            }

            HStack(spacing: WeekSpacing.sm) {
                Text(task.taskNumber)
                    .font(.captionBold)
                    .foregroundStyle(Color.textSecondary)

                TaskZoneBadge(zone: task.zone)

                if task.taskType == .ddl {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(Color.taskDDL)
                }

                if isExpired {
                    Text(String(localized: "status.expired"))
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, WeekSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.taskDDL)
                        .clipShape(Capsule())
                }

                Spacer()
            }

            if expandedTaskIDs.contains(task.id) {
                VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                    if !task.steps.isEmpty {
                        HStack(spacing: WeekSpacing.xs) {
                            Image(systemName: "checklist")
                                .foregroundStyle(Color.textSecondary)
                            Text("步骤 \(task.steps.count)")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    if !task.attachments.isEmpty {
                        HStack(spacing: WeekSpacing.xs) {
                            Image(systemName: "paperclip")
                                .foregroundStyle(Color.textSecondary)
                            Text("附件 \(task.attachments.count)")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    if let startedAt = task.startedAt {
                        Text("开始 \(startedAt, format: .dateTime.month().day().hour().minute())")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }

                    if let endedAt = task.endedAt {
                        Text("结束 \(endedAt, format: .dateTime.month().day().hour().minute())")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WeekSpacing.sm)
                .padding(.bottom, WeekSpacing.xs)
            }
        }
    }

    private var dateRangeText: String {
        "\(snapshot.startDate.formatted(date: .abbreviated, time: .omitted)) - \(snapshot.endDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private func syncExpandedSections(with sections: [ProjectTaskLedgerSection]) {
        let valid = Set(sections.map(\.id))
        expandedSectionIDs = expandedSectionIDs.intersection(valid)
        for section in sections where section.isExpandedByDefault && !seenSectionIDs.contains(section.id) {
            expandedSectionIDs.insert(section.id)
        }
        seenSectionIDs = valid
    }

    private func toggleSection(_ id: String) {
        if expandedSectionIDs.contains(id) {
            expandedSectionIDs.remove(id)
        } else {
            expandedSectionIDs.insert(id)
        }
    }

    private func toggleTaskExpansion(_ id: UUID) {
        if expandedTaskIDs.contains(id) {
            expandedTaskIDs.remove(id)
        } else {
            expandedTaskIDs.insert(id)
        }
    }

    private func isTaskExpired(_ task: TaskItem) -> Bool {
        guard let taskDate = task.day?.date else { return false }
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        return Calendar(identifier: .iso8601).startOfDay(for: taskDate) < today && task.zone != .complete
    }
}
