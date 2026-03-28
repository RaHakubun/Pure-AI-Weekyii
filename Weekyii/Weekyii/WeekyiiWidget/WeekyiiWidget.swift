import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

private enum WeekyiiWidgetKind {
    static let main = "WeekyiiWidget"
}

struct WeekyiiWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WeekyiiWidgetProvider: TimelineProvider {
    private let store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> WeekyiiWidgetEntry {
        WeekyiiWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekyiiWidgetEntry) -> Void) {
        let snapshot = store.load() ?? .placeholder
        completion(WeekyiiWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekyiiWidgetEntry>) -> Void) {
        let snapshot = store.load() ?? .placeholder
        let entry = WeekyiiWidgetEntry(date: Date(), snapshot: snapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct WeekyiiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WeekyiiWidgetKind.main, provider: WeekyiiWidgetProvider()) { entry in
            WeekyiiWidgetRoot(entry: entry)
        }
        .configurationDisplayName("Weekyii")
        .description("快速查看今日任务进度与本周概览。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct WeekyiiLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TodayActivityAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
                .widgetURL(LiveActivityAction.openToday.url())
                .modifier(LiveActivityLockStylingModifier(theme: context.state.liveTheme))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedIslandLeadingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedIslandTrailingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedIslandCenterView(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedIslandActionsView(state: context.state)
                }
            } compactLeading: {
                CompactLeadingIslandView(state: context.state)
            } compactTrailing: {
                CompactTrailingIslandView(state: context.state)
            } minimal: {
                MinimalIslandView(state: context.state)
            }
            .widgetURL(LiveActivityAction.openToday.url())
            .keylineTint(Color(widgetHex: context.state.liveTheme.islandKeylineHex))
        }
    }
}

@available(iOS 16.1, *)
private struct ExpandedIslandLeadingView: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(widgetHex: state.liveTheme.islandChipSecondaryHex).opacity(0.35))
                Image(systemName: liveActivityTaskTypeIcon(raw: state.taskTypeRaw))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextPrimaryHex))
            }
            .frame(width: 30, height: 30)

            Text("当前专注")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextSecondaryHex))
        }
    }
}

@available(iOS 16.1, *)
private struct ExpandedIslandTrailingView: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("剩余")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextSecondaryHex))

            Text(state.killTime, style: .timer)
                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandAccentHex))
        }
    }
}

@available(iOS 16.1, *)
private struct ExpandedIslandCenterView: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.focusTitle)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextPrimaryHex))

            HStack(spacing: 8) {
                islandMetric(title: "完成", value: "\(state.completedCount)/\(state.totalCount)")
                islandMetric(title: "剩余", value: "\(state.frozenCount)")
                islandMetric(title: "进度", value: "\(state.completionPercent)%")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func islandMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextSecondaryHex))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextPrimaryHex))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

@available(iOS 16.1, *)
private struct ExpandedIslandActionsView: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Link(destination: LiveActivityAction.doneFocus.url()) {
                islandActionButton(
                    "完成专注",
                    icon: "checkmark.circle.fill",
                    fillHex: state.liveTheme.islandSuccessHex,
                    foregroundHex: state.liveTheme.islandTextPrimaryHex
                )
            }

            Link(destination: LiveActivityAction.postponeFocus.url(days: 1)) {
                islandActionButton(
                    "后移 +1 天",
                    icon: "calendar.badge.clock",
                    fillHex: state.liveTheme.islandChipSecondaryHex,
                    foregroundHex: state.liveTheme.islandTextPrimaryHex
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func islandActionButton(_ title: String, icon: String, fillHex: String, foregroundHex: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(Color(widgetHex: foregroundHex))
        .background(Color(widgetHex: fillHex), in: Capsule())
    }
}

@available(iOS 16.1, *)
private struct CompactLeadingIslandView: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: liveActivityTaskTypeIcon(raw: state.taskTypeRaw))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandAccentHex))
            Circle()
                .fill(Color(widgetHex: state.liveTheme.islandSuccessHex))
                .frame(width: 5, height: 5)
        }
    }
}

@available(iOS 16.1, *)
private struct CompactTrailingIslandView: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        Text(state.killTime, style: .timer)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(Color(widgetHex: state.liveTheme.islandAccentHex))
    }
}

