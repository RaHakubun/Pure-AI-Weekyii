import SwiftUI

struct StatusBadge: View {
    let status: DayStatus
    @Environment(\.themeSkin) private var skin

    var body: some View {
        if let badge = skin.badge {
            themed(badge)
        } else {
            Text(status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.2))
                .foregroundColor(status.color)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func themed(_ badge: ThemeBadgeSkin) -> some View {
        switch badge.kind {
        case .block:
            Text(status.displayName)
                .font(.caption2.weight(.black))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundColor(.textPrimary)
                .background(status.color.opacity(0.28))
                .overlay(Rectangle().strokeBorder(badge.border?.color ?? status.color, lineWidth: 2))
        case .outline:
            Text(status.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .foregroundColor(status.color)
                .overlay(Capsule().strokeBorder(status.color, lineWidth: 1.5))
                .shadow(color: status.color.opacity(0.35), radius: 3)
        case .stamp:
            Text(status.displayName)
                .font(.caption2.weight(.bold))
                .tracking(2)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .foregroundColor(status.color)
                .overlay(Rectangle().strokeBorder(status.color, lineWidth: 1.5))
                .rotationEffect(.degrees(-3))
        case .bracket:
            Text(verbatim: "[\(status.displayName)]")
                .font(.caption2.weight(.bold))
                .foregroundColor(status.color)
        case .catEars:
            Text(status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.2))
                .foregroundColor(status.color)
                .clipShape(Capsule())
                .overlay(alignment: .top) {
                    CatEarPair()
                        .fill(status.color.opacity(0.85))
                        .frame(width: 22, height: 7)
                        .offset(y: -4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        case .waxSeal:
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [status.color.opacity(0.85), status.color],
                                center: UnitPoint(x: 0.35, y: 0.3),
                                startRadius: 0,
                                endRadius: 13
                            )
                        )
                    Circle()
                        .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
                    // The pressed rim a seal matrix leaves in the wax.
                    Circle()
                        .inset(by: 3)
                        .stroke(Color.black.opacity(0.14), lineWidth: 0.75)
                    LotrGlyphView(glyph: LotrGlyph(status: status))
                        .frame(width: 14, height: 14)
                        .foregroundColor(Color(hex: "#F7E9D0"))
                }
                .frame(width: 24, height: 24)
                .shadow(color: Color.black.opacity(0.25), radius: 0.75, x: 0, y: 0.75)
                Text(status.displayName)
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundColor(status.color)
            }
        case .legend:
            HStack(spacing: 6) {
                Rectangle()
                    .fill(status.color)
                    .frame(width: 12, height: 2)
                Text(status.displayName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.8)
            }
            .foregroundColor(status.color)
        }
    }
}

/// Two ears sitting on the top edge of a status tag. The overlay does not
/// change the badge's layout size, so the status row keeps its height.
private struct CatEarPair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func ear(_ left: CGFloat, _ tip: CGFloat, _ right: CGFloat) {
            path.move(to: CGPoint(x: rect.minX + rect.width * left, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + rect.width * tip, y: rect.minY),
                control: CGPoint(x: rect.minX + rect.width * (left * 0.45 + tip * 0.55), y: rect.minY + rect.height * 0.15)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + rect.width * right, y: rect.maxY),
                control: CGPoint(x: rect.minX + rect.width * (right * 0.45 + tip * 0.55), y: rect.minY + rect.height * 0.15)
            )
            path.closeSubpath()
        }
        ear(0.08, 0.28, 0.46)
        ear(0.54, 0.74, 0.94)
        return path
    }
}
