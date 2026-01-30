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
    }
    
    func save() {
        defaults.set(defaultKillTimeHour, forKey: "defaultKillTimeHour")
        defaults.set(defaultKillTimeMinute, forKey: "defaultKillTimeMinute")
        defaults.set(defaultTaskType.rawValue, forKey: "defaultTaskType")
        defaults.set(killTimeReminderMinutes, forKey: "killTimeReminderMinutes")
        defaults.set(weekStartsOnMonday, forKey: "weekStartsOnMonday")
        defaults.set(iCloudSyncEnabled, forKey: "iCloudSyncEnabled")
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
