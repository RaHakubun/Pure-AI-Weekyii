import SwiftUI

struct TaskRowView: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.taskType.iconName)
                .foregroundColor(task.taskType.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(task.taskNumber)  \(task.title)")
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(task.taskType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
