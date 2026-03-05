import SwiftUI
import SwiftData

// MARK: - Extensions Hub View (New Architecture)

struct ExtensionsHubView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ExtensionsViewModel?
    @State private var mindStampViewModel: MindStampViewModel?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WeekSpacing.lg) {
                    // Projects Module
                    if let viewModel {
                        ProjectsModulePreview(viewModel: viewModel)
                    }

                    // Mind Stamps Module
                    if let mindStampViewModel {
                        MindStampsModulePreview(viewModel: mindStampViewModel)
                    }
                }
                .padding(.horizontal, WeekSpacing.base)
                .padding(.vertical, WeekSpacing.md)
            }
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WeekLogo(size: .small, animated: false)
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
}

// MARK: - Projects Module Preview

private struct ProjectsModulePreview: View {
    let viewModel: ExtensionsViewModel
    @State private var showingCreateSheet = false

    private var activeProjects: [ProjectModel] {
        Array(viewModel.activeProjects().prefix(3))
    }

    private var completedProjects: [ProjectModel] {
        Array(viewModel.completedProjects().prefix(2))
    }

    private var allProjects: [ProjectModel] {
        Array((activeProjects + completedProjects).prefix(5))
    }

    var body: some View {
        ModuleContainer(
            title: String(localized: "extensions.module.projects.title"),
            subtitle: String(localized: "extensions.module.projects.subtitle"),
            icon: "folder.fill",
            iconColor: .weekyiiPrimary,
            seeAllAccessibilityID: "extensionsProjectsSeeAllButton",
            destination: {
                ProjectsFullView(viewModel: viewModel)
            }
        ) {
            if allProjects.isEmpty {
                moduleEmptyState
            } else {
                VStack(spacing: WeekSpacing.sm) {
                    ForEach(allProjects) { project in
                        projectPreviewRow(project)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet, onDismiss: {
            viewModel.refresh()
        }) {
            CreateProjectSheet(viewModel: viewModel)
        }
    }

    private var moduleEmptyState: some View {
        VStack(spacing: WeekSpacing.sm) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(Color.weekyiiGradient)

            Text(String(localized: "project.empty.title"))
                .font(.subheadline)
                .foregroundColor(.textSecondary)

            Button {
                showingCreateSheet = true
            } label: {
                Text(String(localized: "project.add"))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, WeekSpacing.md)
                    .padding(.vertical, WeekSpacing.sm)
                    .background(Color.weekyiiGradient)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WeekSpacing.lg)
    }

    private func projectPreviewRow(_ project: ProjectModel) -> some View {
        NavigationLink(destination: ProjectDetailView(project: project, viewModel: viewModel)) {
            HStack(spacing: WeekSpacing.sm) {
                Image(systemName: project.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: project.color))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: project.color).opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: WeekSpacing.xs) {
                        Text(project.status.displayName)
                            .font(.caption)
                            .foregroundColor(.textTertiary)

                        Text("·")
                            .font(.caption)
                            .foregroundColor(.textTertiary)

                        Text(String(format: String(localized: "project.tasks.count"), project.totalTaskCount))
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color(hex: project.color).opacity(0.15), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(project.progress, 1.0)))
                        .stroke(Color(hex: project.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 22, height: 22)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(WeekSpacing.sm)
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.small))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mind Stamps Module Preview

private struct MindStampsModulePreview: View {
    let viewModel: MindStampViewModel
    @State private var showingEditor = false
    @State private var editingItem: MindStampItem?

    private var previewStamps: [MindStampItem] {
        Array(viewModel.stamps.prefix(4))
    }

