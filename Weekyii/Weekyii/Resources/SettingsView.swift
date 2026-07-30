import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    let workspaceSection: WorkspaceSettingsSection?

    init(workspaceSection: WorkspaceSettingsSection? = nil) {
        self.workspaceSection = workspaceSection
    }

    private static let archiveFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.weekLayoutMetrics) private var layoutMetrics
    @Query(sort: \TaskTypeDefinition.sortOrder) private var taskTypeDefinitions: [TaskTypeDefinition]
    @State private var seedAlertMessage: String?
    @State private var showingClearConfirm = false
    @State private var pendingDefaultKillTimeHour = 0
    @State private var pendingDefaultKillTimeMinute = 0
    @State private var hasInitializedPendingDefaultKillTime = false
    @State private var showingDefaultKillTimeApplyConfirm = false
    @State private var showingDefaultKillTimeRiskConfirm = false
    @State private var showingCannotSyncExpiredTodayAlert = false
    @State private var showingRestoreBackupConfirm = false
    @State private var showingCreateTaskType = false
    @State private var editingTaskTypeIdRaw: String?
    @State private var archiveDocument = WeekyiiArchiveDocument()
    @State private var showingArchiveExporter = false
    @State private var showingArchiveImporter = false
    @State private var pendingImportData: Data?
    @State private var pendingImportInspection: WeekyiiDataArchiveService.Inspection?
    @State private var showingImportConfirm = false
    
    var body: some View {
        NavigationStack {
            Group {
                if let workspaceSection {
                    workspaceSettingsPage(workspaceSection)
                } else {
                    settingsHome
                }
            }
            .navigationTitle(String(localized: "settings.title"))
            .tint(.weekyiiPrimary)
        }
        .frame(maxWidth: layoutMetrics.layoutClass == .compact ? .infinity : 760)
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !hasInitializedPendingDefaultKillTime else { return }
            pendingDefaultKillTimeHour = settings.defaultKillTimeHour
            pendingDefaultKillTimeMinute = settings.defaultKillTimeMinute
            hasInitializedPendingDefaultKillTime = true
        }
        .onChange(of: settings.killTimeReminderMinutes) { _, _ in
            rescheduleTodayKillTimeReminderIfNeeded()
        }
        .onChange(of: settings.fixedReminderEnabled) { _, _ in
            rescheduleTodayKillTimeReminderIfNeeded()
        }
        .onChange(of: settings.fixedReminderHour) { _, _ in
            rescheduleTodayKillTimeReminderIfNeeded()
        }
        .onChange(of: settings.fixedReminderMinute) { _, _ in
            rescheduleTodayKillTimeReminderIfNeeded()
        }
        .alert(String(localized: "alert.title"), isPresented: Binding(get: {
            seedAlertMessage != nil
        }, set: { newValue in
            if !newValue { seedAlertMessage = nil }
        })) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(seedAlertMessage ?? "")
        }
        .alert(String(localized: "settings.debug.clear.confirm_title"), isPresented: $showingClearConfirm) {
            Button(String(localized: "action.cancel"), role: .cancel) { }
            Button(String(localized: "settings.debug.clear.confirm_action"), role: .destructive) {
                do {
                    let seederContext = ModelContext(modelContext.container)
                    let seeder = SampleDataSeeder(modelContext: seederContext)
                    try seeder.clearAllData()
                    appState.reset()
                    seedAlertMessage = String(localized: "settings.debug.clear.success")
                } catch {
                    seedAlertMessage = String(localized: "settings.debug.clear.failed") + " " + error.localizedDescription
                }
            }
        } message: {
            Text(String(localized: "settings.debug.clear.confirm_message"))
        }
        .alert("应用新的默认截止时间", isPresented: $showingDefaultKillTimeApplyConfirm) {
            Button("同步至今日及以后") {
                confirmDefaultKillTimeChange(syncToday: true)
            }
            Button("仅对明日以后生效") {
                confirmDefaultKillTimeChange(syncToday: false)
            }
            Button(String(localized: "action.cancel"), role: .cancel) {
                syncPendingDefaultKillTimeWithSaved()
            }
        } message: {
            Text("你可以选择同步今日，或只让新默认值从明日开始生效。")
        }
        .alert("新截止时间会导致今日任务立即过期", isPresented: $showingDefaultKillTimeRiskConfirm) {
            Button("确认", role: .destructive) {
                applyDefaultKillTime(hour: pendingDefaultKillTimeHour, minute: pendingDefaultKillTimeMinute)
                applyKillTimeToTodayAndExpireIfNeeded(
                    hour: pendingDefaultKillTimeHour,
                    minute: pendingDefaultKillTimeMinute,
                    allowImmediateExpire: true
                )
            }
            Button(String(localized: "action.cancel"), role: .cancel) {
                syncPendingDefaultKillTimeWithSaved()
            }
        } message: {
            Text("提交后今日未完成内容会立即过期，是否继续？")
        }
        .alert("今日已过期", isPresented: $showingCannotSyncExpiredTodayAlert) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text("今日任务流已过期，无法同步到今天。本次提交已取消。")
        }
        .alert("回滚到最新备份", isPresented: $showingRestoreBackupConfirm) {
            Button("取消", role: .cancel) { }
            Button("确认回滚", role: .destructive) {
                let storeURL = WeekyiiPersistence.persistentStoreURL()
                let snapshots = BackupRecoveryService.listSnapshots(storeURL: storeURL)
                guard let latest = snapshots.first else {
                    seedAlertMessage = "没有找到可回滚备份。"
                    return
                }
                do {
                    try BackupRecoveryService.restoreSnapshot(named: latest.folderName, to: storeURL)
                    seedAlertMessage = "已回滚到 \(latest.folderName)。请立即重启应用。"
                } catch {
                    seedAlertMessage = "回滚失败：\(error.localizedDescription)"
                }
            }
        } message: {
            Text("将直接替换当前数据库文件，可能丢失最新数据。")
        }
        .alert("完整替换当前数据？", isPresented: $showingImportConfirm) {
            Button(String(localized: "action.cancel"), role: .cancel) {
                pendingImportData = nil
                pendingImportInspection = nil
            }
            Button("建立恢复点并导入", role: .destructive) {
                performPendingArchiveImport()
            }
        } message: {
            Text("将导入 \(pendingImportInspection?.conciseSummary ?? "所选归档")。当前数据会被完整替换；开始前会自动建立一份本地恢复点。")
        }
        .fileExporter(
            isPresented: $showingArchiveExporter,
            document: archiveDocument,
            contentType: .json,
            defaultFilename: archiveDefaultFilename
        ) { result in
            if case .failure(let error) = result {
                seedAlertMessage = "导出失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingArchiveImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleArchiveSelection(result)
        }
        .sheet(isPresented: $showingCreateTaskType) {
            TaskTypeDefinitionEditorSheet(
                reservedNames: Set(taskTypeDefinitions.map { $0.name.lowercased() })
            ) { name, iconName, colorHex, baseKind in
                createTaskType(name: name, iconName: iconName, colorHex: colorHex, baseKind: baseKind)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingTaskTypeIdRaw != nil },
            set: { if !$0 { editingTaskTypeIdRaw = nil } }
        )) {
            if let definition = taskTypeDefinitions.first(where: { $0.idRaw == editingTaskTypeIdRaw }) {
                TaskTypeDefinitionEditorSheet(
                    definition: definition,
                    reservedNames: Set(taskTypeDefinitions.filter { $0.idRaw != definition.idRaw }.map { $0.name.lowercased() })
                ) { name, iconName, colorHex, baseKind in
                    updateTaskType(definition, name: name, iconName: iconName, colorHex: colorHex, baseKind: baseKind)
                    editingTaskTypeIdRaw = nil
                } onArchive: {
                    archiveTaskType(definition)
                    editingTaskTypeIdRaw = nil
                }
            }
        }
    }

    @ViewBuilder
    private func workspaceSettingsPage(_ section: WorkspaceSettingsSection) -> some View {
        switch section {
        case .appearance:
            appearanceSettingsPage
        case .rhythm:
            todayRhythmSettingsPage
        case .taskTypes:
            taskTypeSettingsPage
        case .future:
            futureSettingsPage
        case .projects:
            ProjectSettingsView()
        case .data:
            dataSettingsPage
        case .about:
            aboutSettingsPage
        case .diagnostics:
            developerSettingsPage
        }
    }

    private var settingsHome: some View {
        List {
            Section("个性化") {
                NavigationLink {
                    appearanceSettingsPage
                } label: {
                    SettingsNavigationRow(
                        title: "外观与主题",
                        value: "\(settings.selectedTheme.displayName) · \(appearanceDisplayName(for: settings.appearanceMode))",
                        icon: "paintpalette.fill",
                        tint: .purple
                    )
                }
            }

            Section("使用方式") {
                NavigationLink {
                    todayRhythmSettingsPage
                } label: {
                    SettingsNavigationRow(
                        title: "今日节奏",
                        value: String(format: "%02d:%02d", settings.defaultKillTimeHour, settings.defaultKillTimeMinute),
                        icon: "timer",
                        tint: .orange
                    )
                }

                NavigationLink {
                    taskTypeSettingsPage
                } label: {
                    SettingsNavigationRow(
                        title: "任务管理",
                        value: "\(activeTaskTypeDefinitions.count) 个类型",
                        icon: "tag.fill",
                        tint: .teal
                    )
                }

                NavigationLink {
                    futureSettingsPage
                } label: {
                    SettingsNavigationRow(
                        title: "未来",
                        value: settings.weekStartsOnMonday ? "周一开始" : nil,
                        icon: "calendar.badge.clock",
                        tint: .blue
                    )
                }

                NavigationLink {
                    ProjectSettingsView()
                } label: {
                    SettingsNavigationRow(
                        title: "项目",
                        value: "默认 \(settings.defaultProjectDurationDays) 天",
                        icon: "folder.fill",
                        tint: .brown
                    )
                }
            }

            Section("数据") {
                NavigationLink {
                    dataSettingsPage
                } label: {
                    SettingsNavigationRow(
                        title: "数据与安全",
                        icon: "lock.shield.fill",
                        tint: .indigo
                    )
                }
            }

            Section("应用") {
                NavigationLink {
                    aboutSettingsPage
                } label: {
                    SettingsNavigationRow(
                        title: "关于 Weekyii",
                        icon: "info.circle.fill",
                        tint: .mint
                    )
                }

                NavigationLink {
                    developerSettingsPage
                } label: {
                    SettingsNavigationRow(
                        title: "开发者与诊断",
                        icon: "hammer.fill",
                        tint: .gray
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var todayRhythmSettingsPage: some View {
        Form {
            Section("执行方式") {
                executionModeSettings
                killTimeSettings
            }
            Section("提醒") {
                reminderSettings
            }
        }
        .navigationTitle("今日节奏")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var taskTypeSettingsPage: some View {
        Form {
            Section("默认类型") {
                taskTypeSettings
            }
            Section("类型管理") {
                taskTypeManagementSettings
            }
            if !archivedTaskTypeDefinitions.isEmpty {
                Section("已归档类型") {
                    ForEach(archivedTaskTypeDefinitions, id: \.idRaw) { definition in
                        archivedTaskTypeRow(definition)
                    }
                }
            }
        }
        .navigationTitle("任务管理")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var futureSettingsPage: some View {
        Form { futureSection }
            .navigationTitle("未来")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var dataSettingsPage: some View {
        Form { dataPrivacySection }
            .navigationTitle("数据与安全")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var aboutSettingsPage: some View {
        Form {
            pastSection
            aboutSection
        }
        .navigationTitle("关于 Weekyii")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var developerSettingsPage: some View {
        Form { developerSection }
            .navigationTitle("开发者与诊断")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var appearanceSettingsPage: some View {
        Form {
            Section("显示模式") {
                Picker(
                    "显示模式",
                    selection: Binding(
                        get: { settings.appearanceModeRaw },
                        set: { settings.appearanceModeRaw = $0 }
                    )
                ) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(appearanceDisplayName(for: mode)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ThemeStatusArtwork(theme: settings.selectedTheme, renderingMode: .staticImage)
                    .frame(height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } header: {
                Text("当前主题")
            } footer: {
                Text("设置中的预览保持静止；动态印象画仅在“今日”页面播放。")
            }

            Section {
                ForEach(WeekTheme.allCases) { theme in
                    let isLocked = theme.isPremiumTheme && !settings.premiumThemeUnlocked
                    Button {
                        guard canSelect(theme) else { return }
                        settings.selectedThemeRaw = theme.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            ThemePaletteMark(theme: theme)

                            Text(theme.displayName)
                                .foregroundStyle(isLocked ? .secondary : .primary)

                            Spacer()

                            if isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if settings.selectedTheme == theme {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked)
                }
            } header: {
                Text("主题")
            } footer: {
                Text("每套主题仍保留独立的色彩与印象画。")
            }
        }
        .navigationTitle("外观与主题")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Past
    @ViewBuilder
    private var pastSection: some View {
        Section {
            if let startDate = appState.systemStartDate {
                HStack(spacing: 12) {
                    SettingsIcon(icon: "calendar", color: .blue)
                    Text(String(localized: "settings.about.start_date"))
                    Spacer()
                    Text(startDate, format: Date.FormatStyle().year().month().day())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                SettingsIcon(icon: "flag.fill", color: .orange)
                Text(String(localized: "settings.about.days_started"))
                Spacer()
                Text("\(appState.daysStartedCount)")
                    .foregroundStyle(.secondary)
            }

        } header: {
            Text("使用历程")
        }
    }

    // MARK: - Future
    @ViewBuilder
    private var futureSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.weekStartsOnMonday },
                set: { settings.weekStartsOnMonday = $0 }
            )) {
                HStack(spacing: 12) {
                    SettingsIcon(icon: "calendar.badge.clock", color: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.week.starts_monday"))
                        Text(String(localized: "settings.week.starts_monday.subtitle"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "settings.future.month_markers.title", defaultValue: "在月视图上显示"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)

                Toggle(isOn: Binding(
                    get: { settings.pendingMonthShowRegular },
                    set: { settings.pendingMonthShowRegular = $0 }
                )) {
                    HStack(spacing: 12) {
                        SettingsIcon(icon: TaskType.regular.monthMarkerIconName, color: .taskRegular)
                        Text(String(localized: "settings.future.month_markers.regular", defaultValue: "常规任务"))
                    }
                }

                Toggle(isOn: Binding(
                    get: { settings.pendingMonthShowDDL },
                    set: { settings.pendingMonthShowDDL = $0 }
                )) {
                    HStack(spacing: 12) {
                        SettingsIcon(icon: TaskType.ddl.monthMarkerIconName, color: .taskDDL)
                        Text(String(localized: "settings.future.month_markers.ddl", defaultValue: "截止任务"))
                    }
                }

                Toggle(isOn: Binding(
                    get: { settings.pendingMonthShowLeisure },
                    set: { settings.pendingMonthShowLeisure = $0 }
                )) {
                    HStack(spacing: 12) {
                        SettingsIcon(icon: TaskType.leisure.monthMarkerIconName, color: .taskLeisure)
                        Text(String(localized: "settings.future.month_markers.leisure", defaultValue: "休闲任务"))
                    }
                }
            }
        } header: {
            Text(String(localized: "settings.section.future", defaultValue: "未来"))
        }
    }

    // MARK: - Data & Privacy
    @ViewBuilder
    private var dataPrivacySection: some View {
        Section {
            Toggle(isOn: .constant(false)) {
                HStack(spacing: 12) {
                    SettingsIcon(icon: "icloud.fill", color: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.icloud.sync"))
                        Text(String(localized: "settings.icloud.coming_soon"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(true)

            Button {
                exportArchive()
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon(icon: "square.and.arrow.up.fill", color: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("导出 Weekyii 数据")
                        Text("单文件包含任务、项目、标签、图片与设置")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                showingArchiveImporter = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon(icon: "square.and.arrow.down.fill", color: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("从归档恢复")
                        Text("校验完成后完整替换当前数据")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            NavigationLink {
                RecoveryPointsView()
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon(icon: "clock.arrow.circlepath", color: .teal)
                    Text("本地恢复点")
                }
            }
        } header: {
            Text(String(localized: "settings.section.data"))
        } footer: {
            Text("归档采用带版本与 SHA-256 校验的 JSON 格式。导入不会合并数据。")
        }
    }

    private var archiveDefaultFilename: String {
        "Weekyii-\(Self.archiveFilenameFormatter.string(from: Date()))"
    }

    private func exportArchive() {
        do {
            archiveDocument = WeekyiiArchiveDocument(data: try WeekyiiDataArchiveService.export(
                modelContext: modelContext,
                settings: settings,
                appState: appState
            ))
            showingArchiveExporter = true
        } catch {
            seedAlertMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func handleArchiveSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            pendingImportInspection = try WeekyiiDataArchiveService.inspect(data)
            pendingImportData = data
            showingImportConfirm = true
        } catch {
            pendingImportData = nil
            pendingImportInspection = nil
            seedAlertMessage = "无法导入：\(error.localizedDescription)"
        }
    }

    private func performPendingArchiveImport() {
        guard let data = pendingImportData else { return }
        do {
            let result = try WeekyiiDataArchiveService.importReplacing(
                data,
                modelContext: modelContext,
                settings: settings,
                appState: appState,
                storeURL: WeekyiiPersistence.persistentStoreURL()
            )
            pendingImportData = nil
            pendingImportInspection = nil
            seedAlertMessage = "恢复完成：\(result.conciseSummary)"
        } catch {
            seedAlertMessage = "恢复失败，当前数据未替换：\(error.localizedDescription)"
        }
    }

    // MARK: - Developer
    @ViewBuilder
    private var developerSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.developerSettingsEnabled },
                set: { settings.developerSettingsEnabled = $0 }
            )) {
                HStack(spacing: 12) {
                    SettingsIcon(icon: "hammer.fill", color: .gray)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.developer.show_debug"))
                        Text(String(localized: "settings.developer.show_debug.subtitle"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if settings.developerSettingsEnabled {
                Toggle(isOn: Binding(
                    get: { settings.premiumThemeUnlocked },
                    set: { settings.premiumThemeUnlocked = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.developer.unlock_lotr", defaultValue: "解锁魔戒主题"))
                        Text(String(localized: "settings.developer.unlock_lotr.subtitle", defaultValue: "本地调试用，不代表真实购买状态"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: Binding(
                    get: { settings.seedPastWeeks },
                    set: { settings.seedPastWeeks = $0 }
                ), in: 1...24) {
                    Text(String(localized: "settings.debug.seed.past_weeks") + " \(settings.seedPastWeeks)")
                }

                Stepper(value: Binding(
                    get: { settings.seedFutureWeeks },
                    set: { settings.seedFutureWeeks = $0 }
                ), in: 0...12) {
                    Text(String(localized: "settings.debug.seed.future_weeks") + " \(settings.seedFutureWeeks)")
                }

                Stepper(value: Binding(
                    get: { settings.seedTasksPerPastDay },
                    set: { settings.seedTasksPerPastDay = $0 }
                ), in: 1...12) {
                    Text(String(localized: "settings.debug.seed.past_tasks") + " \(settings.seedTasksPerPastDay)")
                }

                Stepper(value: Binding(
                    get: { settings.seedTasksPerDraftDay },
                    set: { settings.seedTasksPerDraftDay = $0 }
                ), in: 1...12) {
                    Text(String(localized: "settings.debug.seed.draft_tasks") + " \(settings.seedTasksPerDraftDay)")
                }

                Stepper(value: Binding(
                    get: { settings.seedExpiredEveryNDays },
                    set: { settings.seedExpiredEveryNDays = $0 }
                ), in: 0...7) {
                    Text(expiredEveryLabel)
                }

                Toggle(isOn: Binding(
                    get: { settings.seedIncludeSteps },
                    set: { settings.seedIncludeSteps = $0 }
                )) {
                    Text(String(localized: "settings.debug.seed.include_steps"))
                }

                Toggle(isOn: Binding(
                    get: { settings.seedIncludeAttachments },
                    set: { settings.seedIncludeAttachments = $0 }
                )) {
                    Text(String(localized: "settings.debug.seed.include_attachments"))
                }

                Toggle(isOn: Binding(
                    get: { settings.seedIncludeDescriptions },
                    set: { settings.seedIncludeDescriptions = $0 }
                )) {
                    Text(String(localized: "settings.debug.seed.include_descriptions"))
                }

                Toggle(isOn: Binding(
                    get: { settings.seedAllowExisting },
                    set: { settings.seedAllowExisting = $0 }
                )) {
                    Text(String(localized: "settings.debug.seed.allow_existing"))
                }

                Button {
                    do {
                        let seederContext = ModelContext(modelContext.container)
                        let seeder = SampleDataSeeder(modelContext: seederContext)
                        let result = try seeder.seed(options: seedOptions)
                        switch result {
                        case .seeded:
                            appState.bumpDataRevision()
                            seedAlertMessage = String(localized: "settings.debug.seed.success")
                        case .skippedExisting:
                            seedAlertMessage = String(localized: "settings.debug.seed.already")
                        case .skippedAll:
                            seedAlertMessage = String(localized: "settings.debug.seed.none")
                        }
                    } catch {
                        seedAlertMessage = String(localized: "settings.debug.seed.failed") + " " + error.localizedDescription
                    }
                } label: {
                    Text(String(localized: "settings.debug.seed"))
                }

                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Text(String(localized: "settings.debug.clear"))
                }

                Button("立即重算状态") {
                    let coordinator = makeHealthCoordinator()
                    let report = coordinator.reconcile(trigger: .manualResync, force: true)
                    appState.bumpDataRevision()
                    seedAlertMessage = "重算完成：过期\(report.crossDayExpiredCount + report.staleDaysExpiredCount + report.killTimeExpiredCount)项，修复\(report.totalRepairCount)项。"
                }

                Button("导出状态诊断") {
                    let coordinator = makeHealthCoordinator()
                    UIPasteboard.general.string = coordinator.diagnosticsSnapshot()
                    seedAlertMessage = "状态诊断已复制到剪贴板。"
                }

                Button("列出最近备份摘要") {
                    let storeURL = WeekyiiPersistence.persistentStoreURL()
                    let snapshots = BackupRecoveryService.listSnapshots(storeURL: storeURL).prefix(5)
                    if snapshots.isEmpty {
                        seedAlertMessage = "当前没有可用备份。"
                    } else {
                        let lines = snapshots.map { summary in
                            "\(summary.folderName) | valid=\(summary.isValid ? "yes" : "no") | files=\(summary.fileCount)"
                        }
                        seedAlertMessage = lines.joined(separator: "\n")
                    }
                }

                Button(role: .destructive) {
                    showingRestoreBackupConfirm = true
                } label: {
                    Text("回滚到最新备份（危险）")
                }
            }
        } header: {
            Text(String(localized: "settings.developer.header"))
        } footer: {
            Text(String(localized: "settings.developer.footer"))
        }
    }

    // MARK: - About
    @ViewBuilder
    private var aboutSection: some View {
        Section {
            HStack(spacing: 12) {
                SettingsIcon(icon: "info.circle.fill", color: .teal)
                Text(String(localized: "settings.about.version"))
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }

        } header: {
            Text(String(localized: "settings.about.header"))
        }
    }
    
    // MARK: - Kill Time Settings
    @ViewBuilder
    private var executionModeSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SettingsIcon(icon: "slider.horizontal.3", color: .weekyiiPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("执行模式")
                    Text("修改将在下一次开始任务流时生效")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("执行模式", selection: Binding(
                get: { settings.defaultExecutionModeRaw },
                set: { settings.defaultExecutionModeRaw = $0 }
            )) {
                ForEach(ExecutionMode.allCases) { mode in
                    Text(mode.displayName)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("executionModePicker")

            Text(settings.defaultExecutionMode == .strict
                 ? "严格模式：开始后按固定顺序逐项推进。"
                 : "灵动模式：开始后可解冻草稿区，调整任务并与专注任务交换。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Kill Time Settings
    @ViewBuilder
    private var killTimeSettings: some View {
        DatePicker(selection: pendingDefaultKillTimeDateBinding, displayedComponents: .hourAndMinute) {
            HStack(spacing: 12) {
                SettingsIcon(icon: "clock.fill", color: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.default_kill_time"))
                    Text(String(localized: "settings.default_kill_time.guidance", defaultValue: "一天的任务将在截止时间结算"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .datePickerStyle(.compact)

        if hasPendingDefaultKillTimeChange {
            HStack {
                Spacer()
                Button("取消更改") {
                    withAnimation {
                        syncPendingDefaultKillTimeWithSaved()
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.trailing, 16)

                Button("提交修改") {
                    submitDefaultKillTimeChange()
                }
                .buttonStyle(.borderless)
                .fontWeight(.bold)
                Spacer()
            }
        }
    }
    
    // MARK: - Task Type Settings
    @ViewBuilder
    private var taskTypeSettings: some View {
        Picker(selection: Binding(
            get: { resolvedDefaultTaskTypeId },
            set: { newValue in
                let definition = taskTypeDefinition(for: newValue)
                settings.defaultTaskTypeIdRaw = definition.idRaw
                settings.defaultTaskType = definition.baseKind
            }
        )) {
            ForEach(activeTaskTypeDefinitions, id: \.idRaw) { type in
                HStack {
                    Image(systemName: type.iconName)
                    Text(type.name)
                }
                .tag(type.idRaw)
            }
        } label: {
            HStack(spacing: 12) {
                SettingsIcon(icon: "checkmark.circle.fill", color: .green)
                Text(String(localized: "settings.default_task_type"))
            }
        }
    }

    @ViewBuilder
    private var taskTypeManagementSettings: some View {
        ForEach(activeTaskTypeDefinitions, id: \.idRaw) { definition in
            taskTypeManagementRow(definition)
        }

        Button {
            showingCreateTaskType = true
        } label: {
            Label("新增任务类型", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
        .accessibilityLabel("新增任务类型")
    }

    @ViewBuilder
    private func taskTypeManagementRow(_ definition: TaskTypeDefinition) -> some View {
        let content = HStack(spacing: 12) {
            Image(systemName: definition.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(definition.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(definition.name)
                    .foregroundStyle(.primary)
                Text("\(definition.isBuiltIn ? "系统类型" : "自定义类型") · \(definition.baseKind.displayName)行为")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if definition.idRaw == resolvedDefaultTaskTypeId {
                Text("默认")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(definition.color)
            }

            if !definition.isBuiltIn {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }

        if definition.isBuiltIn {
            content
                .padding(.vertical, 4)
        } else {
            Button {
                editingTaskTypeIdRaw = definition.idRaw
            } label: {
                content
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
    }

    private func archivedTaskTypeRow(_ definition: TaskTypeDefinition) -> some View {
        HStack(spacing: 12) {
            Image(systemName: definition.iconName)
                .foregroundStyle(definition.color)
                .frame(width: 28, height: 28)
            Text(definition.name)
                .foregroundStyle(.secondary)
            Spacer()
            Button("恢复") {
                restoreTaskType(definition)
            }
            .buttonStyle(.borderless)
        }
    }
    
    // MARK: - Reminder Settings
    @ViewBuilder
    private var reminderSettings: some View {
        Picker(selection: Binding(
            get: { settings.killTimeReminderMinutes },
            set: { settings.killTimeReminderMinutes = $0 }
        )) {
            Text(String(localized: "settings.reminder.none")).tag(0)
            Text(String(localized: "settings.reminder.15min")).tag(15)
            Text(String(localized: "settings.reminder.30min")).tag(30)
            Text(String(localized: "settings.reminder.60min")).tag(60)
            Text("提前 90 分钟").tag(90)
            Text("提前 120 分钟").tag(120)
        } label: {
            HStack(spacing: 12) {
                SettingsIcon(icon: "bell.fill", color: .red)
                Text(String(localized: "settings.kill_time_reminder"))
            }
        }

        Toggle(isOn: Binding(
            get: { settings.fixedReminderEnabled },
            set: { settings.fixedReminderEnabled = $0 }
        )) {
            HStack(spacing: 12) {
                SettingsIcon(icon: "bell.badge.fill", color: .pink)
                Text("固定时刻提醒")
            }
        }

        if settings.fixedReminderEnabled {
            DatePicker(selection: fixedReminderDateBinding, displayedComponents: .hourAndMinute) {
                HStack(spacing: 12) {
                    SettingsIcon(icon: "clock.badge.fill", color: .indigo)
                    Text("提醒时刻")
                }
            }
            .datePickerStyle(.compact)
        }

        HStack(spacing: 12) {
            Color.clear
                .frame(width: 28, height: 28)
            Text("系统会自动追加晨间提醒与截止前最后提醒，固定时刻提醒用于你的个人节奏。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var seedOptions: SeedOptions {
        SeedOptions(
            pastWeeks: settings.seedPastWeeks,
            futureWeeks: settings.seedFutureWeeks,
            tasksPerPastDay: settings.seedTasksPerPastDay,
            tasksPerDraftDay: settings.seedTasksPerDraftDay,
            expiredEveryNDays: settings.seedExpiredEveryNDays,
            includeSteps: settings.seedIncludeSteps,
            includeAttachments: settings.seedIncludeAttachments,
            includeDescriptions: settings.seedIncludeDescriptions,
            allowExisting: settings.seedAllowExisting
        )
    }

    private var activeTaskTypeDefinitions: [TaskTypeDefinition] {
        let active = taskTypeDefinitions.filter { !$0.isArchived }
        if active.isEmpty {
            return TaskTypeDefinition.builtInDefinitions()
        }
        return active.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var archivedTaskTypeDefinitions: [TaskTypeDefinition] {
        taskTypeDefinitions
            .filter { $0.isArchived && !$0.isBuiltIn }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var resolvedDefaultTaskTypeId: String {
        if activeTaskTypeDefinitions.contains(where: { $0.idRaw == settings.defaultTaskTypeIdRaw }) {
            return settings.defaultTaskTypeIdRaw
        }
        return TaskType.regular.rawValue
    }

    private func taskTypeDefinition(for idRaw: String) -> TaskTypeDefinition {
        taskTypeDefinitions.first { $0.idRaw == idRaw }
            ?? TaskTypeDefinition.builtInDefinitions().first { $0.idRaw == idRaw }
            ?? TaskTypeCatalog.builtInFallback
    }

    private func createTaskType(name: String, iconName: String, colorHex: String, baseKind: TaskType) {
        let nextOrder = ((try? modelContext.fetch(FetchDescriptor<TaskTypeDefinition>())) ?? [])
            .map(\.sortOrder)
            .max() ?? 2
        modelContext.insert(TaskTypeDefinition(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            baseKind: baseKind,
            sortOrder: nextOrder + 1
        ))
        try? modelContext.save()
    }

    private func updateTaskType(_ definition: TaskTypeDefinition, name: String, iconName: String, colorHex: String, baseKind: TaskType) {
        guard !definition.isBuiltIn else { return }
        definition.name = name
        definition.iconName = iconName
        definition.colorHex = colorHex
        definition.baseKind = baseKind
        let tasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        for task in tasks where task.taskTypeIdRaw == definition.idRaw {
            task.taskType = baseKind
        }
        let suspendedTasks = (try? modelContext.fetch(FetchDescriptor<SuspendedTaskItem>())) ?? []
        for task in suspendedTasks where task.taskTypeIdRaw == definition.idRaw {
            task.taskType = baseKind
        }
        if settings.defaultTaskTypeIdRaw == definition.idRaw {
            settings.defaultTaskType = baseKind
        }
        try? modelContext.save()
    }

    private func archiveTaskType(_ definition: TaskTypeDefinition) {
        guard !definition.isBuiltIn else { return }
        definition.isArchived = true
        if settings.defaultTaskTypeIdRaw == definition.idRaw {
            settings.defaultTaskTypeIdRaw = TaskType.regular.rawValue
            settings.defaultTaskType = .regular
        }
        try? modelContext.save()
    }

    private func restoreTaskType(_ definition: TaskTypeDefinition) {
        guard !definition.isBuiltIn else { return }
        definition.isArchived = false
        try? modelContext.save()
    }
    
    private var expiredEveryLabel: String {
        if settings.seedExpiredEveryNDays == 0 {
            return String(localized: "settings.debug.seed.expired.none")
        }
        let template = String(localized: "settings.debug.seed.expired.every")
        return String(format: template, settings.seedExpiredEveryNDays)
    }

    private func canSelect(_ theme: WeekTheme) -> Bool {
        !theme.isPremiumTheme || settings.premiumThemeUnlocked
    }

    private func appearanceDisplayName(for mode: AppearanceMode) -> String {
        switch mode {
        case .system:
            return String(localized: "settings.appearance.system", defaultValue: "自动")
        case .light:
            return String(localized: "settings.appearance.light", defaultValue: "浅色")
        case .dark:
            return String(localized: "settings.appearance.dark", defaultValue: "深色")
        }
    }

    private var pendingDefaultKillTimeDateBinding: Binding<Date> {
        Binding(
            get: {
                var components = Calendar(identifier: .iso8601).dateComponents([.year, .month, .day], from: Date())
                components.hour = pendingDefaultKillTimeHour
                components.minute = pendingDefaultKillTimeMinute
                components.second = 0
                return Calendar(identifier: .iso8601).date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar(identifier: .iso8601).dateComponents([.hour, .minute], from: newDate)
                pendingDefaultKillTimeHour = min(max(components.hour ?? 0, 0), 23)
                pendingDefaultKillTimeMinute = min(max(components.minute ?? 0, 0), 59)
            }
        )
    }

    private var fixedReminderDateBinding: Binding<Date> {
        Binding(
            get: {
                var components = Calendar(identifier: .iso8601).dateComponents([.year, .month, .day], from: Date())
                components.hour = settings.fixedReminderHour
                components.minute = settings.fixedReminderMinute
                components.second = 0
                return Calendar(identifier: .iso8601).date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar(identifier: .iso8601).dateComponents([.hour, .minute], from: newDate)
                settings.fixedReminderHour = min(max(components.hour ?? 0, 0), 23)
                settings.fixedReminderMinute = min(max(components.minute ?? 0, 0), 59)
            }
        )
    }

    private var hasPendingDefaultKillTimeChange: Bool {
        pendingDefaultKillTimeHour != settings.defaultKillTimeHour
            || pendingDefaultKillTimeMinute != settings.defaultKillTimeMinute
    }

    private func syncPendingDefaultKillTimeWithSaved() {
        pendingDefaultKillTimeHour = settings.defaultKillTimeHour
        pendingDefaultKillTimeMinute = settings.defaultKillTimeMinute
    }

    private func submitDefaultKillTimeChange() {
        guard hasPendingDefaultKillTimeChange else { return }
        showingDefaultKillTimeApplyConfirm = true
    }

    private func confirmDefaultKillTimeChange(syncToday: Bool) {
        guard hasPendingDefaultKillTimeChange else { return }
        if syncToday {
            if isTodayExpired {
                syncPendingDefaultKillTimeWithSaved()
                showingCannotSyncExpiredTodayAlert = true
                return
            }
            if shouldWarnImmediateExpiryForToday(hour: pendingDefaultKillTimeHour, minute: pendingDefaultKillTimeMinute) {
                showingDefaultKillTimeRiskConfirm = true
                return
            }
            applyDefaultKillTime(hour: pendingDefaultKillTimeHour, minute: pendingDefaultKillTimeMinute)
            applyKillTimeToTodayAndExpireIfNeeded(
                hour: pendingDefaultKillTimeHour,
                minute: pendingDefaultKillTimeMinute,
                allowImmediateExpire: false
            )
            return
        }
        applyDefaultKillTime(hour: pendingDefaultKillTimeHour, minute: pendingDefaultKillTimeMinute)
    }

    private var isTodayExpired: Bool {
        guard let today = todayDayModel() else { return false }
        return today.status == .expired
    }

    private func applyDefaultKillTime(hour: Int, minute: Int) {
        settings.defaultKillTimeHour = hour
        settings.defaultKillTimeMinute = minute
    }

    private func rescheduleTodayKillTimeReminderIfNeeded() {
        guard let today = todayDayModel() else { return }
        guard today.status == .draft || today.status == .execute else {
            NotificationService.shared.cancelKillTimeNotification(for: today)
            return
        }
        NotificationService.shared.scheduleKillTimeNotification(
            for: today,
            reminderMinutes: settings.killTimeReminderMinutes,
            fixedReminder: settings.fixedReminderEnabled
                ? DateComponents(hour: settings.fixedReminderHour, minute: settings.fixedReminderMinute)
                : nil
        )
    }

    private func todayDayModel() -> DayModel? {
        let dayId = Date().dayId
        let descriptor = FetchDescriptor<DayModel>(predicate: #Predicate { $0.dayId == dayId })
        return try? modelContext.fetch(descriptor).first
    }

    private func shouldWarnImmediateExpiryForToday(hour: Int, minute: Int) -> Bool {
        guard let today = todayDayModel() else { return false }
        guard today.status == .draft || today.status == .execute else { return false }
        guard hasOpenTasks(today) else { return false }
        guard let newKillDate = makeDate(for: today.date, hour: hour, minute: minute) else { return false }
        return Date() >= newKillDate
    }

    private func applyKillTimeToTodayAndExpireIfNeeded(hour: Int, minute: Int, allowImmediateExpire: Bool) {
        guard let today = todayDayModel() else { return }
        guard today.status == .empty || today.status == .draft || today.status == .execute else { return }

        today.killTimeHour = hour
        today.killTimeMinute = minute
        today.followsDefaultKillTime = true

        guard let newKillDate = makeDate(for: today.date, hour: hour, minute: minute) else {
            try? modelContext.save()
            return
        }

        if allowImmediateExpire, Date() >= newKillDate, (today.status == .draft || today.status == .execute) {
            let expiredCount = today.status == .draft ? 0 : ((today.focusTask == nil ? 0 : 1) + today.frozenTasks.count)
            today.status = .expired
            today.expiredCount = expiredCount
            let toRemove = today.tasks.filter { $0.zone == .draft || $0.zone == .focus || $0.zone == .frozen }
            today.tasks.removeAll { $0.zone == .draft || $0.zone == .focus || $0.zone == .frozen }
            toRemove.forEach { modelContext.delete($0) }
            NotificationService.shared.cancelKillTimeNotification(for: today)
        }

        try? modelContext.save()
    }

    private func hasOpenTasks(_ day: DayModel) -> Bool {
        !day.sortedDraftTasks.isEmpty || day.focusTask != nil || !day.frozenTasks.isEmpty
    }

    private func makeDate(for dayDate: Date, hour: Int, minute: Int) -> Date? {
        var components = Calendar(identifier: .iso8601).dateComponents([.year, .month, .day], from: dayDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar(identifier: .iso8601).date(from: components)
    }

    private func makeHealthCoordinator() -> AppHealthCoordinator {
        AppHealthCoordinator(
            modelContainer: modelContext.container,
            timeProvider: TimeProvider(),
            notificationService: .shared,
            appState: appState,
            userSettings: settings,
            liveActivityService: TodayLiveActivityService.shared
        )
    }
}

@MainActor
private struct SampleDataSeeder {
    let modelContext: ModelContext
    private let calendar = Calendar(identifier: .iso8601)
    private let weekCalculator = WeekCalculator()
    private let sampleTitles = [
        "Review goals",
        "Write summary",
        "Deep work sprint",
        "Inbox zero",
        "Exercise session",
        "Read 30 pages",
        "Plan tomorrow",
        "Design sketch",
        "Refactor module",
        "Update roadmap"
    ]
    private let sampleDescriptions = [
        "Focus on the most important outcome.",
        "Keep it short and concrete.",
        "Time-boxed effort with a clear finish."
    ]
    private let sampleSteps = [
        "Break down tasks",
        "Do the hard part first",
        "Review and wrap up"
    ]
    private let sampleTypes: [TaskType] = [.regular, .ddl, .leisure]
    private let sampleAttachments = [
        (fileName: "reference.pdf", fileType: "application/pdf"),
        (fileName: "notes.txt", fileType: "text/plain")
    ]

    enum SeedResult {
        case seeded
        case skippedExisting
        case skippedAll
    }
    
    func seed(options: SeedOptions) throws -> SeedResult {
        let descriptor = FetchDescriptor<WeekModel>()
        let existingWeeks = (try? modelContext.fetch(descriptor)) ?? []
        if !options.allowExisting, !existingWeeks.isEmpty {
            return .skippedExisting
        }
        let existingWeekIds = Set(existingWeeks.map { $0.weekId })

        let today = calendar.startOfDay(for: Date())
        var inserted = 0
        for offset in (-options.pastWeeks)...options.futureWeeks {
            guard let weekDate = calendar.date(byAdding: .weekOfYear, value: offset, to: today) else { continue }
            let weekId = weekDate.weekId
            if existingWeekIds.contains(weekId) {
                continue
            }
            let status: WeekStatus = offset < 0 ? .past : (offset == 0 ? .present : .pending)
            let week = weekCalculator.makeWeek(for: weekDate, status: status)
            seedWeek(week, relativeTo: today, options: options)
            modelContext.insert(week)
            inserted += 1
        }
        try modelContext.save()
        return inserted > 0 ? .seeded : .skippedAll
    }

    private func seedWeek(_ week: WeekModel, relativeTo today: Date, options: SeedOptions) {
        let sortedDays = week.days.sorted { $0.date < $1.date }
        for (index, day) in sortedDays.enumerated() {
            switch week.status {
            case .pending:
                seedDraftDay(day, index: index, options: options)
            case .past:
                seedPastDay(day, index: index, options: options)
            case .present:
                if calendar.isDate(day.date, inSameDayAs: today) {
                    seedDraftDay(day, index: index, options: options)
                } else if day.date < today {
                    seedPastDay(day, index: index, options: options)
                } else {
                    seedDraftDay(day, index: index, options: options)
                }
            }
        }
        updateWeekStats(week)
    }

    private func seedPastDay(_ day: DayModel, index: Int, options: SeedOptions) {
        let isExpired = options.expiredEveryNDays > 0 && index % options.expiredEveryNDays == 0
        day.initiatedAt = day.date.addingTimeInterval(9 * 3600)
        day.closedAt = day.date.addingTimeInterval(20 * 3600)
        let totalCount = max(1, options.tasksPerPastDay)

        if isExpired {
            day.status = .expired
            let completedCount = max(1, totalCount / 2)
            day.expiredCount = max(0, totalCount - completedCount)
            day.tasks.append(contentsOf: makeTasks(count: completedCount, zone: .complete, seed: index, dayDate: day.date, options: options))
        } else {
            day.status = .completed
            let completedCount = totalCount
            day.tasks.append(contentsOf: makeTasks(count: completedCount, zone: .complete, seed: index, dayDate: day.date, options: options))
        }
    }

    private func seedDraftDay(_ day: DayModel, index: Int, options: SeedOptions) {
        day.status = .draft
        let draftCount = max(1, options.tasksPerDraftDay)
        day.tasks.append(contentsOf: makeTasks(count: draftCount, zone: .draft, seed: index, dayDate: day.date, options: options))
    }

    private func makeTasks(count: Int, zone: TaskZone, seed: Int, dayDate: Date, options: SeedOptions) -> [TaskItem] {
        var tasks: [TaskItem] = []
        for i in 0..<count {
            let title = sampleTitles[(seed + i) % sampleTitles.count]
            let description = options.includeDescriptions
                ? sampleDescriptions[(seed + i) % sampleDescriptions.count]
                : ""
            let type = sampleTypes[(seed + i) % sampleTypes.count]
            let task = TaskItem(
                title: title,
                taskDescription: description,
                taskType: type,
                order: i + 1,
                zone: zone
            )

            if zone == .complete {
                task.completedOrder = i + 1
                task.startedAt = dayDate.addingTimeInterval(TimeInterval((9 + i) * 3600))
                task.endedAt = dayDate.addingTimeInterval(TimeInterval((10 + i) * 3600))
            }

            if options.includeSteps, i % 2 == 0 {
                task.steps = [
                    TaskStep(title: sampleSteps[0]),
                    TaskStep(title: sampleSteps[1])
                ]
            }

            if options.includeAttachments, i % 3 == 0 {
                let attachment = sampleAttachments[(seed + i) % sampleAttachments.count]
                task.attachments = [TaskAttachment(data: nil, fileName: attachment.fileName, fileType: attachment.fileType)]
            }

            tasks.append(task)
        }
        return tasks
    }

    private func updateWeekStats(_ week: WeekModel) {
        week.completedTasksCount = week.days.reduce(0) { $0 + $1.completedTasks.count }
        week.expiredTasksCount = week.days.reduce(0) { $0 + $1.expiredCount }
        week.totalStartedDays = week.days.filter { [.execute, .completed, .expired].contains($0.status) }.count
    }

    func clearAllData() throws {
        let weeks = (try? modelContext.fetch(FetchDescriptor<WeekModel>())) ?? []
        for week in weeks {
            modelContext.delete(week)
        }
        try modelContext.save()

        // Clean up any historical orphan records left by prior model bugs.
        let orphanDays = (try? modelContext.fetch(FetchDescriptor<DayModel>())) ?? []
        for day in orphanDays {
            modelContext.delete(day)
        }
        let orphanTasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        for task in orphanTasks {
            modelContext.delete(task)
        }
        let orphanSteps = (try? modelContext.fetch(FetchDescriptor<TaskStep>())) ?? []
        for step in orphanSteps {
            modelContext.delete(step)
        }
        let orphanAttachments = (try? modelContext.fetch(FetchDescriptor<TaskAttachment>())) ?? []
        for attachment in orphanAttachments {
            modelContext.delete(attachment)
        }
        try modelContext.save()
    }
}

private struct SeedOptions {
    let pastWeeks: Int
    let futureWeeks: Int
    let tasksPerPastDay: Int
    let tasksPerDraftDay: Int
    let expiredEveryNDays: Int
    let includeSteps: Bool
    let includeAttachments: Bool
    let includeDescriptions: Bool
    let allowExisting: Bool
}

private struct TaskTypeDefinitionEditorSheet: View {
    let definition: TaskTypeDefinition?
    let reservedNames: Set<String>
    let onSave: (String, String, String, TaskType) -> Void
    let onArchive: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var iconName: String
    @State private var colorHex: String
    @State private var baseKind: TaskType

    private let icons = ["checkmark.circle", "scope", "pencil.line", "book.closed", "hammer", "bolt", "flame", "calendar.badge.clock", "leaf", "sparkles", "star", "heart", "figure.run", "briefcase", "graduationcap", "music.note", "paintbrush", "cup.and.saucer"]
    private let colors = ["#4A90A4", "#C46A1A", "#8B5A83", "#4D9DE0", "#59A14F", "#E15759", "#B07AA1", "#F28E2B", "#2A9D8F", "#6C5CE7"]

    init(
        definition: TaskTypeDefinition? = nil,
        reservedNames: Set<String> = [],
        onSave: @escaping (String, String, String, TaskType) -> Void,
        onArchive: (() -> Void)? = nil
    ) {
        self.definition = definition
        self.reservedNames = reservedNames
        self.onSave = onSave
        self.onArchive = onArchive
        _name = State(initialValue: definition?.name ?? "")
        _iconName = State(initialValue: definition?.iconName ?? "tag.fill")
        _colorHex = State(initialValue: definition?.colorHex ?? "#4A90A4")
        _baseKind = State(initialValue: definition?.baseKind ?? .regular)
    }

    private var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasDuplicateName: Bool { reservedNames.contains(normalizedName.lowercased()) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: iconName)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Color(hex: colorHex), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(normalizedName.isEmpty ? "新任务类型" : normalizedName)
                                .font(.headline)
                            Label(baseKindLabel, systemImage: baseKind.iconName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("名称") {
                    TextField("类型名称", text: $name)
                    if hasDuplicateName {
                        Label("已有同名类型，请换一个名称", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("任务行为", selection: $baseKind) {
                        ForEach(TaskType.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("任务行为")
                } footer: {
                    Text("决定该类型在截止提醒、未来标记和统计中的归类；名称、图标和颜色仍保持自定义。")
                }

                Section("图标") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                iconName = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(iconName == icon ? .white : Color(hex: colorHex))
                                    .background(iconName == icon ? Color(hex: colorHex) : Color(hex: colorHex).opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("颜色") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(colors, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if colorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if definition?.isBuiltIn == false, let onArchive {
                    Section {
                        Button("归档类型", role: .destructive) {
                            onArchive()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(definition == nil ? "新增任务类型" : "编辑任务类型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.save")) {
                        onSave(normalizedName, iconName, colorHex, baseKind)
                        dismiss()
                    }
                    .disabled(normalizedName.isEmpty || hasDuplicateName)
                }
            }
        }
    }

    private var baseKindLabel: String {
        switch baseKind {
        case .regular: return "按普通任务运行"
        case .ddl: return "按截止任务运行"
        case .leisure: return "按休闲任务运行"
        }
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    var value: String? = nil
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(icon: icon, color: tint)

            Text(title)

            if let value {
                Spacer(minLength: 8)
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
    }
}

private struct ThemePaletteMark: View {
    let theme: WeekTheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme.primaryColor)
            Rectangle().fill(theme.accentColor)
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}

private struct ProjectSettingsView: View {
    @EnvironmentObject private var settings: UserSettings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProjectModel.createdAt, order: .reverse) private var projects: [ProjectModel]
    @State private var errorMessage: String?

    private var currentProjects: [ProjectModel] {
        projects.filter { $0.status == .planning || $0.status == .active }
    }

    private var completedProjects: [ProjectModel] {
        projects.filter { $0.status == .completed }
    }

    private var archivedProjects: [ProjectModel] {
        projects.filter { $0.status == .archived }
    }

    var body: some View {
        Form {
            Section {
                Stepper(value: Binding(
                    get: { settings.defaultProjectDurationDays },
                    set: { settings.defaultProjectDurationDays = min(max($0, 1), 365) }
                ), in: 1...365) {
                    HStack {
                        Label("默认周期", systemImage: "calendar.badge.clock")
                        Spacer()
                        Text("\(settings.defaultProjectDurationDays) 天")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("默认卡片尺寸", selection: Binding(
                    get: { settings.defaultProjectTileSizeRaw },
                    set: { settings.defaultProjectTileSizeRaw = $0 }
                )) {
                    ForEach(ProjectTileSize.allCases, id: \.rawValue) { size in
                        Text(tileSizeName(size)).tag(size.rawValue)
                    }
                }
            } header: {
                Text("新建项目默认值")
            } footer: {
                Text("仅影响以后新建的项目，不会修改现有项目。")
            }

            Section("项目概览") {
                projectCountRow("进行中", count: currentProjects.count, color: .blue)
                projectCountRow("已完成", count: completedProjects.count, color: .green)
                projectCountRow("已归档", count: archivedProjects.count, color: .gray)
            }

            Section("生命周期") {
                Label("逾期项目不会自动隐藏或改变状态", systemImage: "eye")
                Label("完成项目前必须先完成全部开放任务", systemImage: "checkmark.seal")
                Label("归档始终由你主动执行", systemImage: "archivebox")
            }

            if !completedProjects.isEmpty {
                Section("管理已完成项目") {
                    ForEach(completedProjects) { project in
                        projectLifecycleRow(project) {
                            Button("重新打开", systemImage: "arrow.uturn.backward") {
                                update(project, to: .active)
                            }
                            Button("归档", systemImage: "archivebox") {
                                update(project, to: .archived)
                            }
                        }
                    }
                }
            }

            if !archivedProjects.isEmpty {
                Section("管理已归档项目") {
                    ForEach(archivedProjects) { project in
                        projectLifecycleRow(project) {
                            Button("恢复到已完成", systemImage: "arrow.uturn.backward") {
                                update(project, to: .completed)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("项目")
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "alert.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func projectCountRow(_ title: String, count: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
    }

    private func projectLifecycleRow<MenuContent: View>(
        _ project: ProjectModel,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: project.icon)
                .foregroundStyle(Color(hex: project.color))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                Text("\(project.completedTaskCount)/\(project.totalTaskCount) 个任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                menu()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func update(_ project: ProjectModel, to status: ProjectStatus) {
        let allowed: Bool
        switch (project.status, status) {
        case (.completed, .active), (.completed, .archived), (.archived, .completed):
            allowed = true
        default:
            allowed = false
        }
        guard allowed else {
            errorMessage = "当前项目状态不能执行该操作。"
            return
        }
        project.status = status
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func tileSizeName(_ size: ProjectTileSize) -> String {
        switch size {
        case .mini: "迷你"
        case .small: "小型"
        case .medium: "中型"
        case .wide: "宽幅"
        }
    }
}

struct SettingsIcon: View {
    let icon: String
    let color: Color
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(color)
            .cornerRadius(7)
    }
}

private struct RecoveryPointsView: View {
    @State private var snapshots: [BackupRecoveryService.SnapshotSummary] = []
    @State private var pendingSnapshot: BackupRecoveryService.SnapshotSummary?
    @State private var message: String?

    var body: some View {
        List {
            if snapshots.isEmpty {
                ContentUnavailableView("暂无本地恢复点", systemImage: "clock.arrow.circlepath", description: Text("应用启动和数据导入前会自动建立恢复点。"))
            } else {
                Section {
                    ForEach(snapshots, id: \.folderName) { snapshot in
                        Button {
                            guard snapshot.isValid else {
                                message = "该恢复点校验失败，不能使用。"
                                return
                            }
                            pendingSnapshot = snapshot
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: snapshot.isValid ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(snapshot.isValid ? .green : .red)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(snapshot.createdAt, format: .dateTime.year().month().day().hour().minute())
                                        .foregroundStyle(.primary)
                                    Text("\(snapshot.fileCount) 个数据库文件")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("恢复点是设备内的数据库快照。恢复后必须立即完全退出并重新打开 Weekyii。")
                }
            }
        }
        .navigationTitle("本地恢复点")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .alert("恢复这个时间点？", isPresented: Binding(
            get: { pendingSnapshot != nil },
            set: { if !$0 { pendingSnapshot = nil } }
        )) {
            Button("取消", role: .cancel) { pendingSnapshot = nil }
            Button("完整恢复", role: .destructive) { restorePendingSnapshot() }
        } message: {
            Text("当前数据库会被替换。完成后请立即完全退出并重新打开应用。")
        }
        .alert(String(localized: "alert.title"), isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(message ?? "")
        }
    }

    private func reload() {
        snapshots = BackupRecoveryService.listSnapshots(storeURL: WeekyiiPersistence.persistentStoreURL())
    }

    private func restorePendingSnapshot() {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        do {
            try BackupRecoveryService.restoreSnapshot(named: snapshot.folderName, to: WeekyiiPersistence.persistentStoreURL())
            message = "恢复完成。请立即完全退出并重新打开 Weekyii。"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }
}
