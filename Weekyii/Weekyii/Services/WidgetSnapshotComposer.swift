import Foundation
import SwiftData

#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetSnapshotComposer {
    static func makeSnapshot(
        now: Date,
        selectedTheme: WeekTheme,
        appearanceMode: AppearanceMode,
        today: DayModel?,
        presentWeek: WeekModel?,
        taskTypes: TaskTypeCatalog? = nil,
        languageCode: String? = Bundle.main.preferredLocalizations.first
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            theme: selectedTheme.widgetThemeSnapshot(appearanceMode: appearanceMode),
            today: makeTodaySnapshot(now: now, today: today, taskTypes: taskTypes, languageCode: languageCode),
            weekDays: makeWeekDays(now: now, week: presentWeek)
        )
    }

    static func syncFromModelContext(
        modelContext: ModelContext,
        now: Date,
        todayDate: Date,
        selectedThemeRaw: String,
        appearanceModeRaw: String,
        premiumThemeUnlocked: Bool
    ) {
        let theme = WeekTheme.resolvedTheme(rawValue: selectedThemeRaw, premiumThemeUnlocked: premiumThemeUnlocked)
        let appearanceMode = AppearanceMode(rawValue: appearanceModeRaw) ?? .system

        let today = fetchDay(modelContext: modelContext, dayID: todayDate.dayId)
        let presentWeek = fetchPresentWeek(modelContext: modelContext, fallbackDate: todayDate)
        let snapshot = makeSnapshot(
            now: now,
            selectedTheme: theme,
            appearanceMode: appearanceMode,
            today: today,
            presentWeek: presentWeek,
            taskTypes: try? TaskTypeCatalog.load(in: modelContext)
        )

        let store = WidgetSnapshotStore()
        try? store.save(snapshot)

        let sharedDefaults = WeekyiiWidgetBridge.sharedDefaults()
        sharedDefaults.set(selectedThemeRaw, forKey: WeekyiiWidgetBridge.selectedThemeKey)
        sharedDefaults.set(appearanceMode.rawValue, forKey: WeekyiiWidgetBridge.appearanceModeKey)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private static func fetchDay(modelContext: ModelContext, dayID: String) -> DayModel? {
        let descriptor = FetchDescriptor<DayModel>()
        let days = (try? modelContext.fetch(descriptor)) ?? []
        return days.first(where: { $0.dayId == dayID })
    }

    private static func fetchPresentWeek(modelContext: ModelContext, fallbackDate: Date) -> WeekModel? {
        let descriptor = FetchDescriptor<WeekModel>()
        let weeks = (try? modelContext.fetch(descriptor)) ?? []
        if let target = weeks.first(where: { $0.weekId == fallbackDate.weekId }) {
            return target
        }
        return weeks.first(where: { $0.status == .present })
    }

    /// How many upcoming tasks the widgets can show at most (large shows 3, plus one spare).
    static let upcomingLimit = 4

    private static func makeTodaySnapshot(
        now: Date,
        today: DayModel?,
        taskTypes: TaskTypeCatalog?,
        languageCode: String?
    ) -> WidgetTodaySnapshot {
        guard let today else {
            return WidgetTodaySnapshot(
                dayId: now.dayId,
                weekdaySymbol: weekdaySymbol(for: now),
                statusRaw: DayStatus.empty.rawValue,
                killTimeText: "--:--",
                focusTitle: nil,
                totalCount: 0,
                completedCount: 0,
                draftCount: 0,
                frozenCount: 0,
                completionPercent: 0,
                previewTasks: [],
                dayEndsAt: nextDayStart(after: now),
                upcomingTasks: [],
                languageCode: languageCode
            )
        }

        let draft = today.sortedDraftTasks
        let focus = today.focusTask.map { [$0] } ?? []
        let frozen = today.frozenTasks
        let complete = today.completedTasks
        let allTasks = focus + frozen + draft + complete

        let total = allTasks.count
        let completed = complete.count
        let completionPercent = total == 0 ? 0 : Int(((Double(completed) / Double(total)) * 100).rounded())

        let previews = allTasks.prefix(3).map { preview(for: $0, taskTypes: taskTypes) }
        let upcoming = (frozen + draft).prefix(upcomingLimit).map { preview(for: $0, taskTypes: taskTypes) }
        let focusType = today.focusTask.flatMap { typeDefinition(for: $0, taskTypes: taskTypes) }

        return WidgetTodaySnapshot(
            dayId: today.dayId,
            weekdaySymbol: weekdaySymbol(for: today.date),
            statusRaw: today.status.rawValue,
            killTimeText: String(format: "%02d:%02d", today.killTimeHour, today.killTimeMinute),
            focusTitle: today.focusTask?.title,
            totalCount: total,
            completedCount: completed,
            draftCount: draft.count,
            frozenCount: frozen.count,
            completionPercent: min(max(completionPercent, 0), 100),
            previewTasks: previews,
            // Same deadline the state machine uses to expire the day.
            killTime: KillTimeDeadline.date(for: today.date, hour: today.killTimeHour, minute: today.killTimeMinute),
            dayEndsAt: nextDayStart(after: today.date),
            focusTypeName: focusType?.name,
            focusTypeColorHex: focusType?.colorHex,
            upcomingTasks: upcoming,
            languageCode: languageCode
        )
    }

    private static func preview(for task: TaskItem, taskTypes: TaskTypeCatalog?) -> WidgetTaskPreview {
        WidgetTaskPreview(
            id: task.id,
            title: task.title,
            taskTypeRaw: task.taskType.rawValue,
            zoneRaw: task.zone.rawValue,
            typeColorHex: typeDefinition(for: task, taskTypes: taskTypes)?.colorHex
        )
    }

    private static func typeDefinition(for task: TaskItem, taskTypes: TaskTypeCatalog?) -> TaskTypeDefinition? {
        guard let taskTypes else { return nil }
        return taskTypes.definition(for: task.taskTypeIdRaw.isEmpty ? task.taskType.rawValue : task.taskTypeIdRaw)
    }

    /// Start of the app day after `date`, in the app's anchored time zone (the same one `dayId` uses).
    private static func nextDayStart(after date: Date) -> Date? {
        WeekyiiTimeZone.calendar.date(byAdding: .day, value: 1, to: date.startOfDay)
    }

    private static func makeWeekDays(now: Date, week: WeekModel?) -> [WidgetWeekDaySnapshot] {
        let calendar = Calendar(identifier: .iso8601)
        let start = week?.startDate ?? now.startOfWeek
        let dayMap: [String: DayModel] = (week?.days ?? []).reduce(into: [:]) { partialResult, day in
            partialResult[day.dayId] = day
        }

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = date.dayId
            let day = dayMap[key]
            let total = day?.tasks.count ?? 0
            let completed = day?.completedTasks.count ?? 0
            return WidgetWeekDaySnapshot(
                dayId: key,
                weekdaySymbol: weekdaySymbol(for: date),
                dayNumber: calendar.component(.day, from: date),
                statusRaw: day?.status.rawValue ?? DayStatus.empty.rawValue,
                totalCount: total,
                completedCount: completed
            )
        }
    }

    private static func weekdaySymbol(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}
