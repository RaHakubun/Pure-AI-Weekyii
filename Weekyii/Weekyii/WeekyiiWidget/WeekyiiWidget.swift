import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(AppIntents)
import AppIntents
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
        let now = Date()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        let entries = Self.entryDates(for: snapshot.today, now: now)
            .map { WeekyiiWidgetEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    /// Now, plus the moments the widget's state changes on its own: one hour
    /// before the deadline (due soon), the deadline (overdue) and the day boundary.
    /// The countdown itself is a system timer and needs no entries.
    static func entryDates(for today: WidgetTodaySnapshot, now: Date) -> [Date] {
        var dates: [Date] = [now]
        if today.statusRaw == "execute", let killTime = today.killTime {
            dates.append(killTime.addingTimeInterval(-WidgetSemanticData.urgentThreshold))
            dates.append(killTime)
        }
        if let dayEndsAt = today.dayEndsAt {
            dates.append(dayEndsAt)
        }
        return Array(Set(dates.filter { $0 >= now })).sorted()
    }
}

struct WeekyiiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WeekyiiWidgetKind.main, provider: WeekyiiWidgetProvider()) { entry in
            WeekyiiWidgetRoot(entry: entry)
        }
        .configurationDisplayName("Weekyii")
        .description(String(localized: "widget.description", defaultValue: "查看今天的焦点任务、截止倒计时和本周进度。"))
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
struct WeekyiiLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TodayActivityAttributes.self) { context in
            LockScreenLiveActivityView(model: Self.presentation(for: context))
                .widgetURL(LiveActivityAction.openToday.url())
                .modifier(LiveActivityLockStylingModifier(theme: context.state.liveTheme))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(model: Self.presentation(for: context))
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(model: Self.presentation(for: context))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(model: Self.presentation(for: context))
                }
            } compactLeading: {
                IslandCompactLeading(model: Self.presentation(for: context))
            } compactTrailing: {
                IslandCompactTrailing(model: Self.presentation(for: context))
            } minimal: {
                IslandMinimal(model: Self.presentation(for: context))
            }
            .widgetURL(LiveActivityAction.openToday.url())
            .keylineTint(Color(widgetHex: context.state.liveTheme.islandKeylineHex))
        }
    }

    private static func presentation(
        for context: ActivityViewContext<TodayActivityAttributes>
    ) -> LiveActivityPresentation {
        LiveActivityPresentation(state: context.state, isStale: context.isStale)
    }
}

// MARK: - Presentation

/// Everything the Live Activity views derive from a content state: phase,
/// localized copy, task-type styling and the time window.
private struct LiveActivityPresentation {
    enum Phase {
        /// More than an hour left.
        case normal
        /// One hour or less left. Switches on the next content update from the app.
        case urgent
        /// Past the deadline. The system switches here by itself at the stale date.
        case overdue
    }

    static let urgentThreshold: TimeInterval = 3600
    static let overdueLightHex = "#C9372C"
    static let overdueDarkHex = "#FF6B5E"

    let state: TodayActivityAttributes.ContentState
    let phase: Phase
    let bundle: Bundle

    init(state: TodayActivityAttributes.ContentState, isStale: Bool, now: Date = Date()) {
        self.state = state
        if isStale || state.killTime <= now {
            phase = .overdue
        } else if state.killTime.timeIntervalSince(now) <= Self.urgentThreshold {
            phase = .urgent
        } else {
            phase = .normal
        }
        bundle = Self.localizationBundle(for: state.languageCode)
    }

    var theme: LiveActivityThemeSnapshot { state.liveTheme }
    var isOverdue: Bool { phase == .overdue }

    /// Start of today's window (when the user started the day) up to the deadline.
    var timeWindow: ClosedRange<Date>? {
        let start = state.dayStartedAt ?? Calendar.current.startOfDay(for: state.killTime)
        guard start < state.killTime else { return nil }
        return start...state.killTime
    }

    // MARK: Type styling

    var typeColorHex: String {
        if let hex = state.typeColorHex, !hex.isEmpty { return hex }
        switch state.taskTypeRaw {
        case "ddl": return "#C46A1A"
        case "leisure": return "#8B5A83"
        default: return "#4A90A4"
        }
    }

    var typeIconName: String {
        if let icon = state.typeIconName, !icon.isEmpty { return icon }
        switch state.taskTypeRaw {
        case "ddl": return "exclamationmark.triangle.fill"
        case "leisure": return "sparkles"
        default: return "checkmark.circle.fill"
        }
    }

    var typeName: String {
        if let name = state.typeName, !name.isEmpty { return name }
        switch state.taskTypeRaw {
        case "ddl": return String(localized: "live.type.ddl", defaultValue: "DDL", bundle: bundle)
        case "leisure": return String(localized: "live.type.leisure", defaultValue: "休闲", bundle: bundle)
        default: return String(localized: "live.type.regular", defaultValue: "常规", bundle: bundle)
        }
    }

