import SwiftUI

enum KillTimeDeadline {
    static func date(
        for day: Date,
        hour: Int,
        minute: Int,
        timeZone: TimeZone = .current
    ) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.nanosecond = 0

        guard let deadline = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: deadline)
        guard resolved.hour == hour,
              resolved.minute == minute,
              (resolved.second ?? 0) == 0,
              (resolved.nanosecond ?? 0) == 0 else {
            return nil
        }
        return deadline
    }

    static func remainingMinutes(until deadline: Date, at now: Date) -> Double {
        deadline.timeIntervalSince(now) / 60
    }
}

// MARK: - KillTimeEditor

struct KillTimeEditor: View {
    let dayDate: Date
    let hour: Int
    let minute: Int
    let isEditable: Bool
    /// Keep the saved cutoff in the range while its preview changes.
    var rangeAnchorMinutes: Int? = nil
    let onChange: (Int, Int) -> Void
    var onEditingChanged: ((Bool) -> Void)? = nil

    // MARK: - Computed Properties

    /// 当前时间 + 1 小时，作为滑动条可选下界（最大不超过 23:59）
    private func minTimeInMinutes(at now: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        return min((c.hour ?? 0) * 60 + (c.minute ?? 0) + 60, endOfDayInMinutes)
    }

    private let endOfDayInMinutes: Int = 23 * 60 + 59

    private var clampedSelectedTimeInMinutes: Int {
        min(max(hour * 60 + minute, 0), endOfDayInMinutes)
    }

    /// 允许历史旧值低于当前 minTime，避免已设定的时间在展示时被强制上移
    private func sliderLowerBound(at now: Date) -> Double {
        Double(min(minTimeInMinutes(at: now), min(rangeAnchorMinutes ?? clampedSelectedTimeInMinutes, clampedSelectedTimeInMinutes)))
    }

    // MARK: - Body

