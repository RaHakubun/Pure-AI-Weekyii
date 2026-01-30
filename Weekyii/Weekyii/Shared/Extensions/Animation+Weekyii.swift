import SwiftUI

// MARK: - Animation Extensions

extension Animation {
    /// 弹簧动画 - 用于按钮和卡片
    static let weekSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    
    /// 平滑动画 - 用于过渡
    static let weekSmooth = Animation.easeInOut(duration: 0.3)
    
    /// 快速动画 - 用于小元素
    static let weekQuick = Animation.easeOut(duration: 0.2)
    
    /// 庆祝动画 - 用于完成任务
    static let weekCelebration = Animation.spring(response: 0.5, dampingFraction: 0.6)
}

// MARK: - View Modifiers

/// 淡入动画修饰符
struct FadeInModifier: ViewModifier {
    @State private var opacity: Double = 0
    let delay: Double
    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.weekSmooth.delay(delay)) {
                    opacity = 1
                }
            }
    }
}

/// 滑入动画修饰符
struct SlideInModifier: ViewModifier {
    @State private var offset: CGFloat = 20
    @State private var opacity: Double = 0
    let delay: Double
    
    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.weekSpring.delay(delay)) {
                    offset = 0
                    opacity = 1
                }
            }
    }
}

/// 缩放动画修饰符
struct ScaleInModifier: ViewModifier {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    let delay: Double
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.weekSpring.delay(delay)) {
                    scale = 1
                    opacity = 1
                }
            }
    }
}

/// 庆祝动画修饰符
struct CelebrationModifier: ViewModifier {
    @State private var scale: CGFloat = 1
    @State private var rotation: Double = 0
    let isTriggered: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .onChange(of: isTriggered) { _, triggered in
                if triggered {
                    withAnimation(.weekCelebration) {
                        scale = 1.2
                        rotation = 5
                    }
                    withAnimation(.weekCelebration.delay(0.2)) {
                        scale = 1
                        rotation = 0
                    }
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// 淡入动画
    func fadeIn(delay: Double = 0) -> some View {
        modifier(FadeInModifier(delay: delay))
    }
    
    /// 滑入动画
    func slideIn(delay: Double = 0) -> some View {
        modifier(SlideInModifier(delay: delay))
    }
    
    /// 缩放动画
    func scaleIn(delay: Double = 0) -> some View {
        modifier(ScaleInModifier(delay: delay))
    }
    
    /// 庆祝动画
    func celebration(isTriggered: Bool) -> some View {
        modifier(CelebrationModifier(isTriggered: isTriggered))
    }
}
