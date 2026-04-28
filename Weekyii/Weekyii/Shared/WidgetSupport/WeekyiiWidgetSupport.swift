import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

enum LiveActivityAction: String, Codable, CaseIterable, Identifiable {
    case doneFocus = "done-focus"
    case postponeFocus = "postpone-focus"
    case openToday = "open-today"

    static let scheme = "weekyii"
    static let host = "live"

    var id: String { rawValue }

    func url(days: Int = 1) -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = "/\(rawValue)"
        if self == .postponeFocus {
            components.queryItems = [URLQueryItem(name: "days", value: "\(max(1, days))")]
        }
        return components.url ?? URL(string: "weekyii://live/open-today")!
    }

    static func parse(url: URL) -> (action: LiveActivityAction, days: Int)? {
        guard url.scheme == Self.scheme, url.host == Self.host else { return nil }
        let actionRaw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let action = LiveActivityAction(rawValue: actionRaw) else { return nil }
        let daysValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "days" })?
            .value
            .flatMap(Int.init) ?? 1
        return (action, max(1, daysValue))
    }
}

#if canImport(ActivityKit)
struct TodayActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var dayId: String
        var focusTitle: String
        var taskTypeRaw: String
        var killTime: Date
        var remainingSeconds: Int
        var completionPercent: Int
        var completedCount: Int
        var totalCount: Int
        var frozenCount: Int
        var liveTheme: LiveActivityThemeSnapshot
    }

    var dayId: String
}
#endif

// Shared bridge used by app and widget extension.
enum WeekyiiWidgetBridge {
    static let appGroupIdentifier = "group.com.fluentdesign.Weekyii.shared"
    static let snapshotFileName = "weekyii-widget-snapshot.json"
    static let selectedThemeKey = "selectedTheme"
    static let appearanceModeKey = "appearanceMode"
    static let premiumThemeUnlockedKey = "premiumThemeUnlocked"

    static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func containerDirectory(fileManager: FileManager = .default) -> URL {
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return url
        }

        let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return fallback.appendingPathComponent("WeekyiiWidget", isDirectory: true)
    }
}

struct WidgetThemeSnapshot: Codable, Equatable, Hashable {
    var primaryHex: String
    var primaryLightHex: String
    var accentHex: String
    var backgroundHex: String
    var textPrimaryHex: String
    var textSecondaryHex: String
    var darkPrimaryHex: String
    var darkPrimaryLightHex: String
    var darkAccentHex: String
    var darkBackgroundHex: String
    var darkTextPrimaryHex: String
    var darkTextSecondaryHex: String
    var appearanceModeRaw: String

    init(
        primaryHex: String,
        primaryLightHex: String,
        accentHex: String,
        backgroundHex: String,
        textPrimaryHex: String,
        textSecondaryHex: String,
        darkPrimaryHex: String? = nil,
        darkPrimaryLightHex: String? = nil,
        darkAccentHex: String? = nil,
        darkBackgroundHex: String? = nil,
        darkTextPrimaryHex: String? = nil,
        darkTextSecondaryHex: String? = nil,
        appearanceModeRaw: String = AppearanceMode.system.rawValue
    ) {
        self.primaryHex = primaryHex
        self.primaryLightHex = primaryLightHex
        self.accentHex = accentHex
        self.backgroundHex = backgroundHex
        self.textPrimaryHex = textPrimaryHex
        self.textSecondaryHex = textSecondaryHex
        self.darkPrimaryHex = darkPrimaryHex ?? primaryHex
        self.darkPrimaryLightHex = darkPrimaryLightHex ?? primaryLightHex
        self.darkAccentHex = darkAccentHex ?? accentHex
        self.darkBackgroundHex = darkBackgroundHex ?? backgroundHex
        self.darkTextPrimaryHex = darkTextPrimaryHex ?? textPrimaryHex
        self.darkTextSecondaryHex = darkTextSecondaryHex ?? textSecondaryHex
        self.appearanceModeRaw = appearanceModeRaw
    }