    var body: some View {
        // 左端点 = 手机当前时间 + 1 小时，需要随时间前进；每分钟重算一次，
        // 滑动条下界与火焰使用的区间因此保持实时。拖动中滑动条自己会冻结下界。
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let sliderBounds = sliderLowerBound(at: now)...Double(endOfDayInMinutes)
        let selectableRange = deadlineRange(for: sliderBounds)
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            // 时间显示：点按大号时间即可用系统选择器精确输入
            Text(String(format: "%02d:%02d", hour, minute))
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundColor(.textPrimary)
                .monospacedDigit()
                .accessibilityIdentifier("killTimeDisplay")
                .anchorPreference(key: KillTimeLayoutAnchorKey.self, value: .bounds) {
                    // The range rides on the always-present time text, so the
                    // flames still know it when the slider collapses to 23:59.
                    KillTimeLayoutAnchors(slider: nil, time: $0, selectableRange: isEditable ? selectableRange : nil)
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
                if sliderBounds.lowerBound < sliderBounds.upperBound {
                    KillTimeSlider(
                        value: Double(clampedSelectedTimeInMinutes),
                        lowerBound: sliderBounds.lowerBound,
                        upperBound: sliderBounds.upperBound,
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

    /// Absolute dates of the slider's two ends. A collapsed range (both ends at
    /// 23:59) is still returned, so the flames can burn fully in the last hour.
    private func deadlineRange(for minutes: ClosedRange<Double>) -> ClosedRange<Date>? {
        let lower = Int(minutes.lowerBound)
        let upper = Int(minutes.upperBound)
        guard let start = KillTimeDeadline.date(for: dayDate, hour: lower / 60, minute: lower % 60),
              let end = KillTimeDeadline.date(for: dayDate, hour: upper / 60, minute: upper % 60),
              start <= end else { return nil }
        return start...end
    }

    private func composeDate(hour: Int, minute: Int) -> Date {
        KillTimeDeadline.date(for: dayDate, hour: hour, minute: minute) ?? dayDate
    }
}

// MARK: - Kill Time Flame

/// The slider is the normal fire's height reference. The time text defines
/// the extra space urgent flames can occupy without obscuring the time.
struct KillTimeLayoutAnchors {
    var slider: Anchor<CGRect>?
    var time: Anchor<CGRect>?
    var selectableRange: ClosedRange<Date>? = nil
}

struct KillTimeLayoutAnchorKey: PreferenceKey {
    static var defaultValue = KillTimeLayoutAnchors()
    static func reduce(value: inout KillTimeLayoutAnchors, nextValue: () -> KillTimeLayoutAnchors) {
        let next = nextValue()
        value.slider = value.slider ?? next.slider
        value.time = value.time ?? next.time
        value.selectableRange = value.selectableRange ?? next.selectableRange
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
    /// Actual distance from the bottom of the flame canvas to the slider.
    /// Separate from the text-protecting ceiling so normal flames stay below it.
    var trackHeight: CGFloat? = nil
}

/// A preview of deadline pressure, never a source of cutoff state.
struct KillTimeFlameBackground: View {
    let deadline: Date
    let animationsActive: Bool
    var ceiling: KillTimeFlameCeiling? = nil
    var selectableRange: ClosedRange<Date>? = nil

    static func intensity(remainingMinutes: Double) -> Double {
        // Steep squared-exponential: nearly invisible until ~2 hours,
        // then accelerates sharply. Fire truly ignites when it matters.
        let t = max(0, remainingMinutes)
        let linear = exp(-t / 120)
        return linear * linear   // squaring steepens the onset dramatically
    }

    /// Fire shown at the latest selectable cutoff (23:59): small but visible.
    nonisolated static let minimumVisualIntensity = 0.15

    /// Fire strength follows the cutoff's position between the slider's two
    /// ends, not an absolute countdown:
    /// - the earliest end (now + 1 hour, or an earlier saved cutoff) burns fully;
    /// - the latest end (23:59) keeps a small flame (`minimumVisualIntensity`);
    /// - everything in between changes uniformly (linear).
    /// The editor refreshes the earliest end as the phone's clock moves, so the
    /// range keeps shrinking through the day and the same cutoff burns harder.
    static func visualIntensity(deadline: Date, at now: Date, selectableRange: ClosedRange<Date>? = nil) -> Double {
        guard let selectableRange else {
            // No range from the editor: fall back to the countdown curve,
            // normalised so 90 minutes or less burns fully.
            let remaining = KillTimeDeadline.remainingMinutes(until: deadline, at: now)
            let reference = intensity(remainingMinutes: 90)
            return min(intensity(remainingMinutes: remaining) / max(reference, 1e-9), 1)
        }
        // Already past the cutoff: full fire.
        guard deadline > now else { return 1 }
        let span = selectableRange.upperBound.timeIntervalSince(selectableRange.lowerBound)
        // Collapsed range (last hour of the day): nothing later to choose, full fire.
        guard span > 0 else { return 1 }
        let position = min(max(deadline.timeIntervalSince(selectableRange.lowerBound) / span, 0), 1)
        return minimumVisualIntensity + (1 - minimumVisualIntensity) * (1 - position)
    }

    var body: some View {
        KillTimeFlameLayer(
            deadline: deadline,
            animationsActive: animationsActive,
            ceiling: ceiling,
            selectableRange: selectableRange
        )
        // Direct manipulation must not inherit a parent's card transition.
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// Pure geometry shared by live drawing and rendering. Every tongue keeps a
/// deterministic identity; layered waves, value noise and an independent life
/// cycle continuously reshape its height, spine and tip.
enum KillTimeFireField {
    enum Plane: Int, CaseIterable {
        case outer, middle, core

        var heightScale: CGFloat {
            switch self {
            case .outer: return 1
            case .middle: return 0.68
            case .core: return 0.34
            }
        }

        var motionScale: Double {
            switch self {
            case .outer: return 1
            case .middle: return 0.72
            case .core: return 0.48
            }
        }

        var widthScale: Double {
            switch self {
            case .outer: return 1
            case .middle: return 0.58
            // A core is a nested heat column, not a straw: wide enough to read
            // as the hot interior of its own outer lick.
            case .core: return 0.45
            }
        }
    }

    /// Slightly slower material clock — fire feels heavier, more viscous.
    static let motionRate = 0.22

    /// Urgency now kicks in faster: exponent 1.8 instead of 2.2, so the fire
    /// starts crossing the track sooner and feels more threatening.
    static func urgencyBoost(_ intensity: Double) -> Double {
        pow(min(max(intensity, 0), 1), 1.8)
    }

    /// A lick is born at zero, rises to peak, then dies back to zero.
    /// No floor — tongues truly extinguish and reappear, giving organic breathing.
    static func lifeEnvelope(_ life: Double) -> Double {
        let rise = smoothstep(life / 0.28)
        let fall = 1 - smoothstep((life - 0.68) / 0.32)
        return min(rise, fall)   // true zero at endpoints
    }

    private static func smoothstep(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return v * v * (3 - 2 * v)
    }

    struct Tongue: Equatable {
        let root: CGPoint
        let height: CGFloat
        let halfWidth: CGFloat
        let lean: CGFloat
        let curl: CGFloat
        let life: Double
        /// 0 = rounded tip; >0 splits the tip into two prongs. Only strong
        /// licks fork, so the field keeps a mix of wisps and split flames.
        let fork: CGFloat
        /// Higher = the lick stays narrow longer before flaring outward.
        let waist: CGFloat
        /// -1..1: left/right asymmetry of the silhouette.
        let belly: CGFloat
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
        let surge = urgencyBoost(pressure)
        let agitation = 0.30 * pressure + 0.70 * surge
        let trackHeight = min(max(profile?.trackHeight ?? size.height * 0.32, 0), size.height)
        let crossingProgress = min(max((surge - 0.18) / 0.82, 0), 1)
        let crossing = crossingProgress * crossingProgress * (3 - 2 * crossingProgress)
        // Denser tongues — spacing 14pt — so they overlap and merge into a
        // continuous organic mass rather than a comb of separate spikes.
        let count = min(max(Int(size.width / 14), 20), 48)
        let spacing = size.width / CGFloat(count)
        let centerA = 0.5 + 0.42 * sin(t * 0.61)
        let centerB = 0.5 + 0.42 * cos(t * 0.43 + 1.9)
        return (0..<count).compactMap { index -> Tongue? in
            // Inner heat lives inside selected outer licks, rather than
            // forming unrelated rows of orange and yellow peaks.
            if plane == .middle, index % 3 == 1 { return nil }
            if plane == .core, index % 3 != 0 { return nil }
            let anchorOffset = (seededUnit(index, plane: .outer, channel: 3) - 0.5) * 0.66
            let phase = seededUnit(index, plane: plane, channel: 0) * 2 * .pi
            let detailPhase = seededUnit(index, plane: plane, channel: 1) * 2 * .pi
            let tipPhase = seededUnit(index, plane: plane, channel: 2) * 2 * .pi
            let heightTrait = 0.78 + seededUnit(index, plane: plane, channel: 4) * 0.44
            // Wide band: fat blazes remain fat, thin wisps remain wispy.
            let widthTrait = 0.65 + seededUnit(index, plane: plane, channel: 5) * 1.10
            let individualRate = 0.85 + seededUnit(index, plane: plane, channel: 6) * 0.85
            let bendBias = seededUnit(index, plane: plane, channel: 7) * 2 - 1
            let forkTrait = seededUnit(index, plane: plane, channel: 8)
            let waist = 0.45 + seededUnit(index, plane: plane, channel: 9) * 0.30
            let belly = seededUnit(index, plane: plane, channel: 10) * 2 - 1
            let lifeTrait = 0.80 + seededUnit(index, plane: plane, channel: 11) * 0.40
            let noise = noiseSeed(index: index, plane: plane)

            let x = min(max((CGFloat(index) + 0.5 + CGFloat(anchorOffset)) * spacing, 0), size.width)
            let limit = ceiling(at: x, size: size, profile: profile)
            let mediumPhase = t * individualRate * 1.8 + phase
            let mediumWave = 0.52 * sin(mediumPhase)
                + 0.31 * sin(mediumPhase * 1.73 + detailPhase)
                + 0.17 * sin(mediumPhase * 2.41 + tipPhase)
            let breath = sin(t * 0.42 + phase * 0.23 + depth * 0.7)
            let position = Double(x / size.width)
            let distanceA = (position - centerA) / 0.17
            let distanceB = (position - centerB) / 0.30
            let localEnergy = 0.60 * exp(-0.5 * distanceA * distanceA)
                + 0.40 * exp(-0.5 * distanceB * distanceB)
            let pulsePosition = (sin(mediumPhase * 0.83) + 0.35 * sin(mediumPhase * 1.41 + detailPhase)) / 0.60
            let pulse = exp(-0.5 * pulsePosition * pulsePosition)
            // Raised base fraction: pow(0.65) instead of pow(0.8) means fire
            // reaches half-height at lower pressure — more visible ignition.
            let normalFraction = 0.88 * pow(pressure, 0.65)
                + pressure * ((0.08 + 0.10 * pressure) * (pulse - 0.5)
                    + 0.03 * mediumWave + 0.015 * breath)
            let normalHeight = trackHeight * CGFloat(normalFraction)
            let urgentHeight = min(limit, trackHeight * 1.70) * CGFloat(0.88 + 0.12 * pulse + 0.025 * mediumWave)
            let blendedHeight = normalHeight + (urgentHeight - normalHeight) * CGFloat(surge)
            let normalCeiling = trackHeight * 0.96
            let activeCeiling = min(limit * 0.98, normalCeiling + (limit * 0.98 - normalCeiling) * CGFloat(crossing))
            let lifeCycle = t * (0.38 * lifeTrait) + phase / (2 * .pi) + depth * 0.13
            let life = lifeCycle - floor(lifeCycle)
            let envelope = lifeEnvelope(life)
            let centered = 2 * position - 1
            let edgeFalloff = 1 - 0.32 * centered * centered
            let mass = (0.60 + 0.80 * localEnergy) * edgeFalloff
            let heightNoise = (fbmNoise(seed: noise, t * 0.42 * individualRate) - 0.5) * 2
            let heightMultiplier = 1 + (0.20 + 0.30 * agitation) * heightNoise
            let scaled = blendedHeight * CGFloat(heightTrait * envelope * mass * heightMultiplier)
            let height = min(max(scaled, 0), activeCeiling) * plane.heightScale
            // Forks only on strong, well-developed licks.
            let fork = forkTrait > 0.42 && envelope > 0.55
                ? max(0, (forkTrait - 0.42) / 0.58) * (0.40 + 0.60 * pressure)
                : 0

            let movingPhase = t * individualRate * 2.2 + phase
            let tipFrequency = 4.1
            let middleSway = (0.85 - 0.50 * agitation) * sin(movingPhase * 0.58 + detailPhase)
                + (0.15 + 0.15 * agitation) * sin(movingPhase * 1.47 + tipPhase)
                + 0.35 * agitation * sin(movingPhase * 2.7 + phase)
            let tipFlicker = sin(movingPhase * tipFrequency + tipPhase)
            let leanMotion = middleSway * 0.78 + tipFlicker * 0.22
            let curlMotion = sin(movingPhase * 1.17 + detailPhase + depth * 0.28) * 0.80 + tipFlicker * 0.20
            let driftHeight = (fbmNoise(seed: noise &+ 0x51ED, t * 0.38 * individualRate) - 0.5) * 2
            let driftTip = (fbmNoise(seed: noise &+ 0x2F9B, t * 0.85 * individualRate) - 0.5) * 2
            let bendSource = bendBias * 0.55 + middleSway * 0.45 + driftHeight * 0.5 * (0.4 + 0.6 * agitation)
            let bend = tanh(bendSource * 2)
            let lateralScale = min(spacing * 2.8, height * 0.72) * CGFloat(plane.motionScale)
            let leanSway = -0.72 * bend + (0.04 + 0.10 * agitation) * leanMotion + 0.12 * agitation * driftHeight
            let curlSway = 1.20 * bend + (0.08 + 0.22 * agitation) * curlMotion + 0.10 * agitation * driftTip
            // Wider base so flames overlap. Cap raised to 1.4 × height.
            let widthBase = (0.70 + 0.16 * pressure + 0.60 * surge) * widthTrait * plane.widthScale * (0.50 + 0.50 * envelope)

            return Tongue(
                root: CGPoint(x: x, y: size.height + 2),
                height: height,
                // Raised overlap cap: tongues now merge into a continuous mass.
                halfWidth: min(spacing * CGFloat(widthBase), height * 1.40),
                lean: lateralScale * CGFloat(leanSway),
                curl: lateralScale * CGFloat(curlSway),
                life: life,
                fork: CGFloat(fork),
                waist: CGFloat(waist),
                belly: CGFloat(belly)
            )
        }
    }


    private static func seededUnit(_ index: Int, plane: Plane, channel: UInt64) -> Double {
        var value = UInt64(index + 1)
        value = value &+ UInt64(plane.rawValue + 1) &* 0x9E3779B97F4A7C15
        value = value &+ (channel &* 0xD1B54A32D192ED03)
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    private static func noiseSeed(index: Int, plane: Plane) -> UInt64 {
        UInt64(index + 1) &* 0x9E3779B97F4A7C15
            &+ UInt64(plane.rawValue + 1) &* 0xC2B2AE3D27D4EB4F
            &+ 0x5163
    }

    private static func hashUnit(_ seed: UInt64) -> Double {
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Deterministic value noise on a hash lattice: same seed and time always
    /// produce the same perturbation, so the fire never reseeds mid-drag, and
    /// the lattice spacing keeps the wander far slower than a flicker.
    private static func valueNoise(seed: UInt64, _ x: Double) -> Double {
        let position = max(x, 0)
        let base = Int64(position.rounded(.down))
        let fraction = position - Double(base)
        let cell = UInt64(bitPattern: base)
        let a = hashUnit(seed &+ cell &* 0x9E3779B97F4A7C15 &+ 0x165667B19E3779F9)
        let b = hashUnit(seed &+ (cell &+ 1) &* 0x9E3779B97F4A7C15 &+ 0x165667B19E3779F9)
        let blend = fraction * fraction * (3 - 2 * fraction)
        return a + (b - a) * blend
    }

    private static func fbmNoise(seed: UInt64, _ x: Double) -> Double {
        0.68 * valueNoise(seed: seed, x) + 0.32 * valueNoise(seed: seed &+ 0x27220A95, x * 2.7)
    }

    /// Builds one lick as a tapered ribbon along a curved spine. `lean` bends
    /// the lower body and `curl` keeps bending it toward the tip, so the whole
    /// silhouette curves instead of the tip being yanked sideways. Strong
    /// licks carry a forked tip: two prongs around a shallow notch.
    static func flamePath(_ tongue: Tongue) -> Path {
        let h = tongue.height
        let w = tongue.halfWidth
        let x = tongue.root.x
        let y = tongue.root.y
        let lean = tongue.lean
        let curl = tongue.curl
        guard h > 0.5, w > 0.5 else { return Path() }
        let tip = CGPoint(x: x + lean + curl, y: y - h)
        let control1 = CGPoint(x: x + lean * 0.30 + curl * 0.06, y: y - h * 0.32)
        let control2 = CGPoint(x: x + lean * 0.72 + curl * 0.42, y: y - h * 0.72)

        func spine(_ u: CGFloat) -> CGPoint {
            let v = 1 - u
            let w0 = v * v * v
            let w1 = 3 * v * v * u
            let w2 = 3 * v * u * u
            let w3 = u * u * u
            return CGPoint(
                x: w0 * x + w1 * control1.x + w2 * control2.x + w3 * tip.x,
                y: w0 * y + w1 * control1.y + w2 * control2.y + w3 * tip.y
            )
        }

        func tangent(_ u: CGFloat) -> CGPoint {
            let v = 1 - u
            let d1 = 3 * v * v
            let d2 = 6 * v * u
            let d3 = 3 * u * u
            let dx = d1 * (control1.x - x) + d2 * (control2.x - control1.x) + d3 * (tip.x - control2.x)
            let dy = d1 * (control1.y - y) + d2 * (control2.y - control1.y) + d3 * (tip.y - control2.y)
            let length = hypot(dx, dy)
            guard length > 0.0001 else { return CGPoint(x: 0, y: -1) }
            return CGPoint(x: dx / length, y: dy / length)
        }

        // Gourd profile: fat base, pronounced waist pinch, wispy tip.
        // Real flames billow outward near the fuel bed and neck sharply
        // before dissolving into thin licks — never a uniform teardrop.
        func widthAt(_ u: CGFloat) -> CGFloat {
            // Broad base that widens slightly before the waist.
            let baseFlare = pow(max(0, 1 - u), 0.38 + 0.30 * tongue.waist) * (1 + 0.15 * max(0, 1 - u * 3))
            // Sharp pinch at waist then rapid taper — the neck of the gourd.
            let waistU = 0.50 + 0.10 * tongue.waist
            let pinchDepth: CGFloat = 0.25
            let neckGauss = exp(-pow((u - waistU) / 0.15, 2))
            let taper = 1 - (0.72 + pinchDepth * neckGauss) * pow(max(0, u), 1.05 + 0.70 * tongue.waist)
            return w * max(baseFlare * max(taper, 0), 0)
        }

        let samples: [CGFloat] = [0, 0.16, 0.34, 0.54, 0.72, 0.86]
        let bellyLeft = 1 + 0.3 * tongue.belly
        let bellyRight = 1 - 0.3 * tongue.belly
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for u in samples {
            let p = spine(u)
            let n = tangent(u)
            let normal = CGPoint(x: -n.y, y: n.x)
            let half = widthAt(u)
            left.append(CGPoint(x: p.x - normal.x * half * bellyLeft, y: p.y - normal.y * half * bellyLeft))
            right.append(CGPoint(x: p.x + normal.x * half * bellyRight, y: p.y + normal.y * half * bellyRight))
        }

        var path = Path()
        path.move(to: left[0])
        addSmoothCurve(to: &path, through: left)

        if tongue.fork > 0.01 {
            let s = spine(0.86)
            let n = tangent(0.86)
            let normal = CGPoint(x: -n.y, y: n.x)
            let prong = h * 0.14 * (0.4 + tongue.fork)
            let spread = widthAt(0.86) * 0.6 * tongue.fork + 1
            let tipA = CGPoint(x: s.x + n.x * prong - normal.x * spread, y: s.y + n.y * prong - normal.y * spread)
            let tipB = CGPoint(x: s.x + n.x * prong + normal.x * spread, y: s.y + n.y * prong + normal.y * spread)
            let notch = CGPoint(x: s.x - n.x * prong * 0.30, y: s.y - n.y * prong * 0.30)
            let controlA = CGPoint(
                x: left[5].x + n.x * prong * 0.7 - normal.x * spread * 0.8,
                y: left[5].y + n.y * prong * 0.7 - normal.y * spread * 0.8
            )
            let controlNotchA = CGPoint(
                x: tipA.x - n.x * prong * 0.35 + normal.x * (spread * 0.3 + 0.5),
                y: tipA.y - n.y * prong * 0.35 + normal.y * (spread * 0.3 + 0.5)
            )
            let controlNotchB = CGPoint(
                x: tipB.x - n.x * prong * 0.35 - normal.x * (spread * 0.3 + 0.5),
                y: tipB.y - n.y * prong * 0.35 - normal.y * (spread * 0.3 + 0.5)
            )
            let controlB = CGPoint(
                x: right[5].x + n.x * prong * 0.7 + normal.x * spread * 0.8,
                y: right[5].y + n.y * prong * 0.7 + normal.y * spread * 0.8
            )
            path.addQuadCurve(to: tipA, control: controlA)
            path.addQuadCurve(to: notch, control: controlNotchA)
            path.addQuadCurve(to: tipB, control: controlNotchB)
            path.addQuadCurve(to: right[5], control: controlB)
            addSmoothCurve(to: &path, through: [right[5]] + right[0..<5].reversed())
        } else {
            let p = spine(0.97)
            let n = tangent(0.97)
            let normal = CGPoint(x: -n.y, y: n.x)
            let halfTip = widthAt(0.97)
            let leftTip = CGPoint(x: p.x - normal.x * halfTip * bellyLeft, y: p.y - normal.y * halfTip * bellyLeft)
            let rightTip = CGPoint(x: p.x + normal.x * halfTip * bellyRight, y: p.y + normal.y * halfTip * bellyRight)
            let cap = min(w * 0.12, h * 0.03)
            let controlLeftTip = CGPoint(x: tip.x + n.x * cap - normal.x * cap * 0.4, y: tip.y + n.y * cap - normal.y * cap * 0.4)
            let controlRightTip = CGPoint(x: tip.x + n.x * cap, y: tip.y + n.y * cap)
            path.addQuadCurve(to: leftTip, control: controlLeftTip)
            path.addQuadCurve(to: rightTip, control: controlRightTip)
            addSmoothCurve(to: &path, through: [rightTip] + right[0..<5].reversed())
        }
        path.addLine(to: left[0])
        path.closeSubpath()
        return path
    }

    /// Catmull-Rom through the sampled outline, emitted as cubic segments.
    private static func addSmoothCurve(to path: inout Path, through points: [CGPoint]) {
        guard points.count > 1 else { return }
        for i in 0..<(points.count - 1) {
            let previous = points[max(i - 1, 0)]
            let current = points[i]
            let next = points[i + 1]
            let following = points[min(i + 2, points.count - 1)]
            path.addCurve(
                to: next,
                control1: CGPoint(x: current.x + (next.x - previous.x) / 6, y: current.y + (next.y - previous.y) / 6),
                control2: CGPoint(x: next.x - (following.x - current.x) / 6, y: next.y - (following.y - current.y) / 6)
            )
        }
    }
}

/// Four-temperature thermal ramp: deep red glow → saturated orange → amber body → white-hot core.
/// Glow is a diffuse bloom pass; the three named planes are sharp silhouette fills.
struct KillTimeFirePalette {
    /// Deep saturated red: the outermost diffuse bloom / haze layer.
    let glow: Color
    /// Saturated orange: outer silhouette flame tips.
    let outer: Color
    /// Rich amber: mid-body silhouette.
    let body: Color
    /// Near-white yellow: white-hot core column.
    let core: Color
    /// Hot orange for the glowing bed at the base of the outer plane.
    let outerBase: Color
    /// Amber for the bed of the body plane.
    let bodyBase: Color
    /// Pale cream for the bed of the core plane.
    let coreBase: Color
    /// Bright ember spark color.
    let ember: Color
    /// Overall silhouette opacity — raised to make fire genuinely visible.
    let opacity: Double

    init(theme: WeekTheme, isDark: Bool) {
        if theme == .lotr {
            // 红皮书: a candle and a hearth, not a blowtorch. Burnt umber and
            // vermilion ink, kept below the page's gilt so it no longer is the
            // loudest colour on the page.
            glow      = Color(hex: isDark ? "6E2410" : "8A3A1E")
            outer     = Color(hex: isDark ? "A33A18" : "A8452A")
            body      = Color(hex: isDark ? "C26A2C" : "BF7440")
            core      = Color(hex: isDark ? "E3BE78" : "E2C48C")
            outerBase = Color(hex: isDark ? "9A4420" : "9E4E2C")
            bodyBase  = Color(hex: isDark ? "C08A44" : "C49258")
            coreBase  = Color(hex: isDark ? "EBD6A2" : "EEDDB4")
            ember     = Color(hex: isDark ? "D49A52" : "C98E4E")
            opacity   = isDark ? 0.74 : 0.58
            return
        }
        glow      = Color(hex: isDark ? "C03010" : "CC3A10")
        outer     = Color(hex: isDark ? "F04010" : "F25220")
        body      = Color(hex: isDark ? "FF8018" : "FF8C22")
        core      = Color(hex: isDark ? "FFD060" : "FFDC78")
        outerBase = Color(hex: isDark ? "FF6020" : "FF6828")
        bodyBase  = Color(hex: isDark ? "FFB030" : "FFBA40")
        coreBase  = Color(hex: isDark ? "FFF0B0" : "FFF4C0")
        ember     = Color(hex: isDark ? "FFB840" : "FFC048")
        opacity   = isDark ? 0.96 : 1.00
    }
}


private struct KillTimeFlameInput: Equatable {
    let deadline: Date
    let selectableRange: ClosedRange<Date>?
}

private struct KillTimeFlameLayer: View {
    let deadline: Date
    let animationsActive: Bool
    let ceiling: KillTimeFlameCeiling?
    let selectableRange: ClosedRange<Date>?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.weekyiiReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = KillTimeFireClock()
    @State private var isVisible = false
    @State private var pressureOrigin: Double?
    @State private var pressureChangedAt: TimeInterval = 0

    private var input: KillTimeFlameInput {
        KillTimeFlameInput(deadline: deadline, selectableRange: selectableRange)
    }

    private var shouldAnimate: Bool {
        animationsActive
            && scenePhase == .active
            && !systemReduceMotion
            && !reduceMotion
            && isVisible
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shouldAnimate)) { context in
            let pressure = KillTimeFlameBackground.visualIntensity(deadline: deadline, at: context.date, selectableRange: selectableRange)
            let animationTime = clock.time(at: context.date)
            KillTimeFireCanvas(
                intensity: easedPressure(target: pressure, time: animationTime),
                time: animationTime,
                ceiling: ceiling,
                palette: KillTimeFirePalette(theme: WeekTheme.activeTheme, isDark: colorScheme == .dark)
            )
        }
        .onAppear { clock.setRunning(shouldAnimate, at: .now) }
        .onScrollVisibilityChange(threshold: 0.05) { isVisible = $0 }
        .onChange(of: shouldAnimate) { _, running in
            clock.setRunning(running, at: .now)
            if !running { pressureOrigin = nil }
        }
        .onChange(of: input) { oldInput, _ in
            guard shouldAnimate else {
                pressureOrigin = nil
                return
            }
            let now = Date.now
            let time = clock.time(at: now)
            let previousPressure = KillTimeFlameBackground.visualIntensity(deadline: oldInput.deadline, at: now, selectableRange: oldInput.selectableRange)
            pressureOrigin = easedPressure(target: previousPressure, time: time)
            pressureChangedAt = time
        }
        .onDisappear { clock.setRunning(false, at: .now) }
    }

    private func easedPressure(target: Double, time: TimeInterval) -> Double {
        guard shouldAnimate, let pressureOrigin else { return target }
        // Analytic exponential response, sampled by the existing Timeline.
        // Retarget from the current displayed pressure during continuous drag.
        let elapsed = max(0, time - pressureChangedAt)
        return target + (pressureOrigin - target) * exp(-elapsed / 0.07)
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
            guard pressure > 0.005 else { return }

            // ── Precompute tongues ───────────────────────────────────────────
            // Outer tongues are used by both the glow bloom and the outer
            // silhouette pass, so compute them once.
            let outerTongues = KillTimeFireField.tongues(
                size: size, time: time, intensity: pressure, ceiling: ceiling, plane: .outer
            )

            // Helper: build a filled silhouette path from tongue array.
            func silhouettePath(tongues: [KillTimeFireField.Tongue], bedHeight: CGFloat, inset: CGFloat = 0) -> Path {
                var path = Path(CGRect(x: inset, y: size.height - bedHeight,
                                       width: size.width - inset * 2, height: bedHeight + 2))
                for tongue in tongues { path.addPath(KillTimeFireField.flamePath(tongue)) }
                return path
            }

            // ── Pass 0: Fuel-bed glow band ───────────────────────────────────
            // A bright horizontal band at the very bottom simulates the
            // incandescent fuel bed that anchors every real fire.
            let bedBandHeight: CGFloat = max(4, 6 + pressure * 10)
            context.drawLayer { bedCtx in
                bedCtx.addFilter(.blur(radius: bedBandHeight * 0.8))
                let bedRect = CGRect(x: -8, y: size.height - bedBandHeight * 0.6,
                                     width: size.width + 16, height: bedBandHeight)
                bedCtx.fill(
                    Path(bedRect),
                    with: .color(palette.coreBase.opacity(0.45 * pressure * palette.opacity))
                )
            }

            // ── Pass 1: Soft glow bloom ──────────────────────────────────────
            // A blurred copy of the outer silhouette with the deep-red glow
            // colour. Creates the heat-haze corona around the flame mass.
            let glowSilhouette = silhouettePath(
                tongues: outerTongues,
                bedHeight: min(size.height * 0.18, 8 + pressure * 14),
                inset: -4
            )
            context.drawLayer { glowCtx in
                glowCtx.addFilter(.blur(radius: 14 + 10 * pressure))
                glowCtx.fill(
                    glowSilhouette,
                    with: .linearGradient(
                        Gradient(colors: [
                            palette.glow.opacity(0.60 * pressure),
                            palette.outer.opacity(0.45 * pressure),
                            palette.body.opacity(0.28 * pressure)
                        ]),
                        startPoint: CGPoint(x: 0, y: size.height * 0.20),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            // ── Pass 2: Sharp silhouette planes ──────────────────────────────
            // Outer is painted normally. Middle and core use additive
            // blending (.plusLighter) so overlap areas glow hotter — the key
            // to making fire look like it has real internal temperature.
            for plane in KillTimeFireField.Plane.allCases {
                let tongues: [KillTimeFireField.Tongue]
                if plane == .outer {
                    tongues = outerTongues  // reuse cached
                } else {
                    tongues = KillTimeFireField.tongues(
                        size: size, time: time, intensity: pressure, ceiling: ceiling, plane: plane
                    )
                }
                let bedHeight = min(size.height * 0.16, 6 + pressure * 12) * plane.heightScale
                let silhouette = silhouettePath(tongues: tongues, bedHeight: bedHeight)

                let tipColor  = plane == .outer ? palette.outer : (plane == .middle ? palette.body  : palette.core)
                let midColor  = plane == .outer ? palette.body  : (plane == .middle ? palette.bodyBase : palette.coreBase)
                let baseColor = plane == .outer ? palette.outerBase : (plane == .middle ? palette.bodyBase : palette.coreBase)
                let planeAlpha = (plane == .outer ? 1.0 : (plane == .middle ? 0.88 : 0.82)) * palette.opacity

                let stops: [Gradient.Stop] = [
                    .init(color: tipColor.opacity(planeAlpha),  location: 0.00),
                    .init(color: midColor.opacity(planeAlpha),  location: 0.42),
                    .init(color: baseColor.opacity(planeAlpha), location: 1.00)
                ]
                let topY = plane == .outer
                    ? size.height * 0.20
                    : (plane == .middle ? size.height * 0.35 : size.height * 0.50)

                let gradient: GraphicsContext.Shading = .linearGradient(
                    Gradient(stops: stops),
                    startPoint: CGPoint(x: 0, y: topY),
                    endPoint: CGPoint(x: 0, y: size.height)
                )

                if plane == .outer {
                    context.fill(silhouette, with: gradient)
                } else {
                    // Additive blend: where inner planes overlap the outer,
                    // brightness adds up — creating the hot-center illusion.
                    context.drawLayer { layerCtx in
                        layerCtx.blendMode = .plusLighter
                        layerCtx.fill(silhouette, with: gradient)
                    }
                }
            }

            // ── Pass 3: Rising embers ────────────────────────────────────────
            // 16 sparks rising from the bed. Phase-stable so they don't
            // reseed mid-drag.
            for index in 0..<16 {
                let seed = Double(index)
                let t = time * KillTimeFireField.motionRate
                let period = 1.8 + seed * 0.108
                let cycle = t / period + seed * 0.618034
                let life = cycle - floor(cycle)
                let xFraction = CGFloat((sin(seed * 7.3 + 1.1) + 1) / 2)
                let x = size.width * (0.06 + 0.88 * xFraction)
                    + sin(t * 1.3 + seed) * 4
                let limit = KillTimeFireField.ceiling(at: x, size: size, profile: ceiling)
                let urgency = 0.15 * pressure + 0.85 * KillTimeFireField.urgencyBoost(pressure)
                let maxRise = limit * (0.25 + urgency * 0.75)
                let riseY = size.height - maxRise * CGFloat(life)
                let alpha = min(life * 4, 1) * max(0, 1 - (life - 0.6) / 0.4) * urgency * palette.opacity
                let width: CGFloat = max(1.2, 1.8 + pressure * 1.2)
                let driftX = x + sin(t * 2.1 + seed * 3.7) * 5 * CGFloat(life)
                let rect = CGRect(x: driftX - width / 2, y: riseY - width * 1.8,
                                  width: width, height: width * 2.2)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: width / 2),
                    with: .color(palette.ember.opacity(alpha))
                )
            }
        }
        // ── Bottom mask ───────────────────────────────────────────────────────
        .mask(alignment: .bottom) {
            let urgency = KillTimeFireField.urgencyBoost(intensity)
            LinearGradient(stops: [
                .init(color: .clear,              location: 0.00),
                .init(color: .clear,              location: max(0, 0.12 - 0.10 * urgency)),
                .init(color: .black.opacity(0.60 + 0.40 * urgency), location: 0.36),
                .init(color: .black,              location: 0.56),
                .init(color: .black,              location: 1.00)
            ], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


// MARK: - Preview

#Preview {
    WeekCard {
        KillTimeEditor(
            dayDate: Date(),
            hour: 20,
            minute: 30,
            isEditable: true,
            onChange: { _, _ in }
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}
