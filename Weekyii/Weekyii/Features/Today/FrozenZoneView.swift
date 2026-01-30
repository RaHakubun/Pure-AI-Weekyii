import SwiftUI

// MARK: - FrozenZoneView - 冻结区视图

struct FrozenZoneView: View {
    let tasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            if tasks.isEmpty {
                Text(String(localized: "zone.frozen.empty"))
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
