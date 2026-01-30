import SwiftUI

// MARK: - ProgressRing - 进度环组件

struct ProgressRing: View {
    let progress: Double // 0.0 - 1.0
    let lineWidth: CGFloat
    let size: CGFloat
    let showPercentage: Bool
    
    init(
        progress: Double,
        lineWidth: CGFloat = 12,
        size: CGFloat = 120,
        showPercentage: Bool = true
    ) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.lineWidth = lineWidth
        self.size = size
        self.showPercentage = showPercentage
    }
    
    var body: some View {
        ZStack {
            // 背景环
            Circle()
                .stroke(Color.backgroundTertiary, lineWidth: lineWidth)
            
            // 进度环
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.weekyiiGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            
            // 中心文字
            if showPercentage {
                VStack(spacing: WeekSpacing.xxs) {
                    Text("\(Int(progress * 100))%")
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                    Text(String(localized: "progress.complete"))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Mini Progress Ring

struct MiniProgressRing: View {
    let progress: Double
    let size: CGFloat
    
    init(progress: Double, size: CGFloat = 40) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.size = size
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.backgroundTertiary, lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.weekyiiGradient,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let progress: Double
    let height: CGFloat
    let showPercentage: Bool
    
    init(progress: Double, height: CGFloat = 8, showPercentage: Bool = false) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.height = height
        self.showPercentage = showPercentage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.backgroundTertiary)
                    
                    // 进度条
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.weekyiiGradient)
                        .frame(width: geometry.size.width * progress)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: height)
            
            if showPercentage {
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        ProgressRing(progress: 0.75)
        
        HStack(spacing: 20) {
            MiniProgressRing(progress: 0.3)
            MiniProgressRing(progress: 0.6)
            MiniProgressRing(progress: 1.0)
        }
        
        VStack(spacing: 16) {
            ProgressBar(progress: 0.25, showPercentage: true)
            ProgressBar(progress: 0.5, showPercentage: true)
            ProgressBar(progress: 0.85, showPercentage: true)
        }
        .padding(.horizontal)
    }
    .padding()
    .background(Color.backgroundPrimary)
}
