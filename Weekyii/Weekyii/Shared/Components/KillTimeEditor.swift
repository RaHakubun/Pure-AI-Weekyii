import SwiftUI

// MARK: - KillTimeEditor

struct KillTimeEditor: View {
    let hour: Int
    let minute: Int
    let isEditable: Bool
    /// Keep the saved cutoff in the range while its preview changes.
    var rangeAnchorMinutes: Int? = nil
    let onChange: (Int, Int) -> Void
    var onEditingChanged: ((Bool) -> Void)? = nil

    // MARK: - Computed Properties

    /// 当前时间 + 1 小时，作为滑动条可选下界（最大不超过 23:59）
    private var minTimeInMinutes: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return min((c.hour ?? 0) * 60 + (c.minute ?? 0) + 60, endOfDayInMinutes)
    }

    private let endOfDayInMinutes: Int = 23 * 60 + 59

    private var clampedSelectedTimeInMinutes: Int {
        min(max(hour * 60 + minute, 0), endOfDayInMinutes)
    }

    /// 允许历史旧值低于当前 minTime，避免已设定的时间在展示时被强制上移
    private var sliderLowerBound: Double {
        Double(min(minTimeInMinutes, min(rangeAnchorMinutes ?? clampedSelectedTimeInMinutes, clampedSelectedTimeInMinutes)))
    }

    private var isSliderRangeValid: Bool {
        sliderLowerBound < Double(endOfDayInMinutes)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            // 时间显示：点按大号时间即可用系统选择器精确输入
            Text(String(format: "%02d:%02d", hour, minute))
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundColor(.textPrimary)
                .monospacedDigit()
                .accessibilityIdentifier("killTimeDisplay")
                .anchorPreference(key: KillTimeLayoutAnchorKey.self, value: .bounds) {
                    KillTimeLayoutAnchors(slider: nil, time: $0)
                }
                .overlay {
                    if isEditable {
                        // Invisible compact picker over the time keeps the precise
                        // input without a second, duplicate time chip.
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { composeDate(hour: hour, minute: minute) },
                                set: { newDate in
                                    let c = Calendar(identifier: .iso8601)
                                        .dateComponents([.hour, .minute], from: newDate)
                                    onChange(c.hour ?? hour, c.minute ?? minute)
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        // Lowest opacity that still receives taps; fully invisible.
                        .opacity(0.011)
                    }
                }

            // 滑动条（含上下刻度尺）
            if isEditable {
                if isSliderRangeValid {
                    KillTimeSlider(
                        value: Double(clampedSelectedTimeInMinutes),
                        lowerBound: sliderLowerBound,
                        upperBound: Double(endOfDayInMinutes),
                        onChange: { newValue in
                            let total = Int(newValue.rounded())
                            onChange(total / 60, total % 60)
                        },
                        onEditingChanged: onEditingChanged
                    )
                    .anchorPreference(key: KillTimeLayoutAnchorKey.self, value: .bounds) {
                        KillTimeLayoutAnchors(slider: $0, time: nil)
                    }
                    // Room under the track for the flames to rise into.
                    .padding(.bottom, 28)
                } else {
                    Text("当前仅可选择 23:59，请使用时间选择器确认。")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func composeDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar(identifier: .iso8601)
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }
}

// MARK: - Kill Time Flame

/// Positions the card needs to shape the flames: the slider (its track is the
/// ceiling on the left) and the big time text (open space to its right lets
/// the flames climb higher).
struct KillTimeLayoutAnchors {
    var slider: Anchor<CGRect>?
    var time: Anchor<CGRect>?

}

struct KillTimeLayoutAnchorKey: PreferenceKey {
    static var defaultValue = KillTimeLayoutAnchors()
    static func reduce(value: inout KillTimeLayoutAnchors, nextValue: () -> KillTimeLayoutAnchors) {
        let next = nextValue()
        value.slider = value.slider ?? next.slider
        value.time = value.time ?? next.time
    }
}

/// Where the flames may reach, in points above the card's bottom edge.
struct KillTimeFlameCeiling: Equatable {
    /// Ceiling over the big time (left): a little above the slider track.
    var left: CGFloat
    /// Ceiling in the open space to the right: up to the top of the time row.
    var right: CGFloat
    /// Fraction of the width where the time text ends; the ceiling rises after it.
    var transition: CGFloat
}

/// A preview of deadline pressure, never a source of cutoff state.
struct KillTimeFlameBackground: View {
    let hour: Int
    let minute: Int
    let isAnimating: Bool
    var ceiling: KillTimeFlameCeiling? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.weekyiiReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    static func intensity(remainingMinutes: Double) -> Double {
        // No three-hour dead zone: moving any same-day cutoff earlier adds
        // pressure. Three hours is the decay scale, not a visibility switch.
        exp(-max(0, remainingMinutes) / 180)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 15, paused: scenePhase != .active)) { context in
            let remaining = killDate(on: context.date).timeIntervalSince(context.date) / 60
            KillTimeFlameLayer(
                intensity: Self.intensity(remainingMinutes: remaining),
                isAnimating: isAnimating && scenePhase == .active && !reduceMotion && !systemReduceMotion,
                ceiling: ceiling
            )
            // Direct manipulation must not inherit a parent's card transition.
            .transaction { $0.animation = nil }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func killDate(on date: Date) -> Date {
        let calendar = Calendar(identifier: .iso8601)
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? date
    }
}

/// Accumulates only visible running time. Pausing never replaces the phase
/// with zero, and resuming never jumps forward by the time spent off-screen.
struct KillTimeFireClock {
    private var elapsed: TimeInterval = 0
    private var resumedAt: Date?

    func time(at date: Date) -> TimeInterval {
        elapsed + (resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    mutating func setRunning(_ running: Bool, at date: Date) {
        if running, resumedAt == nil {
            resumedAt = date
        } else if !running, resumedAt != nil {
            elapsed = time(at: date)
            resumedAt = nil
        }
    }
}

/// Pure geometry shared by live drawing and rendering tests. Tongues have
/// independent lifecycles; intensity never changes their phase or identity.
enum KillTimeFireField {
    enum Plane: Int, CaseIterable {
        case outer, middle, core

        var heightScale: CGFloat {
            switch self {
            case .outer: return 1
            case .middle: return 0.76
            case .core: return 0.46
            }
        }

        var spacing: CGFloat {
            switch self {
            case .outer: return 34
            case .middle: return 30
            case .core: return 28
            }
        }
    }

    /// One slow material motion clock for tongues, curl and rising embers.
    static let motionRate = 0.28

    struct Tongue: Equatable {
        let root: CGPoint
        let height: CGFloat
        let halfWidth: CGFloat
        let lean: CGFloat
        let curl: CGFloat
        let life: Double
    }

    static func ceiling(at x: CGFloat, size: CGSize, profile: KillTimeFlameCeiling?) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        let profile = profile ?? KillTimeFlameCeiling(left: size.height * 0.45, right: size.height * 0.7, transition: 0.45)
        let start = min(max(profile.transition, 0), 0.95)
        let p = min(max((x / size.width - start) / max(1 - start, 0.05), 0), 1)
        let eased = p * p * (3 - 2 * p)
        return min(max(profile.left + (profile.right - profile.left) * eased, 0), size.height)
    }

    static func tongues(size: CGSize, time: TimeInterval, intensity: Double, ceiling profile: KillTimeFlameCeiling?, plane: Plane = .outer) -> [Tongue] {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return [] }
        let pressure = min(max(intensity, 0), 1)
        let t = time * motionRate
        let depth = Double(plane.rawValue)
        let count = max(7, min(24, Int(size.width / plane.spacing)))
        let spacing = size.width / CGFloat(count)
        return (0..<count).map { index in
            let seed = Double(index)
            let phase = seed * 2.399963 + depth * 1.17
            let cycle = t / (1.65 + 0.65 * (0.5 + 0.5 * sin(seed * 7.13))) + seed * 0.618034 + depth * 0.31
            let life = cycle - floor(cycle)
            // A tongue grows, curls as it rises, then contracts into the bed.
            let envelope = pow(max(0, sin(.pi * life)), 0.7)
            let x = min(max((CGFloat(index) + 0.5) * spacing + sin(phase) * spacing * 0.18, 0), size.width)
            let limit = ceiling(at: x, size: size, profile: profile)
            let variation = 0.64 + 0.36 * (0.5 + 0.5 * sin(seed * 4.71))
            let height = limit * (0.035 + 0.90 * pressure) * variation * (0.28 + 0.72 * envelope) * plane.heightScale
            return Tongue(
                root: CGPoint(x: x, y: size.height + 2),
                height: height,
                halfWidth: min(spacing * (0.52 + 0.40 * pressure), height * 0.64),
                lean: sin(t * 1.7 + phase) * height * 0.13,
                curl: sin(t * 2.3 + phase + life * 2) * height * 0.19,
                life: life
            )
        }
    }
}

/// Theme-aware ink colors; no generic RGB fire pasted over the app's palette.
struct KillTimeFirePalette {
    let outer: Color
    let body: Color
    let core: Color
    let opacity: Double
    let shadow: Color
    let shadowOpacity: Double

    init(theme: WeekTheme, isDark: Bool) {
        let palette = theme.palette(for: isDark ? .dark : .light, systemIsDark: isDark)
        let surface = Color(hex: palette.backgroundSecondary)
        // Opaque tonal surfaces keep the three materials legible, rather than
        // washing together as three transparent copies of the same shape.
        outer = Color(hex: palette.taskDDL).mix(with: surface, by: isDark ? 0.34 : 0.30)
        body = Color(hex: palette.accentOrange).mix(with: surface, by: isDark ? 0.10 : 0.08)
        core = Color(hex: palette.accentOrangeLight).mix(with: .white, by: isDark ? 0.08 : 0.20)
        shadow = Color(hex: palette.primaryDark).mix(with: .black, by: 0.65)
        shadowOpacity = theme == .terminal ? 0 : (isDark ? 0.28 : 0.14)
        opacity = isDark ? 0.64 : 0.82
    }
}

private struct KillTimeFlameLayer: View {
    let intensity: Double
    let isAnimating: Bool
    let ceiling: KillTimeFlameCeiling?
    @Environment(\.colorScheme) private var colorScheme
    @State private var clock = KillTimeFireClock()
    @State private var isVisible = true

    private var shouldAnimate: Bool { isAnimating && isVisible }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shouldAnimate)) { context in
            KillTimeFireCanvas(
                intensity: intensity,
                time: clock.time(at: context.date),
                ceiling: ceiling,
                palette: KillTimeFirePalette(theme: WeekTheme.activeTheme, isDark: colorScheme == .dark)
            )
        }
        .onAppear { clock.setRunning(shouldAnimate, at: .now) }
        .onScrollVisibilityChange(threshold: 0.05) { isVisible = $0 }
        .onChange(of: shouldAnimate) { _, running in clock.setRunning(running, at: .now) }
        .onDisappear { clock.setRunning(false, at: .now) }
    }
}

