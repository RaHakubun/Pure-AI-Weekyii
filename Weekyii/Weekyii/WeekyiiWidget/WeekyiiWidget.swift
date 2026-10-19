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
        guard let languageCode,
              let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return .main
        }
        return bundle
    }
}

// MARK: - Shared pieces

/// Self-updating countdown to the deadline; after the deadline the same system
/// timer counts up, prefixed with "+".
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
    var height: CGFloat = 36
    var expands = true

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(.subheadline.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 14)
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
    var height: CGFloat = 36

    var body: some View {
        HStack(spacing: 10) {
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
                .layoutPriority(1)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(model.timerCaption)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(model.isOverdue ? tint : secondaryTextColor)
                    LiveCountdownText(model: model)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            }

            LiveTimeBar(
                model: model,
                tint: tint,
                overdueColor: overdueColor,
                track: Color(widgetHex: palette.progressTrackHex).opacity(0.2)
            )

            LiveActionRow(model: model, colors: buttonColors, height: 34)
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
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(model.islandTint)
                .frame(maxWidth: 116, alignment: .trailing)
        }
        .padding(.trailing, 4)
    }
}

private struct IslandExpandedBottom: View {
    let model: LiveActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.state.focusTitle)
                    .font(.headline.weight(.bold))
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

            LiveActionRow(model: model, colors: islandButtonColors(for: model), height: 36)
        }
        .padding(.horizontal, 4)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("当下")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tokens.textSecondary)
                    .lineLimit(1)
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
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 5) {
                    Text(semantic.keyline)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tokens.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text("完成 \(semantic.completedCount)/\(semantic.totalCount)")
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(tokens.textSecondary)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }

            WidgetLinearProgress(progress: semantic.progress, fill: tokens.primary, track: tokens.ringTrack)
                .frame(height: 6)
        }
        .padding(12)
    }

    private var systemMediumView: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(semantic.progressPercent)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(tokens.primary)
                    Text("%")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tokens.textSecondary)
                }
                .lineLimit(1)

                Text("\(semantic.stateLabel) · 完成 \(semantic.completedCount)/\(semantic.totalCount)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tokens.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(semantic.keyline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tokens.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: 0)
                    Text("截止 \(semantic.killTimeText)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                WidgetLinearProgress(progress: semantic.progress, fill: tokens.primary, track: tokens.ringTrack)
                    .frame(height: 6)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(semantic.previewRows.prefix(2)) { row in
                        WidgetTaskPreviewLine(row: row, color: zoneColor(raw: row.zoneRaw), textColor: tokens.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .minimumScaleFactor(0.86)

                WidgetStatsStrip(semantic: semantic, tokens: tokens)

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
                .lineLimit(1)
                .foregroundStyle(tokens.textPrimary)
        }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(semantic.stateLabel)
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

            Text("完成 \(semantic.completedCount)/\(semantic.totalCount) · 剩余 \(semantic.remainingCount)")
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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

private struct WidgetStatsStrip: View {
    let semantic: WidgetSemanticData
    let tokens: WidgetVisualTokens

    var body: some View {
        HStack(spacing: 8) {
            stat("进度", "\(semantic.progressPercent)%")
            Divider()
                .frame(height: 16)
                .overlay(tokens.stroke)
            stat("完成", "\(semantic.completedCount)/\(semantic.totalCount)")
            Divider()
                .frame(height: 16)
                .overlay(tokens.stroke)
            stat("剩余", "\(semantic.remainingCount)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tokens.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(tokens.textSecondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(tokens.textPrimary)
                .monospacedDigit()
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity)
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