    var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    func resolvedPalette(isDarkSystem: Bool) -> WidgetThemePalette {
        let useDark: Bool
        switch appearanceMode {
        case .system:
            useDark = isDarkSystem
        case .light:
            useDark = false
        case .dark:
            useDark = true
        }

        if useDark {
            return WidgetThemePalette(
                primaryHex: darkPrimaryHex,
                primaryLightHex: darkPrimaryLightHex,
                accentHex: darkAccentHex,
                backgroundHex: darkBackgroundHex,
                textPrimaryHex: darkTextPrimaryHex,
                textSecondaryHex: darkTextSecondaryHex
            )
        }

        return WidgetThemePalette(
            primaryHex: primaryHex,
            primaryLightHex: primaryLightHex,
            accentHex: accentHex,
            backgroundHex: backgroundHex,
            textPrimaryHex: textPrimaryHex,
            textSecondaryHex: textSecondaryHex
        )
    }

    private enum CodingKeys: String, CodingKey {
        case primaryHex
        case primaryLightHex
        case accentHex
        case backgroundHex
        case textPrimaryHex
        case textSecondaryHex
        case darkPrimaryHex
        case darkPrimaryLightHex
        case darkAccentHex
        case darkBackgroundHex
        case darkTextPrimaryHex
        case darkTextSecondaryHex
        case appearanceModeRaw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        primaryHex = try container.decode(String.self, forKey: .primaryHex)
        primaryLightHex = try container.decode(String.self, forKey: .primaryLightHex)
        accentHex = try container.decode(String.self, forKey: .accentHex)
        backgroundHex = try container.decode(String.self, forKey: .backgroundHex)
        textPrimaryHex = try container.decode(String.self, forKey: .textPrimaryHex)
        textSecondaryHex = try container.decode(String.self, forKey: .textSecondaryHex)

        darkPrimaryHex = try container.decodeIfPresent(String.self, forKey: .darkPrimaryHex) ?? primaryHex
        darkPrimaryLightHex = try container.decodeIfPresent(String.self, forKey: .darkPrimaryLightHex) ?? primaryLightHex
        darkAccentHex = try container.decodeIfPresent(String.self, forKey: .darkAccentHex) ?? accentHex
        darkBackgroundHex = try container.decodeIfPresent(String.self, forKey: .darkBackgroundHex) ?? backgroundHex
        darkTextPrimaryHex = try container.decodeIfPresent(String.self, forKey: .darkTextPrimaryHex) ?? textPrimaryHex
        darkTextSecondaryHex = try container.decodeIfPresent(String.self, forKey: .darkTextSecondaryHex) ?? textSecondaryHex
        appearanceModeRaw = try container.decodeIfPresent(String.self, forKey: .appearanceModeRaw) ?? AppearanceMode.system.rawValue
    }
}

struct WidgetThemePalette: Equatable, Hashable {
    var primaryHex: String
    var primaryLightHex: String
    var accentHex: String
    var backgroundHex: String
    var textPrimaryHex: String
    var textSecondaryHex: String
}

// Live Activities do not share widget semantics directly.
// The island always renders against a system-managed dark capsule, while the
// lock screen card resolves independently for light/dark appearance.
struct LiveActivityLockPalette: Equatable, Hashable {
    var backgroundHex: String
    var surfaceHex: String
    var textPrimaryHex: String
    var textSecondaryHex: String
    var accentHex: String
    var progressTrackHex: String
}

struct LiveActivityThemeSnapshot: Codable, Equatable, Hashable {
    var islandTextPrimaryHex: String
    var islandTextSecondaryHex: String
    var islandAccentHex: String
    var islandWarningHex: String
    var islandSuccessHex: String
    var islandChipPrimaryHex: String
    var islandChipSecondaryHex: String
    var islandKeylineHex: String
    var lockBackgroundHex: String
    var lockSurfaceHex: String
    var lockTextPrimaryHex: String
    var lockTextSecondaryHex: String
    var lockAccentHex: String
    var lockProgressTrackHex: String
    var darkLockBackgroundHex: String
    var darkLockSurfaceHex: String
    var darkLockTextPrimaryHex: String
    var darkLockTextSecondaryHex: String
    var darkLockAccentHex: String
    var darkLockProgressTrackHex: String
    var appearanceModeRaw: String

