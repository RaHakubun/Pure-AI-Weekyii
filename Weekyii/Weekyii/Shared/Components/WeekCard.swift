import SwiftUI

// MARK: - WeekCard - 增强版卡片组件

struct WeekCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    let useGradient: Bool
    let accentColor: Color?
    let shadow: WeekShadow
    
    init(
        useGradient: Bool = false,
        accentColor: Color? = nil,
        shadow: WeekShadow = .light,
        @ViewBuilder content: () -> Content
    ) {
        self.useGradient = useGradient
        self.accentColor = accentColor
        self.shadow = shadow
        self.content = content()
    }
    
    var body: some View {
        let isPremiumTheme = WeekTheme.activeTheme.isPremiumTheme

        VStack(alignment: .leading, spacing: WeekSpacing.base) {
            content
        }
        .weekPadding(WeekSpacing.lg)
        .background(backgroundView)
        .clipShape(.rect(cornerRadius: WeekRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.large)
                .stroke(borderColor(isPremiumTheme: isPremiumTheme), lineWidth: 1)
        )
        .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        .overlay(accentBar(isPremiumTheme: isPremiumTheme), alignment: .top)
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        let isPremiumTheme = WeekTheme.activeTheme.isPremiumTheme

        if useGradient {
            ZStack {
                Color.weekyiiGradient
                if isPremiumTheme {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        } else {
            ZStack {
                Color.backgroundSecondary
                if isPremiumTheme {
                    LinearGradient(
                        colors: [
                            Color.weekyiiPrimary.opacity(0.10),
                            Color.clear,
                            Color.accentOrange.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)
                }
                if colorScheme == .dark {
                    Color.backgroundTertiary.opacity(0.28)
                }
            }
        }
    }

    private func borderColor(isPremiumTheme: Bool) -> Color {
        if useGradient {
            return isPremiumTheme
                ? Color.white.opacity(colorScheme == .dark ? 0.32 : 0.22)
                : Color.white.opacity(colorScheme == .dark ? 0.24 : 0.18)
        }
        if isPremiumTheme {
            return Color.weekyiiPrimary.opacity(colorScheme == .dark ? 0.30 : 0.22)
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.backgroundTertiary
    }
    
    @ViewBuilder
    private func accentBar(isPremiumTheme: Bool) -> some View {
        if let color = accentColor {
            let barStyle: AnyShapeStyle = isPremiumTheme
                ? AnyShapeStyle(
                    LinearGradient(
                        colors: [Color.weekyiiPrimary, Color.weekyiiPrimaryLight, color],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                : AnyShapeStyle(color)

            VStack {
                RoundedRectangle(cornerRadius: WeekRadius.full)
                    .fill(barStyle)
                    .frame(width: isPremiumTheme ? 56 : 40, height: 4)
                    .padding(.top, WeekSpacing.md)
                Spacer()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        WeekCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("普通卡片")
                    .font(.titleSmall)
                Text("这是一个普通的卡片示例")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
        }
        
        WeekCard(useGradient: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("渐变卡片")
                    .font(.titleSmall)
                    .foregroundColor(.white)
                Text("这是一个带渐变背景的卡片")
                    .font(.bodyMedium)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        
        WeekCard(accentColor: .accentOrange) {
            VStack(alignment: .leading, spacing: 8) {
                Text("带装饰条的卡片")
                    .font(.titleSmall)
                Text("顶部有橙色装饰条")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
        }
    }
    .padding()
    .background(Color.backgroundPrimary)
}
