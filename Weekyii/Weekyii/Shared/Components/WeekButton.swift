import SwiftUI

// MARK: - WeekButton - 增强版按钮组件

struct WeekButton: View {
    enum Style {
        case primary
        case secondary
        case outline
    }
    
    let title: String
    let icon: String?
    let style: Style
    let isEnabled: Bool
    let action: () -> Void
    
    init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isEnabled = isEnabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: WeekSpacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.bodyMedium.weight(.semibold))
                }
                Text(title)
                    .font(.bodyLarge.weight(.semibold))
            }
            .weekPaddingHorizontal(WeekSpacing.xl)
            .weekPaddingVertical(14)
            .background(backgroundForStyle)
            .foregroundColor(foregroundForStyle)
            .clipShape(.rect(cornerRadius: WeekRadius.xlarge))
            .overlay(outlineOverlay)
        }
        .buttonStyle(ScaleButtonStyle())
        .shadow(color: shadowForStyle.color, radius: shadowForStyle.radius, x: shadowForStyle.x, y: shadowForStyle.y)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
    }
    
    @ViewBuilder
    private var backgroundForStyle: some View {
        switch style {
        case .primary:
            Color.weekyiiGradient
        case .secondary:
            Color.weekyiiPrimary.opacity(0.1)
        case .outline:
            Color.clear
        }
    }
    
    private var foregroundForStyle: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return .weekyiiPrimary
        case .outline:
            return .weekyiiPrimary
        }
    }
    
    @ViewBuilder
    private var outlineOverlay: some View {
        if style == .outline {
            RoundedRectangle(cornerRadius: WeekRadius.xlarge)
                .stroke(Color.weekyiiPrimary, lineWidth: 2)
        }
    }

    private var shadowForStyle: WeekShadow {
        switch style {
        case .primary:
            return .medium
        case .secondary:
            return .light
        case .outline:
            return WeekShadow(color: .clear, radius: 0, x: 0, y: 0)
        }
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        WeekButton("Primary Button", icon: "plus.circle.fill", style: .primary) {
        }
        
        WeekButton("Secondary Button", icon: "star.fill", style: .secondary) {
        }
        
        WeekButton("Outline Button", icon: "arrow.right", style: .outline) {
        }
        
        WeekButton("Disabled Button", style: .primary, isEnabled: false) {
        }
    }
    .padding()
    .background(Color.backgroundPrimary)
}
