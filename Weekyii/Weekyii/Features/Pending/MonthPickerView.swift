import SwiftUI

struct MonthPickerView: View {
    @Binding var month: Date
    private let calendar = Calendar(identifier: .iso8601)

    var body: some View {
        HStack(spacing: 16) {
            Button(action: { month = previousMonth(from: month) }) {
                Image(systemName: "chevron.left")
            }

            Text(month, format: Date.FormatStyle().year().month())
                .font(.headline)
                .frame(maxWidth: .infinity)

            Button(action: { month = nextMonth(from: month) }) {
                Image(systemName: "chevron.right")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func previousMonth(from date: Date) -> Date {
        calendar.date(byAdding: .month, value: -1, to: date) ?? date
    }

    private func nextMonth(from date: Date) -> Date {
        calendar.date(byAdding: .month, value: 1, to: date) ?? date
    }
}