    init(
        islandTextPrimaryHex: String,
        islandTextSecondaryHex: String,
        islandAccentHex: String,
        islandWarningHex: String,
        islandSuccessHex: String,
        islandChipPrimaryHex: String,
        islandChipSecondaryHex: String,
        islandKeylineHex: String,
        lockBackgroundHex: String,
        lockSurfaceHex: String,
        lockTextPrimaryHex: String,
        lockTextSecondaryHex: String,
        lockAccentHex: String,
        lockProgressTrackHex: String,
        darkLockBackgroundHex: String? = nil,
        darkLockSurfaceHex: String? = nil,
        darkLockTextPrimaryHex: String? = nil,
        darkLockTextSecondaryHex: String? = nil,
        darkLockAccentHex: String? = nil,
        darkLockProgressTrackHex: String? = nil,
        appearanceModeRaw: String = AppearanceMode.system.rawValue
    ) {
        self.islandTextPrimaryHex = islandTextPrimaryHex
        self.islandTextSecondaryHex = islandTextSecondaryHex
        self.islandAccentHex = islandAccentHex
        self.islandWarningHex = islandWarningHex
        self.islandSuccessHex = islandSuccessHex
        self.islandChipPrimaryHex = islandChipPrimaryHex
        self.islandChipSecondaryHex = islandChipSecondaryHex
        self.islandKeylineHex = islandKeylineHex
        self.lockBackgroundHex = lockBackgroundHex
        self.lockSurfaceHex = lockSurfaceHex
        self.lockTextPrimaryHex = lockTextPrimaryHex
        self.lockTextSecondaryHex = lockTextSecondaryHex
        self.lockAccentHex = lockAccentHex
        self.lockProgressTrackHex = lockProgressTrackHex
        self.darkLockBackgroundHex = darkLockBackgroundHex ?? lockBackgroundHex
        self.darkLockSurfaceHex = darkLockSurfaceHex ?? lockSurfaceHex
        self.darkLockTextPrimaryHex = darkLockTextPrimaryHex ?? lockTextPrimaryHex
        self.darkLockTextSecondaryHex = darkLockTextSecondaryHex ?? lockTextSecondaryHex
        self.darkLockAccentHex = darkLockAccentHex ?? lockAccentHex
        self.darkLockProgressTrackHex = darkLockProgressTrackHex ?? lockProgressTrackHex
        self.appearanceModeRaw = appearanceModeRaw
    }

    var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    func resolvedLockPalette(isDarkSystem: Bool) -> LiveActivityLockPalette {
        let useDark: Bool
        switch appearanceMode {
        case .system:
            useDark = isDarkSystem
        case .light:
            useDark = false
        case .dark:
            useDark = true
        }

        if useDark {
            return LiveActivityLockPalette(
                backgroundHex: darkLockBackgroundHex,
                surfaceHex: darkLockSurfaceHex,
                textPrimaryHex: darkLockTextPrimaryHex,
                textSecondaryHex: darkLockTextSecondaryHex,
                accentHex: darkLockAccentHex,
                progressTrackHex: darkLockProgressTrackHex
            )
        }

        return LiveActivityLockPalette(
            backgroundHex: lockBackgroundHex,
            surfaceHex: lockSurfaceHex,
            textPrimaryHex: lockTextPrimaryHex,
            textSecondaryHex: lockTextSecondaryHex,
            accentHex: lockAccentHex,
            progressTrackHex: lockProgressTrackHex
        )
    }

