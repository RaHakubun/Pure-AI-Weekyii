import SwiftUI

struct DayCardView: View {
    let day: DayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.dayOfWeek)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(day.date, format: Date.FormatStyle().month().day())
                .font(.headline)
            StatusBadge(status: day.status)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
