import SwiftUI

// MARK: - EmptyStateView - 空状态视图

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    @State private var isAnimating = false
    
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: WeekSpacing.xl) {
            // 图标
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundStyle(Color.weekyiiGradient)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0.6)
            
            // 文字
            VStack(spacing: WeekSpacing.sm) {
                Text(title)
                    .font(.titleMedium)
                    .foregroundColor(.textPrimary)
                
                Text(subtitle)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(isAnimating ? 1.0 : 0.0)
            .offset(y: isAnimating ? 0 : 20)
            
            // 操作按钮
            if let actionTitle = actionTitle, let action = action {
                WeekButton(actionTitle, icon: "plus.circle.fill", style: .primary, action: action)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .offset(y: isAnimating ? 0 : 20)
            }
        }
        .frame(maxWidth: .infinity)
        .weekPaddingVertical(WeekSpacing.xxxl)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        WeekCard {
            EmptyStateView(
                title: "没有任务",
                subtitle: "点击下方按钮创建第一个任务",
                systemImage: "square.and.pencil",
                actionTitle: "创建任务",
                action: { print("Create task") }
            )
        }
        
        WeekCard {
            EmptyStateView(
                title: "暂无数据",
                subtitle: "这里还没有任何内容",
                systemImage: "tray"
            )
        }
    }
    .padding()
    .background(Color.backgroundPrimary)
}
