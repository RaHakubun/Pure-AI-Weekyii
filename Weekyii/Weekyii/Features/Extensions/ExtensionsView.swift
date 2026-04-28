import SwiftUI
import SwiftData

private enum ExtensionTab: String, CaseIterable {
    case projects
    case mindStamps

    var title: String {
        switch self {
        case .projects: String(localized: "extensions.tab.projects")
        case .mindStamps: String(localized: "extensions.tab.mindstamps")
        }
    }

    var icon: String {
        switch self {
        case .projects: "folder.fill"
        case .mindStamps: "seal.fill"
        }
    }
}

struct ExtensionsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ExtensionsViewModel?
    @State private var mindStampViewModel: MindStampViewModel?
    @State private var selectedTab: ExtensionTab = .projects
    @State private var showingCreateSheet = false
    @State private var showingMindStampEditor = false
    @State private var addingTaskProject: ProjectModel?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab switcher
                tabSwitcher
                    .padding(.horizontal, WeekSpacing.base)
                    .padding(.top, WeekSpacing.sm)

                ScrollView {
                    switch selectedTab {
                    case .projects:
                        projectsContent
                    case .mindStamps:
                        mindStampsContent
                    }
                }
            }
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WeekLogo(size: .small, animated: false)
                }

                if selectedTab == .mindStamps {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingMindStampEditor = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.weekyiiPrimary)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .accessibilityLabel(String(localized: "mindstamp.add"))
                        .accessibilityIdentifier("mindstampsToolbarCreateButton")
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet, onDismiss: {
                viewModel?.refresh()
            }) {
                if let viewModel {
                    CreateProjectSheet(viewModel: viewModel)
                }
            }
            .sheet(item: $addingTaskProject, onDismiss: {
                viewModel?.refresh()
            }) { project in
                if let viewModel {
                    AddProjectTaskSheet(project: project, viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showingMindStampEditor, onDismiss: {
                mindStampViewModel?.refresh()
            }) {
                if let mindStampViewModel {
                    MindStampEditorSheet(viewModel: mindStampViewModel)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ExtensionsViewModel(modelContext: modelContext)
            }
            if mindStampViewModel == nil {
                mindStampViewModel = MindStampViewModel(modelContext: modelContext)
            }
            viewModel?.refresh()
            mindStampViewModel?.refresh()
        }
        .onChange(of: viewModel?.errorMessage) { _, newValue in
            if let newValue { errorMessage = newValue }
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

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(ExtensionTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .background(Color.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
    }

    private func tabButton(_ tab: ExtensionTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(selectedTab == tab ? .white : .textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                selectedTab == tab
                    ? AnyShapeStyle(Color.weekyiiGradient)
                    : AnyShapeStyle(Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Projects Content

    private var projectsContent: some View {
        Group {
            if let viewModel {
                let active = viewModel.activeProjects()
                let completed = viewModel.completedProjects()

                if active.isEmpty && completed.isEmpty {
                    emptyStateView
                        .padding(.horizontal, WeekSpacing.base)
                } else {
                    VStack(spacing: WeekSpacing.md) {
                        MasonryLayout(columns: 2, spacing: WeekSpacing.sm) {
                            ForEach(active + completed) { project in
                                NavigationLink(destination: ProjectDetailView(project: project, viewModel: viewModel)) {
                                    ProjectInlineCard(
                                        project: project,
                                        viewModel: viewModel,
                                        onAddTask: {
                                            addingTaskProject = project
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, WeekSpacing.sm)

                        // Add project button
                        Button {
                            showingCreateSheet = true
                        } label: {
                            HStack(spacing: WeekSpacing.xs) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                Text(String(localized: "project.add"))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, WeekSpacing.xl)
                            .padding(.vertical, WeekSpacing.md)
                            .background(Color.weekyiiGradient)
                            .clipShape(Capsule())
                            .shadow(color: Color.weekyiiPrimary.opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.bottom, WeekSpacing.lg)
                    }
                    .padding(.top, WeekSpacing.sm)
                }
            } else {
                ProgressView()
                    .padding(.top, WeekSpacing.xxxl)
            }
        }
    }

    // MARK: - Mind Stamps Content

    private var mindStampsContent: some View {
        Group {
            if let mindStampViewModel {
                MindStampListView(viewModel: mindStampViewModel)
                    .padding(.horizontal, WeekSpacing.xl)
                .padding(.top, WeekSpacing.sm)
            } else {
                ProgressView()
                    .padding(.top, WeekSpacing.xxxl)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.weekyiiGradient)

                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "project.empty.title"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)

                    Text(String(localized: "project.empty.subtitle"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showingCreateSheet = true
                } label: {
                    HStack(spacing: WeekSpacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text(String(localized: "project.add"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, WeekSpacing.xl)
                    .padding(.vertical, WeekSpacing.md)
                    .background(Color.weekyiiGradient)
                    .clipShape(Capsule())
                    .shadow(color: Color.weekyiiPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
    }
}

// MARK: - Project Inline Card (Enhanced)

private struct ProjectInlineCard: View {
    let project: ProjectModel
    let viewModel: ExtensionsViewModel
    let onAddTask: () -> Void

    private let maxVisibleTasks = 4
    @State private var appeared = false

    private var projectColor: Color { Color(hex: project.color) }
    private var isFinished: Bool { project.status == .completed || project.status == .archived }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部渐变色条
            LinearGradient(
                colors: [projectColor, projectColor.opacity(0.6)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 5)

            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                cardHeader
                taskList

                if !isFinished {
                    addButton
                }
            }
            .padding(WeekSpacing.md)
        }
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .stroke(projectColor.opacity(0.15), lineWidth: 1)
        )
        // Completed overlay
        .overlay {
            if isFinished {
                RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                    .fill(Color.backgroundSecondary.opacity(0.5))
                    .overlay {
                        VStack(spacing: WeekSpacing.xs) {
                            Image(systemName: project.status == .archived ? "archivebox.fill" : "checkmark.seal.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(project.status == .archived ? Color.textTertiary : Color.accentGreen)
                            Text(project.status.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(project.status == .archived ? .textTertiary : .accentGreen)
                        }
                    }
            }
        }
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        // Entry animation
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(spacing: WeekSpacing.sm) {
            Image(systemName: project.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(projectColor)

            Text(project.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 4)

            ZStack {
                Circle()
                    .stroke(projectColor.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(min(project.progress, 1.0)))
                    .stroke(projectColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(project.progress * 100))")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(projectColor)
            }
            .frame(width: 26, height: 26)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.textTertiary)
        }
    }

    // MARK: - Task List

    private var taskList: some View {
        let tasks = project.tasks.sorted { $0.order < $1.order }
        let displayTasks = Array(tasks.prefix(maxVisibleTasks))
        let remaining = tasks.count - displayTasks.count
        let expired = project.expiredTaskCount

        return VStack(alignment: .leading, spacing: WeekSpacing.xs) {
            if tasks.isEmpty {
                Text(String(localized: "project.tasks.empty"))
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .padding(.vertical, WeekSpacing.xs)
            } else {
                ForEach(displayTasks) { task in
                    taskRow(task)
                }

                HStack(spacing: WeekSpacing.sm) {
                    if remaining > 0 {
                        Text(String(format: String(localized: "project.card.more"), remaining))
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }

                    Spacer()

                    if expired > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text(String(format: String(localized: "project.card.expired"), expired))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.taskDDL)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            ZStack {
                Circle()
                    .strokeBorder(
                        task.zone == .complete ? Color.accentGreen : Color.textTertiary.opacity(0.4),
                        lineWidth: 1.5
                    )
                    .frame(width: 14, height: 14)
                if task.zone == .complete {
                    Circle()
                        .fill(Color.accentGreen)
                        .frame(width: 14, height: 14)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundColor(task.zone == .complete ? .textTertiary : .textPrimary)
                    .strikethrough(task.zone == .complete)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let day = task.day {
                        Image(systemName: "calendar")
                            .font(.system(size: 8))
                        Text(day.date, format: .dateTime.month().day())
                            .font(.system(size: 10))
                    }

                    if task.taskType == .ddl {
                        Text(task.taskType.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(task.taskType.color)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .foregroundColor(.textTertiary)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            onAddTask()
        } label: {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                Text(String(localized: "project.card.add_task"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(projectColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, WeekSpacing.sm)
            .background(projectColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Masonry Layout (两列瀑布流)

private struct MasonryLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            let size = result.sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let totalWidth = proposal.width ?? 400
        let columnWidth = (totalWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []

        for subview in subviews {
            let minHeight = columnHeights.min() ?? 0
            let columnIndex = columnHeights.firstIndex(of: minHeight) ?? 0

            let x = CGFloat(columnIndex) * (columnWidth + spacing)
            let y = columnHeights[columnIndex]

            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            positions.append(CGPoint(x: x, y: y))
            sizes.append(CGSize(width: columnWidth, height: size.height))

            columnHeights[columnIndex] += size.height + spacing
        }

        let maxHeight = columnHeights.max() ?? 0
        return ArrangeResult(
            size: CGSize(width: totalWidth, height: max(0, maxHeight - spacing)),
            positions: positions,
            sizes: sizes
        )
    }

    private struct ArrangeResult {
        let size: CGSize
        let positions: [CGPoint]
        let sizes: [CGSize]
    }
}
