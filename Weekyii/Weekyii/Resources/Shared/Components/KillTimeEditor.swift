import SwiftUI

struct KillTimeEditor: View {
    let hour: Int
    let minute: Int
    let isEditable: Bool
    let onChange: (Int, Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(String(localized: "kill_time.label"))
                .font(.subheadline)
            Spacer()
            DatePicker(
                "",
                selection: Binding(get: {
                    composeDate(hour: hour, minute: minute)
                }, set: { newValue in
                    let components = Calendar(identifier: .iso8601).dateComponents([.hour, .minute], from: newValue)
                    let newHour = components.hour ?? hour
                    let newMinute = components.minute ?? minute
                    onChange(newHour, newMinute)
                }),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .disabled(!isEditable)
        }
    }

    private func composeDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar(identifier: .iso8601)
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }
}