@available(iOS 16.1, *)
private struct MinimalIslandView: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(state.completionPercent) / 100)
                .stroke(
                    Color(widgetHex: state.liveTheme.islandAccentHex),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: liveActivityTaskTypeIcon(raw: state.taskTypeRaw))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextPrimaryHex))
        }
        .padding(3)
    }
}

@available(iOS 16.1, *)
private struct LockScreenLiveActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: TodayActivityAttributes.ContentState

    private var palette: LiveActivityLockPalette {
        state.liveTheme.resolvedLockPalette(isDarkSystem: colorScheme == .dark)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(widgetHex: palette.surfaceHex))
                        Image(systemName: liveActivityTaskTypeIcon(raw: state.taskTypeRaw))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(widgetHex: palette.accentHex))
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前专注")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(widgetHex: palette.textSecondaryHex))
                        Text(deadlineLabel(for: state.killTime))
                            .font(.caption2)
                            .foregroundStyle(Color(widgetHex: palette.textSecondaryHex))
                    }
                }

                Spacer()

                Text(state.killTime, style: .timer)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color(widgetHex: palette.accentHex))
            }

            Text(state.focusTitle)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(Color(widgetHex: palette.textPrimaryHex))

            HStack(spacing: 10) {
                lockMetricCard(title: "完成", value: "\(state.completedCount)/\(state.totalCount)")
                lockMetricCard(title: "剩余", value: "\(state.frozenCount)")
                lockMetricCard(title: "进度", value: "\(state.completionPercent)%")
            }

            HStack(spacing: 10) {
                Link(destination: LiveActivityAction.doneFocus.url()) {
                    lockActionButton(
                        "完成专注",
                        icon: "checkmark.circle.fill",
                        fill: Color(widgetHex: palette.accentHex),
                        foreground: Color(widgetHex: palette.backgroundHex)
                    )
                }

                Link(destination: LiveActivityAction.postponeFocus.url(days: 1)) {
                    lockActionButton(
                        "后移 +1 天",
                        icon: "calendar.badge.clock",
                        fill: Color(widgetHex: palette.surfaceHex),
                        foreground: Color(widgetHex: palette.textPrimaryHex)
                    )
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func lockMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color(widgetHex: palette.textSecondaryHex))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(widgetHex: palette.textPrimaryHex))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(widgetHex: palette.surfaceHex), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func lockActionButton(_ title: String, icon: String, fill: Color, foreground: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(foreground)
        .background(fill, in: Capsule())
    }
}

@available(iOS 16.1, *)
private struct LiveActivityLockStylingModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let theme: LiveActivityThemeSnapshot

    func body(content: Content) -> some View {
        let palette = theme.resolvedLockPalette(isDarkSystem: colorScheme == .dark)
        content
            .activityBackgroundTint(Color(widgetHex: palette.backgroundHex))
            .activitySystemActionForegroundColor(Color(widgetHex: palette.textPrimaryHex))
    }
}
#else
struct WeekyiiLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekyiiLiveActivityFallback", provider: WeekyiiWidgetProvider()) { entry in
            WeekyiiWidgetRoot(entry: entry)
        }
        .supportedFamilies([.systemSmall])
    }
}
#endif

private func liveActivityTaskTypeIcon(raw: String) -> String {
    switch raw {
    case "ddl":
        return "exclamationmark.triangle.fill"
    case "leisure":
        return "sparkles"
    default:
        return "checkmark.circle.fill"
    }
}

private func deadlineLabel(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "截止 HH:mm"
    return formatter.string(from: date)
}

