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
            .cornerRadius(WeekRadius.medium)
            .overlay(outlineOverlay)
        }
        .buttonStyle(ScaleButtonStyle())
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
            RoundedRectangle(cornerRadius: WeekRadius.medium)
                .stroke(Color.weekyiiPrimary, lineWidth: 2)
        }
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        WeekButton("Primary Button", icon: "plus.circle.fill", style: .primary) {
            print("Primary tapped")
        }
        
        WeekButton("Secondary Button", icon: "star.fill", style: .secondary) {
            print("Secondary tapped")
        }
        
        WeekButton("Outline Button", icon: "arrow.right", style: .outline) {
            print("Outline tapped")
        }
        
        WeekButton("Disabled Button", style: .primary, isEnabled: false) {
            print("This won't print")
        }
    }
    .padding()
    .background(Color.backgroundPrimary)
}
