import SwiftUI

// MARK: - LoadingView - 加载骨架屏

struct LoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: WeekSpacing.lg) {
            // Logo 动画
            WeekLogo(size: .medium, animated: true)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .opacity(isAnimating ? 1.0 : 0.6)
            
            // 加载文字
            Text(String(localized: "loading"))
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .opacity(isAnimating ? 1.0 : 0.4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundPrimary)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - SkeletonView - 骨架屏卡片

struct SkeletonView: View {
    @State private var isAnimating = false
    let height: CGFloat
    
    init(height: CGFloat = 60) {
        self.height = height
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: WeekRadius.medium)
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.1),
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.1)
                    ],
                    startPoint: isAnimating ? .leading : .trailing,
                    endPoint: isAnimating ? .trailing : .leading
                )
            )
            .frame(height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        LoadingView()
            .frame(height: 200)
        
        VStack(spacing: 12) {
            SkeletonView(height: 80)
            SkeletonView(height: 60)
            SkeletonView(height: 60)
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
