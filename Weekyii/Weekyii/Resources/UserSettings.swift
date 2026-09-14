import Foundation
import Combine
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    @Published var defaultTaskTypeIdRaw: String {
        didSet { save() }
    }

    @Published var defaultExecutionModeRaw: String {
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

    // Morning Reminder Rhythm (shared by the daily kill-time reminder and the
    // suspended-task morning checkpoints)
    @Published var morningReminderHour: Int {
        didSet { save() }
    }
    @Published var morningReminderMinute: Int {
        didSet { save() }
    }

    // Suspended Task Reminder Rhythm
    @Published var suspendedReminderEnabled: Bool {
        didSet { save() }
    }
    @Published var suspendedReminderIntensityRaw: String {
        didSet { save() }
    }
    @Published var suspendedReminderAdvanceDays: Int {
        didSet { save() }
    }
    @Published var suspendedReminderEveningHour: Int {
        didSet { save() }
    }
    @Published var suspendedReminderEveningMinute: Int {
        didSet { save() }
    }

    // Suspended Task Defaults
    @Published var suspendedDefaultCountdownDays: Int {
        didSet { save() }
    }

    // What happens when a suspended task passes its decision deadline.
    @Published var suspendedExpiryPolicyRaw: String {
        didSet { save() }
    }
    
    // Week Settings
    @Published var weekStartsOnMonday: Bool {
        didSet { save() }
    }

    // Project Defaults
    @Published var defaultProjectDurationDays: Int {
        didSet { save() }
    }
    @Published var defaultProjectTileSizeRaw: String {
        didSet { save() }
    }
    @Published var defaultProjectColorHex: String {
        didSet { save() }
    }
    @Published var defaultProjectIconName: String {
        didSet { save() }
    }
    @Published var boardColumnCount: Int {
        didSet { save() }
    }

    // Motion Settings
    @Published var reduceMotionEnabled: Bool {
        didSet { save() }
    }
    @Published var moduleTileRotationEnabled: Bool {
        didSet { save() }
    }
    @Published var startRitualEnabled: Bool {
        didSet { save() }
    }

    // Language Settings
    @Published var languageOverrideRaw: String {
        didSet { save() }
    }

    // Data Settings
    @Published var recoveryPointRetentionCount: Int {
        didSet { save() }
    }

    // Pending Month View Marker Settings
    @Published var pendingMonthShowRegular: Bool {
        didSet { save() }
    }
    @Published var pendingMonthShowDDL: Bool {
        didSet { save() }
    }
    @Published var pendingMonthShowLeisure: Bool {
        didSet { save() }
    }
    
    // Theme Settings
    @Published var selectedThemeRaw: String {
        didSet { save() }
    }
    @Published var appearanceModeRaw: String {
        didSet { save() }
    }
    @Published var premiumThemeUnlocked: Bool {
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
    
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Load saved values or use defaults
        self.defaultKillTimeHour = defaults.object(forKey: "defaultKillTimeHour") as? Int ?? 23
        self.defaultKillTimeMinute = defaults.object(forKey: "defaultKillTimeMinute") as? Int ?? 45
        
        let resolvedDefaultTaskType: TaskType
        if let rawTaskType = defaults.string(forKey: "defaultTaskType"),
           let taskType = TaskType(rawValue: rawTaskType) {
            resolvedDefaultTaskType = taskType
        } else {
            resolvedDefaultTaskType = .regular
        }
        self.defaultTaskType = resolvedDefaultTaskType
        self.defaultTaskTypeIdRaw = defaults.string(forKey: "defaultTaskTypeId") ?? resolvedDefaultTaskType.rawValue
        self.defaultExecutionModeRaw = defaults.string(forKey: "defaultExecutionMode") ?? ExecutionMode.strict.rawValue
        
        self.killTimeReminderMinutes = defaults.object(forKey: "killTimeReminderMinutes") as? Int ?? 60
        self.fixedReminderEnabled = defaults.object(forKey: "fixedReminderEnabled") as? Bool ?? false
        self.fixedReminderHour = defaults.object(forKey: "fixedReminderHour") as? Int ?? 21
        self.fixedReminderMinute = defaults.object(forKey: "fixedReminderMinute") as? Int ?? 0
        self.morningReminderHour = defaults.object(forKey: "morningReminderHour") as? Int ?? 9
        self.morningReminderMinute = defaults.object(forKey: "morningReminderMinute") as? Int ?? 0
        self.suspendedReminderEnabled = defaults.object(forKey: "suspendedReminderEnabled") as? Bool ?? true
        self.suspendedReminderIntensityRaw = defaults.string(forKey: "suspendedReminderIntensity") ?? SuspendedReminderIntensity.full.rawValue
        self.suspendedReminderAdvanceDays = defaults.object(forKey: "suspendedReminderAdvanceDays") as? Int ?? 3
        self.suspendedReminderEveningHour = defaults.object(forKey: "suspendedReminderEveningHour") as? Int ?? 19
        self.suspendedReminderEveningMinute = defaults.object(forKey: "suspendedReminderEveningMinute") as? Int ?? 30
        self.suspendedDefaultCountdownDays = defaults.object(forKey: "suspendedDefaultCountdownDays") as? Int ?? 10
        self.suspendedExpiryPolicyRaw = defaults.string(forKey: "suspendedExpiryPolicy") ?? SuspendedExpiryPolicy.autoDelete.rawValue
        self.weekStartsOnMonday = defaults.object(forKey: "weekStartsOnMonday") as? Bool ?? true
        self.defaultProjectDurationDays = defaults.object(forKey: "defaultProjectDurationDays") as? Int ?? 7
        self.defaultProjectTileSizeRaw = defaults.string(forKey: "defaultProjectTileSize") ?? ProjectTileSize.medium.rawValue
        self.defaultProjectColorHex = defaults.string(forKey: "defaultProjectColor") ?? "#C46A1A"
        self.defaultProjectIconName = defaults.string(forKey: "defaultProjectIcon") ?? "folder.fill"
        self.boardColumnCount = defaults.object(forKey: "boardColumnCount") as? Int ?? 4
        self.reduceMotionEnabled = defaults.object(forKey: "reduceMotionEnabled") as? Bool ?? false
        self.moduleTileRotationEnabled = defaults.object(forKey: "moduleTileRotationEnabled") as? Bool ?? true
        self.startRitualEnabled = defaults.object(forKey: "startRitualEnabled") as? Bool ?? true
        self.languageOverrideRaw = defaults.string(forKey: "languageOverride") ?? LanguageOverride.system.rawValue
        self.recoveryPointRetentionCount = defaults.object(forKey: "recoveryPointRetentionCount") as? Int ?? 8
        self.pendingMonthShowRegular = defaults.object(forKey: "pendingMonthShowRegular") as? Bool ?? false
        self.pendingMonthShowDDL = defaults.object(forKey: "pendingMonthShowDDL") as? Bool ?? true
        self.pendingMonthShowLeisure = defaults.object(forKey: "pendingMonthShowLeisure") as? Bool ?? false
        self.selectedThemeRaw = defaults.string(forKey: "selectedTheme") ?? WeekTheme.amber.rawValue
        self.appearanceModeRaw = defaults.string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
        self.premiumThemeUnlocked = defaults.object(forKey: "premiumThemeUnlocked") as? Bool ?? false
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

        let sharedDefaults = WeekyiiWidgetBridge.sharedDefaults()
        sharedDefaults.set(selectedThemeRaw, forKey: WeekyiiWidgetBridge.selectedThemeKey)
        sharedDefaults.set(appearanceModeRaw, forKey: WeekyiiWidgetBridge.appearanceModeKey)
        sharedDefaults.set(premiumThemeUnlocked, forKey: WeekyiiWidgetBridge.premiumThemeUnlockedKey)

        syncNotificationConfiguration()
    }
    
    func save() {
        defaults.set(defaultKillTimeHour, forKey: "defaultKillTimeHour")
        defaults.set(defaultKillTimeMinute, forKey: "defaultKillTimeMinute")
        defaults.set(defaultTaskType.rawValue, forKey: "defaultTaskType")
        defaults.set(defaultTaskTypeIdRaw, forKey: "defaultTaskTypeId")
        defaults.set(defaultExecutionModeRaw, forKey: "defaultExecutionMode")
        defaults.set(killTimeReminderMinutes, forKey: "killTimeReminderMinutes")
        defaults.set(fixedReminderEnabled, forKey: "fixedReminderEnabled")
        defaults.set(fixedReminderHour, forKey: "fixedReminderHour")
        defaults.set(fixedReminderMinute, forKey: "fixedReminderMinute")
        defaults.set(morningReminderHour, forKey: "morningReminderHour")
        defaults.set(morningReminderMinute, forKey: "morningReminderMinute")
        defaults.set(suspendedReminderEnabled, forKey: "suspendedReminderEnabled")
        defaults.set(suspendedReminderIntensityRaw, forKey: "suspendedReminderIntensity")
        defaults.set(suspendedReminderAdvanceDays, forKey: "suspendedReminderAdvanceDays")
        defaults.set(suspendedReminderEveningHour, forKey: "suspendedReminderEveningHour")
        defaults.set(suspendedReminderEveningMinute, forKey: "suspendedReminderEveningMinute")
        defaults.set(suspendedDefaultCountdownDays, forKey: "suspendedDefaultCountdownDays")
        defaults.set(suspendedExpiryPolicyRaw, forKey: "suspendedExpiryPolicy")
        defaults.set(weekStartsOnMonday, forKey: "weekStartsOnMonday")
        defaults.set(defaultProjectDurationDays, forKey: "defaultProjectDurationDays")
        defaults.set(defaultProjectTileSizeRaw, forKey: "defaultProjectTileSize")
        defaults.set(defaultProjectColorHex, forKey: "defaultProjectColor")
        defaults.set(defaultProjectIconName, forKey: "defaultProjectIcon")
        defaults.set(boardColumnCount, forKey: "boardColumnCount")
        defaults.set(reduceMotionEnabled, forKey: "reduceMotionEnabled")
        defaults.set(moduleTileRotationEnabled, forKey: "moduleTileRotationEnabled")
        defaults.set(startRitualEnabled, forKey: "startRitualEnabled")
        defaults.set(languageOverrideRaw, forKey: "languageOverride")
        defaults.set(recoveryPointRetentionCount, forKey: "recoveryPointRetentionCount")
        defaults.set(pendingMonthShowRegular, forKey: "pendingMonthShowRegular")
        defaults.set(pendingMonthShowDDL, forKey: "pendingMonthShowDDL")
        defaults.set(pendingMonthShowLeisure, forKey: "pendingMonthShowLeisure")
        defaults.set(selectedThemeRaw, forKey: "selectedTheme")
        defaults.set(appearanceModeRaw, forKey: "appearanceMode")
        defaults.set(premiumThemeUnlocked, forKey: "premiumThemeUnlocked")
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

        let sharedDefaults = WeekyiiWidgetBridge.sharedDefaults()
        sharedDefaults.set(selectedThemeRaw, forKey: WeekyiiWidgetBridge.selectedThemeKey)
        sharedDefaults.set(appearanceModeRaw, forKey: WeekyiiWidgetBridge.appearanceModeKey)
        sharedDefaults.set(premiumThemeUnlocked, forKey: WeekyiiWidgetBridge.premiumThemeUnlockedKey)

        syncNotificationConfiguration()

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
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
        get { WeekTheme.resolvedTheme(rawValue: selectedThemeRaw, premiumThemeUnlocked: premiumThemeUnlocked) }
        set { selectedThemeRaw = newValue.rawValue }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }

    var defaultExecutionMode: ExecutionMode {
        get { ExecutionMode(rawValue: defaultExecutionModeRaw) ?? .strict }
        set { defaultExecutionModeRaw = newValue.rawValue }
    }

    var defaultProjectTileSize: ProjectTileSize {
        get { ProjectTileSize(storedValue: defaultProjectTileSizeRaw) ?? .medium }
        set { defaultProjectTileSizeRaw = newValue.rawValue }
    }

    var suspendedReminderIntensity: SuspendedReminderIntensity {
        get { SuspendedReminderIntensity(rawValue: suspendedReminderIntensityRaw) ?? .full }
        set { suspendedReminderIntensityRaw = newValue.rawValue }
    }

    var suspendedExpiryPolicy: SuspendedExpiryPolicy {
        get { SuspendedExpiryPolicy(rawValue: suspendedExpiryPolicyRaw) ?? .autoDelete }
        set { suspendedExpiryPolicyRaw = newValue.rawValue }
    }

    var languageOverride: LanguageOverride {
        get { LanguageOverride(rawValue: languageOverrideRaw) ?? .system }
        set { languageOverrideRaw = newValue.rawValue }
    }

    /// Board columns are clamped so a `wide` tile can still be laid out.
    var effectiveBoardColumnCount: Int {
        min(max(boardColumnCount, 2), 6)
    }

    var effectiveRecoveryPointRetentionCount: Int {
        min(max(recoveryPointRetentionCount, 1), 50)
    }

    var isMorningReminderValid: Bool {
        morningReminderHour >= 0 && morningReminderHour <= 23 &&
        morningReminderMinute >= 0 && morningReminderMinute <= 59
    }

    var isSuspendedEveningReminderValid: Bool {
        suspendedReminderEveningHour >= 0 && suspendedReminderEveningHour <= 23 &&
        suspendedReminderEveningMinute >= 0 && suspendedReminderEveningMinute <= 59
    }

    /// Single source of truth for reminder timing consumed by `NotificationService`.
    var notificationConfiguration: NotificationConfiguration {
        NotificationConfiguration(
            morningHour: morningReminderHour,
            morningMinute: morningReminderMinute,
            suspendedReminderEnabled: suspendedReminderEnabled,
            suspendedReminderIntensity: suspendedReminderIntensity,
            suspendedAdvanceDays: min(max(suspendedReminderAdvanceDays, 1), 14),
            suspendedEveningHour: suspendedReminderEveningHour,
            suspendedEveningMinute: suspendedReminderEveningMinute,
            suspendedExpiryPolicy: suspendedExpiryPolicy
        )
    }

    /// Pushes the current reminder rhythm into the notification scheduler so that
    /// call sites never have to thread settings through.
    func syncNotificationConfiguration() {
        NotificationService.shared.configuration = notificationConfiguration
    }

    /// Applies an in-app language override. The change takes effect after the app restarts.
    func setLanguageOverride(_ override: LanguageOverride) {
        languageOverrideRaw = override.rawValue
        applyLanguageOverride()
    }

    private func applyLanguageOverride() {
        let key = "AppleLanguages"
        if languageOverride == .system {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set([languageOverride.rawValue], forKey: key)
        }
    }

    var effectiveColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
