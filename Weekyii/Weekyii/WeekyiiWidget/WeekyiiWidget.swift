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
                    IslandExpandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedActions(state: context.state)
                }
            } compactLeading: {
                IslandCompactLeading(state: context.state)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state)
            } minimal: {
                IslandMinimal(state: context.state)
            }
            .widgetURL(LiveActivityAction.openToday.url())
            .keylineTint(Color(widgetHex: context.state.liveTheme.islandKeylineHex))
        }
    }
}

@available(iOS 16.1, *)
private struct LockScreenLiveActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: TodayActivityAttributes.ContentState

    private var palette: LiveActivityLockPalette {
        state.liveTheme.resolvedLockPalette(isDarkSystem: colorScheme == .dark)
    }

    private var progress: CGFloat {
        CGFloat(max(min(state.completionPercent, 100), 0)) / 100
    }

    private var remainingLabel: String {
        liveActivityCompactDurationText(seconds: state.remainingSeconds)
    }

    private var usesLightBackground: Bool {
        isHexColorLight(palette.backgroundHex)
    }

    private var primaryTextColor: Color {
        usesLightBackground ? Color(widgetHex: "#1F1712") : Color(widgetHex: palette.textPrimaryHex)
    }

    private var secondaryTextColor: Color {
        usesLightBackground ? Color(widgetHex: "#6E584A") : Color(widgetHex: palette.textSecondaryHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(widgetHex: palette.surfaceHex))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: liveActivityTaskTypeIcon(raw: state.taskTypeRaw))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(widgetHex: palette.accentHex))
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.focusTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(primaryTextColor)
                    Text(deadlineLabel(for: state.killTime))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("剩余")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                    Text(remainingLabel)
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .foregroundStyle(Color(widgetHex: palette.accentHex))
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            LiveLinearProgress(
                progress: progress,
                fill: Color(widgetHex: palette.accentHex),
                track: Color(widgetHex: palette.progressTrackHex).opacity(0.28)
            )
            .frame(height: 6)

            HStack(spacing: 6) {
                lockMetric("完成", value: "\(state.completedCount)/\(state.totalCount)")
                lockMetric("总数", value: "\(state.totalCount)")
                lockMetric("剩余", value: "\(state.frozenCount)")
            }

            HStack(spacing: 8) {
                Link(destination: LiveActivityAction.doneFocus.url()) {
                    LiveActionCapsule(
                        title: "完成专注",
                        icon: "checkmark.circle.fill",
                        fill: Color(widgetHex: palette.accentHex),
                        foreground: Color(widgetHex: palette.backgroundHex),
                        verticalPadding: 7
                    )
                }

                Link(destination: LiveActivityAction.postponeFocus.url(days: 1)) {
                    LiveActionCapsule(
                        title: "后移 +1 天",
                        icon: "calendar.badge.clock",
                        fill: Color(widgetHex: palette.surfaceHex),
                        foreground: primaryTextColor,
                        verticalPadding: 7
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func lockMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(primaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(widgetHex: palette.surfaceHex), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

@available(iOS 16.1, *)
private struct IslandExpandedLeading: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        Circle()
            .fill(Color(widgetHex: state.liveTheme.islandChipSecondaryHex).opacity(0.26))
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: liveActivityTaskTypeIcon(raw: state.taskTypeRaw))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextPrimaryHex))
            }
            .frame(width: 24, height: 24, alignment: .center)
            .accessibilityLabel(liveActivityTaskTypeLabel(raw: state.taskTypeRaw))
    }
}

@available(iOS 16.1, *)
private struct IslandExpandedTrailing: View {
    let state: TodayActivityAttributes.ContentState

    private var remainingLabel: String {
        liveActivityCompactDurationText(seconds: state.remainingSeconds)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("剩余")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextSecondaryHex))
            Text(remainingLabel)
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandAccentHex))
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

@available(iOS 16.1, *)
private struct IslandExpandedCenter: View {
    let state: TodayActivityAttributes.ContentState

