import SwiftUI

// MARK: - KillTimeSlider

/// 带上下刻度尺的自定义时间滑动条。
/// 刻度高度与透明度随焦点（thumb 位置）连续渐变：越近越高越深，越远越矮越淡。
struct KillTimeSlider: View {

    /// 当前值（分钟数，0…1439）
    let value: Double
    /// 可选最小值（分钟数）
    let lowerBound: Double
    /// 可选最大值（分钟数），通常为 23×60+59
    let upperBound: Double
    let onChange: (Double) -> Void
    var onEditingChanged: ((Bool) -> Void)? = nil

    // MARK: Layout

    private let thumbDiameter: CGFloat = 18
    private let trackHeight: CGFloat = 4
    private let topRulerHeight: CGFloat = 20
    private let bottomRulerHeight: CGFloat = 32   // 多留空间给时间标签

    // MARK: State

    /// 拖动开始时冻结下界，防止 lowerBound 随 value 变化而抖动
    @State private var frozenLowerBound: Double? = nil
    @State private var isDragging = false

    // MARK: Helpers

    private var effectiveLowerBound: Double {
        frozenLowerBound ?? lowerBound
    }

    private var displayValue: Double {
        let lb = effectiveLowerBound
        return min(max(value, lb), upperBound)
    }

    // MARK: Body

    var body: some View {
        GeometryReader { proxy in
            let totalWidth  = proxy.size.width
            let thumbRadius = thumbDiameter / 2
            let trackWidth  = totalWidth - thumbDiameter

            let lb    = effectiveLowerBound
            let range = max(1.0, upperBound - lb)
            let ratio = CGFloat((displayValue - lb) / range)
            let thumbCenterX = thumbRadius + ratio * trackWidth

            VStack(spacing: 0) {
                // 上方刻度尺（刻度线向下生长）
                KillTimeRuler(
                    currentMinutes: displayValue,
                    lowerBound: lb,
                    upperBound: upperBound,
                    thumbRadius: thumbRadius,
                    trackWidth: trackWidth,
                    isAbove: true
                )
                .frame(height: topRulerHeight)
                .allowsHitTesting(false)

                // 轨道 + 滑块
                trackRow(thumbCenterX: thumbCenterX, thumbRadius: thumbRadius)
                    .frame(height: thumbDiameter)

                // 下方刻度尺（刻度线向上生长 + 整点标签）
                KillTimeRuler(
                    currentMinutes: displayValue,
                    lowerBound: lb,
                    upperBound: upperBound,
                    thumbRadius: thumbRadius,
                    trackWidth: trackWidth,
                    isAbove: false
                )
                .frame(height: bottomRulerHeight)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(makeGesture(thumbRadius: thumbRadius, trackWidth: trackWidth))
        }
        .frame(height: topRulerHeight + thumbDiameter + bottomRulerHeight)
    }

    // MARK: - Track Row

    @ViewBuilder
    private func trackRow(thumbCenterX: CGFloat, thumbRadius: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // 背景轨道
            RoundedRectangle(cornerRadius: trackHeight / 2)
                .fill(Color.secondary.opacity(0.2))
                .frame(height: trackHeight)
                .padding(.horizontal, thumbRadius)

            // 进度填充（从轨道起点到 thumb 中心）
            RoundedRectangle(cornerRadius: trackHeight / 2)
                .fill(Color.weekyiiPrimary)
                .frame(width: max(0, thumbCenterX - thumbRadius), height: trackHeight)
                .offset(x: thumbRadius)

            // 滑块
            Circle()
                .fill(Color.white)
                .shadow(
                    color: .black.opacity(isDragging ? 0.22 : 0.15),
                    radius: isDragging ? 5 : 3,
                    x: 0, y: 1
                )
                .overlay(Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
                .frame(width: thumbDiameter, height: thumbDiameter)
                .offset(x: thumbCenterX - thumbRadius)
                .scaleEffect(isDragging ? 1.12 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
        }
    }

    // MARK: - Gesture

    private func makeGesture(thumbRadius: CGFloat, trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if !isDragging {
                    isDragging = true
                    frozenLowerBound = lowerBound
                    onEditingChanged?(true)
                }
                let lb       = frozenLowerBound ?? lowerBound
                let rawRatio = Double((drag.location.x - thumbRadius) / trackWidth)
                let newValue = lb + rawRatio * (upperBound - lb)
                onChange(min(max(newValue, lb), upperBound))
            }
            .onEnded { _ in
                isDragging = false
                frozenLowerBound = nil
                onEditingChanged?(false)
            }
    }
}

// MARK: - KillTimeRuler

/// Canvas 刻度尺，上下两用。
/// 每根刻度线的高度与透明度由其与 thumb 的距离决定，形成随 thumb 移动的焦点渐变效果。
private struct KillTimeRuler: View {

    let currentMinutes: Double
    let lowerBound: Double
    let upperBound: Double
    let thumbRadius: CGFloat
    let trackWidth: CGFloat
    /// true = 刻度从底部向上生长（上方尺）；false = 从顶部向下生长（下方尺）
    let isAbove: Bool