/// Kept separate from the clock so QA can render exact phases and pressures.
struct KillTimeFireCanvas: View {
    let intensity: Double
    let time: TimeInterval
    let ceiling: KillTimeFlameCeiling?
    let palette: KillTimeFirePalette

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let pressure = min(max(intensity, 0), 1)
            // Each plane is an independent connected material surface, with
            // its own spacing and phase. Front planes occlude the rear ones.
            for plane in KillTimeFireField.Plane.allCases {
                let tongues = KillTimeFireField.tongues(size: size, time: time, intensity: pressure, ceiling: ceiling, plane: plane)
                let bedHeight = min(size.height * 0.12, 2 + pressure * 8) * plane.heightScale
                var silhouette = Path(CGRect(x: 0, y: size.height - bedHeight, width: size.width, height: bedHeight + 2))
                for tongue in tongues {
                    silhouette.addPath(flame(tongue))
                }
                let color = plane == .outer ? palette.outer : (plane == .middle ? palette.body : palette.core)
                context.drawLayer { material in
                    if plane != .outer {
                        material.addFilter(.shadow(
                            color: palette.shadow.opacity(palette.shadowOpacity),
                            radius: plane == .middle ? 2 : 1.2,
                            x: 0, y: -1
                        ))
                    }
                    material.fill(silhouette, with: .color(color))
                }
                context.stroke(silhouette, with: .color(palette.core.opacity(0.20)), lineWidth: 0.5)
            }