    private var progress: CGFloat {
        CGFloat(max(min(state.completionPercent, 100), 0)) / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.focusTitle)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextPrimaryHex))
                .frame(maxWidth: .infinity, alignment: .leading)

            LiveLinearProgress(
                progress: progress,
                fill: Color(widgetHex: state.liveTheme.islandAccentHex),
                track: Color.white.opacity(0.16)
            )
            .frame(height: 7)

            HStack(spacing: 6) {
                islandMetric("完成", value: "\(state.completedCount)")
                islandMetric("总数", value: "\(state.totalCount)")
                islandMetric("剩余", value: "\(state.frozenCount)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func islandMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextSecondaryHex))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(widgetHex: state.liveTheme.islandTextPrimaryHex))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

@available(iOS 16.1, *)
private struct IslandExpandedActions: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Link(destination: LiveActivityAction.doneFocus.url()) {
                LiveActionCapsule(
                    title: "完成专注",
                    icon: "checkmark.circle.fill",
                    fill: Color(widgetHex: state.liveTheme.islandSuccessHex),
                    foreground: Color(widgetHex: state.liveTheme.islandTextPrimaryHex)
                )
            }

            Link(destination: LiveActivityAction.postponeFocus.url(days: 1)) {
                LiveActionCapsule(
                    title: "后移 +1 天",
                    icon: "calendar.badge.clock",
                    fill: Color(widgetHex: state.liveTheme.islandChipSecondaryHex),
                    foreground: Color(widgetHex: state.liveTheme.islandTextPrimaryHex)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(iOS 16.1, *)
private struct IslandCompactLeading: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        Image(systemName: liveActivityTaskTypeIcon(raw: state.taskTypeRaw))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color(widgetHex: state.liveTheme.islandAccentHex))
            .frame(width: 13, height: 13)
    }
}

@available(iOS 16.1, *)
private struct IslandCompactTrailing: View {
    let state: TodayActivityAttributes.ContentState

    private var iconColor: Color {
        if state.remainingSeconds <= 3600 {
            return Color(widgetHex: state.liveTheme.islandWarningHex)
        }
        return Color(widgetHex: state.liveTheme.islandAccentHex)
    }

    var body: some View {
        Image(systemName: "timer")
            .font(.system(size: 10, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(iconColor)
            .frame(width: 12, height: 12)
    }
}

@available(iOS 16.1, *)
private struct IslandMinimal: View {
    let state: TodayActivityAttributes.ContentState

    private var progress: CGFloat {
        CGFloat(max(min(state.completionPercent, 100), 0)) / 100
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
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

private struct WeekyiiWidgetRoot: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: WeekyiiWidgetEntry

    private var palette: WidgetThemePalette {
        entry.snapshot.theme.resolvedPalette(isDarkSystem: colorScheme == .dark)
    }

    private var tokens: WidgetVisualTokens {
        WidgetVisualTokens(palette: palette)
    }

    private var semantic: WidgetSemanticData {
        WidgetSemanticData(snapshot: entry.snapshot)
    }

    private var familyBackground: Color {
        switch family {
        case .accessoryInline, .accessoryRectangular, .accessoryCircular:
            return tokens.accessoryBackground
        default:
            return tokens.background
        }
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                systemSmallView
            case .systemMedium:
                systemMediumView
            case .systemLarge:
                systemLargeView
            case .accessoryInline:
                accessoryInlineView
            case .accessoryRectangular:
                accessoryRectangularView
            case .accessoryCircular:
                accessoryCircularView
            default:
                systemSmallView
            }
        }
        .weekyiiWidgetContainerBackground(familyBackground)
        .widgetURL(LiveActivityAction.openToday.url())
    }

    private var systemSmallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("当下")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tokens.textSecondary)
                Spacer()
                WidgetStatusPill(text: semantic.stateLabel, tokens: tokens)
            }

            HStack(alignment: .center, spacing: 10) {
                WidgetProgressRing(
                    progress: semantic.progress,
                    lineWidth: 7,
                    tint: tokens.primary,
                    track: tokens.ringTrack,
                    centerText: semantic.totalCount == 0 ? "--" : "\(semantic.progressPercent)",
                    centerTextColor: tokens.textPrimary
                )
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(semantic.keyline)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tokens.textPrimary)
                        .lineLimit(2)
                    Text("完成 \(semantic.completedCount)/\(semantic.totalCount)")
                        .font(.caption2)
                        .foregroundStyle(tokens.textSecondary)
                }
                Spacer(minLength: 0)
            }

            WidgetLinearProgress(progress: semantic.progress, fill: tokens.primary, track: tokens.ringTrack)
                .frame(height: 6)
        }
        .padding(12)
    }

    private var systemMediumView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("今天")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tokens.textPrimary)
                    Spacer(minLength: 0)
                    Text(semantic.killTimeText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tokens.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(semantic.progressPercent)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(tokens.primary)
                    Text("%")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tokens.textSecondary)
                }

                HStack(spacing: 8) {
                    WidgetMetricPill(title: "完成", value: semantic.completedCount, tokens: tokens)
                    WidgetMetricPill(title: "剩余", value: semantic.remainingCount, tokens: tokens)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(semantic.keyline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tokens.textPrimary)
                    .lineLimit(2)

                WidgetLinearProgress(progress: semantic.progress, fill: tokens.primary, track: tokens.ringTrack)
                    .frame(height: 6)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(semantic.previewRows.prefix(3)) { row in
                        WidgetTaskPreviewLine(row: row, color: zoneColor(raw: row.zoneRaw), textColor: tokens.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tokens.stroke, lineWidth: 1)
            }
        }
        .padding(14)
    }

    private var systemLargeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Weekyii · 当下")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tokens.primary)
                    Spacer()
                    Text("截止 \(semantic.killTimeText)")
                        .font(.caption)
                        .foregroundStyle(tokens.textSecondary)
                }

                Text(semantic.keyline)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tokens.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    WidgetMetricPill(title: "进度", valueText: "\(semantic.progressPercent)%", tokens: tokens)
                    WidgetMetricPill(title: "完成", value: semantic.completedCount, tokens: tokens)
                    WidgetMetricPill(title: "总数", value: semantic.totalCount, tokens: tokens)
                    WidgetMetricPill(title: "剩余", value: semantic.remainingCount, tokens: tokens)
                }

                WidgetLinearProgress(progress: semantic.progress, fill: tokens.primary, track: tokens.ringTrack)
                    .frame(height: 7)
            }
            .padding(12)
            .background(tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tokens.stroke, lineWidth: 1)
            }

            Text("本周条带")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tokens.textSecondary)
                .padding(.leading, 2)

            HStack(spacing: 6) {
                ForEach(semantic.weekDays.prefix(7)) { day in
                    WidgetWeekStripCell(day: day, tokens: tokens)
                }
            }
        }
        .padding(14)
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon(raw: semantic.statusRaw))
                .foregroundStyle(tokens.primary)
            Text("当下 \(semantic.completedCount)/\(semantic.totalCount) · \(semantic.stateLabel)")
                .foregroundStyle(tokens.textPrimary)
        }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(semantic.keyline)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(tokens.textPrimary)
                Spacer(minLength: 0)
                Text("\(semantic.progressPercent)%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tokens.primary)
            }

            WidgetLinearProgress(progress: semantic.progress, fill: tokens.primary, track: tokens.ringTrack)
                .frame(height: 5)

            HStack(spacing: 8) {
                Text("完成 \(semantic.completedCount)/\(semantic.totalCount)")
                Text("剩余 \(semantic.remainingCount)")
            }
            .font(.caption2)
            .foregroundStyle(tokens.textSecondary)
        }
    }

    private var accessoryCircularView: some View {
        WidgetProgressRing(
            progress: semantic.progress,
            lineWidth: 4,
            tint: tokens.primary,
            track: tokens.ringTrack,
            centerText: semantic.totalCount == 0 ? "--" : "\(semantic.progressPercent)",
            centerTextColor: tokens.textPrimary
        )
        .padding(2)
    }

    private func zoneColor(raw: String) -> Color {
        switch raw {
        case "focus":
            return tokens.primary
        case "frozen":
            return tokens.warning
        case "draft":
            return tokens.accent
        case "completed":
            return tokens.success
        case "expired":
            return tokens.danger
        default:
            return tokens.primary
        }
    }
}