    // MARK: Tick Config

    private struct TickLevel {
        let interval: Int       // 分钟间隔（5 / 15 / 30 / 60）
        let baseH: CGFloat      // 远离焦点时的基础高度
        let extraH: CGFloat     // 焦点中心的额外增量
        let baseAlpha: Double   // 远离焦点时的透明度
        let peakAlpha: Double   // 焦点中心的透明度
        let strokeWidth: CGFloat
        /// 每级独立的焦点衰减窗口（越小的刻度窗口越窄，仅在 thumb 附近出现）
        let focusWindow: Double
    }

    private static let levels: [TickLevel] = [
        TickLevel(interval:  5, baseH: 1.5, extraH: 3.5, baseAlpha: 0.00, peakAlpha: 0.35, strokeWidth: 0.6,  focusWindow: 18.0),
        TickLevel(interval: 15, baseH: 2.0, extraH: 5.0, baseAlpha: 0.05, peakAlpha: 0.52, strokeWidth: 0.75, focusWindow: 38.0),
        TickLevel(interval: 30, baseH: 2.5, extraH: 7.0, baseAlpha: 0.09, peakAlpha: 0.68, strokeWidth: 1.0,  focusWindow: 62.0),
        TickLevel(interval: 60, baseH: 3.0, extraH: 12.0, baseAlpha: 0.13, peakAlpha: 0.92, strokeWidth: 1.0,  focusWindow: 88.0),
    ]

    // MARK: Body

    var body: some View {
        Canvas { context, size in
            let range = upperBound - lowerBound
            guard range > 0, trackWidth > 0 else { return }

            // 以 5 分钟为步长遍历所有刻度（细密度基础）
            let step   = 5
            let startM = (Int(lowerBound) / step) * step
            let endM   = ((Int(ceil(upperBound)) / step) + 1) * step

            var m = startM
            while m <= endM {
                let mD = Double(m)
                guard mD >= lowerBound, mD <= upperBound else { m += step; continue }

                // 按间隔选取刻度级别（优先取最高级）
                let level: TickLevel
                if      m % 60 == 0 { level = Self.levels[3] }
                else if m % 30 == 0 { level = Self.levels[2] }
                else if m % 15 == 0 { level = Self.levels[1] }
                else                { level = Self.levels[0] }

                // X 坐标：与 Slider 轨道完全对齐（thumbRadius 为轨道起点偏移）
                let ratio = CGFloat((mD - lowerBound) / range)
                let x     = thumbRadius + ratio * trackWidth

                // 各级独立焦点窗口 + 三次方衰减，小间隔刻度仅在 thumb 附近浮现
                let t         = max(0.0, 1.0 - abs(mD - currentMinutes) / level.focusWindow)
                let proximity = t * t * t

                let tickH = level.baseH  + CGFloat(proximity) * level.extraH
                let alpha = level.baseAlpha + proximity * (level.peakAlpha - level.baseAlpha)

                // 绘制刻度线
                let y0: CGFloat = isAbove ? size.height : 0
                let y1: CGFloat = isAbove ? size.height - tickH : tickH

                var path = Path()
                path.move(to: CGPoint(x: x, y: y0))
                path.addLine(to: CGPoint(x: x, y: y1))
                context.stroke(path, with: .color(Color.secondary.opacity(alpha)), lineWidth: level.strokeWidth)

                // 整点时间标签（仅下方刻度尺）
                if !isAbove, m % 60 == 0 {
                    drawHourLabel(
                        context: context,
                        hour: m / 60,
                        x: x,
                        yTop: tickH + 3,
                        alpha: alpha * 0.85,
                        canvasWidth: size.width
                    )
                }

                m += step
            }
        }
    }

    // MARK: - Label Drawing

    private func drawHourLabel(
        context: GraphicsContext,
        hour: Int,
        x: CGFloat,
        yTop: CGFloat,
        alpha: Double,
        canvasWidth: CGFloat
    ) {
        // 边缘处调整对齐方向，防止文字被裁剪
        let anchor: UnitPoint
        if x < thumbRadius + 18 {
            anchor = .topLeading
        } else if x > thumbRadius + trackWidth - 18 {
            anchor = .topTrailing
        } else {
            anchor = .top
        }

        context.draw(
            Text(String(format: "%d:00", hour))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.secondary.opacity(alpha)),
            at: CGPoint(x: x, y: yTop),
            anchor: anchor
        )
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State var minutes: Double = 21 * 60 + 30
        var body: some View {
            VStack(spacing: WeekSpacing.lg) {
                WeekCard {
                    VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                        Text(String(format: "%02d:%02d", Int(minutes) / 60, Int(minutes) % 60))
                            .font(.titleLarge)
                            .monospacedDigit()
                        KillTimeSlider(
                            value: minutes,
                            lowerBound: 18 * 60,
                            upperBound: 23 * 60 + 59,
                            onChange: { minutes = $0 }
                        )
                    }
                }
            }
            .padding()
            .background(Color.backgroundPrimary)
        }
    }
    return PreviewWrapper()
}