private struct WeekyiiWidgetRoot: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: WeekyiiWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        case .accessoryInline:
            inlineLockView
        case .accessoryRectangular:
            rectangularLockView
        case .accessoryCircular:
            circularLockView
        default:
            smallView
        }
    }

    private var colors: WidgetThemePalette {
        entry.snapshot.theme.resolvedPalette(isDarkSystem: colorScheme == .dark)
    }

    private var completionText: String {
        "\(entry.snapshot.today.completedCount)/\(entry.snapshot.today.totalCount)"
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.snapshot.today.weekdaySymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
                Spacer()
                Text(entry.snapshot.today.killTimeText)
                    .font(.caption2)
                    .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.snapshot.today.completionPercent)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(widgetHex: colors.primaryHex))
                Text("%")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
            }

            Text(entry.snapshot.today.focusTitle ?? "暂无焦点任务")
                .font(.caption)
                .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))
                .lineLimit(2)

            Spacer(minLength: 0)

            Text("完成 \(completionText)")
                .font(.caption2)
                .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
        }
        .padding(12)
        .containerBackground(Color(widgetHex: colors.backgroundHex), for: .widget)
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日")
                    .font(.headline)
                    .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))

                Text("\(entry.snapshot.today.completionPercent)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(widgetHex: colors.primaryHex))

                HStack(spacing: 8) {
                    chip(title: "完成", value: entry.snapshot.today.completedCount)
                    chip(title: "剩余", value: max(entry.snapshot.today.totalCount - entry.snapshot.today.completedCount, 0))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.snapshot.today.previewTasks.prefix(3)) { task in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(zoneColor(raw: task.zoneRaw))
                            .frame(width: 6, height: 6)
                        Text(task.title)
                            .font(.caption)
                            .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))
                            .lineLimit(1)
                    }
                }
                if entry.snapshot.today.previewTasks.isEmpty {
                    Text("今天没有待办")
                        .font(.caption)
                        .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .containerBackground(Color(widgetHex: colors.backgroundHex), for: .widget)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Weekyii")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(widgetHex: colors.primaryHex))
                Spacer()
                Text("Kill \(entry.snapshot.today.killTimeText)")
                    .font(.caption)
                    .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
            }

            HStack(alignment: .center, spacing: 10) {
                Text("\(entry.snapshot.today.completionPercent)%")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(widgetHex: colors.primaryHex))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.snapshot.today.focusTitle ?? "暂无焦点任务")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))
                    Text("完成 \(completionText)")
                        .font(.caption)
                        .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
                }
                Spacer(minLength: 0)
            }

            Divider()
                .overlay(Color(widgetHex: colors.primaryLightHex).opacity(0.35))

            Text("本周")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(entry.snapshot.weekDays.prefix(7)) { day in
                    VStack(spacing: 4) {
                        Text(day.weekdaySymbol.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
                        Text("\(day.dayNumber)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(zoneColor(raw: day.statusRaw).opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(14)
        .containerBackground(Color(widgetHex: colors.backgroundHex), for: .widget)
    }

    private var inlineLockView: some View {
        Text("今日 \(completionText)")
    }

    private var rectangularLockView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.snapshot.today.completionPercent)% · \(completionText)")
                .font(.caption.weight(.semibold))
            Text(entry.snapshot.today.focusTitle ?? "暂无焦点任务")
                .font(.caption2)
                .lineLimit(1)
        }
    }

    private var circularLockView: some View {
        ZStack {
            Circle()
                .stroke(Color(widgetHex: colors.primaryLightHex).opacity(0.35), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(entry.snapshot.today.completionPercent) / 100)
                .stroke(Color(widgetHex: colors.primaryHex), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(entry.snapshot.today.completionPercent)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .padding(3)
    }

    private func chip(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(widgetHex: colors.primaryLightHex).opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func zoneColor(raw: String) -> Color {
        switch raw {
        case "focus":
            return Color(widgetHex: colors.primaryHex)
        case "frozen":
            return Color(widgetHex: colors.accentHex)
        case "draft":
            return Color(widgetHex: colors.primaryLightHex)
        case "completed":
            return .green
        case "expired":
            return .red
        default:
            return Color(widgetHex: colors.primaryHex)
        }
    }
}

private extension Color {
    init(widgetHex: String) {
        let cleaned = widgetHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var intValue: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&intValue)

        let r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (r, g, b) = ((intValue >> 8) * 17, (intValue >> 4 & 0xF) * 17, (intValue & 0xF) * 17)
        case 6:
            (r, g, b) = (intValue >> 16, intValue >> 8 & 0xFF, intValue & 0xFF)
        default:
            (r, g, b) = (196, 106, 26)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

#if DEBUG && canImport(ActivityKit)
@available(iOS 17.0, *)
private let previewActivityAttributes = TodayActivityAttributes(dayId: "2026-03-16")

@available(iOS 17.0, *)
private let previewAmberLiveTheme = LiveActivityThemeSnapshot(
    islandTextPrimaryHex: "#F7EBDD",
    islandTextSecondaryHex: "#D2BDA9",
    islandAccentHex: "#E0A35B",
    islandWarningHex: "#F18B70",
    islandSuccessHex: "#6ECBC3",
    islandChipPrimaryHex: "#E0A35B",
    islandChipSecondaryHex: "#F4AE77",
    islandKeylineHex: "#E0A35B",
    lockBackgroundHex: "#FFFDF9",
    lockSurfaceHex: "#F6EDE3",
    lockTextPrimaryHex: "#2A1D16",
    lockTextSecondaryHex: "#6B5A4F",
    lockAccentHex: "#C46A1A",
    lockProgressTrackHex: "#E0A35B",
    darkLockBackgroundHex: "#221A14",
    darkLockSurfaceHex: "#2E241D",
    darkLockTextPrimaryHex: "#F7EBDD",
    darkLockTextSecondaryHex: "#D2BDA9",
    darkLockAccentHex: "#E0A35B",
    darkLockProgressTrackHex: "#F2C284",
    appearanceModeRaw: AppearanceMode.light.rawValue
)

@available(iOS 17.0, *)
private let previewLotrLiveTheme = LiveActivityThemeSnapshot(
    islandTextPrimaryHex: "#E6DECf",
    islandTextSecondaryHex: "#B8AB94",
    islandAccentHex: "#AF9160",
    islandWarningHex: "#D28F62",
    islandSuccessHex: "#8392AA",
    islandChipPrimaryHex: "#AF9160",
    islandChipSecondaryHex: "#BE8354",
    islandKeylineHex: "#AF9160",
    lockBackgroundHex: "#F5F2EB",
    lockSurfaceHex: "#DDD8CD",
    lockTextPrimaryHex: "#211D18",
    lockTextSecondaryHex: "#4E4439",
    lockAccentHex: "#7F683C",
    lockProgressTrackHex: "#B79863",
    darkLockBackgroundHex: "#101411",
    darkLockSurfaceHex: "#171C18",
    darkLockTextPrimaryHex: "#E6DECf",
    darkLockTextSecondaryHex: "#B8AB94",
    darkLockAccentHex: "#AF9160",
    darkLockProgressTrackHex: "#C6AA79",
    appearanceModeRaw: AppearanceMode.dark.rawValue
)

@available(iOS 17.0, *)
private let amberLiveActivityPreviewState = TodayActivityAttributes.ContentState(
    dayId: "2026-03-16",
    focusTitle: "整理提案与明日计划",
    taskTypeRaw: "regular",
    killTime: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 22, minute: 30)) ?? Date(),
    remainingSeconds: 3600,
    completionPercent: 40,
    completedCount: 2,
    totalCount: 5,
    frozenCount: 2,
    liveTheme: previewAmberLiveTheme
)

@available(iOS 17.0, *)
private let lotrLiveActivityPreviewState = TodayActivityAttributes.ContentState(
    dayId: "2026-03-16",
    focusTitle: "穿过黑夜前把今天的核心任务做完",
    taskTypeRaw: "ddl",
    killTime: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 23, minute: 45)) ?? Date(),
    remainingSeconds: 5400,
    completionPercent: 66,
    completedCount: 2,
    totalCount: 3,
    frozenCount: 0,
    liveTheme: previewLotrLiveTheme
)

@available(iOS 17.0, *)
#Preview("Live Activity Lock · Amber", as: .content, using: previewActivityAttributes) {
    WeekyiiLiveActivityWidget()
} contentStates: {
    amberLiveActivityPreviewState
}

@available(iOS 17.0, *)
#Preview("Live Activity Expanded · Amber", as: .dynamicIsland(.expanded), using: previewActivityAttributes) {
    WeekyiiLiveActivityWidget()
} contentStates: {
    amberLiveActivityPreviewState
}

@available(iOS 17.0, *)
#Preview("Live Activity Compact · Amber", as: .dynamicIsland(.compact), using: previewActivityAttributes) {
    WeekyiiLiveActivityWidget()
} contentStates: {
    amberLiveActivityPreviewState
}

@available(iOS 17.0, *)
#Preview("Live Activity Minimal · Lotr", as: .dynamicIsland(.minimal), using: previewActivityAttributes) {
    WeekyiiLiveActivityWidget()
} contentStates: {
    lotrLiveActivityPreviewState
}
#endif