private struct WidgetVisualTokens {
    let primary: Color
    let accent: Color
    let background: Color
    let accessoryBackground: Color
    let surface: Color
    let textPrimary: Color
    let textSecondary: Color
    let ringTrack: Color
    let stroke: Color
    let success: Color
    let warning: Color
    let danger: Color

    init(palette: WidgetThemePalette) {
        let primaryColor = Color(widgetHex: palette.primaryHex)
        let accentColor = Color(widgetHex: palette.accentHex)
        let baseBackground = Color(widgetHex: palette.backgroundHex)
        let textMain = Color(widgetHex: palette.textPrimaryHex)

        primary = primaryColor
        accent = accentColor
        background = baseBackground
        accessoryBackground = baseBackground.opacity(0.75)
        surface = Color(widgetHex: palette.primaryLightHex).opacity(0.14)
        textPrimary = textMain
        textSecondary = Color(widgetHex: palette.textSecondaryHex)
        ringTrack = Color(widgetHex: palette.primaryLightHex).opacity(0.3)
        stroke = textMain.opacity(0.08)
        success = Color.green
        warning = Color.orange
        danger = Color.red
    }
}

private struct WidgetWeekDaySemantic: Identifiable {
    let id: String
    let weekday: String
    let number: Int
    let progress: CGFloat
    let completed: Int
    let total: Int
    let statusRaw: String

