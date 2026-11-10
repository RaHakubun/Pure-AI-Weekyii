import SwiftUI

struct ProjectDetailView: View {
    let project: ProjectModel
    let viewModel: ExtensionsViewModel

    @State private var showingAddTaskSheet = false
    @State private var showingEditProjectSheet = false
    @State private var showingDeleteAlert = false
    @State private var deletingTask: TaskItem?
    @State private var editingTask: TaskItem?
    @State private var selectedDayID: String?
    @State private var expandedTaskIDs: Set<UUID> = []
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.weekLayoutMetrics) private var layoutMetrics

    /// 详情页为浅色底，项目色全部走前景/描边用途，亮色系压暗后才可读。
    private var projectColor: Color { Color.weekyiiEmphasis(hex: project.color) }
    private var snapshot: ProjectDetailSnapshot { viewModel.projectDetailSnapshot(for: project) }
    private var isProjectWritable: Bool { project.status == .planning || project.status == .active }

    var body: some View {
        ScrollView {
            Group {
                if layoutMetrics.layoutClass.supportsTwoColumns {
                    HStack(alignment: .top, spacing: WeekSpacing.xl) {
                        VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                            identitySection
                            lifecycleSection
                            summarySection
                        }
                        .frame(width: layoutMetrics.auxiliaryColumnWidth)

                        ledgerSection
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                        identitySection
                        lifecycleSection
                        summarySection
                        ledgerSection
                    }
                }
            }
            .padding(.horizontal, layoutMetrics.pageHorizontalPadding)
            .padding(.vertical, WeekSpacing.base)
            .weekReadableContent()
        }
        .background(Color.backgroundPrimary)
        .navigationTitle(snapshot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAddTaskSheet, onDismiss: { viewModel.refresh() }) {
            AddProjectTaskSheet(project: project, viewModel: viewModel)
                .weekFormWidth()
        }
        .sheet(isPresented: $showingEditProjectSheet, onDismiss: { viewModel.refresh() }) {
            CreateProjectSheet(viewModel: viewModel, projectToEdit: project)
                .weekFormWidth()
        }
        .sheet(item: $editingTask, onDismiss: { viewModel.refresh() }) { task in
            TaskEditorSheet(
                title: String(localized: "draft.edit_title"),
                initialTitle: task.title,
                initialDescription: task.taskDescription,
                initialType: task.taskType,
                initialTypeIdRaw: task.taskTypeIdRaw,
                initialSteps: task.steps,
                initialAttachments: task.attachments
            ) { _, _, _, _, _ in
            } onSaveWithTypeId: { title, description, type, typeIdRaw, steps, attachments in
                viewModel.updateProjectTask(
                    task,
                    title: title,
                    description: description,
                    type: type,
                    taskTypeIdRaw: typeIdRaw,
                    steps: steps,
                    attachments: attachments
                )
                editingTask = nil
            }
            .weekFormWidth()
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
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let newValue { errorMessage = newValue }
        }
        .alert(String(localized: "alert.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isProjectWritable {
                Button {
                    showingAddTaskSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(projectColor)
                }
            }

            Menu {
                if isProjectWritable {
                    Button("编辑项目信息", systemImage: "pencil") {
                        showingEditProjectSheet = true
                    }
                }
                if project.status == .active && project.isAllCompleted {
                    Button(String(localized: "project.action.complete")) {
                        viewModel.updateStatus(project, to: .completed)
                    }
                }
                if project.status == .completed {
                    Button(String(localized: "project.action.archive")) {
                        viewModel.updateStatus(project, to: .archived)
                    }
                    Button("重新打开项目") {
                        viewModel.updateStatus(project, to: .active)
                    }
                }
                if project.status == .archived {
                    Button("恢复到已完成") {
                        viewModel.updateStatus(project, to: .completed)
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
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(alignment: .top, spacing: WeekSpacing.md) {
                    Image(systemName: snapshot.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.weekyiiOnFeature)
                        .frame(width: 48, height: 48)
                        .background(Color.weekyiiOnFeature.opacity(0.2))
                        .clipShape(.rect(cornerRadius: WeekRadius.medium))

                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        Text(snapshot.name)
                            .font(.titleMedium)
                            .foregroundStyle(Color.weekyiiOnFeature)
                            .fixedSize(horizontal: false, vertical: true)
                        if !snapshot.projectDescription.isEmpty {
                            Text(snapshot.projectDescription)
                                .font(.caption)
                                .foregroundStyle(Color.weekyiiOnFeatureSecondary)
                                .lineLimit(3)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(snapshot.status.displayName)
                        .font(.captionBold)
                        .foregroundStyle(projectColor)
                        .padding(.horizontal, WeekSpacing.sm)
                        .padding(.vertical, WeekSpacing.xs)
                        .background(Capsule().fill(Color.white))
                }
                Rectangle().fill(Color.weekyiiOnFeature.opacity(0.25)).frame(height: 1)
                HStack {
                    Text(dateRangeText)
                    Spacer(minLength: WeekSpacing.sm)
                    Text(String(localized: "project.detail.period", defaultValue: "项目周期"))
                }
                .font(.caption)
                .foregroundStyle(Color.weekyiiOnFeatureSecondary)
            }
        }
    }

    @ViewBuilder
    private var lifecycleSection: some View {
        if project.status == .active && project.isAllCompleted {
            WeekCard(accentColor: .accentGreen) {
                HStack(spacing: WeekSpacing.md) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentGreen)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("所有项目任务均已完成")
                            .font(.titleSmall)
                            .foregroundStyle(Color.textPrimary)
                        Text("确认结项后，项目将进入只读状态。")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Button("确认结项") {
                        viewModel.updateStatus(project, to: .completed)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentGreen)
                }
            }
        } else if project.status == .completed {
            WeekCard(accentColor: projectColor) {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    Label("项目已完成", systemImage: "checkmark.circle.fill")
                        .font(.titleSmall)
                        .foregroundStyle(Color.accentGreen)
                    Text("已完成项目保持只读。你可以归档收纳，或重新打开继续添加任务。")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    HStack {
                        Button("重新打开") {
                            viewModel.updateStatus(project, to: .active)
                        }
                        .buttonStyle(.bordered)
                        Button("归档项目") {
                            viewModel.updateStatus(project, to: .archived)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        } else if project.status == .archived {
            WeekCard {
                HStack(spacing: WeekSpacing.md) {
                    Image(systemName: "archivebox.fill")
                        .font(.title2)
                        .foregroundStyle(Color.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("项目已归档")
                            .font(.titleSmall)
                            .foregroundStyle(Color.textPrimary)
                        Text("任务记录仍然保留，恢复后可重新打开项目。")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Button("恢复") {
                        viewModel.updateStatus(project, to: .completed)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var openTaskCount: Int {
        max(snapshot.remainingCount - snapshot.expiredCount, 0)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            Text(String(localized: "project.detail.progress", defaultValue: "项目进展"))
                .font(.titleMedium)
                .foregroundStyle(Color.textPrimary)

            WeekCard(accentColor: projectColor) {
                VStack(alignment: .leading, spacing: WeekSpacing.md) {
                    HStack(alignment: .firstTextBaseline, spacing: WeekSpacing.xs) {
                        Text("\(snapshot.completedCount) / \(snapshot.totalCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.textPrimary)
                        Text(String(localized: "project.detail.items_completed", defaultValue: "项已完成"))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    progressBar
                    HStack(alignment: .top, spacing: WeekSpacing.sm) {
                        summaryMetric(String(localized: "project.stat.completed"), value: snapshot.completedCount, color: .accentGreen)
                        summaryMetric(String(localized: "project.stat.expired"), value: snapshot.expiredCount, color: .taskDDL)
                        summaryMetric(String(localized: "project.detail.open", defaultValue: "未逾期待办"), value: openTaskCount, color: .textPrimary)
                    }
                    if snapshot.expiredCount > 0 {
                        Label {
                            Text(expiredCountText(snapshot.expiredCount))
                                .font(.captionBold)
                            + Text(String(localized: "project.detail.overdue_in_remaining", defaultValue: " · 计入剩余任务"))
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill")
                        }
                        .foregroundStyle(Color.taskDDL)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(WeekSpacing.sm)
                        .background(Color.taskDDL.opacity(0.10))
                        .clipShape(.rect(cornerRadius: WeekRadius.medium))
                    }
                }
            }

            WeekCard {
                HStack(alignment: .center, spacing: WeekSpacing.sm) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(projectColor)
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        Text(String(localized: "project.detail.next", defaultValue: "下一步"))
                            .font(.captionBold)
                            .foregroundStyle(Color.textPrimary)
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
                            Text(String(localized: "project.detail.no_next", defaultValue: "暂无待办任务"))
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    Spacer(minLength: WeekSpacing.sm)
                    if snapshot.nextTaskTitle == nil && isProjectWritable {
                        Button {
                            showingAddTaskSheet = true
                        } label: {
                            Label(String(localized: "project.detail.add_task", defaultValue: "添加任务"), systemImage: "plus")
                                .font(.captionBold)
                                .foregroundStyle(projectColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            let total = max(snapshot.totalCount, 0)
            let completed = min(max(snapshot.completedCount, 0), total)
            let overdue = min(max(snapshot.expiredCount, 0), total - completed)
            HStack(spacing: 0) {
                if total > 0 {
                    Color.accentGreen.frame(width: geometry.size.width * CGFloat(completed) / CGFloat(total))
                    Color.taskDDL.frame(width: geometry.size.width * CGFloat(overdue) / CGFloat(total))
                }
                Color.backgroundTertiary
            }
            .clipShape(Capsule())
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }

    private func summaryMetric(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.xs) {
            Text("\(value)")
                .font(.titleSmall)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "project.detail.weekly_tasks", defaultValue: "每周任务"))
                    .font(.titleMedium)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: WeekSpacing.sm)
                if !snapshot.sections.isEmpty {
                    Text(String(localized: "project.detail.select_day", defaultValue: "点击日期查看任务"))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            if snapshot.sections.isEmpty {
                WeekCard {
                    VStack(spacing: WeekSpacing.md) {
                        Image(systemName: "tray")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.textTertiary)
                        Text(String(localized: "project.tasks.empty"))
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textSecondary)
                        if isProjectWritable {
                            Button {
                                showingAddTaskSheet = true
                            } label: {
                                Text(String(localized: "project.tasks.add_first"))
                                    .font(.bodyMedium)
                                    .foregroundStyle(projectColor)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .weekPaddingVertical(WeekSpacing.lg)
                }
            } else {
                HStack(spacing: WeekSpacing.md) {
                    legendItem("checkmark", title: String(localized: "project.stat.completed"), color: .accentGreen)
                    legendItem("exclamationmark", title: String(localized: "project.stat.expired"), color: .taskDDL)
                    legendItem("circle.fill", title: String(localized: "project.detail.open", defaultValue: "未逾期待办"), color: projectColor)
                }
                ForEach(ProjectDetailWeek.groups(from: snapshot.sections)) { week in
                    weekCard(week)
                }
            }
        }
    }

    private func legendItem(_ symbol: String, title: String, color: Color) -> some View {
        HStack(spacing: WeekSpacing.xs) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
    }

    private func weekCard(_ week: ProjectDetailWeek) -> some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(weekDate(week.start, week: week)) – \(weekDate(week.end, week: week))")
                        .font(.titleSmall)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: WeekSpacing.xs)
                    Text(String(localized: "project.detail.monday_sunday", defaultValue: "周一至周日"))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                HStack(spacing: WeekSpacing.md) {
                    Text(countText(String(localized: "project.detail.week_completed", defaultValue: "完成 %lld"), count: week.completedCount))
                        .foregroundStyle(Color.textSecondary)
                    if week.expiredCount > 0 {
                        Text(countText(String(localized: "project.detail.week_expired", defaultValue: "逾期 %lld"), count: week.expiredCount))
                            .foregroundStyle(Color.taskDDL)
                    }
                    if week.openCount > 0 {
                        Text(countText(String(localized: "project.detail.week_open", defaultValue: "待办 %lld"), count: week.openCount))
                            .foregroundStyle(projectColor)
                    }
                }
                .font(.caption)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(week.days, id: \.dayId) { date in
                        dayButton(date, section: week.section(on: date))
                    }
                }

                if let selectedDayID, let date = week.days.first(where: { $0.dayId == selectedDayID }) {
                    Divider()
                    selectedDayDetail(date, section: week.section(on: date))
                }
            }
        }
    }

    private func dayButton(_ date: Date, section: ProjectTaskLedgerSection?) -> some View {
        let selected = selectedDayID == date.dayId
        let completed = section?.tasks.filter { $0.zone == .complete }.count ?? 0
        let open = section?.tasks.filter { $0.zone != .complete }.count ?? 0
        let overdue = section?.expiredCount ?? 0
        let accessibilitySummary = [
            countText(String(localized: "project.detail.week_completed", defaultValue: "完成 %lld"), count: completed),
            countText(String(localized: "project.detail.week_expired", defaultValue: "逾期 %lld"), count: overdue),
            countText(String(localized: "project.detail.week_open", defaultValue: "待办 %lld"), count: open)
        ].joined(separator: ", ")
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDayID = selected ? nil : date.dayId
            }
        } label: {
            VStack(spacing: WeekSpacing.xs) {
                Text(WeekyiiWeekday.localizedSymbol(for: date.isoWeekday))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                VStack(spacing: WeekSpacing.xs) {
                    Text("\(WeekyiiTimeZone.calendar.component(.day, from: date))")
                        .font(.captionBold)
                        .foregroundStyle(selected ? projectColor : Color.textPrimary)
                    HStack(spacing: 2) {
                        if completed > 0 { dayMarker("checkmark", color: .accentGreen) }
                        if overdue > 0 { dayMarker("exclamationmark", color: .taskDDL) }
                        if open > 0 { dayMarker("circle.fill", color: projectColor) }
                        if completed + overdue + open == 0 {
                            Text("·").font(.caption).foregroundStyle(selected ? projectColor : Color.textTertiary)
                        }
                    }
                    .frame(height: 11)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(selected ? projectColor.opacity(0.14) : Color.clear)
                .clipShape(.rect(cornerRadius: WeekRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: WeekRadius.medium).stroke(selected ? projectColor : Color.clear, lineWidth: 1))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(shortDate(date)), \(WeekyiiWeekday.localizedSymbol(for: date.isoWeekday)), \(accessibilitySummary)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayMarker(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
    }

    private func selectedDayDetail(_ date: Date, section: ProjectTaskLedgerSection?) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HStack {
                Text("\(shortDate(date)) · \(WeekyiiWeekday.localizedSymbol(for: date.isoWeekday))")
                    .font(.captionBold)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                let count = (section?.tasks.count ?? 0) + (section?.expiredCount ?? 0)
                Text(countText(String(localized: "project.detail.day_count", defaultValue: "%lld 项任务"), count: count))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            if let section {
                if section.expiredCount > 0 {
                    Label(expiredCountText(section.expiredCount), systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.taskDDL)
                }
                ForEach(section.tasks) { task in
                    taskRow(task)
                }
            } else {
                Text(String(localized: "project.detail.no_tasks_day", defaultValue: "当天没有任务"))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func countText(_ template: String, count: Int) -> String {
        String(format: template, locale: Locale.current, Int64(count))
    }

    private func shortDate(_ date: Date) -> String {
        formattedDate(date, includingYear: false)
    }

    private func weekDate(_ date: Date, week: ProjectDetailWeek) -> String {
        let calendar = WeekyiiTimeZone.calendar
        let crossesYear = calendar.component(.year, from: week.start) != calendar.component(.year, from: week.end)
        let spansYears = Set(snapshot.sections.map { calendar.component(.year, from: $0.date) }).count > 1
        return formattedDate(date, includingYear: crossesYear || spansYears)
    }

    private func formattedDate(_ date: Date, includingYear: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = WeekyiiTimeZone.timeZone
        formatter.setLocalizedDateFormatFromTemplate(includingYear ? "yMMMd" : "MMMd")
        return formatter.string(from: date)
    }

    private func taskRow(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HStack(alignment: .top, spacing: WeekSpacing.sm) {
                Button {
                    toggleTaskExpansion(task.id)
                } label: {
                    TaskRowView(task: task)
                }
                .buttonStyle(.plain)

                if canEditTaskFromProject(task) {
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
        "\(shortDate(snapshot.startDate)) – \(shortDate(snapshot.endDate))"
    }

    private func canEditTaskFromProject(_ task: TaskItem) -> Bool {
        guard isProjectWritable, let day = task.day else { return false }
        return (day.status == .empty || day.status == .draft) && task.zone == .draft
    }

    private func toggleTaskExpansion(_ id: UUID) {
        if expandedTaskIDs.contains(id) {
            expandedTaskIDs.remove(id)
        } else {
            expandedTaskIDs.insert(id)
        }
    }

    private func expiredCountText(_ count: Int) -> String {
        String(
            format: String(localized: "extensions.hub.projects.status.overdue", defaultValue: "%lld 项已逾期"),
            locale: Locale.current,
            Int64(count)
        )
    }
}

/// View-only weekly grouping. Uses the same anchored ISO week as the rest of Weekyii.
struct ProjectDetailWeek: Identifiable {
    let start: Date
    let sections: [ProjectTaskLedgerSection]

    var id: String { start.dayId }
    var end: Date { start.addingDays(6) }
    var days: [Date] { (0..<7).map { start.addingDays($0) } }
    var completedCount: Int { sections.reduce(0) { $0 + $1.tasks.filter { $0.zone == .complete }.count } }
    var expiredCount: Int { sections.reduce(0) { $0 + $1.expiredCount } }
    var openCount: Int { sections.reduce(0) { $0 + $1.tasks.filter { $0.zone != .complete }.count } }

    func section(on date: Date) -> ProjectTaskLedgerSection? {
        sections.first { $0.id == date.dayId }
    }

    static func groups(from sections: [ProjectTaskLedgerSection]) -> [ProjectDetailWeek] {
        let grouped = Dictionary(grouping: sections) { $0.date.startOfWeek }
        return grouped.map { start, days in
            ProjectDetailWeek(start: start, sections: days.sorted { $0.date < $1.date })
        }.sorted { $0.start < $1.start }
    }
}
