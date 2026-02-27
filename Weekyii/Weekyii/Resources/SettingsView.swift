import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var seedAlertMessage: String?
    @State private var showingClearConfirm = false
    @State private var pendingDefaultKillTimeHour = 0
    @State private var pendingDefaultKillTimeMinute = 0
    @State private var hasInitializedPendingDefaultKillTime = false
    @State private var showingDefaultKillTimeApplyConfirm = false
    @State private var showingDefaultKillTimeRiskConfirm = false
    @State private var showingCannotSyncExpiredTodayAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Tasks & Time
                Section {
                    killTimeSettings
                    reminderSettings
                    taskTypeSettings
                } header: {
                    Text(String(localized: "settings.section.tasks"))
                }
                
                // MARK: - Week & Stats
                Section {
                    Picker(selection: Binding(
                        get: { settings.selectedThemeRaw },
                        set: { settings.selectedThemeRaw = $0 }
                    )) {
                        ForEach(WeekTheme.allCases) { theme in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(theme.primaryColor)
                                    .frame(width: 10, height: 10)
                                Circle()
                                    .fill(theme.accentColor)
                                    .frame(width: 10, height: 10)
                                Text(theme.displayName)
                            }
                            .tag(theme.rawValue)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(icon: "paintpalette.fill", color: .purple)
                            Text("主题色")
                        }
                    }

                    themePalettePreview
                } header: {
                    Text(String(localized: "settings.section.week"))
                }
                
                // MARK: - Data & Privacy
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

                // MARK: - Developer Settings
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
                    }
                } header: {
                    Text(String(localized: "settings.developer.header"))
                } footer: {
                    Text(String(localized: "settings.developer.footer"))
                }
                
                // MARK: - About
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
                    
                    HStack(spacing: 12) {
                        SettingsIcon(icon: "flag.fill", color: .orange)
                        Text(String(localized: "settings.about.days_started"))
                        Spacer()
                        Text("\(appState.daysStartedCount)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "settings.about.header"))
                }
            }
            .navigationTitle(String(localized: "settings.title"))
            .tint(.weekyiiPrimary)
        }
        .onAppear {
            guard !hasInitializedPendingDefaultKillTime else { return }
            pendingDefaultKillTimeHour = settings.defaultKillTimeHour
            pendingDefaultKillTimeMinute = settings.defaultKillTimeMinute
            hasInitializedPendingDefaultKillTime = true
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
    }
    
    // MARK: - Kill Time Settings
    @ViewBuilder
    private var killTimeSettings: some View {
        HStack(spacing: 12) {
            SettingsIcon(icon: "clock.fill", color: .orange)
            Text(String(localized: "settings.default_kill_time"))
            Spacer()
            
            HStack(spacing: 2) {
                Picker("", selection: Binding(
                    get: { pendingDefaultKillTimeHour },
                    set: { pendingDefaultKillTimeHour = $0 }
                )) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 58)
                .clipped()
                
                Text(":")
                    .foregroundStyle(.secondary)
                
                Picker("", selection: Binding(
                    get: { pendingDefaultKillTimeMinute },
                    set: { pendingDefaultKillTimeMinute = $0 }
                )) {
                    ForEach(0..<60, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 58)
                .clipped()
            }
            .padding(.vertical, 2)
            .background(Color(uiColor: .tertiarySystemFill))
            .cornerRadius(8)
        }

        HStack(spacing: 12) {
            Color.clear
                .frame(width: 28, height: 28) // Placeholder padding
            Text("手动输入")
                .foregroundStyle(.secondary)
            Spacer()
            timeInputField("HH", value: Binding(
                get: { pendingDefaultKillTimeHour },
                set: { pendingDefaultKillTimeHour = min(max($0, 0), 23) }
            ))
            Text(":")
                .foregroundStyle(.secondary)
            timeInputField("MM", value: Binding(
                get: { pendingDefaultKillTimeMinute },
                set: { pendingDefaultKillTimeMinute = min(max($0, 0), 59) }
            ))
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
            get: { settings.defaultTaskType },
            set: { settings.defaultTaskType = $0 }
        )) {
            ForEach(TaskType.allCases, id: \.self) { type in
                HStack {
                    Image(systemName: type.iconName)
                    Text(type.displayName)
                }
                .tag(type)
            }
        } label: {
            HStack(spacing: 12) {
                SettingsIcon(icon: "checkmark.circle.fill", color: .green)
                Text(String(localized: "settings.default_task_type"))
            }
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
        } label: {
            HStack(spacing: 12) {
                SettingsIcon(icon: "bell.fill", color: .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.kill_time_reminder"))
                    Text(String(localized: "settings.kill_time_reminder.subtitle"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                Color.clear
                    .frame(width: 28, height: 28) // Placeholder alignment
                Text("提醒时刻")
                    .foregroundStyle(.secondary)
                Spacer()
                
                HStack(spacing: 2) {
                    Picker("", selection: Binding(
                        get: { settings.fixedReminderHour },
                        set: { settings.fixedReminderHour = min(max($0, 0), 23) }
                    )) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d", hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 58)
                    .clipped()
                    
                    Text(":")
                        .foregroundStyle(.secondary)
                    
                    Picker("", selection: Binding(
                        get: { settings.fixedReminderMinute },
                        set: { settings.fixedReminderMinute = min(max($0, 0), 59) }
                    )) {
                        ForEach(0..<60, id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 58)
                    .clipped()
                }
                .padding(.vertical, 2)
                .background(Color(uiColor: .tertiarySystemFill))
                .cornerRadius(8)
            }
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
    
    private var expiredEveryLabel: String {
        if settings.seedExpiredEveryNDays == 0 {
            return String(localized: "settings.debug.seed.expired.none")
        }
        let template = String(localized: "settings.debug.seed.expired.every")
        return String(format: template, settings.seedExpiredEveryNDays)
    }

    private var themePalettePreview: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 28, height: 28) // Placeholder padding
            Text("主题预览")
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.selectedTheme.primaryColor)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.selectedTheme.accentColor)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.selectedTheme.backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(settings.selectedTheme.primaryColor.opacity(0.35), lineWidth: 1)
                    )
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            }
        }
    }

    private func timeInputField(_ placeholder: String, value: Binding<Int>) -> some View {
        TextField(placeholder, value: value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(width: 56)
            .textFieldStyle(.roundedBorder)
            .font(.body.monospacedDigit())
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
