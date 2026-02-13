import SwiftUI

extension View {
    func weekyiiCard() -> some View {
        self
            .padding(12)
            .background(Color.backgroundSecondary)
            .clipShape(.rect(cornerRadius: WeekRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.medium)
                    .stroke(Color.backgroundTertiary, lineWidth: 1)
            )
            .shadow(color: WeekShadow.light.color, radius: WeekShadow.light.radius, x: WeekShadow.light.x, y: WeekShadow.light.y)
    }
}
