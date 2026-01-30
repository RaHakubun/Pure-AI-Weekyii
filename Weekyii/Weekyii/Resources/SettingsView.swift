import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var seedAlertMessage: String?
    @State private var showingClearConfirm = false
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Default Parameters
                Section {
                    killTimeSettings
                    taskTypeSettings
                    reminderSettings
                } header: {
                    Text(String(localized: "settings.defaults.header"))
                } footer: {
                    Text(String(localized: "settings.defaults.footer"))
                }
                
                // MARK: - Week Settings
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.weekStartsOnMonday },
                        set: { settings.weekStartsOnMonday = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "settings.week.starts_monday"))
                            Text(String(localized: "settings.week.starts_monday.subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(String(localized: "settings.week.header"))
                }
                
                // MARK: - iCloud Sync (Placeholder)
                Section {
                    Toggle(isOn: .constant(false)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "settings.icloud.sync"))
                            Text(String(localized: "settings.icloud.coming_soon"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(true)
                    
                    HStack {
                        Text(String(localized: "settings.icloud.status"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(localized: "settings.icloud.status.disabled"))
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Text(String(localized: "settings.icloud.header"))
                } footer: {
                    Text(String(localized: "settings.icloud.footer"))
                }

                // MARK: - Debug Tools
                Section {
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
                            let seeder = SampleDataSeeder(modelContext: modelContext)
                            let result = try seeder.seed(options: seedOptions)
                            switch result {
                            case .seeded:
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
                } header: {
                    Text(String(localized: "settings.debug.header"))
                } footer: {
                    Text(String(localized: "settings.debug.seed.footer"))
                }
                
                // MARK: - About
                Section {
                    HStack {
                        Text(String(localized: "settings.about.version"))
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    if let startDate = appState.systemStartDate {
                        HStack {
                            Text(String(localized: "settings.about.start_date"))
                            Spacer()
                            Text(startDate, format: Date.FormatStyle().year().month().day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
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
                    let seeder = SampleDataSeeder(modelContext: modelContext)
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
    }
    
    // MARK: - Kill Time Settings
    private var killTimeSettings: some View {
        HStack {
            Text(String(localized: "settings.default_kill_time"))
            Spacer()
            Picker("", selection: Binding(
                get: { settings.defaultKillTimeHour },
                set: { settings.defaultKillTimeHour = $0 }
            )) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 70)
            
            Text(":")
            
            Picker("", selection: Binding(
                get: { settings.defaultKillTimeMinute },
                set: { settings.defaultKillTimeMinute = $0 }
            )) {
                ForEach([0, 15, 30, 45], id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 70)
        }
    }
    
    // MARK: - Task Type Settings
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
            Text(String(localized: "settings.default_task_type"))
        }
    }
    
    // MARK: - Reminder Settings
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
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.kill_time_reminder"))
                Text(String(localized: "settings.kill_time_reminder.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                day.status = .empty
            case .past:
                seedPastDay(day, index: index, options: options)
            case .present:
                if calendar.isDate(day.date, inSameDayAs: today) {
                    seedDraftDay(day, index: index, options: options)
                } else if day.date < today {
                    seedPastDay(day, index: index, options: options)
                } else {
                    day.status = .empty
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
            day.tasks.append(contentsOf: makeTasks(count: completedCount, zone: .complete, day: day, seed: index, options: options))
        } else {
            day.status = .completed
            let completedCount = totalCount
            day.tasks.append(contentsOf: makeTasks(count: completedCount, zone: .complete, day: day, seed: index, options: options))
        }
    }

    private func seedDraftDay(_ day: DayModel, index: Int, options: SeedOptions) {
        day.status = .draft
        let draftCount = max(1, options.tasksPerDraftDay)
        day.tasks.append(contentsOf: makeTasks(count: draftCount, zone: .draft, day: day, seed: index, options: options))
    }

    private func makeTasks(count: Int, zone: TaskZone, day: DayModel, seed: Int, options: SeedOptions) -> [TaskItem] {
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
            task.day = day

            if zone == .complete {
                task.completedOrder = i + 1
                task.endedAt = day.date.addingTimeInterval(TimeInterval((10 + i) * 3600))
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
        let days = (try? modelContext.fetch(FetchDescriptor<DayModel>())) ?? []
        for day in days {
            modelContext.delete(day)
        }
        let tasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        for task in tasks {
            modelContext.delete(task)
        }
        let steps = (try? modelContext.fetch(FetchDescriptor<TaskStep>())) ?? []
        for step in steps {
            modelContext.delete(step)
        }
        let attachments = (try? modelContext.fetch(FetchDescriptor<TaskAttachment>())) ?? []
        for attachment in attachments {
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
