import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
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
    
    var body: some View {
        NavigationStack {
            settingsHome
            .navigationTitle(String(localized: "settings.title"))
            .tint(.weekyiiPrimary)
        }
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
        .sheet(isPresented: $showingCreateTaskType) {
            TaskTypeDefinitionEditorSheet { name, iconName, colorHex in
                createTaskType(name: name, iconName: iconName, colorHex: colorHex)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingTaskTypeIdRaw != nil },
            set: { if !$0 { editingTaskTypeIdRaw = nil } }
        )) {
            if let definition = taskTypeDefinitions.first(where: { $0.idRaw == editingTaskTypeIdRaw }) {
                TaskTypeDefinitionEditorSheet(definition: definition) { name, iconName, colorHex in
                    updateTaskType(definition, name: name, iconName: iconName, colorHex: colorHex)
                    editingTaskTypeIdRaw = nil
                } onArchive: {
                    archiveTaskType(definition)
                    editingTaskTypeIdRaw = nil
                }
            }
        }
    }

    private var settingsHome: some View {
        ScrollView {
            VStack(spacing: WeekSpacing.lg) {
                settingsHero

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: WeekSpacing.md),
                        GridItem(.flexible())
                    ],
                    spacing: WeekSpacing.md
                ) {
                    NavigationLink {
                        todayRhythmSettingsPage
                    } label: {
                        SettingsNavigationCard(
                            title: "今日节奏",
                            subtitle: String(format: "%02d:%02d · %@", settings.defaultKillTimeHour, settings.defaultKillTimeMinute, settings.defaultExecutionMode.displayName),
                            icon: "timer",
                            tint: .orange
                        )
                    }

                    NavigationLink {
                        appearanceSettingsPage
                    } label: {
                        SettingsNavigationCard(
                            title: "外观与主题",
                            subtitle: "\(settings.selectedTheme.displayName) · \(appearanceDisplayName(for: settings.appearanceMode))",
                            icon: "paintpalette.fill",
                            tint: .purple
                        )
                    }

                    NavigationLink {
                        taskTypeSettingsPage
                    } label: {
                        SettingsNavigationCard(
                            title: "任务与分类",
                            subtitle: "\(activeTaskTypeDefinitions.count) 个任务类型",
                            icon: "tag.fill",
                            tint: .teal
                        )
                    }

                    NavigationLink {
                        futureSettingsPage
                    } label: {
                        SettingsNavigationCard(
                            title: "未来与日历",
                            subtitle: settings.weekStartsOnMonday ? "周一作为每周开始" : "跟随当前周起始设置",
                            icon: "calendar.badge.clock",
                            tint: .blue
                        )
                    }

                    NavigationLink {
                        dataSettingsPage
                    } label: {
                        SettingsNavigationCard(
                            title: "数据与安全",
                            subtitle: "导出、同步与本地数据",
                            icon: "lock.shield.fill",
                            tint: .indigo
                        )
                    }

                    NavigationLink {
                        aboutSettingsPage
                    } label: {
                        SettingsNavigationCard(
                            title: "关于 Weekyii",
                            subtitle: "版本、历程与高级选项",
                            icon: "info.circle.fill",
                            tint: .mint
                        )
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, WeekSpacing.base)
            .padding(.vertical, WeekSpacing.md)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
    }

    private var settingsHero: some View {
        ThemeStatusArtwork(theme: settings.selectedTheme)
            .frame(height: 132)
            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.selectedTheme.displayName)
                            .font(.titleMedium)
                            .foregroundStyle(.white)
                        Text("让 Weekyii 按照你的节奏与审美运行")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .padding(WeekSpacing.md)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.large, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
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
        }
        .navigationTitle("任务与分类")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var futureSettingsPage: some View {
        Form { futureSection }
            .navigationTitle("未来与日历")
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
            Section("高级") {
                NavigationLink {
                    developerSettingsPage
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(icon: "hammer.fill", color: .gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("开发者与诊断")
                            Text("测试数据、状态诊断与备份恢复")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                WeekCard {
                    VStack(alignment: .leading, spacing: WeekSpacing.md) {
                        Label("显示模式", systemImage: "circle.lefthalf.filled")
                            .font(.titleSmall)
                            .foregroundStyle(Color.textPrimary)
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
                }

                VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                    Text("选择主题")
                        .font(.titleMedium)
                        .foregroundStyle(Color.textPrimary)
                    Text("每套主题都拥有独立的色彩、明暗关系与印象画。")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: WeekSpacing.md),
                        GridItem(.flexible())
                    ],
                    spacing: WeekSpacing.md
                ) {
                    ForEach(WeekTheme.allCases) { theme in
                        Button {
                            guard canSelect(theme) else { return }
                            withAnimation(.easeInOut(duration: 0.22)) {
                                settings.selectedThemeRaw = theme.rawValue
                            }
                        } label: {
                            ThemeSelectionCard(
                                theme: theme,
                                isSelected: settings.selectedTheme == theme,
                                isLocked: theme.isPremiumTheme && !settings.premiumThemeUnlocked
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(theme.isPremiumTheme && !settings.premiumThemeUnlocked)
                    }
                }
            }
            .padding(WeekSpacing.base)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("外观与主题")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Past
    @ViewBuilder
    private var pastSection: some View {
        Section {
            HStack(spacing: 12) {
                SettingsIcon(icon: "flag.fill", color: .orange)
                Text(String(localized: "settings.about.days_started"))
                Spacer()
                Text("\(appState.daysStartedCount)")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                SettingsIcon(icon: "chart.bar.fill", color: .mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.past.summary.title", defaultValue: "统计口径说明"))
                    Text(String(localized: "settings.past.summary.note", defaultValue: "completed 计入完成详情；expired 仅保留数量，不保留任务详情。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(String(localized: "settings.section.past", defaultValue: "过去"))
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

            HStack(spacing: 12) {
                SettingsIcon(icon: "square.and.arrow.up.fill", color: .indigo)
                Text(String(localized: "settings.data.export"))
                Spacer()
                Text(String(localized: "settings.data.export.coming_soon"))
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Text(String(localized: "settings.section.data"))
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

            if let startDate = appState.systemStartDate {
                HStack(spacing: 12) {
                    SettingsIcon(icon: "calendar", color: .blue)
                    Text(String(localized: "settings.about.start_date"))
                    Spacer()
                    Text(startDate, format: Date.FormatStyle().year().month().day())
                        .foregroundStyle(.secondary)
                }
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
        HStack(spacing: 12) {
            SettingsIcon(icon: "clock.fill", color: .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.default_kill_time"))
                Text(String(localized: "settings.default_kill_time.guidance", defaultValue: "一天的任务将在截止时间结算"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DatePicker(
                "",
                selection: pendingDefaultKillTimeDateBinding,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .background(Color(uiColor: .tertiarySystemFill))
            .cornerRadius(8)
        }

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
        HStack(spacing: 12) {
            SettingsIcon(icon: "tag.fill", color: .teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("任务类型管理")
                Text("\(activeTaskTypeDefinitions.count) 个类型 · 自定义分类外观")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingCreateTaskType = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("新增任务类型")
        }

        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(activeTaskTypeDefinitions, id: \.idRaw) { definition in
                    taskTypePill(definition)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 54, bottom: 10, trailing: 16))
    }

    private func taskTypePill(_ definition: TaskTypeDefinition) -> some View {
        Button {
            guard !definition.isBuiltIn else { return }
            editingTaskTypeIdRaw = definition.idRaw
        } label: {
            HStack(spacing: 6) {
                Image(systemName: definition.iconName)
                    .font(.caption.weight(.semibold))
                Text(definition.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(definition.color)
            .frame(width: 78, height: 34)
            .background(definition.color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(definition.isBuiltIn ? definition.name : "编辑 \(definition.name)")
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
            HStack(spacing: 12) {
                SettingsIcon(icon: "clock.badge.fill", color: .indigo)
                Text("提醒时刻")
                Spacer()
                DatePicker(
                    "",
                    selection: fixedReminderDateBinding,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .background(Color(uiColor: .tertiarySystemFill))
                .cornerRadius(8)
            }
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

    private func createTaskType(name: String, iconName: String, colorHex: String) {
        let nextOrder = ((try? modelContext.fetch(FetchDescriptor<TaskTypeDefinition>())) ?? [])
            .map(\.sortOrder)
            .max() ?? 2
        modelContext.insert(TaskTypeDefinition(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            baseKind: .regular,
            sortOrder: nextOrder + 1
        ))
        try? modelContext.save()
    }

    private func updateTaskType(_ definition: TaskTypeDefinition, name: String, iconName: String, colorHex: String) {
        guard !definition.isBuiltIn else { return }
        definition.name = name
        definition.iconName = iconName
        definition.colorHex = colorHex
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
    let onSave: (String, String, String) -> Void
    let onArchive: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var iconName: String
    @State private var colorHex: String

    private let icons = ["checkmark.circle", "scope", "pencil.line", "book.closed", "hammer", "bolt", "flame", "calendar.badge.clock", "leaf", "sparkles", "star", "heart"]
    private let colors = ["#4A90A4", "#C46A1A", "#8B5A83", "#4D9DE0", "#59A14F", "#E15759", "#B07AA1", "#F28E2B"]

    init(
        definition: TaskTypeDefinition? = nil,
        onSave: @escaping (String, String, String) -> Void,
        onArchive: (() -> Void)? = nil
    ) {
        self.definition = definition
        self.onSave = onSave
        self.onArchive = onArchive
        _name = State(initialValue: definition?.name ?? "")
        _iconName = State(initialValue: definition?.iconName ?? "tag.fill")
        _colorHex = State(initialValue: definition?.colorHex ?? "#4A90A4")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础") {
                    TextField("类型名称", text: $name)
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
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), iconName, colorHex)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct SettingsNavigationCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.titleSmall)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(WeekSpacing.md)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .stroke(tint.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

private struct ThemeSelectionCard: View {
    let theme: WeekTheme
    let isSelected: Bool
    let isLocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            ThemeStatusArtwork(theme: theme)
                .frame(height: 76)
                .clipShape(RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.46), in: Circle())
                            .padding(6)
                    }
                }

            HStack(spacing: WeekSpacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.bodyMedium.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 4) {
                        Circle().fill(theme.primaryColor).frame(width: 7, height: 7)
                        Circle().fill(theme.accentColor).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.primaryColor)
                }
            }
        }
        .padding(8)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .stroke(isSelected ? theme.primaryColor : Color.clear, lineWidth: 2)
        )
        .opacity(isLocked ? 0.66 : 1)
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