            // A handful of short-lived embers move upward, never sideways
            // across the time text. Their phase also stays stable while dragging.
            for index in 0..<7 {
                let seed = Double(index)
                let t = time * KillTimeFireField.motionRate
                let cycle = t / (2.4 + seed * 0.13) + seed * 0.618034
                let life = cycle - floor(cycle)
                let x = size.width * (0.08 + 0.84 * CGFloat((sin(seed * 8.1) + 1) / 2))
                let limit = KillTimeFireField.ceiling(at: x, size: size, profile: ceiling)
                let rise = limit * CGFloat(life) * (0.15 + pressure * 0.8)
                let alpha = pow(sin(.pi * life), 2) * pressure * pressure * palette.opacity
                let width: CGFloat = 1 + pressure * 0.8
                let rect = CGRect(x: x + sin(t + seed) * 3, y: size.height - rise, width: width, height: width * 2.4)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(palette.body.opacity(alpha)))
            }
        }
        .mask(alignment: .bottom) {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.28),
                .init(color: .black.opacity(0.35), location: 0.5),
                .init(color: .black, location: 0.76),
                .init(color: .black, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func flame(_ tongue: KillTimeFireField.Tongue) -> Path {
        let h = tongue.height
        let w = tongue.halfWidth
        let x = tongue.root.x
        let y = tongue.root.y
        let lean = tongue.lean
        let curl = tongue.curl
        let tip = CGPoint(x: x + lean + curl, y: y - h)
        var path = Path()
        path.move(to: CGPoint(x: x - w, y: y))
        path.addCurve(to: tip,
                      control1: CGPoint(x: x - w * 1.30, y: y - h * 0.38),
                      control2: CGPoint(x: x + lean - w * 0.62, y: y - h * 0.55))
        // Unequal shoulders and a bent tip give a flame, not a teardrop.
        path.addCurve(to: CGPoint(x: x + w, y: y),
                      control1: CGPoint(x: x + lean + curl * 0.2 + w * 0.1, y: y - h * 0.66),
                      control2: CGPoint(x: x + w * 1.32, y: y - h * 0.26))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    WeekCard {
        KillTimeEditor(
            hour: 20,
            minute: 30,
            isEditable: true,
            onChange: { _, _ in }
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}
