import SwiftUI

struct TaskRowView: View {
    enum RenderContext {
        case normalCard
        case reorderList
    }

    let task: TaskItem
    let titleAccessibilityIdentifier: String?
    let showsProjectOrigin: Bool
    let renderContext: RenderContext

    init(
        task: TaskItem,
        titleAccessibilityIdentifier: String? = nil,
        showsProjectOrigin: Bool = false,
        renderContext: RenderContext = .normalCard
    ) {
        self.task = task
        self.titleAccessibilityIdentifier = titleAccessibilityIdentifier
        self.showsProjectOrigin = showsProjectOrigin
        self.renderContext = renderContext
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WeekSpacing.sm) {
            // Left Accent Bar
            RoundedRectangle(cornerRadius: 2)
                .fill(task.taskType.color)
                .frame(width: 4, height: 28)
                .padding(.top, 2)
            
            // Icon
            Image(systemName: task.taskType.iconName)
                .font(.headline)
                .foregroundColor(task.taskType.color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                // Title
                titleView
                
                if showsProjectOrigin {
                    TaskProjectOriginBadge(project: task.project)
                }

                // Description
                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer()
            
            // Steps Indicator
            if !task.steps.isEmpty {
                let completed = task.steps.filter(\.isCompleted).count
                HStack(spacing: 2) {
                    Image(systemName: "checklist")
                    Text("\(completed)/\(task.steps.count)")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium)
                .stroke(
                    borderColor,
                    style: StrokeStyle(lineWidth: 1, lineJoin: .round)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .compositingGroup()
    }
    
    @ViewBuilder
    private var titleView: some View {
        if let titleAccessibilityIdentifier {
            Text(task.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .accessibilityIdentifier(titleAccessibilityIdentifier)
        } else {
            Text(task.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
        }
    }

    private var backgroundColor: Color {
        switch renderContext {
        case .normalCard:
            return .backgroundSecondary
        case .reorderList:
            return .backgroundSecondary
        }
    }

    private var borderColor: Color {
        switch renderContext {
        case .normalCard:
            return .backgroundTertiary
        case .reorderList:
            return Color.backgroundTertiary.opacity(0.92)
        }
    }
}

struct TaskProjectOriginBadge: View {
    let project: ProjectModel?
    var isOnDarkBackground: Bool = false

    var body: some View {
        if let project {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                Text(
                    String(
                        format: String(localized: "task.project.origin", defaultValue: "来自 %@"),
                        project.name
                    )
                )
                .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(isOnDarkBackground ? Color.white.opacity(0.95) : Color.textSecondary)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(isOnDarkBackground ? Color.white.opacity(0.16) : Color.backgroundTertiary, in: Capsule())
            .accessibilityIdentifier("taskProjectOriginBadge")
        }
    }
}
