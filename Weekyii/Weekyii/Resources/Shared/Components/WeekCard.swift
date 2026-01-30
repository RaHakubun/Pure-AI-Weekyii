import SwiftUI

// MARK: - WeekCard - 增强版卡片组件

struct WeekCard<Content: View>: View {
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
        VStack(alignment: .leading, spacing: WeekSpacing.base) {
            content
        }
        .weekPadding(WeekSpacing.lg)
        .background(backgroundView)
        .cornerRadius(WeekRadius.large)
        .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        .overlay(accentBar, alignment: .top)
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        if useGradient {
            Color.weekyiiGradient
        } else {
            Color.backgroundSecondary
        }
    }
    
    @ViewBuilder
    private var accentBar: some View {
        if let color = accentColor {
            VStack {
                RoundedRectangle(cornerRadius: WeekRadius.full)
                    .fill(color)
                    .frame(width: 40, height: 4)
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
