import Foundation
import Combine
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

struct AutoStartConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    static let `default` = AutoStartConfiguration(isEnabled: false, hour: 9, minute: 0)
}

struct AutoStartDailyPlan: Codable, Equatable {
    var dayId: String
    var isEnabled: Bool
    var hour: Int
    var minute: Int
    var wasSkipped: Bool
    var activationDeferredUntilTomorrow: Bool
}

/// Week list or month calendar on the Pending and Past tabs.
enum WeekBrowseMode: String {
    case weekList
    case month
}

final class UserSettings: ObservableObject {
    private static let cloudSyncRequestedKey = "cloudSyncRequested"
    private static let legacyCloudSyncEnabledKey = "cloudSyncEnabled"
    private static let cloudSyncPreferenceMigratedV2Key = "weekyii.cloudSyncPreferenceMigratedV2"
    private static let autoStartConfigurationKey = "weekyii.autoStart.configuration"
    private static let autoStartDailyPlanKey = "weekyii.autoStart.dailyPlan"
    private static let autoStartWasEverEnabledKey = "weekyii.autoStart.wasEverEnabled"
    static let pendingBrowseModeKey = "weekyii.pending.browseMode"
    static let pastBrowseModeKey = "weekyii.past.browseMode"

    // Default Kill Time
    @Published var defaultKillTimeHour: Int {
        didSet { save() }
    }
    @Published var defaultKillTimeMinute: Int {
        didSet { save() }
    }

