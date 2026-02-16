import SwiftUI

struct ProjectDetailView: View {
    let project: ProjectModel
    let viewModel: ExtensionsViewModel

    @State private var showingAddTaskSheet = false
    @State private var showingDeleteAlert = false
    @State private var animateProgress = false
    @Environment(\.dismiss) private var dismiss

    private var projectColor: Color { Color(hex: project.color) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                // Hero section
                heroSection

                // Action buttons
                actionButtons

                // Task list (grouped by date)
                taskListSection
            }
            .weekPadding(WeekSpacing.base)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddTaskSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(projectColor)
                }
            }
        }
        .sheet(isPresented: $showingAddTaskSheet, onDismiss: {
            viewModel.refresh()
        }) {
            AddProjectTaskSheet(project: project, viewModel: viewModel)
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                    animateProgress = true
                }
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 0) {
            // Gradient banner with icon
            ZStack {
                LinearGradient(
                    colors: [projectColor, projectColor.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Decorative circles
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 120, height: 120)
                    .offset(x: -80, y: -30)

                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 80, height: 80)
                    .offset(x: 100, y: 20)

                VStack(spacing: WeekSpacing.sm) {
                    // Large icon
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 64, height: 64)
                        Image(systemName: project.icon)
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }

                    // Status badge
                    Text(project.status.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(projectColor)
                        .padding(.horizontal, WeekSpacing.md)
                        .padding(.vertical, WeekSpacing.xxs)
                        .background(
                            Capsule()
                                .fill(Color.white)
                        )

                    // Date range
                    Text(dateRangeText)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous))

            // Description + Progress card (overlapping the banner)
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                if !project.projectDescription.isEmpty {
                    Text(project.projectDescription)
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }

                // Progress ring + Stats row
                HStack(spacing: WeekSpacing.xl) {
                    // Ring progress chart
                    ZStack {
                        Circle()
                            .stroke(projectColor.opacity(0.1), lineWidth: 8)
                            .frame(width: 80, height: 80)

                        Circle()
                            .trim(from: 0, to: animateProgress ? CGFloat(min(project.progress, 1.0)) : 0)
                            .stroke(
                                projectColor,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 80, height: 80)

                        VStack(spacing: 0) {
                            Text("\(Int(project.progress * 100))")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(projectColor)
                                .contentTransition(.numericText())
                            Text("%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textTertiary)
                        }
                    }

                    // Stats
                    VStack(alignment: .leading, spacing: WeekSpacing.md) {
                        statRow(
                            icon: "list.bullet",
                            label: String(localized: "project.stat.total"),
                            value: "\(project.totalTaskCount)",
                            color: .textPrimary
                        )
                        statRow(
                            icon: "checkmark.circle.fill",
                            label: String(localized: "project.stat.completed"),
                            value: "\(project.completedTaskCount)",
                            color: .accentGreen
                        )

                        let remaining = project.totalTaskCount - project.completedTaskCount
                        statRow(
                            icon: "clock",
                            label: String(localized: "project.stat.remaining"),
                            value: "\(remaining)",
                            color: projectColor
                        )

                        if project.expiredTaskCount > 0 {
                            statRow(
                                icon: "exclamationmark.triangle.fill",
                                label: String(localized: "project.stat.expired"),
                                value: "\(project.expiredTaskCount)",
                                color: .taskDDL
                            )
                        }
                    }
                }
            }
            .padding(WeekSpacing.lg)
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous)
                    .stroke(Color.backgroundTertiary, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            .padding(.horizontal, WeekSpacing.sm)
            .offset(y: -24)
        }
    }

    private func statRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
                .frame(width: 18)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: WeekSpacing.sm) {
            if project.status == .active && project.isAllCompleted {
                Button {
                    viewModel.updateStatus(project, to: .completed)
                } label: {
                    Label(String(localized: "project.action.complete"), systemImage: "checkmark.circle")
                        .font(.bodyMedium)
                        .foregroundColor(.accentGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WeekSpacing.md)
                        .background(Color.accentGreen.opacity(0.1))
                        .cornerRadius(WeekRadius.small)
                }
                .buttonStyle(.plain)
            }

            if project.status == .completed {
                Button {
                    viewModel.updateStatus(project, to: .archived)
                } label: {
                    Label(String(localized: "project.action.archive"), systemImage: "archivebox")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WeekSpacing.md)
                        .background(Color.backgroundTertiary)
                        .cornerRadius(WeekRadius.small)
                }
                .buttonStyle(.plain)
            }

            Button {
                showingDeleteAlert = true
            } label: {
                Label(String(localized: "project.action.delete"), systemImage: "trash")
                    .font(.bodyMedium)
                    .foregroundColor(.taskDDL)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WeekSpacing.md)
                    .background(Color.taskDDL.opacity(0.1))
                    .cornerRadius(WeekRadius.small)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Task List

    private var taskListSection: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            Text(String(localized: "project.tasks.title"))
                .font(.titleMedium)
                .foregroundColor(.textPrimary)

            let grouped = viewModel.tasksByDate(for: project)

            if grouped.isEmpty {
                WeekCard {
                    VStack(spacing: WeekSpacing.md) {
                        Image(systemName: "tray")
                            .font(.system(size: 36))
                            .foregroundColor(.textTertiary)
                        Text(String(localized: "project.tasks.empty"))
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                        Button {
                            showingAddTaskSheet = true
                        } label: {
                            Text(String(localized: "project.tasks.add_first"))
                                .font(.bodyMedium)
                                .foregroundColor(projectColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .weekPaddingVertical(WeekSpacing.lg)
                }
            } else {
                ForEach(grouped, id: \.date) { group in
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        // Date header
                        Text(group.date, format: .dateTime.month().day().weekday(.wide))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .padding(.leading, WeekSpacing.xs)

                        WeekCard {
                            VStack(spacing: WeekSpacing.xs) {
                                ForEach(group.tasks) { task in
                                    let isExpired = isTaskExpired(task)

                                    HStack(spacing: WeekSpacing.sm) {
                                        // Status dot
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    task.zone == .complete ? Color.accentGreen :
                                                    isExpired ? Color.taskDDL :
                                                    projectColor.opacity(0.3)
                                                )
                                                .frame(width: 8, height: 8)

                                            if task.zone == .complete {
                                                Circle()
                                                    .stroke(Color.accentGreen.opacity(0.3), lineWidth: 3)
                                                    .frame(width: 14, height: 14)
                                            }
                                        }

                                        Text(task.title)
                                            .font(.bodyMedium)
                                            .foregroundColor(
                                                task.zone == .complete ? .textTertiary :
                                                isExpired ? .taskDDL :
                                                .textPrimary
                                            )
                                            .strikethrough(task.zone == .complete)

                                        Spacer()

                                        if task.taskType == .ddl {
                                            Image(systemName: "flame.fill")
                                                .font(.caption2)
                                                .foregroundColor(.taskDDL)
                                        }

                                        if isExpired && task.zone != .complete {
                                            Text(String(localized: "status.expired"))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.taskDDL)
                                                .clipShape(Capsule())
                                        } else {
                                            Text(task.zone == .complete ?
                                                String(localized: "status.completed") :
                                                String(localized: "status.draft"))
                                                .font(.caption2)
                                                .foregroundColor(task.zone == .complete ? .accentGreen : .textTertiary)
                                        }
                                    }

                                    if task.id != group.tasks.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func isTaskExpired(_ task: TaskItem) -> Bool {
        guard let taskDate = task.day?.date else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        return taskDate < today && task.zone != .complete
    }

    private var dateRangeText: String {
        "\(project.startDate.formatted(date: .numeric, time: .omitted)) - \(project.endDate.formatted(date: .numeric, time: .omitted))"
    }
}
