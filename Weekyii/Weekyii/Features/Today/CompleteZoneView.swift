import SwiftUI

// MARK: - CompleteZoneView - 完成区视图

struct CompleteZoneView: View {
    let tasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            if tasks.isEmpty {
                Text(String(localized: "zone.complete.empty"))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .weekPaddingVertical(WeekSpacing.md)
            } else {
                ForEach(tasks) { task in
                    TaskCard(task: task, showStatus: false)
                }
            }
        }
    }
}