    /// Type icon normally; a flame when the deadline is close; a warning sign once overdue.
    var glyphSymbol: String {
        switch phase {
        case .normal: return typeIconName
        case .urgent: return "flame.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        }
    }

    // MARK: Copy

    var statusText: String {
        switch phase {
        case .normal: return String(localized: "live.status.focus", defaultValue: "专注中", bundle: bundle)
        case .urgent: return String(localized: "live.status.urgent", defaultValue: "即将截止", bundle: bundle)
        case .overdue: return String(localized: "live.status.overdue", defaultValue: "已超时", bundle: bundle)
        }
    }

    var statusWithTypeText: String {
        "\(statusText) · \(typeName)"
    }

    var deadlineText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: state.killTime)
        return String(localized: "live.deadline", defaultValue: "截止 \(time)", bundle: bundle)
    }

    var timerCaption: String {
        if isOverdue {
            return String(localized: "live.over_by", defaultValue: "已超出", bundle: bundle)
        }
        return String(localized: "live.remaining", defaultValue: "剩余时间", bundle: bundle)
    }

    /// Compact leading label: the task title, or 已超时 once overdue.
    var compactLabel: String {
        isOverdue ? statusText : state.focusTitle
    }

    var metaText: String {
        var parts: [String] = []
        if let next = state.nextTitle, !next.isEmpty {
            parts.append(String(localized: "live.meta.next", defaultValue: "下一项 \(next)", bundle: bundle))
        }
        let pending = state.frozenCount
        parts.append(String(localized: "live.meta.pending", defaultValue: "待办 \(pending)", bundle: bundle))
        let completed = state.completedCount
        let total = state.totalCount
        parts.append(String(localized: "live.meta.done", defaultValue: "已完成 \(completed)/\(total)", bundle: bundle))
        return parts.joined(separator: " · ")
    }

    var doneTitle: String { String(localized: "live.action.done", defaultValue: "完成", bundle: bundle) }
    var postponeTitle: String { String(localized: "live.action.postpone", defaultValue: "推迟到明天", bundle: bundle) }
    var confirmDoneTitle: String { String(localized: "live.action.confirm_done", defaultValue: "确认完成", bundle: bundle) }
    var confirmPostponeTitle: String { String(localized: "live.action.confirm_postpone", defaultValue: "确认推迟", bundle: bundle) }
    var cancelTitle: String { String(localized: "live.action.cancel", defaultValue: "取消", bundle: bundle) }

    // MARK: Island colors (always rendered on the black island)

    var islandPrimary: Color { Color(widgetHex: theme.islandTextPrimaryHex) }
    var islandSecondary: Color { Color(widgetHex: theme.islandTextSecondaryHex) }

    var islandTint: Color {
        switch phase {
        case .normal: return Color(widgetHex: theme.islandAccentHex)
        case .urgent: return Color(widgetHex: theme.islandWarningHex)
        case .overdue: return Color(widgetHex: Self.overdueDarkHex)
        }
    }

    /// Glyph color on a dark background: the type color lifted for contrast.
    var islandGlyphColor: Color {
        switch phase {
        case .normal: return Color(widgetHex: typeColorHex).mix(with: .white, by: 0.3)
        case .urgent, .overdue: return islandTint
        }
    }

    // MARK: Helpers

    private static func localizationBundle(for languageCode: String?) -> Bundle {
        weekyiiLocalizationBundle(for: languageCode)
    }
}

// MARK: - Shared pieces

/// Self-updating countdown to the deadline; after the deadline the same system
/// timer counts up, prefixed with "+".
private extension LiveActivityPresentation {
    /// Width for the large expanded/lock-screen countdown (22pt rounded, monospaced).
    var countdownColumnWidth: CGFloat {
        if isOverdue { return 104 }
        return state.killTime.timeIntervalSinceNow >= 3600 ? 92 : 68
    }
}

private struct LiveCountdownText: View {
    let model: LiveActivityPresentation

    var body: some View {
        (model.isOverdue ? Text(verbatim: "+") + Text(model.state.killTime, style: .timer) : Text(model.state.killTime, style: .timer))
            .monospacedDigit()
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
    }
}

private struct LiveGlyph: View {
    let symbol: String
    let color: Color
    var size: CGFloat
    var cornerRadius: CGFloat? = nil

