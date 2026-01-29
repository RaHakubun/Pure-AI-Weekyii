import SwiftUI

struct FocusZoneView: View {
    let task: TaskItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "zone.focus"))
                .font(.headline)

            if let task {
                TaskRowView(task: task)
            } else {
                Text(String(localized: "zone.focus.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
