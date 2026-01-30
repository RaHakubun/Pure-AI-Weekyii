import SwiftUI

// MARK: - FocusZoneView - 专注区视图

struct FocusZoneView: View {
    let task: TaskItem?

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            if let task {
                TaskCard(task: task, showStatus: false)
            } else {
                Text(String(localized: "zone.focus.empty"))
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .weekPaddingVertical(WeekSpacing.md)
            }
        }
    }
}