    private enum CodingKeys: String, CodingKey {
        case islandTextPrimaryHex
        case islandTextSecondaryHex
        case islandAccentHex
        case islandWarningHex
        case islandSuccessHex
        case islandChipPrimaryHex
        case islandChipSecondaryHex
        case islandKeylineHex
        case lockBackgroundHex
        case lockSurfaceHex
        case lockTextPrimaryHex
        case lockTextSecondaryHex
        case lockAccentHex
        case lockProgressTrackHex
        case darkLockBackgroundHex
        case darkLockSurfaceHex
        case darkLockTextPrimaryHex
        case darkLockTextSecondaryHex
        case darkLockAccentHex
        case darkLockProgressTrackHex
        case appearanceModeRaw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        islandTextPrimaryHex = try container.decode(String.self, forKey: .islandTextPrimaryHex)
        islandTextSecondaryHex = try container.decode(String.self, forKey: .islandTextSecondaryHex)
        islandAccentHex = try container.decode(String.self, forKey: .islandAccentHex)
        islandWarningHex = try container.decode(String.self, forKey: .islandWarningHex)
        islandSuccessHex = try container.decode(String.self, forKey: .islandSuccessHex)
        islandChipPrimaryHex = try container.decode(String.self, forKey: .islandChipPrimaryHex)
        islandChipSecondaryHex = try container.decode(String.self, forKey: .islandChipSecondaryHex)
        islandKeylineHex = try container.decode(String.self, forKey: .islandKeylineHex)
        lockBackgroundHex = try container.decode(String.self, forKey: .lockBackgroundHex)
        lockSurfaceHex = try container.decode(String.self, forKey: .lockSurfaceHex)
        lockTextPrimaryHex = try container.decode(String.self, forKey: .lockTextPrimaryHex)
        lockTextSecondaryHex = try container.decode(String.self, forKey: .lockTextSecondaryHex)
        lockAccentHex = try container.decode(String.self, forKey: .lockAccentHex)
        lockProgressTrackHex = try container.decode(String.self, forKey: .lockProgressTrackHex)
        darkLockBackgroundHex = try container.decodeIfPresent(String.self, forKey: .darkLockBackgroundHex) ?? lockBackgroundHex
        darkLockSurfaceHex = try container.decodeIfPresent(String.self, forKey: .darkLockSurfaceHex) ?? lockSurfaceHex
        darkLockTextPrimaryHex = try container.decodeIfPresent(String.self, forKey: .darkLockTextPrimaryHex) ?? lockTextPrimaryHex
        darkLockTextSecondaryHex = try container.decodeIfPresent(String.self, forKey: .darkLockTextSecondaryHex) ?? lockTextSecondaryHex
        darkLockAccentHex = try container.decodeIfPresent(String.self, forKey: .darkLockAccentHex) ?? lockAccentHex
        darkLockProgressTrackHex = try container.decodeIfPresent(String.self, forKey: .darkLockProgressTrackHex) ?? lockProgressTrackHex
        appearanceModeRaw = try container.decodeIfPresent(String.self, forKey: .appearanceModeRaw) ?? AppearanceMode.system.rawValue
    }
}

struct WidgetTaskPreview: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var taskTypeRaw: String
    var zoneRaw: String
}

struct WidgetTodaySnapshot: Codable, Equatable {
    var dayId: String
    var weekdaySymbol: String
    var statusRaw: String
    var killTimeText: String
    var focusTitle: String?
    var totalCount: Int
    var completedCount: Int
    var draftCount: Int
    var frozenCount: Int
    var completionPercent: Int
    var previewTasks: [WidgetTaskPreview]
}

struct WidgetWeekDaySnapshot: Codable, Equatable, Identifiable {
    var dayId: String
    var weekdaySymbol: String
    var dayNumber: Int
    var statusRaw: String
    var totalCount: Int
    var completedCount: Int

    var id: String { dayId }
}

struct WidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var theme: WidgetThemeSnapshot
    var today: WidgetTodaySnapshot
    var weekDays: [WidgetWeekDaySnapshot]

    static let placeholder = WidgetSnapshot(
        generatedAt: Date(),
        theme: WidgetThemeSnapshot(
            primaryHex: "#C46A1A",
            primaryLightHex: "#E0A35B",
            accentHex: "#F08A3C",
            backgroundHex: "#FFFDF9",
            textPrimaryHex: "#2A1D16",
            textSecondaryHex: "#6B5A4F"
        ),
        today: WidgetTodaySnapshot(
            dayId: Date().description,
            weekdaySymbol: "Today",
            statusRaw: "draft",
            killTimeText: "23:45",
            focusTitle: "Open Weekyii",
            totalCount: 0,
            completedCount: 0,
            draftCount: 0,
            frozenCount: 0,
            completionPercent: 0,
            previewTasks: []
        ),
        weekDays: []
    )
}

struct WidgetSnapshotStore {
    private let fileManager: FileManager
    let directoryURL: URL

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? WeekyiiWidgetBridge.containerDirectory(fileManager: fileManager)
    }

    private var fileURL: URL {
        directoryURL.appendingPathComponent(WeekyiiWidgetBridge.snapshotFileName)
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