    var body: some View {
        let background = color.opacity(0.22)
        Group {
            if let cornerRadius {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(background)
            } else {
                Circle().fill(background)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

/// Time bar from "day started" to the deadline, animated by the system.
private struct LiveTimeBar: View {
    let model: LiveActivityPresentation
    let tint: Color
    let overdueColor: Color
    let track: Color

    var body: some View {
        if model.isOverdue {
            Capsule()
                .fill(overdueColor)
                .frame(height: 5)
        } else if let window = model.timeWindow {
            ProgressView(timerInterval: window, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(tint)
        } else {
            Capsule()
                .fill(track)
                .frame(height: 5)
        }
    }
}

private struct LiveActionButtonLabel: View {
    let title: String
    var icon: String?
    let fill: Color
    let foreground: Color
    var height: CGFloat = 28
    var expands = true

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .imageScale(.small)
            }
            Text(title)
        }
        .font(.caption.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .frame(maxWidth: expands ? .infinity : nil)
        .frame(height: height)
        .foregroundStyle(foreground)
        .background(fill, in: Capsule())
        .contentShape(Capsule())
    }
}

private struct LiveActionButtonColors {
    var doneFill: Color
    var doneForeground: Color
    var secondaryFill: Color
    var secondaryForeground: Color
    var confirmDoneFill: Color
    var confirmPostponeFill: Color
    var confirmForeground: Color
}

/// 完成 / 推迟到明天 → second tap 确认完成 / 确认推迟, or 取消. Runs as App Intents, so
/// the app is not brought to the foreground.
private struct LiveActionRow: View {
    let model: LiveActivityPresentation
    let colors: LiveActionButtonColors
    var height: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            switch model.state.pendingAction {
            case .doneFocus:
                confirmButtons(
                    action: .doneFocus,
                    title: model.confirmDoneTitle,
                    icon: "checkmark",
                    fill: colors.confirmDoneFill
                )
            case .postponeFocus:
                confirmButtons(
                    action: .postponeFocus,
                    title: model.confirmPostponeTitle,
                    icon: "arrow.right",
                    fill: colors.confirmPostponeFill
                )
            case .openToday, nil:
                Button(intent: LiveActivityRequestConfirmIntent(action: .doneFocus)) {
                    LiveActionButtonLabel(
                        title: model.doneTitle,
                        icon: "checkmark",
                        fill: colors.doneFill,
                        foreground: colors.doneForeground,
                        height: height
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LiveActivityRequestConfirmIntent(action: .postponeFocus)) {
                    LiveActionButtonLabel(
                        title: model.postponeTitle,
                        icon: "arrow.right",
                        fill: colors.secondaryFill,
                        foreground: colors.secondaryForeground,
                        height: height
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func confirmButtons(action: LiveActivityAction, title: String, icon: String, fill: Color) -> some View {
        Button(intent: LiveActivityPerformActionIntent(action: action)) {
            LiveActionButtonLabel(
                title: title,
                icon: icon,
                fill: fill,
                foreground: colors.confirmForeground,
                height: height
            )
        }
        .buttonStyle(.plain)

        Button(intent: LiveActivityCancelConfirmIntent()) {
            LiveActionButtonLabel(
                title: model.cancelTitle,
                fill: colors.secondaryFill,
                foreground: colors.secondaryForeground,
                height: height,
                expands: false
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lock screen / notification banner

private struct LockScreenLiveActivityView: View {
    let model: LiveActivityPresentation

    private var palette: LiveActivityLockPalette {
        model.theme.resolvedLockPalette(prefersDarkLock: model.theme.usesExplicitDarkLockPalette)
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

    private var overdueColor: Color {
        Color(widgetHex: usesLightBackground ? LiveActivityPresentation.overdueLightHex : LiveActivityPresentation.overdueDarkHex)
    }

    private var tint: Color {
        switch model.phase {
        case .normal:
            return Color(widgetHex: palette.accentHex)
        case .urgent:
            let warning = Color(widgetHex: model.theme.islandWarningHex)
            return usesLightBackground ? warning.mix(with: .black, by: 0.25) : warning
        case .overdue:
            return overdueColor
        }
    }

    private var glyphColor: Color {
        switch model.phase {
        case .normal:
            let typeColor = Color(widgetHex: model.typeColorHex)
            return usesLightBackground ? typeColor : typeColor.mix(with: .white, by: 0.3)
        case .urgent, .overdue:
            return tint
        }
    }

    /// Header/status color: neutral normally, phase color when urgent or overdue.
    private var statusColor: Color {
        model.phase == .normal ? secondaryTextColor : tint
    }

    private var buttonColors: LiveActionButtonColors {
        let success = Color(widgetHex: model.theme.islandSuccessHex)
        let doneFill = usesLightBackground ? success.mix(with: .black, by: 0.3) : success
        let doneForeground: Color = usesLightBackground || !liveActivityPrefersDarkForeground(model.theme.islandSuccessHex)
            ? .white
            : Color(widgetHex: "#0F2624")
        return LiveActionButtonColors(
            doneFill: doneFill,
            doneForeground: doneForeground,
            secondaryFill: Color(widgetHex: palette.surfaceHex),
            secondaryForeground: primaryTextColor,
            confirmDoneFill: Color(widgetHex: "#3FA67A"),
            confirmPostponeFill: Color(widgetHex: usesLightBackground ? "#B4561A" : model.theme.islandChipSecondaryHex),
            confirmForeground: .white
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                LiveGlyph(symbol: model.glyphSymbol, color: glyphColor, size: 20)
                Text(verbatim: "Weekyii · \(model.statusText)")
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(model.deadlineText)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.state.focusTitle)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(primaryTextColor)
                    Text(model.metaText)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(secondaryTextColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(model.timerCaption)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(model.isOverdue ? tint : secondaryTextColor)
                    LiveCountdownText(model: model)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(tint)
                }
                // `Text(_, style: .timer)` reports a flexible width; give the column a
                // fixed width so it is never pushed past the trailing edge.
                .frame(width: model.countdownColumnWidth, alignment: .trailing)
                .layoutPriority(1)
            }

            LiveTimeBar(
                model: model,
                tint: tint,
                overdueColor: overdueColor,
                track: Color(widgetHex: palette.progressTrackHex).opacity(0.2)
            )

            LiveActionRow(model: model, colors: buttonColors, height: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Dynamic Island

private func islandButtonColors(for model: LiveActivityPresentation) -> LiveActionButtonColors {
    let successHex = model.theme.islandSuccessHex
    return LiveActionButtonColors(
        doneFill: Color(widgetHex: successHex),
        doneForeground: liveActivityPrefersDarkForeground(successHex) ? Color(widgetHex: "#0F2624") : .white,
        secondaryFill: Color.white.opacity(0.14),
        secondaryForeground: model.islandPrimary,
        confirmDoneFill: Color(widgetHex: "#3FA67A"),
        confirmPostponeFill: Color(widgetHex: model.theme.islandChipSecondaryHex),
        confirmForeground: .white
    )
}

private struct IslandExpandedLeading: View {
    let model: LiveActivityPresentation

    var body: some View {
        HStack(spacing: 8) {
            LiveGlyph(symbol: model.glyphSymbol, color: model.islandGlyphColor, size: 34, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusWithTypeText)
                    .foregroundStyle(model.phase == .normal ? model.islandSecondary : model.islandTint)
                Text(model.deadlineText)
                    .foregroundStyle(model.isOverdue ? model.islandTint : model.islandPrimary)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IslandExpandedTrailing: View {
    let model: LiveActivityPresentation

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(model.timerCaption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(model.isOverdue ? model.islandTint : model.islandSecondary)
                .lineLimit(1)
            LiveCountdownText(model: model)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .foregroundStyle(model.islandTint)
        }
        .frame(width: model.countdownColumnWidth, alignment: .trailing)
        .padding(.trailing, 4)
    }
}

private struct IslandExpandedBottom: View {
    let model: LiveActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.state.focusTitle)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(model.islandPrimary)
                Text(model.metaText)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(model.islandSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LiveTimeBar(
                model: model,
                tint: model.islandTint,
                overdueColor: model.islandTint,
                track: Color.white.opacity(0.14)
            )

            LiveActionRow(model: model, colors: islandButtonColors(for: model), height: 28)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

private struct IslandCompactLeading: View {
    let model: LiveActivityPresentation

    var body: some View {
        HStack(spacing: 5) {
            LiveGlyph(symbol: model.glyphSymbol, color: model.islandGlyphColor, size: 20)
            Text(model.compactLabel)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(model.isOverdue ? model.islandTint : model.islandPrimary)
                .frame(maxWidth: 58, alignment: .leading)
        }
    }
}

private struct IslandCompactTrailing: View {
    let model: LiveActivityPresentation

    /// `Text(_, style: .timer)` reports a flexible width, so it gets an explicit
    /// cap sized for its longest expected form.
    private var maxWidth: CGFloat {
        if model.isOverdue { return 64 }
        return model.state.killTime.timeIntervalSinceNow >= 3600 ? 56 : 44
    }

    var body: some View {
        LiveCountdownText(model: model)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(model.islandTint)
            .frame(maxWidth: maxWidth, alignment: .trailing)
    }
}

private struct IslandMinimal: View {
    let model: LiveActivityPresentation

    var body: some View {
        ZStack {
            if !model.isOverdue, let window = model.timeWindow {
                // Ring empties from "day started" to the deadline, driven by the system.
                ProgressView(timerInterval: window, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(model.islandTint)
            } else {
                Circle()
                    .stroke(model.isOverdue ? model.islandTint : Color.white.opacity(0.18), lineWidth: 2.5)
            }
            Image(systemName: model.glyphSymbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(model.islandGlyphColor)
        }
        .padding(2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(model.statusText) · \(model.state.focusTitle)"))
    }
}

private struct LiveActivityLockStylingModifier: ViewModifier {
    let theme: LiveActivityThemeSnapshot

    func body(content: Content) -> some View {
        let palette = theme.resolvedLockPalette(prefersDarkLock: theme.usesExplicitDarkLockPalette)
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

// MARK: - Home & lock screen widgets

/// What the widget says about today at a given timeline moment.
private enum WidgetDayPhase {
    /// Executing, more than an hour left.
    case focus
    /// Executing, one hour or less left.
    case urgent
    /// Executing, deadline passed, the app has not closed the day yet.
    case overdue
    case completed
    /// The day expired.
    case ended
    /// Planned (draft) or nothing planned yet.
    case notStarted
    /// The snapshot still describes a previous day.
    case newDay

    var showsCountdown: Bool {
        switch self {
        case .focus, .urgent, .overdue: return true
        default: return false
        }
    }
}

private struct WeekyiiWidgetRoot: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: WeekyiiWidgetEntry

    private var isDark: Bool {
        switch entry.snapshot.theme.appearanceMode {
        case .system: return colorScheme == .dark
        case .light: return false
        case .dark: return true
        }
    }

    private var tokens: WidgetVisualTokens {
        WidgetVisualTokens(
            palette: entry.snapshot.theme.resolvedPalette(isDarkSystem: colorScheme == .dark),
            isDark: isDark
        )
    }

    private var semantic: WidgetSemanticData {
        WidgetSemanticData(snapshot: entry.snapshot, now: entry.date)
    }

    private var familyBackground: Color {
        switch family {
        case .accessoryInline, .accessoryRectangular, .accessoryCircular:
            // The lock screen draws its own material; theme colors are not used there.
            return .clear
        default:
            return tokens.background
        }
    }

    var body: some View {
        let semantic = self.semantic
        let tokens = self.tokens
        Group {
            switch family {
            case .systemSmall:
                WidgetSmallView(semantic: semantic, tokens: tokens)
            case .systemMedium:
                WidgetMediumView(semantic: semantic, tokens: tokens)
            case .systemLarge:
                WidgetLargeView(semantic: semantic, tokens: tokens)
            case .accessoryInline:
                WidgetInlineView(semantic: semantic)
            case .accessoryRectangular:
                WidgetRectangularView(semantic: semantic)
            case .accessoryCircular:
                WidgetCircularView(semantic: semantic)
            default:
                WidgetSmallView(semantic: semantic, tokens: tokens)
            }
        }
        .weekyiiWidgetContainerBackground(familyBackground)
        .widgetURL(LiveActivityAction.openToday.url())
    }
}

// MARK: System families

private struct WidgetSmallView: View {
    let semantic: WidgetSemanticData
    let tokens: WidgetVisualTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                WidgetStateLabel(text: semantic.stateLabel, tint: tokens.tint(for: semantic.phase))
                Spacer(minLength: 4)
                if semantic.showsCounts {
                    Text(verbatim: "\(semantic.completedCount)/\(semantic.totalCount)")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(1)
                }
            }

            Text(semantic.keyline)
                .font(.headline)
                .foregroundStyle(tokens.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .padding(.top, 6)

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 0) {
                if semantic.phase.showsCountdown, let killTime = semantic.killTime {
                    WidgetCountdownText(killTime: killTime, overdue: semantic.phase == .overdue)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(tokens.tint(for: semantic.phase))
                        .widgetAccentable()
                    Text(semantic.deadlineText)
                        .font(.caption2)
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                } else if let caption = semantic.summaryCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(2)
                }

                if semantic.showsCounts {
                    WidgetLinearProgress(progress: semantic.progress, fill: tokens.tint(for: semantic.phase), track: tokens.ringTrack)
                        .frame(height: 4)
                        .padding(.top, 7)
                }
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WidgetMediumView: View {
    let semantic: WidgetSemanticData
    let tokens: WidgetVisualTokens

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetStateLabel(text: semantic.stateLabel, tint: tokens.tint(for: semantic.phase))
                Spacer(minLength: 6)
                if semantic.phase.showsCountdown, let killTime = semantic.killTime {
                    WidgetCountdownText(killTime: killTime, overdue: semantic.phase == .overdue)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(tokens.tint(for: semantic.phase))
                        .widgetAccentable()
                    Text(semantic.deadlineText)
                        .font(.caption2)
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                } else if semantic.showsCounts {
                    Text(verbatim: "\(semantic.progressPercent)%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(tokens.tint(for: semantic.phase))
                        .lineLimit(1)
                        .widgetAccentable()
                }
                if semantic.showsCounts {
                    WidgetLinearProgress(progress: semantic.progress, fill: tokens.tint(for: semantic.phase), track: tokens.ringTrack)
                        .frame(height: 4)
                        .padding(.top, 8)
                    Text(semantic.doneText)
                        .font(.caption2)
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(1)
                        .padding(.top, 4)
                }
            }
            .frame(width: 118, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(tokens.stroke)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                WidgetKeylineRow(semantic: semantic, tokens: tokens, font: .subheadline.weight(.semibold), lineLimit: 2)

                let rows = Array(semantic.listRows.prefix(2))
                if !rows.isEmpty {
                    WidgetSectionTitle(text: semantic.upNextTitle, tokens: tokens)
                        .padding(.top, 10)
                    ForEach(rows) { row in
                        WidgetTaskRow(row: row, tokens: tokens)
                            .padding(.top, 5)
                    }
                }

                Spacer(minLength: 0)

                if let more = semantic.moreText(afterShowing: rows.count) {
                    Text(more)
                        .font(.caption2)
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct WidgetLargeView: View {
    let semantic: WidgetSemanticData
    let tokens: WidgetVisualTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(semantic.dateHeader)
                    .font(.headline)
                    .foregroundStyle(tokens.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                WidgetStatusPill(text: semantic.stateLabel, tint: tokens.tint(for: semantic.phase), tokens: tokens)
            }

            focusCard
                .padding(.top, 10)

            let rows = Array(semantic.listRows.prefix(3))
            if !rows.isEmpty {
                WidgetSectionTitle(text: semantic.upNextTitle, tokens: tokens)
                    .padding(.top, 12)
                ForEach(rows) { row in
                    WidgetTaskRow(row: row, tokens: tokens)
                        .padding(.top, 6)
                }
                if let more = semantic.moreText(afterShowing: rows.count) {
                    Text(more)
                        .font(.caption2)
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(1)
                        .padding(.top, 5)
                }
            }

            Spacer(minLength: 8)

            if !semantic.weekDays.isEmpty {
                HStack(spacing: 6) {
                    ForEach(semantic.weekDays.prefix(7)) { day in
                        WidgetWeekStripCell(day: day, isToday: day.id == semantic.todayId && semantic.phase != .newDay, tokens: tokens)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if semantic.hasFocusTask {
                Text(semantic.focusTypeName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(widgetHex: semantic.focusTypeColorHex))
                    .lineLimit(1)
                    .padding(.bottom, 3)
            }

            Text(semantic.keyline)
                .font(.headline)
                .foregroundStyle(tokens.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if semantic.phase.showsCountdown, let killTime = semantic.killTime {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    WidgetCountdownText(killTime: killTime, overdue: semantic.phase == .overdue)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(tokens.tint(for: semantic.phase))
                        .widgetAccentable()
                    Spacer(minLength: 4)
                    Text(semantic.deadlineText)
                        .font(.caption)
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(1)
                }
                .padding(.top, 8)
            } else if let caption = semantic.summaryCaption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(tokens.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 6)
            }

            if semantic.showsCounts {
                WidgetLinearProgress(progress: semantic.progress, fill: tokens.tint(for: semantic.phase), track: tokens.ringTrack)
                    .frame(height: 6)
                    .padding(.top, 8)
                Text(semantic.doneAndRemainingText)
                    .font(.caption2)
                    .foregroundStyle(tokens.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: Accessory families (lock screen)
// These render in the system's vibrant style, so they use semantic foreground
// styles instead of theme colors.

private struct WidgetInlineView: View {
    let semantic: WidgetSemanticData

    var body: some View {
        if semantic.phase.showsCountdown, let killTime = semantic.killTime {
            // Timer first so it survives truncation of a long title.
            (WidgetCountdownText.text(killTime: killTime, overdue: semantic.phase == .overdue)
                + Text(verbatim: " · ")
                + Text(semantic.keyline))
                .lineLimit(1)
        } else {
            Text(semantic.inlineSummary)
                .lineLimit(1)
        }
    }
}

private struct WidgetRectangularView: View {
    let semantic: WidgetSemanticData

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Group {
                if semantic.phase.showsCountdown, let killTime = semantic.killTime {
                    Text(semantic.stateLabel)
                        + Text(verbatim: " · ")
                        + WidgetCountdownText.text(killTime: killTime, overdue: semantic.phase == .overdue)
                } else {
                    Text(semantic.stateLabel)
                }
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .widgetAccentable()

            Text(semantic.keyline)
                .font(.headline)
                .lineLimit(1)

            Text(semantic.rectangularFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WidgetCircularView: View {
    let semantic: WidgetSemanticData

    var body: some View {
        Gauge(value: Double(semantic.progress)) {
            EmptyView()
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text(verbatim: semantic.totalCount == 0 ? "--" : "\(semantic.completedCount)/\(semantic.totalCount)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(semantic.doneShortTitle)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}

// MARK: Pieces

/// Self-updating countdown to the deadline; past the deadline the system timer counts up, prefixed with "+".
private struct WidgetCountdownText: View {
    let killTime: Date
    let overdue: Bool

    static func text(killTime: Date, overdue: Bool) -> Text {
        overdue ? Text(verbatim: "+") + Text(killTime, style: .timer) : Text(killTime, style: .timer)
    }

    var body: some View {
        Self.text(killTime: killTime, overdue: overdue)
            .monospacedDigit()
            .lineLimit(1)
            .multilineTextAlignment(.leading)
    }
}

private struct WidgetStateLabel: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .widgetAccentable()
    }
}

private struct WidgetStatusPill: View {
    let text: String
    let tint: Color
    let tokens: WidgetVisualTokens

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .widgetAccentable()
    }
}

private struct WidgetSectionTitle: View {
    let text: String
    let tokens: WidgetVisualTokens

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tokens.textSecondary)
            .lineLimit(1)
    }
}

/// Focus title with a thin bar in the task-type color (medium widget).
private struct WidgetKeylineRow: View {
    let semantic: WidgetSemanticData
    let tokens: WidgetVisualTokens
    let font: Font
    let lineLimit: Int

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if semantic.hasFocusTask {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(widgetHex: semantic.focusTypeColorHex))
                    .frame(width: 3)
            }
            Text(semantic.keyline)
                .font(font)
                .foregroundStyle(tokens.textPrimary)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.85)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WidgetTaskRow: View {
    let row: WidgetTaskPreview
    let tokens: WidgetVisualTokens

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(widgetHex: row.typeColorHex ?? widgetBuiltInTypeColorHex(raw: row.taskTypeRaw)))
                .frame(width: 7, height: 7)
            Text(row.title)
                .font(.footnote)
                .foregroundStyle(tokens.textPrimary)
                .lineLimit(1)
        }
    }
}

private struct WidgetWeekStripCell: View {
    let day: WidgetWeekDaySemantic
    let isToday: Bool
    let tokens: WidgetVisualTokens

    var body: some View {
        VStack(spacing: 2) {
            Text(day.weekday)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isToday ? tokens.onPrimary : tokens.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: "\(day.number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(isToday ? tokens.onPrimary : tokens.textPrimary)
                .lineLimit(1)

            WidgetLinearProgress(
                progress: day.progress,
                fill: isToday ? tokens.onPrimary : progressFill,
                track: isToday ? tokens.onPrimary.opacity(0.35) : tokens.ringTrack
            )
            .frame(height: 3)
            .padding(.horizontal, 3)
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity)
        .background(isToday ? tokens.primary : tokens.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var progressFill: Color {
        switch day.statusRaw {
        case "completed":
            return tokens.success
        case "expired":
            return tokens.textSecondary
        default:
            return tokens.primary
        }
    }
}

// MARK: Data

private struct WidgetVisualTokens {
    static let overdueLightHex = "#C9372C"
    static let overdueDarkHex = "#FF6B5E"

    let primary: Color
    let accent: Color
    let background: Color
    let surface: Color
    let textPrimary: Color
    let textSecondary: Color
    let ringTrack: Color
    let stroke: Color
    let success: Color
    let danger: Color
    /// Text drawn on a `primary` fill.
    let onPrimary: Color

    init(palette: WidgetThemePalette, isDark: Bool) {
        let textMain = Color(widgetHex: palette.textPrimaryHex)
        primary = Color(widgetHex: palette.primaryHex)
        accent = Color(widgetHex: palette.accentHex)
        background = Color(widgetHex: palette.backgroundHex)
        surface = Color(widgetHex: palette.primaryLightHex).opacity(0.14)
        textPrimary = textMain
        textSecondary = Color(widgetHex: palette.textSecondaryHex)
        ringTrack = Color(widgetHex: palette.primaryLightHex).opacity(0.3)
        stroke = textMain.opacity(0.08)
        success = Color(widgetHex: palette.successHex)
        danger = Color(widgetHex: isDark ? Self.overdueDarkHex : Self.overdueLightHex)
        onPrimary = liveActivityPrefersDarkForeground(palette.primaryHex) ? Color(widgetHex: "#1F1A17") : .white
    }

    func tint(for phase: WidgetDayPhase) -> Color {
        switch phase {
        case .focus, .newDay: return primary
        case .urgent: return accent
        case .overdue: return danger
        case .completed: return success
        case .ended, .notStarted: return textSecondary
        }
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

    init(snapshot: WidgetWeekDaySnapshot, weekday: String) {
        id = snapshot.dayId
        self.weekday = weekday
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
    static let urgentThreshold: TimeInterval = 3600

    let phase: WidgetDayPhase
    let bundle: Bundle
    let todayId: String
    let killTime: Date?
    let killTimeText: String
    let keyline: String
    let hasFocusTask: Bool
    let focusTypeName: String
    let focusTypeColorHex: String
    let progressPercent: Int
    let progress: CGFloat
    let completedCount: Int
    let totalCount: Int
    let remainingCount: Int
    /// Upcoming rows to list, never repeating the keyline task.
    let listRows: [WidgetTaskPreview]
    /// Upcoming tasks not yet accounted for by the keyline (frozen + draft, minus the keyline task).
    let listTotal: Int
    let weekDays: [WidgetWeekDaySemantic]
    let dateHeader: String

    init(snapshot: WidgetSnapshot, now: Date) {
        let today = snapshot.today
        let bundle = weekyiiLocalizationBundle(for: today.languageCode)
        let locale = today.languageCode.map { Locale(identifier: $0) } ?? .current
        self.bundle = bundle

        if let dayEndsAt = today.dayEndsAt, now >= dayEndsAt {
            phase = .newDay
        } else {
            switch today.statusRaw {
            case "execute":
                if let killTime = today.killTime {
                    if now >= killTime {
                        phase = .overdue
                    } else if killTime.timeIntervalSince(now) <= Self.urgentThreshold {
                        phase = .urgent
                    } else {
                        phase = .focus
                    }
                } else {
                    phase = .focus
                }
            case "completed":
                phase = .completed
            case "expired":
                phase = .ended
            default:
                phase = .notStarted
            }
        }

        let boundedPercent = min(max(today.completionPercent, 0), 100)
        todayId = today.dayId
        killTime = today.killTime
        killTimeText = today.killTimeText
        progressPercent = boundedPercent
        progress = CGFloat(boundedPercent) / 100
        completedCount = today.completedCount
        totalCount = today.totalCount
        remainingCount = max(today.totalCount - today.completedCount, 0)

        // Older snapshots have no upcoming list; derive it from the preview rows.
        let upcoming = today.upcomingTasks
            ?? today.previewTasks.filter { $0.zoneRaw == "frozen" || $0.zoneRaw == "draft" }
        let pendingCount = max(today.frozenCount + today.draftCount, upcoming.count)

        let focusTitle = today.focusTitle.flatMap { $0.isEmpty ? nil : $0 }
        let focusPreview = today.previewTasks.first { $0.zoneRaw == "focus" }
        hasFocusTask = focusTitle != nil && phase != .newDay
        let focusTypeRaw = focusPreview?.taskTypeRaw ?? "regular"
        focusTypeColorHex = today.focusTypeColorHex ?? focusPreview?.typeColorHex ?? widgetBuiltInTypeColorHex(raw: focusTypeRaw)
        if let name = today.focusTypeName, !name.isEmpty {
            focusTypeName = name
        } else {
            switch focusTypeRaw {
            case "ddl": focusTypeName = String(localized: "live.type.ddl", defaultValue: "DDL", bundle: bundle)
            case "leisure": focusTypeName = String(localized: "live.type.leisure", defaultValue: "休闲", bundle: bundle)
            default: focusTypeName = String(localized: "live.type.regular", defaultValue: "常规", bundle: bundle)
            }
        }

        var consumedByKeyline = 0
        switch phase {
        case .newDay:
            keyline = String(localized: "widget.keyline.new_day", defaultValue: "打开 Weekyii 开始今天", bundle: bundle)
        case .completed:
            keyline = String(localized: "widget.keyline.all_done", defaultValue: "今天的任务都完成了", bundle: bundle)
        case .ended:
            keyline = String(localized: "widget.keyline.ended", defaultValue: "今天已结束", bundle: bundle)
        case .focus, .urgent, .overdue, .notStarted:
            if let focusTitle {
                keyline = focusTitle
            } else if let first = upcoming.first {
                keyline = first.title
                consumedByKeyline = 1
            } else {
                keyline = String(localized: "widget.keyline.no_tasks", defaultValue: "今天还没有任务", bundle: bundle)
            }
        }

        if phase == .newDay {
            listRows = []
            listTotal = 0
        } else {
            listRows = Array(upcoming.dropFirst(consumedByKeyline))
            listTotal = max(pendingCount - consumedByKeyline, 0)
        }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = Calendar(identifier: .gregorian)
        weekdayFormatter.locale = locale
        weekdayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE")

        weekDays = snapshot.weekDays.map { day in
            let weekday = dayFormatter.date(from: day.dayId).map { weekdayFormatter.string(from: $0) } ?? day.weekdaySymbol
            return WidgetWeekDaySemantic(snapshot: day, weekday: weekday)
        }

        if phase != .newDay, let date = dayFormatter.date(from: today.dayId) {
            let headerFormatter = DateFormatter()
            headerFormatter.calendar = Calendar(identifier: .gregorian)
            headerFormatter.locale = locale
            headerFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            headerFormatter.setLocalizedDateFormatFromTemplate("MMMdEEEE")
            dateHeader = headerFormatter.string(from: date)
        } else {
            dateHeader = "Weekyii"
        }
    }

    /// Counts and progress only make sense once there is a plan for a current day.
    var showsCounts: Bool {
        phase != .newDay && totalCount > 0
    }

    var stateLabel: String {
        switch phase {
        case .focus: return String(localized: "live.status.focus", defaultValue: "专注中", bundle: bundle)
        case .urgent: return String(localized: "live.status.urgent", defaultValue: "即将截止", bundle: bundle)
        case .overdue: return String(localized: "live.status.overdue", defaultValue: "已超时", bundle: bundle)
        case .completed: return String(localized: "widget.status.completed", defaultValue: "今日完成", bundle: bundle)
        case .ended: return String(localized: "widget.status.ended", defaultValue: "已结束", bundle: bundle)
        case .notStarted: return String(localized: "widget.status.not_started", defaultValue: "未开始", bundle: bundle)
        case .newDay: return String(localized: "widget.status.new_day", defaultValue: "新的一天", bundle: bundle)
        }
    }

    var deadlineText: String {
        let time = killTimeText
        return String(localized: "live.deadline", defaultValue: "截止 \(time)", bundle: bundle)
    }

    var doneText: String {
        let completed = completedCount
        let total = totalCount
        return String(localized: "widget.done", defaultValue: "完成 \(completed)/\(total)", bundle: bundle)
    }

    var doneAndRemainingText: String {
        let remaining = remainingCount
        let remainingText = String(localized: "widget.remaining", defaultValue: "剩余 \(remaining)", bundle: bundle)
        return "\(doneText) · \(remainingText)"
    }

    var doneShortTitle: String {
        String(localized: "widget.done_short", defaultValue: "完成", bundle: bundle)
    }

    var upNextTitle: String {
        String(localized: "widget.up_next", defaultValue: "接下来", bundle: bundle)
    }

    func moreText(afterShowing shown: Int) -> String? {
        let more = listTotal - shown
        guard more > 0 else { return nil }
        return String(localized: "widget.more", defaultValue: "还有 \(more) 项", bundle: bundle)
    }

    /// Secondary line when there is no countdown to show.
    var summaryCaption: String? {
        switch phase {
        case .completed, .ended:
            return totalCount > 0 ? doneText : nil
        case .notStarted:
            guard totalCount > 0 else { return nil }
            let planned = totalCount
            return String(localized: "widget.planned", defaultValue: "已规划 \(planned) 项", bundle: bundle)
        case .newDay, .focus, .urgent, .overdue:
            return nil
        }
    }

    var inlineSummary: String {
        if showsCounts {
            return "\(stateLabel) · \(doneText)"
        }
        return "\(stateLabel) · \(keyline)"
    }

    var rectangularFooter: String {
        if let next = listRows.first?.title {
            return String(localized: "live.meta.next", defaultValue: "下一项 \(next)", bundle: bundle)
        }
        if showsCounts {
            return doneText
        }
        return "Weekyii"
    }
}

private func widgetBuiltInTypeColorHex(raw: String) -> String {
    switch raw {
    case "ddl": return "#C46A1A"
    case "leisure": return "#8B5A83"
    default: return "#4A90A4"
    }
}

/// The `.lproj` bundle for the language the app runs in, so widget copy follows
/// the in-app language rather than only the system language.
private func weekyiiLocalizationBundle(for languageCode: String?) -> Bundle {
    guard let languageCode,
          let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else {
        return .main
    }
    return bundle
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
                    .widgetAccentable()
            }
        }
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

/// Whether text on top of `hex` should be dark for legibility.
private func liveActivityPrefersDarkForeground(_ hex: String) -> Bool {
    var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if sanitized.hasPrefix("#") { sanitized.removeFirst() }
    guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
        return false
    }
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return 0.299 * r + 0.587 * g + 0.114 * b > 0.55
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