    var body: some View {
        ModuleContainer(
            title: String(localized: "extensions.module.mindstamps.title"),
            subtitle: String(localized: "extensions.module.mindstamps.subtitle"),
            icon: "seal.fill",
            iconColor: .accentPink,
            seeAllAccessibilityID: "extensionsMindStampsSeeAllButton",
            destination: {
                MindStampsFullView(viewModel: viewModel)
            }
        ) {
            if previewStamps.isEmpty {
                moduleEmptyState
            } else {
                VStack(spacing: WeekSpacing.sm) {
                    ForEach(previewStamps) { stamp in
                        stampPreviewRow(stamp)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            viewModel.refresh()
        }) {
            MindStampEditorSheet(viewModel: viewModel)
        }
    }

    private var moduleEmptyState: some View {
        VStack(spacing: WeekSpacing.sm) {
            Image(systemName: "seal.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.accentPink)

            Text(String(localized: "mindstamp.empty.title"))
                .font(.subheadline)
                .foregroundColor(.textSecondary)

            Button {
                showingEditor = true
            } label: {
                Text(String(localized: "mindstamp.add"))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, WeekSpacing.md)
                    .padding(.vertical, WeekSpacing.sm)
                    .background(Color.accentPink)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WeekSpacing.lg)
    }

    private func stampPreviewRow(_ stamp: MindStampItem) -> some View {
        Button {
            editingItem = stamp
        } label: {
            HStack(spacing: WeekSpacing.sm) {
                if let blob = stamp.imageBlob, let uiImage = UIImage(data: blob) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.small))
                } else {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentPink)
                        .frame(width: 44, height: 44)
                        .background(Color.accentPink.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.small))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(stamp.text.isEmpty ? String(localized: "mindstamp.placeholder") : stamp.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    Text(stamp.createdAt, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(WeekSpacing.sm)
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.small))
        }
        .buttonStyle(.plain)
        .sheet(item: $editingItem, onDismiss: {
            viewModel.refresh()
        }) { item in
            MindStampEditorSheet(viewModel: viewModel, editingItem: item)
        }
    }
}

// MARK: - Module Container

private struct ModuleContainer<Content: View, Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let seeAllAccessibilityID: String?
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                Spacer()

                NavigationLink(destination: destination()) {
                    HStack(spacing: 2) {
                        Text(String(localized: "extensions.module.see_all"))
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.weekyiiPrimary)
                }
                .accessibilityIdentifier(seeAllAccessibilityID ?? "")
            }

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.textSecondary)

            content()
        }
        .padding(WeekSpacing.md)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium))
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Projects Full View (Wrapped Existing)

private struct ProjectsFullView: View {
    @State private var viewModel: ExtensionsViewModel
    @State private var showingCreateSheet = false
    @State private var addingTaskProject: ProjectModel?
    @State private var errorMessage: String?

    init(viewModel: ExtensionsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WeekSpacing.md) {
                if viewModel.projects.isEmpty {
                    emptyStateView
                } else {
                    LazyVGrid(columns: tileColumns, spacing: WeekSpacing.sm) {
                        ForEach(viewModel.projects) { project in
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
                }

                if shouldShowFooterCreateButton {
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
                    .accessibilityIdentifier("projectsFooterCreateButton")
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.bottom, WeekSpacing.lg)
                }
            }
            .padding(.horizontal, WeekSpacing.base)
            .padding(.top, WeekSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "extensions.tab.projects"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCreateSheet, onDismiss: {
            viewModel.refresh()
        }) {
            CreateProjectSheet(viewModel: viewModel)
        }
        .sheet(item: $addingTaskProject, onDismiss: {
            viewModel.refresh()
        }) { project in
            AddProjectTaskSheet(project: project, viewModel: viewModel)
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
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

    private var tileColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 140), spacing: WeekSpacing.sm),
            GridItem(.flexible(minimum: 140), spacing: WeekSpacing.sm)
        ]
    }

    private var shouldShowFooterCreateButton: Bool {
        !viewModel.projects.isEmpty
    }

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
                .accessibilityIdentifier("projectsEmptyCreateButton")
                .buttonStyle(ScaleButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
    }
}

// MARK: - Mind Stamps Full View (Wrapped Existing)

private struct MindStampsFullView: View {
    @State var viewModel: MindStampViewModel
    @State private var showingEditor = false

