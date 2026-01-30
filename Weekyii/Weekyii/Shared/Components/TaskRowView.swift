import SwiftUI

struct TaskRowView: View {
    let task: TaskItem

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
                Text(task.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                
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
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(WeekRadius.medium)
    }
}
