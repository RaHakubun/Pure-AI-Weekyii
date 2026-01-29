import SwiftUI

struct PastDayDetailView: View {
    let day: DayModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(day.date, format: Date.FormatStyle().weekday(.abbreviated).month().day().year())
                        .font(.headline)
                    StatusBadge(status: day.status)
                }
                .weekyiiCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "past.completed"))
                        .font(.headline)
                    if day.completedTasks.isEmpty {
                        Text(String(localized: "past.completed.empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(day.completedTasks) { task in
                            TaskRowView(task: task)
                        }
                    }
                }
                .weekyiiCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "past.expired"))
                        .font(.headline)
                    Text("\(day.expiredCount)")
                        .font(.title2)
                    Text(String(localized: "past.expired.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .weekyiiCard()
            }
            .padding()
        }
        .navigationTitle(day.dayId)
    }
}
