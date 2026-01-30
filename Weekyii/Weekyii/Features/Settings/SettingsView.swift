import SwiftUI

struct SettingsView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(AppState.self) private var appState
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                    // 默认参数
                    defaultParametersSection
                    
                    // 周设置
                    weekSettingsSection
                    
                    // iCloud 同步
                    iCloudSection
                    
                    // 关于
                    aboutSection
                }
                .weekPadding(WeekSpacing.base)
            }
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WeekLogo(size: .small, animated: false)
                }
            }
        }
    }
    
    // MARK: - Default Parameters Section
    
    private var defaultParametersSection: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.weekyiiPrimary)
                    Text(String(localized: "settings.defaults.header"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                
                Divider()
                
                // Kill Time
                settingRow(
                    icon: "clock.fill",
                    title: String(localized: "settings.default_kill_time")
                ) {
                    killTimePicker
                }
                
                Divider()
                
                // Task Type
                settingRow(
                    icon: "list.bullet",
                    title: String(localized: "settings.default_task_type")
                ) {
                    taskTypePicker
                }
                
                Divider()
                
                // Reminder
                settingRow(
                    icon: "bell.fill",
                    title: String(localized: "settings.kill_time_reminder")
                ) {
                    reminderPicker
                }
            }
        }
    }
    
    // MARK: - Week Settings Section
    
    private var weekSettingsSection: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.weekyiiPrimary)
                    Text(String(localized: "settings.week.header"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                
                Divider()
                
                Toggle(isOn: Binding(
                    get: { settings.weekStartsOnMonday },
                    set: { settings.weekStartsOnMonday = $0 }
                )) {
                    VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                        Text(String(localized: "settings.week.starts_monday"))
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)
                        Text(String(localized: "settings.week.starts_monday.subtitle"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
                .tint(.weekyiiPrimary)
            }
        }
    }
    
    // MARK: - iCloud Section
    
    private var iCloudSection: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    Image(systemName: "icloud.fill")
                        .foregroundColor(.accentOrange)
                    Text(String(localized: "settings.icloud.header"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                
                Divider()
                
                Toggle(isOn: .constant(false)) {
                    VStack(alignment: .leading, spacing: WeekSpacing.xxs) {
                        Text(String(localized: "settings.icloud.sync"))
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)
                        Text(String(localized: "settings.icloud.coming_soon"))
                            .font(.caption)
                            .foregroundColor(.accentOrange)
                    }
                }
                .disabled(true)
            }
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.accentGreen)
                    Text(String(localized: "settings.about.header"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                
                Divider()
                
                // Version
                HStack {
                    Text(String(localized: "settings.about.version"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("1.0.0")
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)
                }
                
                // Start Date
                if let startDate = appState.systemStartDate {
                    HStack {
                        Text(String(localized: "settings.about.start_date"))
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(startDate, format: Date.FormatStyle().year().month().day())
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)
                    }
                }
                
                // Days Started
                HStack {
                    Text(String(localized: "settings.about.days_started"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("\(appState.daysStartedCount)")
                        .font(.titleMedium)
                        .foregroundColor(.weekyiiPrimary)
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func settingRow<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.textSecondary)
                .frame(width: 20)
            Text(title)
                .font(.bodyMedium)
                .foregroundColor(.textPrimary)
            Spacer()
            content()
        }
    }
    
    private var killTimePicker: some View {
        HStack(spacing: 4) {
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
                .foregroundColor(.textSecondary)
            
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
    
    private var taskTypePicker: some View {
        Picker("", selection: Binding(
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
        }
        .pickerStyle(.menu)
    }
    
    private var reminderPicker: some View {
        Picker("", selection: Binding(
            get: { settings.killTimeReminderMinutes },
            set: { settings.killTimeReminderMinutes = $0 }
        )) {
            Text(String(localized: "settings.reminder.none")).tag(0)
            Text(String(localized: "settings.reminder.15min")).tag(15)
            Text(String(localized: "settings.reminder.30min")).tag(30)
            Text(String(localized: "settings.reminder.60min")).tag(60)
        }
        .pickerStyle(.menu)
    }
}