    init(snapshot: WidgetWeekDaySnapshot) {
        id = snapshot.dayId
        weekday = snapshot.weekdaySymbol
        number = snapshot.dayNumber
        completed = snapshot.completedCount
        total = snapshot.totalCount
        statusRaw = snapshot.statusRaw
        if snapshot.totalCount == 0 {
            progress = 0
        } else {
            let raw = CGFloat(snapshot.completedCount) / CGFloat(snapshot.totalCount)
            progress = max(min(raw, 1), 0)
        }
    }
}

private struct WidgetSemanticData {
    let statusRaw: String
    let todayTitle: String
    let killTimeText: String
    let keyline: String
    let progressPercent: Int
    let progress: CGFloat
    let completedCount: Int
    let totalCount: Int
    let remainingCount: Int
    let stateLabel: String
    let previewRows: [WidgetTaskPreview]
    let weekDays: [WidgetWeekDaySemantic]

    init(snapshot: WidgetSnapshot) {
        let today = snapshot.today
        let boundedPercent = min(max(today.completionPercent, 0), 100)

        statusRaw = today.statusRaw
        todayTitle = today.weekdaySymbol
        killTimeText = today.killTimeText
        progressPercent = boundedPercent
        progress = CGFloat(boundedPercent) / 100
        completedCount = today.completedCount
        totalCount = today.totalCount
        remainingCount = max(today.totalCount - today.completedCount, 0)
        previewRows = today.previewTasks
        weekDays = snapshot.weekDays.map(WidgetWeekDaySemantic.init)

        if let focus = today.focusTitle, !focus.isEmpty {
            keyline = focus
        } else if let first = today.previewTasks.first {
            keyline = first.title
        } else {
            keyline = "今天没有待办"
        }

        switch today.statusRaw {
        case "execute":
            stateLabel = "专注"
        case "draft":
            stateLabel = "草稿"
        case "completed":
            stateLabel = "完成"
        case "expired":
            stateLabel = "过期"
        default:
            stateLabel = "待开始"
        }
    }
}

