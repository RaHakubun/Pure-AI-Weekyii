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
        if skin.glyphs == .ring {
            // 指环王：单一锻金，自上而下。
            return RingGilt.gradient
        }
        if isCat {
            // Ginger fur, lighter at the top like a sunlit back.
            return LinearGradient(
                colors: [Color.weekyiiPrimaryLight, Color.weekyiiPrimary],
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
    
    @ViewBuilder
    private var wordmark: some View {
        if isCat {
            // A round, upright wordmark; the ears sit on the W.
            Text("Weekyii")
                .font(.system(size: size.fontSize * 1.05, weight: .heavy, design: .rounded))
        } else {
            Text("Weekyii")
                .font(.system(size: size.fontSize * 1.05, weight: .semibold, design: .serif))
                .italic()
        }
    }

    var body: some View {
        wordmark
            .foregroundStyle(logoGradient)
            .overlay(alignment: .bottom) { inscription }
            .overlay(alignment: .topLeading) { catEars }
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
        }
    }

    /// 猫猫：两只耳朵立在 "W" 的两个尖上。只是叠加层，不改变字标尺寸。
    @ViewBuilder
    fileprivate var catEars: some View {
        if isCat {
            CatEarPairShape()
                .fill(Color.weekyiiPrimaryLight)
                .frame(width: size.fontSize * 0.95, height: size.fontSize * 0.3)
                .padding(.leading, size.fontSize * 0.04)
                .offset(y: -size.fontSize * 0.08)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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
