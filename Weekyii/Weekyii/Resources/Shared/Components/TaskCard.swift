import SwiftUI

// MARK: - TaskCard - 任务卡片组件

struct TaskCard: View {
    let task: TaskItem
    let showStatus: Bool
    let onTap: (() -> Void)?
    
    init(task: TaskItem, showStatus: Bool = true, onTap: (() -> Void)? = nil) {
        self.task = task
        self.showStatus = showStatus
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: WeekSpacing.md) {
                // 左侧彩色边条
                RoundedRectangle(cornerRadius: WeekRadius.full)
                    .fill(task.taskType.color)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                    HStack(spacing: WeekSpacing.sm) {
                        // 任务类型图标
                        Image(systemName: task.taskType.icon)
                            .foregroundColor(task.taskType.color)
                            .font(.caption)
                        
                        Text(task.title)
                            .font(.bodyLarge)
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        if showStatus {
                            StatusBadge(zone: task.zone)
                        }
                    }
                    
                    // 时间信息
                    if let startedAt = task.startedAt {
                        HStack(spacing: WeekSpacing.xs) {
                            Image(systemName: "clock")
                                .font(.captionSmall)
                            Text(formatTime(startedAt))
                                .font(.caption)
                        }
                        .foregroundColor(.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .weekPadding(WeekSpacing.base)
            .background(Color.backgroundSecondary)
            .cornerRadius(WeekRadius.medium)
            .shadow(color: WeekShadow.light.color, radius: WeekShadow.light.radius, x: WeekShadow.light.x, y: WeekShadow.light.y)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let zone: TaskZone
    
    var body: some View {
        Text(zoneName)
            .font(.captionBold)
            .foregroundColor(zoneColor)
            .padding(.horizontal, WeekSpacing.sm)
            .padding(.vertical, WeekSpacing.xs)
            .background(zoneColor.opacity(0.15))
            .cornerRadius(WeekRadius.small)
    }
    
    private var zoneName: String {
        switch zone {
        case .draft: return String(localized: "zone.draft")
        case .focus: return String(localized: "zone.focus")
        case .frozen: return String(localized: "zone.frozen")
        case .complete: return String(localized: "zone.complete")
        }
    }
    
    private var zoneColor: Color {
        switch zone {
        case .draft: return .textSecondary
        case .focus: return .accentOrange
        case .frozen: return .weekyiiPrimary
        case .complete: return .accentGreen
        }
    }
}

// MARK: - TaskType Extension

extension TaskType {
    var color: Color {
        switch self {
        case .regular: return .taskRegular
        case .ddl: return .taskDDL
        case .leisure: return .taskLeisure
        }
    }
    
    var icon: String {
        switch self {
        case .regular: return "circle.fill"
        case .ddl: return "exclamationmark.triangle.fill"
        case .leisure: return "star.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        TaskCard(
            task: TaskItem(
                title: "完成项目文档",
                taskType: .regular,
                order: 1,
                zone: .focus
            )
        )
        
        TaskCard(
            task: TaskItem(
                title: "提交作业 - 截止今晚",
                taskType: .ddl,
                order: 2,
                zone: .frozen
            )
        )
        
        TaskCard(
            task: TaskItem(
                title: "看电影放松一下",
                taskType: .leisure,
                order: 3,
                zone: .complete
            )
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}
