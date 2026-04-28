import SwiftUI

// MARK: - FrozenZoneView - 冻结区视图

struct FrozenZoneView: View {
    let tasks: [TaskItem]
    var showsProjectOrigin: Bool = false
    var onTapTask: ((TaskItem) -> Void)? = nil
    var onPostponeTask: ((TaskItem) -> Void)? = nil

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
                    TaskCard(
                        task: task,
                        showStatus: false,
                        showsProjectOrigin: showsProjectOrigin,
                        onTap: {
                            onTapTask?(task)
                        }
                    )
                    .contextMenu {
                        if let onPostponeTask {
                            Button("后移任务", systemImage: "calendar.badge.clock") {
                                onPostponeTask(task)
                            }
                        }
                    }
                }
            }
        }
    }
}