private struct WidgetStatusPill: View {
    let text: String
    let tokens: WidgetVisualTokens

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tokens.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tokens.surface, in: Capsule())
    }
}

private struct WidgetMetricPill: View {
    let title: String
    let valueText: String
    let tokens: WidgetVisualTokens

    init(title: String, value: Int, tokens: WidgetVisualTokens) {
        self.title = title
        self.valueText = "\(value)"
        self.tokens = tokens
    }

    init(title: String, valueText: String, tokens: WidgetVisualTokens) {
        self.title = title
        self.valueText = valueText
        self.tokens = tokens
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(tokens.textSecondary)
            Text(valueText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tokens.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tokens.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct WidgetTaskPreviewLine: View {
    let row: WidgetTaskPreview
    let color: Color
    let textColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(row.title)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(textColor)
        }
    }
}

private struct WidgetWeekStripCell: View {
    let day: WidgetWeekDaySemantic
    let tokens: WidgetVisualTokens

    var body: some View {
        VStack(spacing: 4) {
            Text(day.weekday.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tokens.textSecondary)
            Text("\(day.number)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tokens.textPrimary)

            WidgetLinearProgress(
                progress: day.progress,
                fill: progressFill,
                track: tokens.ringTrack
            )
            .frame(height: 4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(tokens.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var progressFill: Color {
        switch day.statusRaw {
        case "completed":
            return tokens.success
        case "expired":
            return tokens.danger
        default:
            return tokens.primary
        }
    }
}

private struct WidgetProgressRing: View {
    let progress: CGFloat
    let lineWidth: CGFloat
    let tint: Color
    let track: Color
    let centerText: String
    let centerTextColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(centerText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(centerTextColor)
        }
    }
}

private struct WidgetLinearProgress: View {
    let progress: CGFloat
    let fill: Color
    let track: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(min(progress, 1), 0) * proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: width)
            }
        }
    }
}

private struct LiveActionCapsule: View {
    let title: String
    let icon: String
    let fill: Color
    let foreground: Color
    var verticalPadding: CGFloat = 9

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, verticalPadding)
        .foregroundStyle(foreground)
        .background(fill, in: Capsule())
    }
}

private struct LiveLinearProgress: View {
    let progress: CGFloat
    let fill: Color
    let track: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(min(progress, 1), 0) * proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: width)
            }
        }
    }
}

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

private func liveActivityTaskTypeLabel(raw: String) -> String {
    switch raw {
    case "ddl":
        return "DDL"
    case "leisure":
        return "休闲"
    default:
        return "常规"
    }
}

private func liveActivityDurationText(seconds: Int) -> String {
    let safe = max(0, seconds)
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    let secs = safe % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, secs)
}

private func liveActivityCompactDurationText(seconds: Int) -> String {
    let safe = max(0, seconds)
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    let secs = safe % 60
    if hours > 0 {
        return String(format: "%d:%02d", hours, minutes)
    }
    return String(format: "%02d:%02d", minutes, secs)
}

private func statusIcon(raw: String) -> String {
    switch raw {
    case "execute":
        return "bolt.fill"
    case "completed":
        return "checkmark.seal.fill"
    case "expired":
        return "xmark.seal.fill"
    case "draft":
        return "square.and.pencil"
    default:
        return "circle.dotted"
    }
}

private func isHexColorLight(_ hex: String) -> Bool {
    var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if sanitized.hasPrefix("#") { sanitized.removeFirst() }
    guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
        return false
    }
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    let luma = 0.299 * r + 0.587 * g + 0.114 * b
    return luma > 0.72
}

private func deadlineLabel(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "截止 HH:mm"
    return formatter.string(from: date)
}

private extension View {
    @ViewBuilder
    func weekyiiWidgetContainerBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { color }
        } else {
            background(color)
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
