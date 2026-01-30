import Foundation
import Observation

@Observable
final class UserSettings {
    // Default Kill Time
    var defaultKillTimeHour: Int {
        didSet { save() }
    }
    var defaultKillTimeMinute: Int {
        didSet { save() }
    }
    
    // Default Task Type
    var defaultTaskType: TaskType {
        didSet { save() }
    }
    
    // Notification Settings
    var killTimeReminderMinutes: Int {
        didSet { save() }
    }
    
    // Week Settings
    var weekStartsOnMonday: Bool {
        didSet { save() }
    }
    
    // iCloud Sync (placeholder)
    var iCloudSyncEnabled: Bool {
        didSet { save() }
    }

    // Demo Seed Settings
    var seedPastWeeks: Int {
        didSet { save() }
    }
    var seedFutureWeeks: Int {
        didSet { save() }
    }
    var seedTasksPerPastDay: Int {
        didSet { save() }
    }
    var seedTasksPerDraftDay: Int {
        didSet { save() }
    }
    var seedExpiredEveryNDays: Int {
        didSet { save() }
    }
    var seedIncludeSteps: Bool {
        didSet { save() }
    }
    var seedIncludeAttachments: Bool {
        didSet { save() }
    }
    var seedIncludeDescriptions: Bool {
        didSet { save() }
    }
    var seedAllowExisting: Bool {
        didSet { save() }
    }
    
    private let defaults = UserDefaults.standard
    
    init() {
        // Load saved values or use defaults
        self.defaultKillTimeHour = defaults.object(forKey: "defaultKillTimeHour") as? Int ?? 20
        self.defaultKillTimeMinute = defaults.object(forKey: "defaultKillTimeMinute") as? Int ?? 0
        
        if let rawTaskType = defaults.string(forKey: "defaultTaskType"),
           let taskType = TaskType(rawValue: rawTaskType) {
            self.defaultTaskType = taskType
        } else {
            self.defaultTaskType = .regular
        }
        
        self.killTimeReminderMinutes = defaults.object(forKey: "killTimeReminderMinutes") as? Int ?? 30
        self.weekStartsOnMonday = defaults.object(forKey: "weekStartsOnMonday") as? Bool ?? true
        self.iCloudSyncEnabled = defaults.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
        
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
        defaults.set(weekStartsOnMonday, forKey: "weekStartsOnMonday")
        defaults.set(iCloudSyncEnabled, forKey: "iCloudSyncEnabled")
        
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
}