    init(viewModel: MindStampViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WeekSpacing.md) {
                if viewModel.stamps.isEmpty {
                    emptyState
                } else {
                    MindStampListView(viewModel: viewModel)
                }

                if shouldShowFooterCreateButton {
                    Button {
                        showingEditor = true
                    } label: {
                        HStack(spacing: WeekSpacing.xs) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text(String(localized: "mindstamp.add"))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, WeekSpacing.xl)
                        .padding(.vertical, WeekSpacing.md)
                        .background(Color.accentPink)
                        .clipShape(Capsule())
                        .shadow(color: Color.accentPink.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .accessibilityIdentifier("mindstampsFooterCreateButton")
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.bottom, WeekSpacing.lg)
                }
            }
            .padding(.horizontal, WeekSpacing.base)
            .padding(.top, WeekSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "extensions.tab.mindstamps"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor, onDismiss: {
            viewModel.refresh()
        }) {
            MindStampEditorSheet(viewModel: viewModel)
        }
    }

    private var shouldShowFooterCreateButton: Bool {
        !viewModel.stamps.isEmpty
    }

    private var emptyState: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentPink)

                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "mindstamp.empty.title"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)

                    Text(String(localized: "mindstamp.empty.subtitle"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showingEditor = true
                } label: {
                    HStack(spacing: WeekSpacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text(String(localized: "mindstamp.add"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, WeekSpacing.xl)
                    .padding(.vertical, WeekSpacing.md)
                    .background(Color.accentPink)
                    .clipShape(Capsule())
                    .shadow(color: Color.accentPink.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .accessibilityIdentifier("mindstampsEmptyCreateButton")
                .buttonStyle(ScaleButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
    }
}

// MARK: - Masonry Layout

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

// MARK: - Project Inline Card

private struct ProjectInlineCard: View {
    let project: ProjectModel
    let viewModel: ExtensionsViewModel
    let onAddTask: () -> Void

    private let maxVisibleTasks = 2
    @State private var appeared = false

    private var projectColor: Color { Color(hex: project.color) }
    private var isFinished: Bool { project.status == .completed || project.status == .archived }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinearGradient(
                colors: [projectColor, projectColor.opacity(0.6)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 5)

            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                cardHeader
                quickStats
                taskList

                if !isFinished {
                    addButton
                }
            }
            .padding(WeekSpacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .stroke(projectColor.opacity(0.15), lineWidth: 1)
        )
        .overlay {
            if isFinished {
                RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                    .fill(Color.backgroundSecondary.opacity(0.5))
                    .overlay {
                        VStack(spacing: WeekSpacing.xs) {
                            Image(systemName: project.status == .archived ? "archivebox.fill" : "checkmark.seal.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(project.status == .archived ? Color.textTertiary : Color.accentGreen)
                            Text(project.status.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(project.status == .archived ? .textTertiary : .accentGreen)
                        }
                    }
            }
        }
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.xs) {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: project.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(projectColor)

                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }

            HStack(spacing: WeekSpacing.xs) {
                Text(project.status.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(projectColor.opacity(0.12))
                    .foregroundColor(projectColor)
                    .clipShape(Capsule())

                Spacer()

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
                .frame(width: 24, height: 24)
            }
        }
    }

    private var quickStats: some View {
        HStack(spacing: WeekSpacing.xs) {
            statChip(
                icon: "checkmark.circle.fill",
                text: "\(project.completedTaskCount)",
                color: .accentGreen
            )
            statChip(
                icon: "clock",
                text: "\(max(project.totalTaskCount - project.completedTaskCount, 0))",
                color: .textSecondary
            )
            if project.expiredTaskCount > 0 {
                statChip(
                    icon: "exclamationmark.triangle.fill",
                    text: "\(project.expiredTaskCount)",
                    color: .taskDDL
                )
            }
        }
    }

    private func statChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }

    private var taskList: some View {
        let tasks = project.tasks.sorted { $0.order < $1.order }
        let displayTasks = Array(tasks.prefix(maxVisibleTasks))
        let remaining = tasks.count - displayTasks.count

        return VStack(alignment: .leading, spacing: WeekSpacing.xs) {
            if tasks.isEmpty {
                Text(String(localized: "project.tasks.empty"))
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .padding(.vertical, WeekSpacing.xs)
            } else {
                ForEach(displayTasks) { task in
                    taskRow(task)
                }

                if remaining > 0 {
                    Text(String(format: String(localized: "project.card.more"), remaining))
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
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
                    .font(.system(size: 12))
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
        }
    }

    private var addButton: some View {
        Button {
            onAddTask()
        } label: {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                Text(String(localized: "project.card.add_task"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(projectColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(projectColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
