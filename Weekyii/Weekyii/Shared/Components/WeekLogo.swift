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
    @Environment(\.themeSkin) private var skin

    private var isLotr: Bool { skin.glyphs == .lotr }
    private var isCat: Bool { skin.glyphs == .cat }

    private var logoGradient: LinearGradient {
        if isLotr {
            // Forged gold, lit from above.
            return LinearGradient(
                colors: [Color(hex: "#F4DFA6"), Color(hex: "#C9A45C"), Color(hex: "#8A6630")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [Color.weekyiiPrimary, Color.weekyiiPrimaryLight],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    init(size: Size = .large, animated: Bool = true) {
        self.size = size
        self.animated = animated
    }
    
    var body: some View {
        Text("Weekyii")
            .font(.system(size: size.fontSize * 1.05, weight: .semibold, design: .serif))
            .italic()
            .foregroundStyle(logoGradient)
            .overlay(alignment: .bottom) { inscription }
            .weekSoftShadow(color: Color.weekyiiPrimary.opacity(0.25), radius: 10, x: 0, y: 6)
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

extension WeekLogo {
    /// 魔戒：字标下方一道极淡的金色戒文，像至尊戒上的火焰文字。
    /// 只是叠加层，不改变字标的尺寸与布局。
    @ViewBuilder
    fileprivate var inscription: some View {
        if isLotr {
            ElvishInscriptionBand(seed: 11, color: Color(hex: "#B59A62"), opacity: 0.5, lineWidth: 0.7)
                .frame(width: size.fontSize * 3.6, height: max(6, size.fontSize * 0.24))
                .offset(y: max(5, size.fontSize * 0.2))
        } else if isCat {
            CatTailInscription()
                .stroke(Color(hex: "#8A6A55").opacity(0.55), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                .frame(width: size.fontSize * 2.4, height: max(8, size.fontSize * 0.28))
                .offset(y: max(6, size.fontSize * 0.22))
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
            CatCoveredSymbol(systemName: "calendar", pointSize: size.fontSize)
                .font(.system(size: size.fontSize))
                .foregroundStyle(Color.weekyiiPrimary)
            
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