    /// Explicit device-local opt-in for the future custom-zone sync engine.
    @Published var cloudSyncRequested: Bool {
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

    @Published private(set) var autoStartConfiguration: AutoStartConfiguration
    @Published private(set) var autoStartDailyPlan: AutoStartDailyPlan?
    private(set) var autoStartWasEverEnabled: Bool
    
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

    // Past Month View Marker Settings (device-local display preference only;
    // intentionally not part of SwiftData, iCloud sync or data archives)
    @Published var pastMonthShowUnfinishedFace: Bool {
        didSet { save() }
    }
    @Published var pastMonthShowNotStartedFace: Bool {
        didSet { save() }
    }
    @Published var pastMonthShowCompletedCount: Bool {
        didSet { save() }
    }
    @Published var pastMonthShowRecordDot: Bool {
        didSet { save() }
    }
    @Published var pastMonthShowExpiredFlame: Bool {
        didSet { save() }
    }

    // Pending / Past browse mode: the last chosen view (week list or month
    // calendar) is restored on launch. Device-local display preference only;
    // intentionally not part of SwiftData, iCloud sync or data archives.
    @Published var pendingBrowseModeRaw: String {
        didSet { save() }
    }
    @Published var pastBrowseModeRaw: String {
        didSet { save() }
    }
    /// False under UI tests, so every run starts from the week list and never
    /// leaves a stored mode behind for the next run.
    private let restoresBrowseModes: Bool
    
    // Theme Settings
    @Published var selectedThemeRaw: String {
        didSet { save() }
    }
    @Published var appearanceModeRaw: String {
        didSet { save() }
    }
    /// Local display mirror of the resolved VIP access, written only by
    /// `PurchaseService` (and DEBUG overrides). It unlocks VIP themes and flexible
    /// mode for display/start decisions and is mirrored to widgets via the App Group.
    /// It is never an entitlement for iCloud sync and is not restored from archives.
    @Published var premiumThemeUnlocked: Bool {
        didSet { save() }
    }
    /// In-memory only: true once `PurchaseService` has resolved StoreKit at least once
    /// in this process. Until then the persisted mirror above may be stale, so it may
    /// only drive theme display (to avoid a launch flicker), never feature decisions.
    @Published var vipAccessResolved = false
    
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
    
    init(
        defaults: UserDefaults = .standard,
        restoresBrowseModes: Bool = !ProcessInfo.processInfo.arguments.contains("-uiTesting")
    ) {
        self.defaults = defaults
        self.restoresBrowseModes = restoresBrowseModes
        // Load saved values or use defaults
        self.defaultKillTimeHour = defaults.object(forKey: "defaultKillTimeHour") as? Int ?? 23
        self.defaultKillTimeMinute = defaults.object(forKey: "defaultKillTimeMinute") as? Int ?? 45
        let storedCloudSyncRequested = defaults.object(forKey: Self.cloudSyncRequestedKey) as? Bool
        self.cloudSyncRequested = storedCloudSyncRequested ?? false
        if storedCloudSyncRequested == nil {
            defaults.set(false, forKey: Self.cloudSyncRequestedKey)
        }
        if defaults.object(forKey: Self.cloudSyncPreferenceMigratedV2Key) as? Bool != true {
            // The legacy sync preference cannot opt into the new explicit
            // sync engine. A valid V2 value above always takes precedence. Keep
            // the retired value untouched for upgrade diagnostics and compatibility.
            defaults.set(true, forKey: Self.cloudSyncPreferenceMigratedV2Key)
        }
        
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
        let storedAutoStartConfiguration = defaults.data(forKey: Self.autoStartConfigurationKey)
            .flatMap { try? JSONDecoder().decode(AutoStartConfiguration.self, from: $0) }
        self.autoStartConfiguration = storedAutoStartConfiguration ?? .default
        self.autoStartDailyPlan = defaults.data(forKey: Self.autoStartDailyPlanKey)
            .flatMap { try? JSONDecoder().decode(AutoStartDailyPlan.self, from: $0) }
        self.autoStartWasEverEnabled = defaults.bool(forKey: Self.autoStartWasEverEnabledKey)
            || (storedAutoStartConfiguration?.isEnabled ?? false)
        
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
        self.defaultProjectColorHex = defaults.string(forKey: "defaultProjectColor") ?? "#E39A3F"
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
        let pastMarkerDefaults = PastMonthMarkerOptions.default
        self.pastMonthShowUnfinishedFace = defaults.object(forKey: "pastMonthShowUnfinishedFace") as? Bool ?? pastMarkerDefaults.showsUnfinishedFace
        self.pastMonthShowNotStartedFace = defaults.object(forKey: "pastMonthShowNotStartedFace") as? Bool ?? pastMarkerDefaults.showsNotStartedFace
        self.pastMonthShowCompletedCount = defaults.object(forKey: "pastMonthShowCompletedCount") as? Bool ?? pastMarkerDefaults.showsCompletedCount
        self.pastMonthShowRecordDot = defaults.object(forKey: "pastMonthShowRecordDot") as? Bool ?? pastMarkerDefaults.showsRecordDot
        self.pastMonthShowExpiredFlame = defaults.object(forKey: "pastMonthShowExpiredFlame") as? Bool ?? pastMarkerDefaults.showsExpiredFlame
        self.pendingBrowseModeRaw = restoresBrowseModes
            ? defaults.string(forKey: Self.pendingBrowseModeKey) ?? WeekBrowseMode.weekList.rawValue
            : WeekBrowseMode.weekList.rawValue
        self.pastBrowseModeRaw = restoresBrowseModes
            ? defaults.string(forKey: Self.pastBrowseModeKey) ?? WeekBrowseMode.weekList.rawValue
            : WeekBrowseMode.weekList.rawValue
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
    
    func setCloudSyncRequested(_ requested: Bool) {
        cloudSyncRequested = requested
    }

    @discardableResult
    func ensureAutoStartPlan(dayId: String) -> AutoStartDailyPlan {
        if let plan = autoStartDailyPlan, plan.dayId == dayId {
            return plan
        }

        let plan = AutoStartDailyPlan(
            dayId: dayId,
            isEnabled: autoStartConfiguration.isEnabled,
            hour: autoStartConfiguration.hour,
            minute: autoStartConfiguration.minute,
            wasSkipped: false,
            activationDeferredUntilTomorrow: false
        )
        autoStartDailyPlan = plan
        save()
        return plan
    }

    func updateAutoStartConfiguration(
        isEnabled: Bool,
        hour: Int,
        minute: Int,
        today: Date,
        dayId: String,
        todayStatus: DayStatus?,
        now: Date
    ) {
        let boundedHour = min(max(hour, 0), 23)
        let boundedMinute = min(max(minute, 0), 59)
        let currentPlan = ensureAutoStartPlan(dayId: dayId)
        let wasEverEnabled = autoStartWasEverEnabled
        let isBeforeTodaysPlan = AutoStartSchedule.date(
            on: today,
            hour: currentPlan.hour,
            minute: currentPlan.minute
        ).map { now < $0 } ?? false

        autoStartConfiguration = AutoStartConfiguration(
            isEnabled: isEnabled,
            hour: boundedHour,
            minute: boundedMinute
        )
        if isEnabled {
            autoStartWasEverEnabled = true
        }

        if todayStatus == .execute || todayStatus == .completed || todayStatus == .expired {
            save()
            return
        }

        var updatedPlan = currentPlan
        if isBeforeTodaysPlan {
            updatedPlan.hour = boundedHour
            updatedPlan.minute = boundedMinute
        }

        if !isEnabled {
            // Turning the switch off takes effect immediately for today's plan.
            updatedPlan.isEnabled = false
        } else if !updatedPlan.wasSkipped {
            if !isBeforeTodaysPlan && !wasEverEnabled {
                // Persist the first late opt-in for the rest of this day so a
                // later time edit or switch cycle cannot silently activate it.
                updatedPlan.activationDeferredUntilTomorrow = true
                updatedPlan.isEnabled = false
            } else if !updatedPlan.activationDeferredUntilTomorrow {
                updatedPlan.isEnabled = true
            } else {
                updatedPlan.isEnabled = false
            }
        } else {
            // A same-day skip is sticky, including across repeated switch changes.
            updatedPlan.isEnabled = false
        }

        autoStartDailyPlan = updatedPlan
        save()
    }

    func markAutoStartSkipped(dayId: String) {
        guard var plan = autoStartDailyPlan,
              plan.dayId == dayId,
              !plan.wasSkipped else { return }
        plan.wasSkipped = true
        plan.isEnabled = false
        autoStartDailyPlan = plan
        save()
    }

    func restoreAutoStartConfiguration(isEnabled: Bool, hour: Int, minute: Int) {
        autoStartConfiguration = AutoStartConfiguration(
            isEnabled: isEnabled,
            hour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59)
        )
        autoStartWasEverEnabled = isEnabled
        autoStartDailyPlan = nil
        save()
    }

    func save() {
        defaults.set(defaultKillTimeHour, forKey: "defaultKillTimeHour")
        defaults.set(defaultKillTimeMinute, forKey: "defaultKillTimeMinute")
        defaults.set(cloudSyncRequested, forKey: Self.cloudSyncRequestedKey)
        defaults.set(defaultTaskType.rawValue, forKey: "defaultTaskType")
        defaults.set(defaultTaskTypeIdRaw, forKey: "defaultTaskTypeId")
        defaults.set(defaultExecutionModeRaw, forKey: "defaultExecutionMode")
        if let data = try? JSONEncoder().encode(autoStartConfiguration) {
            defaults.set(data, forKey: Self.autoStartConfigurationKey)
        }
        if let autoStartDailyPlan,
           let data = try? JSONEncoder().encode(autoStartDailyPlan) {
            defaults.set(data, forKey: Self.autoStartDailyPlanKey)
        } else {
            defaults.removeObject(forKey: Self.autoStartDailyPlanKey)
        }
        defaults.set(autoStartWasEverEnabled, forKey: Self.autoStartWasEverEnabledKey)
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
        defaults.set(pastMonthShowUnfinishedFace, forKey: "pastMonthShowUnfinishedFace")
        defaults.set(pastMonthShowNotStartedFace, forKey: "pastMonthShowNotStartedFace")
        defaults.set(pastMonthShowCompletedCount, forKey: "pastMonthShowCompletedCount")
        defaults.set(pastMonthShowRecordDot, forKey: "pastMonthShowRecordDot")
        defaults.set(pastMonthShowExpiredFlame, forKey: "pastMonthShowExpiredFlame")
        if restoresBrowseModes {
            defaults.set(pendingBrowseModeRaw, forKey: Self.pendingBrowseModeKey)
            defaults.set(pastBrowseModeRaw, forKey: Self.pastBrowseModeKey)
        }
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

    /// Unknown stored values fall back to the week list.
    var pendingBrowseMode: WeekBrowseMode {
        get { WeekBrowseMode(rawValue: pendingBrowseModeRaw) ?? .weekList }
        set { pendingBrowseModeRaw = newValue.rawValue }
    }

    var pastBrowseMode: WeekBrowseMode {
        get { WeekBrowseMode(rawValue: pastBrowseModeRaw) ?? .weekList }
        set { pastBrowseModeRaw = newValue.rawValue }
    }

    var pastMonthMarkerOptions: PastMonthMarkerOptions {
        get {
            PastMonthMarkerOptions(
                showsUnfinishedFace: pastMonthShowUnfinishedFace,
                showsNotStartedFace: pastMonthShowNotStartedFace,
                showsCompletedCount: pastMonthShowCompletedCount,
                showsRecordDot: pastMonthShowRecordDot,
                showsExpiredFlame: pastMonthShowExpiredFlame
            )
        }
        set {
            pastMonthShowUnfinishedFace = newValue.showsUnfinishedFace
            pastMonthShowNotStartedFace = newValue.showsNotStartedFace
            pastMonthShowCompletedCount = newValue.showsCompletedCount
            pastMonthShowRecordDot = newValue.showsRecordDot
            pastMonthShowExpiredFlame = newValue.showsExpiredFlame
        }
    }

    var defaultExecutionMode: ExecutionMode {
        get { ExecutionMode(rawValue: defaultExecutionModeRaw) ?? .strict }
        set { defaultExecutionModeRaw = newValue.rawValue }
    }

    /// VIP access for feature decisions (flexible mode, selecting VIP themes).
    /// Requires a StoreKit resolution in this launch, not just the persisted mirror.
    var hasVIPAccess: Bool { premiumThemeUnlocked && vipAccessResolved }

    /// The mode a newly started day actually uses. Flexible mode is VIP: without
    /// access the day starts strict, while the stored preference is kept so it
    /// returns as soon as VIP is active again. A day already running is never changed.
    var effectiveDefaultExecutionMode: ExecutionMode {
        defaultExecutionMode == .flexible && !hasVIPAccess ? .strict : defaultExecutionMode
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
