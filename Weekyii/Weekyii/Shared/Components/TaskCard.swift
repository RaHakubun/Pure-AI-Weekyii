import SwiftUI

// MARK: - TaskCard - 任务卡片组件

struct TaskCard: View {
    let task: TaskItem
    let showStatus: Bool
    let showsProjectOrigin: Bool
    let showsHabitOrigin: Bool
    let onTap: (() -> Void)?
    @Environment(\.taskTypePresentationCatalog) private var taskTypeCatalog
    @Environment(\.themeSkin) private var skin

    private var taskType: TaskTypePresentation {
        taskTypeCatalog.resolve(idRaw: task.taskTypeIdRaw, fallback: task.taskType)
    }
    
    init(
        task: TaskItem,
        showStatus: Bool = true,
        showsProjectOrigin: Bool = false,
        showsHabitOrigin: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.task = task
        self.showStatus = showStatus
        self.showsProjectOrigin = showsProjectOrigin
        self.showsHabitOrigin = showsHabitOrigin
        self.onTap = onTap
    }
    
    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        if let row = skin.row {
            themedCardContent(row)
        } else {
            classicCardContent
        }
    }

    private func themedCardContent(_ row: ThemeRowSkin) -> some View {
        HStack(spacing: WeekSpacing.md) {
            RoundedRectangle(cornerRadius: row.barCornerRadius)
                .fill(taskType.color)
                .frame(width: row.barWidth)
                .shadow(color: row.barGlows ? taskType.color.opacity(0.8) : .clear, radius: row.barGlows ? 4 : 0)
                .overlay(alignment: .trailing) {
                    if row.barFlush {
                        Rectangle()
                            .fill(row.surface.border.color)
                            .frame(width: row.surface.borderWidth)
                    }
                }

            details
                .padding(.vertical, row.barFlush ? WeekSpacing.base : 0)
                .padding(.trailing, row.barFlush ? WeekSpacing.base : 0)
        }
        .weekPadding(row.barFlush ? 0 : WeekSpacing.base)
        .themedSurface(row.surface)
    }

    /// The original row drawing, unchanged for classic themes.
    private var classicCardContent: some View {
        HStack(spacing: WeekSpacing.md) {
            // 左侧彩色边条
            RoundedRectangle(cornerRadius: WeekRadius.full)
                .fill(taskType.color)
                .frame(width: 4)

            details
        }
        .weekPadding(WeekSpacing.base)
        .background(Color.backgroundSecondary)
        .clipShape(.rect(cornerRadius: WeekRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium)
                .stroke(Color.backgroundTertiary, lineWidth: 1)
        )
        .shadow(color: WeekShadow.light.color, radius: WeekShadow.light.radius, x: WeekShadow.light.x, y: WeekShadow.light.y)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.xs) {
            HStack(spacing: WeekSpacing.sm) {
                // 任务类型图标
                Image(systemName: taskType.iconName)
                    .foregroundColor(taskType.color)
                    .font(.caption)

                Text(task.title)
                    .font(.bodyLarge)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                Spacer()

                if showsProjectOrigin {
                    TaskProjectOriginBadge(project: task.project)
                }

                if showsHabitOrigin {
                    TaskHabitOriginBadge(habit: task.habit)
                }

                if showStatus {
                    TaskZoneBadge(zone: task.zone)
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
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
