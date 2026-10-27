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
