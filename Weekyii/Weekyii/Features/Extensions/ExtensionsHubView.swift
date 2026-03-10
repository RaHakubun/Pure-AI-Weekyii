import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    private enum BoardMetrics {
        static let columns = 4
        static let columnSpacing: CGFloat = 6
        static let rowSpacing: CGFloat = 6
        static let horizontalPadding: CGFloat = 16
        static let footerSpacing: CGFloat = 32
    }

    @State private var viewModel: ExtensionsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingCreateSheet = false
    @State private var tileProjects: [ProjectModel] = []
    @State private var isEditingTiles = false
    @State private var draggingProjectID: UUID?
    @State private var deletingProject: ProjectModel?
    @State private var liveTick: Int = 0
    @State private var errorMessage: String?

    init(viewModel: ExtensionsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(String(localized: "extensions.tab.projects"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editToolbar }
            .sheet(isPresented: $showingCreateSheet, onDismiss: {
                viewModel.refresh()
            }) {
                CreateProjectSheet(viewModel: viewModel)
            }
            .onAppear {
                syncTileProjectsFromModel(force: true)
            }
            .onChange(of: viewModel.projects.map(\.id)) { _, _ in
                syncTileProjectsFromModel(force: draggingProjectID == nil)
            }
            .task(id: tickerTaskKey) {
                guard scenePhase == .active, !isEditingTiles else { return }
                while !Task.isCancelled, scenePhase == .active, !isEditingTiles {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled, scenePhase == .active, !isEditingTiles else { break }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        liveTick &+= 1
                    }
                }
            }
            .confirmationDialog(
                String(localized: "project.delete.confirm"),
                isPresented: Binding(
                    get: { deletingProject != nil },
                    set: { if !$0 { deletingProject = nil } }
                ),
                titleVisibility: .visible
            ) {
                deleteDialogActions
            } message: {
                Text(String(localized: "project.delete.choice.message"))
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

    private var content: some View {
        ScrollView {
            VStack(spacing: WeekSpacing.md) {
                if viewModel.projects.isEmpty {
                    emptyStateView
                } else {
                    if isEditingTiles {
                        Text(String(localized: "project.tiles.edit_hint"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }

                    ProjectTileGridLayout(
                        columns: BoardMetrics.columns,
                        columnSpacing: BoardMetrics.columnSpacing,
                        rowSpacing: BoardMetrics.rowSpacing
                    ) {
                        ForEach(tileProjects) { project in
                            tileView(for: project)
                                .layoutValue(key: TileColSpanLayoutKey.self, value: project.tileSize.colSpan)
                                .layoutValue(key: TileRowSpanLayoutKey.self, value: project.tileSize.rowSpan)
                        }
                    }
                    .animation(draggingProjectID == nil ? .interactiveSpring(response: 0.22, dampingFraction: 0.88) : nil, value: tileProjects.map(\.id))
                    .animation(draggingProjectID == nil ? .interactiveSpring(response: 0.22, dampingFraction: 0.88) : nil, value: tileProjects.map(\.tileSizeRaw))
                    .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.9), value: isEditingTiles)
                    .transaction { transaction in
                        if draggingProjectID != nil {
                            transaction.animation = nil
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
                    .padding(.top, BoardMetrics.footerSpacing)
                    .padding(.bottom, BoardMetrics.footerSpacing)
                }
            }
            .padding(.horizontal, BoardMetrics.horizontalPadding)
            .padding(.top, WeekSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        if !viewModel.projects.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditingTiles ? String(localized: "action.done") : String(localized: "action.edit")) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        isEditingTiles.toggle()
                        if !isEditingTiles {
                            draggingProjectID = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var deleteDialogActions: some View {
        if let project = deletingProject {
            Button(String(localized: "project.delete.choice.only_project"), role: .destructive) {
                viewModel.deleteProject(project, includeTasks: false)
                deletingProject = nil
            }
            Button(String(localized: "project.delete.choice.with_tasks"), role: .destructive) {
                viewModel.deleteProject(project, includeTasks: true)
                deletingProject = nil
            }
        }
        Button(String(localized: "action.cancel"), role: .cancel) {
            deletingProject = nil
        }
    }

    private var shouldShowFooterCreateButton: Bool {
        !viewModel.projects.isEmpty
    }

    private var tickerTaskKey: String {
        "\(scenePhase == .active)-\(isEditingTiles)"
    }

    private func syncTileProjectsFromModel(force: Bool) {
        guard force else { return }
        tileProjects = viewModel.sortedProjectsForBoard()
    }

    @ViewBuilder
    private func tileView(for project: ProjectModel) -> some View {
        let snapshot = snapshotForTile(project)
        let isCompactTile = project.tileSize == .mini || project.tileSize == .small
        let overlayPadding: CGFloat = isCompactTile ? 3 : 6
        let deleteButtonSize: CGFloat = isCompactTile ? 14 : 20
        let resizeIconSize: CGFloat = isCompactTile ? 9 : 12
        let resizeButtonPadding: CGFloat = isCompactTile ? 5 : 8
        let isDraggingTile = draggingProjectID == project.id

        if isEditingTiles {
            ProjectMetroTileView(
                snapshot: snapshot,
                tileSize: project.tileSize,
                statusText: project.status.displayName,
                liveTick: liveTick,
                isEditing: true,
                isDragging: isDraggingTile
            )
            .overlay(alignment: .topTrailing) {
                Button {
                    deletingProject = project
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: deleteButtonSize, weight: .bold))
                        .foregroundStyle(.white, .red)
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                }
                .padding(overlayPadding)
                .buttonStyle(.plain)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        viewModel.cycleTileSize(for: project)
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: resizeIconSize, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(resizeButtonPadding)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .padding(overlayPadding)
                .buttonStyle(.plain)
            }
            .contentShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
            .opacity(isDraggingTile ? 0.86 : 1)
            .onDrag {
                draggingProjectID = project.id
                return NSItemProvider(object: NSString(string: project.id.uuidString))
            } preview: {
                Color.clear
                    .frame(width: 1, height: 1)
            }
            .onDrop(
                of: [UTType.text.identifier],
                delegate: ProjectTileDropDelegate(
                    targetProjectID: project.id,
                    projects: $tileProjects,
                    draggingProjectID: $draggingProjectID
                ) { orderedIDs in
                    viewModel.updateTileOrder(with: orderedIDs)
                }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        isEditingTiles = true
                    }
                }
            )
        } else {
            NavigationLink(destination: ProjectDetailView(project: project, viewModel: viewModel)) {
                ProjectMetroTileView(
                    snapshot: snapshot,
                    tileSize: project.tileSize,
                    statusText: project.status.displayName,
                    liveTick: liveTick,
                    isEditing: false,
                    isDragging: false
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        isEditingTiles = true
                    }
                }
            )
        }
    }

    private func snapshotForTile(_ project: ProjectModel) -> ProjectTileSnapshot {
        viewModel.tileSnapshotsByProjectID[project.id] ?? ProjectTileSnapshot(
            projectID: project.id,
            name: project.name,
            icon: project.icon,
            colorHex: project.color,
            progress: project.progress,
            completedCount: project.completedTaskCount,
            totalCount: project.totalTaskCount,
            remainingCount: max(project.totalTaskCount - project.completedTaskCount, 0),
            expiredCount: project.expiredTaskCount,
            nextTaskTitle: nil,
            nextTaskDate: nil
        )
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

private struct ProjectMetroTileView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let snapshot: ProjectTileSnapshot
    let tileSize: ProjectTileSize
    let statusText: String
    let liveTick: Int
    let isEditing: Bool
    let isDragging: Bool
    @State private var breathing = false

    private var projectColor: Color { Color(hex: snapshot.colorHex) }

    var body: some View {
        let presentation = ProjectTilePresentation(
            snapshot: snapshot,
            size: tileSize,
            isEditing: isEditing,
            liveTick: liveTick
        )

        tileContent(presentation: presentation)
        .padding(.top, presentation.contentInsets.top)
        .padding(.leading, presentation.contentInsets.leading)
        .padding(.bottom, presentation.contentInsets.bottom)
        .padding(.trailing, presentation.contentInsets.trailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .stroke(isEditing ? .white.opacity(0.22) : .white.opacity(0.12), lineWidth: isEditing ? 1.5 : 1)
        )
        .shadow(
            color: .black.opacity(isDragging ? 0.16 : 0.10),
            radius: isDragging ? 8 : 5,
            x: 0,
            y: isDragging ? 4 : 3
        )
        .scaleEffect(scaleValue)
        .onAppear {
            if !reduceMotion {
                breathing = true
            }
        }
        .animation(
            reduceMotion || isEditing ? .default : .easeInOut(duration: 1.9).repeatForever(autoreverses: true),
            value: breathing
        )
    }

    @ViewBuilder
    private func tileContent(presentation: ProjectTilePresentation) -> some View {
        switch tileSize {
        case .mini:
            miniTileBody(presentation: presentation)
        case .small:
            smallTileBody(presentation: presentation)
        case .medium:
            mediumTileBody(presentation: presentation)
        case .wide:
            wideTileBody(presentation: presentation)
        }
    }

    private var tileBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    projectColor.opacity(0.95),
                    projectColor.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    .white.opacity(breathing && !isEditing ? 0.18 : 0.08),
                    .white.opacity(0.02),
                    .black.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .fill(.white.opacity(0.05))
                .padding(1)
        }
    }

    private func miniTileBody(presentation: ProjectTilePresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            tileIconBadge(size: 10)

            Spacer(minLength: 0)

            miniPrimaryPanel(for: presentation.livePanel)

            if !isEditing {
                Text(snapshot.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(presentation.titleLineLimit)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func smallTileBody(presentation: ProjectTilePresentation) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                tileIconBadge(size: 9)

                Spacer(minLength: 0)

                if !isEditing {
                    Text(snapshot.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 0)

            smallPrimaryPanel(for: presentation.livePanel)
        }
    }

    private func mediumTileBody(presentation: ProjectTilePresentation) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            tileHeader(presentation: presentation, titleFontSize: 17, titleWeight: .bold)

            Spacer(minLength: 0)

            mediumPrimaryPanel(for: presentation.livePanel)
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.28), value: presentation.livePanel)
        }
    }

    private func wideTileBody(presentation: ProjectTilePresentation) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            tileHeader(presentation: presentation, titleFontSize: 16, titleWeight: .bold)

            Spacer(minLength: 0)

            widePrimaryPanel(for: presentation.livePanel)
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.28), value: presentation.livePanel)
        }
    }

    private func tileHeader(
        presentation: ProjectTilePresentation,
        titleFontSize: CGFloat,
        titleWeight: Font.Weight
    ) -> some View {
        HStack(alignment: .top, spacing: WeekSpacing.xs) {
            tileIconBadge(size: 11)

            Text(snapshot.name)
                .font(.system(size: titleFontSize, weight: titleWeight, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(presentation.titleLineLimit)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)

            if presentation.showsStatusChip {
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(projectColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.96), in: Capsule())
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
    }

    private func tileIconBadge(size: CGFloat) -> some View {
        Image(systemName: snapshot.icon)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.white.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func miniPrimaryPanel(for panel: ProjectTileLivePanel) -> some View {
        switch panel {
        case .progress:
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(Int(snapshot.progress * 100))")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
        case .metrics, .nextTask:
            HStack(spacing: 4) {
                Image(systemName: snapshot.remainingCount > 0 ? "clock.fill" : "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(snapshot.remainingCount > 0 ? .white.opacity(0.9) : Color.accentGreen)
                Text("\(snapshot.remainingCount > 0 ? snapshot.remainingCount : snapshot.completedCount)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private func smallPrimaryPanel(for panel: ProjectTileLivePanel) -> some View {
        switch panel {
        case .progress:
            VStack(alignment: .trailing, spacing: 2) {
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(Int(snapshot.progress * 100))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
            }
        case .metrics, .nextTask:
            VStack(alignment: .trailing, spacing: 2) {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: snapshot.remainingCount > 0 ? "clock.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(snapshot.remainingCount > 0 ? .white.opacity(0.9) : Color.accentGreen)
                    Text("\(snapshot.remainingCount > 0 ? snapshot.remainingCount : snapshot.completedCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @ViewBuilder
    private func mediumPrimaryPanel(for panel: ProjectTileLivePanel) -> some View {
        switch panel {
        case .progress:
            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(Int(snapshot.progress * 100))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.system(size: 18, weight: .semibold))
                }

                HStack(spacing: WeekSpacing.sm) {
                    metricCard(title: String(localized: "project.stat.completed"), value: snapshot.completedCount, tint: .accentGreen)
                    metricCard(title: String(localized: "project.stat.total"), value: snapshot.totalCount, tint: .white)
                }
            }
        case .metrics:
            HStack(spacing: WeekSpacing.sm) {
                metricCard(title: String(localized: "project.stat.completed"), value: snapshot.completedCount, tint: .accentGreen)
                metricCard(title: String(localized: "project.stat.remaining"), value: snapshot.remainingCount, tint: .white)
            }
        case .nextTask:
            nextTaskPanel(showsDate: true, titleFontSize: 17, secondaryFontSize: 12)
        }
    }

    @ViewBuilder
    private func widePrimaryPanel(for panel: ProjectTileLivePanel) -> some View {
        switch panel {
        case .progress:
            HStack(alignment: .bottom, spacing: WeekSpacing.lg) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text("\(Int(snapshot.progress * 100))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.system(size: 14, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 6) {
                    compactStatLabel(String(localized: "project.stat.completed"), value: snapshot.completedCount)
                    compactStatLabel(String(localized: "project.stat.remaining"), value: snapshot.remainingCount)
                }
            }
        case .metrics:
            HStack(spacing: WeekSpacing.sm) {
                metricCard(title: String(localized: "project.stat.completed"), value: snapshot.completedCount, tint: .accentGreen)
                metricCard(title: String(localized: "project.stat.remaining"), value: snapshot.remainingCount, tint: .white)
                if snapshot.expiredCount > 0 {
                    metricCard(title: String(localized: "project.stat.expired"), value: snapshot.expiredCount, tint: .taskDDL)
                }
            }
        case .nextTask:
            nextTaskPanel(showsDate: true, titleFontSize: 18, secondaryFontSize: 12)
        }
    }

    private func nextTaskPanel(showsDate: Bool, titleFontSize: CGFloat, secondaryFontSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.nextTaskTitle ?? String(localized: "project.tasks.empty"))
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .lineLimit(2)

            if showsDate, let date = snapshot.nextTaskDate {
                Text(date, format: .dateTime.month().day())
                    .font(.system(size: secondaryFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
            }
        }
    }

    private func compactStatLabel(_ title: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
            Text("\(value)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func metricPill(icon: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text("\(value)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.16), in: Capsule())
    }

    private func metricCard(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous))
    }

    private var progressSummaryText: String {
        "\(snapshot.completedCount)/\(snapshot.totalCount) | \(snapshot.remainingCount) 剩余"
    }

    private var scaleValue: CGFloat {
        if isDragging { return 1.05 }
        if isEditing { return 0.97 }
        return 1.0
    }
}

private struct TileColSpanLayoutKey: LayoutValueKey {
    nonisolated static let defaultValue = 1
}

private struct TileRowSpanLayoutKey: LayoutValueKey {
    nonisolated static let defaultValue = 1
}

private struct ProjectTileGridLayout: Layout {
    let columns: Int
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let arranged = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: arranged.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in arranged.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], totalHeight: CGFloat) {
        let safeColumns = max(columns, 1)
        let totalSpacing = columnSpacing * CGFloat(max(safeColumns - 1, 0))
        let cell = max((width - totalSpacing) / CGFloat(safeColumns), 1)

        var occupancy: [[Bool]] = []
        var frames: [CGRect] = Array(repeating: .zero, count: subviews.count)
        var maxUsedRow = 0

        func ensureRows(_ count: Int) {
            while occupancy.count < count {
                occupancy.append(Array(repeating: false, count: safeColumns))
            }
        }

        func canPlace(row: Int, col: Int, colSpan: Int, rowSpan: Int) -> Bool {
            guard col + colSpan <= safeColumns else { return false }
            ensureRows(row + rowSpan)
            for r in row..<(row + rowSpan) {
                for c in col..<(col + colSpan) where occupancy[r][c] {
                    return false
                }
            }
            return true
        }

        func occupy(row: Int, col: Int, colSpan: Int, rowSpan: Int) {
            for r in row..<(row + rowSpan) {
                for c in col..<(col + colSpan) {
                    occupancy[r][c] = true
                }
            }
        }

        for (index, subview) in subviews.enumerated() {
            let colSpan = max(1, min(safeColumns, subview[TileColSpanLayoutKey.self]))
            let rowSpan = max(1, subview[TileRowSpanLayoutKey.self])
            var row = 0
            var placed = false

            while !placed {
                ensureRows(row + rowSpan)
                for col in 0...(safeColumns - colSpan) {
                    if canPlace(row: row, col: col, colSpan: colSpan, rowSpan: rowSpan) {
                        occupy(row: row, col: col, colSpan: colSpan, rowSpan: rowSpan)
                        let x = CGFloat(col) * (cell + columnSpacing)
                        let y = CGFloat(row) * (cell + rowSpacing)
                        let width = CGFloat(colSpan) * cell + CGFloat(colSpan - 1) * columnSpacing
                        let height = CGFloat(rowSpan) * cell + CGFloat(rowSpan - 1) * rowSpacing
                        frames[index] = CGRect(x: x, y: y, width: width, height: height)
                        maxUsedRow = max(maxUsedRow, row + rowSpan)
                        placed = true
                        break
                    }
                }
                if !placed {
                    row += 1
                }
            }
        }

        let totalHeight = CGFloat(maxUsedRow) * cell + CGFloat(max(maxUsedRow - 1, 0)) * rowSpacing
        return (frames, totalHeight)
    }
}

private struct ProjectTileDropDelegate: DropDelegate {
    let targetProjectID: UUID
    @Binding var projects: [ProjectModel]
    @Binding var draggingProjectID: UUID?
    let didReorder: ([UUID]) -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggingProjectID,
            draggingProjectID != targetProjectID,
            let from = projects.firstIndex(where: { $0.id == draggingProjectID }),
            let to = projects.firstIndex(where: { $0.id == targetProjectID })
        else {
            return
        }

        projects.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: to > from ? to + 1 : to
        )
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggingProjectID != nil else { return false }
        didReorder(projects.map(\.id))
        draggingProjectID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
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
