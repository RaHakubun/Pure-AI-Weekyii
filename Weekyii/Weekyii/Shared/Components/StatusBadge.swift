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
        }
    }
}
