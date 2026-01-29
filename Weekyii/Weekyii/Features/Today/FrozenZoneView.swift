import SwiftUI

struct FrozenZoneView: View {
    let tasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "zone.frozen"))
                .font(.headline)

            if tasks.isEmpty {
                Text(String(localized: "zone.frozen.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    TaskRowView(task: task)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
