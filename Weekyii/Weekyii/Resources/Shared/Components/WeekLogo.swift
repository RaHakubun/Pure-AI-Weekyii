import SwiftUI

// MARK: - WeekLogo - Weekyii 品牌标识

struct WeekLogo: View {
    enum Size {
        case small, medium, large
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 24
            case .medium: return 36
            case .large: return 48
            }
        }
    }
    
    let size: Size
    let animated: Bool
    
    @State private var isAnimating = false
    
    init(size: Size = .large, animated: Bool = true) {
        self.size = size
        self.animated = animated
    }
    
    var body: some View {
        Text("Weekyii")
            .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.weekyiiPrimary, Color.weekyiiPrimaryLight],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: Color.weekyiiPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
            .offset(y: animated && isAnimating ? -3 : 3)
            .animation(
                animated ? .easeInOut(duration: 2.0).repeatForever(autoreverses: true) : .default,
                value: isAnimating
            )
            .onAppear {
                if animated {
                    isAnimating = true
                }
            }
    }
}

// MARK: - WeekLogoWithIcon - 带图标的品牌标识

struct WeekLogoWithIcon: View {
    let size: WeekLogo.Size
    
    init(size: WeekLogo.Size = .medium) {
        self.size = size
    }
    
    var body: some View {
        HStack(spacing: WeekSpacing.sm) {
            Image(systemName: "calendar.circle.fill")
                .font(.system(size: size.fontSize))
                .foregroundStyle(Color.weekyiiGradient)
            
            WeekLogo(size: size, animated: false)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        WeekLogo(size: .large, animated: true)
        
        WeekLogo(size: .medium, animated: false)
        
        WeekLogo(size: .small, animated: false)
        
        Divider()
        
        WeekLogoWithIcon(size: .large)
        
        WeekLogoWithIcon(size: .medium)
    }
    .padding()
    .background(Color.backgroundPrimary)
}
