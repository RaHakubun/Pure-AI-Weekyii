import Foundation
import Combine

final class UserSettings: ObservableObject {
    // Default Kill Time
    @Published var defaultKillTimeHour: Int {
        didSet { save() }
    }
    @Published var defaultKillTimeMinute: Int {
        didSet { save() }
    }
    
    // Default Task Type
    @Published var defaultTaskType: TaskType {
        didSet { save() }
    }
    
    // Notification Settings
    @Published var killTimeReminderMinutes: Int {
        didSet { save() }
    }
    @Published var fixedReminderEnabled: Bool {
        didSet { save() }
    }
    @Published var fixedReminderHour: Int {
        didSet { save() }
    }
    @Published var fixedReminderMinute: Int {
        didSet { save() }
    }
    
    // Week Settings
    @Published var weekStartsOnMonday: Bool {
        didSet { save() }
    }
    
    // iCloud Sync (placeholder)
    @Published var iCloudSyncEnabled: Bool {
        didSet { save() }
    }

    // Theme Settings
    @Published var selectedThemeRaw: String {
        didSet { save() }
    }
    
    // Developer Settings
    @Published var developerSettingsEnabled: Bool {
        didSet { save() }
    }

    // Demo Seed Settings
    @Published var seedPastWeeks: Int {
        didSet { save() }
    }
    @Published var seedFutureWeeks: Int {
        didSet { save() }
    }
    @Published var seedTasksPerPastDay: Int {
        didSet { save() }
    }
    @Published var seedTasksPerDraftDay: Int {
        didSet { save() }
    }
    @Published var seedExpiredEveryNDays: Int {
        didSet { save() }
    }
    @Published var seedIncludeSteps: Bool {
        didSet { save() }
    }
    @Published var seedIncludeAttachments: Bool {
        didSet { save() }
    }
    @Published var seedIncludeDescriptions: Bool {
        didSet { save() }
    }
    @Published var seedAllowExisting: Bool {
        didSet { save() }
    }
    
    private let defaults = UserDefaults.standard
    
    init() {
        // Load saved values or use defaults
        self.defaultKillTimeHour = defaults.object(forKey: "defaultKillTimeHour") as? Int ?? 23
        self.defaultKillTimeMinute = defaults.object(forKey: "defaultKillTimeMinute") as? Int ?? 45
        
        if let rawTaskType = defaults.string(forKey: "defaultTaskType"),
           let taskType = TaskType(rawValue: rawTaskType) {
            self.defaultTaskType = taskType
        } else {
            self.defaultTaskType = .regular
        }
        
        self.killTimeReminderMinutes = defaults.object(forKey: "killTimeReminderMinutes") as? Int ?? 60
        self.fixedReminderEnabled = defaults.object(forKey: "fixedReminderEnabled") as? Bool ?? false
        self.fixedReminderHour = defaults.object(forKey: "fixedReminderHour") as? Int ?? 21
        self.fixedReminderMinute = defaults.object(forKey: "fixedReminderMinute") as? Int ?? 0
        self.weekStartsOnMonday = defaults.object(forKey: "weekStartsOnMonday") as? Bool ?? true
        self.iCloudSyncEnabled = defaults.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
        self.selectedThemeRaw = defaults.string(forKey: "selectedTheme") ?? WeekTheme.amber.rawValue
        self.developerSettingsEnabled = defaults.object(forKey: "developerSettingsEnabled") as? Bool ?? false
        
        self.seedPastWeeks = defaults.object(forKey: "seedPastWeeks") as? Int ?? 8
        self.seedFutureWeeks = defaults.object(forKey: "seedFutureWeeks") as? Int ?? 4
        self.seedTasksPerPastDay = defaults.object(forKey: "seedTasksPerPastDay") as? Int ?? 4
        self.seedTasksPerDraftDay = defaults.object(forKey: "seedTasksPerDraftDay") as? Int ?? 5
        self.seedExpiredEveryNDays = defaults.object(forKey: "seedExpiredEveryNDays") as? Int ?? 3
        self.seedIncludeSteps = defaults.object(forKey: "seedIncludeSteps") as? Bool ?? true
        self.seedIncludeAttachments = defaults.object(forKey: "seedIncludeAttachments") as? Bool ?? false
        self.seedIncludeDescriptions = defaults.object(forKey: "seedIncludeDescriptions") as? Bool ?? true
        self.seedAllowExisting = defaults.object(forKey: "seedAllowExisting") as? Bool ?? false
    }
    
    func save() {
        defaults.set(defaultKillTimeHour, forKey: "defaultKillTimeHour")
        defaults.set(defaultKillTimeMinute, forKey: "defaultKillTimeMinute")
        defaults.set(defaultTaskType.rawValue, forKey: "defaultTaskType")
        defaults.set(killTimeReminderMinutes, forKey: "killTimeReminderMinutes")
        defaults.set(fixedReminderEnabled, forKey: "fixedReminderEnabled")
        defaults.set(fixedReminderHour, forKey: "fixedReminderHour")
        defaults.set(fixedReminderMinute, forKey: "fixedReminderMinute")
        defaults.set(weekStartsOnMonday, forKey: "weekStartsOnMonday")
        defaults.set(iCloudSyncEnabled, forKey: "iCloudSyncEnabled")
        defaults.set(selectedThemeRaw, forKey: "selectedTheme")
        defaults.set(developerSettingsEnabled, forKey: "developerSettingsEnabled")
        
        defaults.set(seedPastWeeks, forKey: "seedPastWeeks")
        defaults.set(seedFutureWeeks, forKey: "seedFutureWeeks")
        defaults.set(seedTasksPerPastDay, forKey: "seedTasksPerPastDay")
        defaults.set(seedTasksPerDraftDay, forKey: "seedTasksPerDraftDay")
        defaults.set(seedExpiredEveryNDays, forKey: "seedExpiredEveryNDays")
        defaults.set(seedIncludeSteps, forKey: "seedIncludeSteps")
        defaults.set(seedIncludeAttachments, forKey: "seedIncludeAttachments")
        defaults.set(seedIncludeDescriptions, forKey: "seedIncludeDescriptions")
        defaults.set(seedAllowExisting, forKey: "seedAllowExisting")
    }
    
    // Validation helpers
    var isKillTimeValid: Bool {
        defaultKillTimeHour >= 0 && defaultKillTimeHour <= 23 &&
        defaultKillTimeMinute >= 0 && defaultKillTimeMinute <= 59
    }
    
    var isReminderValid: Bool {
        killTimeReminderMinutes >= 0 && killTimeReminderMinutes <= 120
    }

    var isFixedReminderValid: Bool {
        fixedReminderHour >= 0 && fixedReminderHour <= 23 &&
        fixedReminderMinute >= 0 && fixedReminderMinute <= 59
    }

    var selectedTheme: WeekTheme {
        get { WeekTheme(rawValue: selectedThemeRaw) ?? .amber }
        set { selectedThemeRaw = newValue.rawValue }
    }
}
