import SwiftUI

struct OrderedTaskRow: View {
    let task: TaskItem
    let index: Int
    var showsChevron = true
    var accessibilityIdentifier: String?
    @Environment(\.taskTypePresentationCatalog) private var taskTypeCatalog

    private var taskType: TaskTypePresentation {
        taskTypeCatalog.resolve(idRaw: task.taskTypeIdRaw, fallback: task.taskType)
    }

    var body: some View {
        HStack(spacing: WeekSpacing.md) {
            ZStack {
                Circle()
                    .fill(taskType.color.opacity(0.12))
                Text(String(format: "%02d", index + 1))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(taskType.color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                Text(task.title)
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                HStack(spacing: WeekSpacing.sm) {
                    Label(taskType.name, systemImage: taskType.iconName)
                        .foregroundStyle(taskType.color)

                    if !task.steps.isEmpty {
                        let completedSteps = task.steps.filter(\.isCompleted).count
                        Label("\(completedSteps)/\(task.steps.count)", systemImage: "checklist")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .font(.caption2.weight(.medium))
            }

            Spacer(minLength: WeekSpacing.sm)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, WeekSpacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}
