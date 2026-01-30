import SwiftUI

// MARK: - Page Transition Modifiers

/// 页面过渡动画
struct PageTransitionModifier: ViewModifier {
    let isPresented: Bool
    
    func body(content: Content) -> some View {
        content
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
    }
}

/// 卡片交互动画
struct CardInteractionModifier: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .shadow(
                color: isPressed ? Color.black.opacity(0.1) : Color.black.opacity(0.15),
                radius: isPressed ? 4 : 8,
                y: isPressed ? 2 : 4
            )
            .animation(.weekSpring, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

/// 任务完成庆祝动画
struct TaskCompletionModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1.0
    let isCompleted: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .onChange(of: isCompleted) { _, completed in
                if completed {
                    // 庆祝动画序列
                    withAnimation(.weekCelebration) {
                        scale = 1.2
                        rotation = 10
                    }
                    
                    withAnimation(.weekCelebration.delay(0.2)) {
                        scale = 0.9
                        rotation = -5
                    }
                    
                    withAnimation(.weekCelebration.delay(0.4)) {
                        scale = 1.0
                        rotation = 0
                    }
                }
            }
    }
}

/// 列表项滑入动画
struct ListItemSlideModifier: ViewModifier {
    let index: Int
    @State private var offset: CGFloat = 50
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.weekSpring.delay(Double(index) * 0.05)) {
                    offset = 0
                    opacity = 1
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// 页面过渡动画
    func pageTransition(isPresented: Bool) -> some View {
        modifier(PageTransitionModifier(isPresented: isPresented))
    }
    
    /// 卡片交互动画
    func cardInteraction() -> some View {
        modifier(CardInteractionModifier())
    }
    
    /// 任务完成庆祝动画
    func taskCompletion(isCompleted: Bool) -> some View {
        modifier(TaskCompletionModifier(isCompleted: isCompleted))
    }
    
    /// 列表项滑入动画
    func listItemSlide(index: Int) -> some View {
        modifier(ListItemSlideModifier(index: index))
    }
}
