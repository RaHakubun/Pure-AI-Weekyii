import SwiftUI

struct CreateWeekSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var weekIdText = ""
    @State private var selectedMode: Mode = .date
    @State private var errorMessage: String?

    let viewModel: PendingViewModel

    enum Mode: String, CaseIterable {
        case date
        case weekId
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "pending.create.mode"))) {
                    Picker(String(localized: "pending.create.mode"), selection: $selectedMode) {
                        Text(String(localized: "pending.create.by_date")).tag(Mode.date)
                        Text(String(localized: "pending.create.by_week")) .tag(Mode.weekId)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedMode == .date {
                    Section(header: Text(String(localized: "pending.create.date"))) {
                        DatePicker(String(localized: "pending.create.date"), selection: $selectedDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                    }
                } else {
                    Section(header: Text(String(localized: "pending.create.week_id"))) {
                        TextField("2026-W05", text: $weekIdText)
                            .textInputAutocapitalization(.never)
                    }
                }
            }
            .navigationTitle(String(localized: "pending.create.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.create")) {
                        if selectedMode == .date {
                            viewModel.createWeek(containing: selectedDate)
                        } else {
                            let trimmed = weekIdText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard isValidWeekId(trimmed) else {
                                errorMessage = String(localized: "error.date_format_invalid")
                                return
                            }
                            viewModel.createWeek(weekId: trimmed)
                        }
                        dismiss()
                    }
                    .disabled(selectedMode == .weekId && weekIdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                }
            }
            .alert(String(localized: "alert.title"), isPresented: Binding(get: {
                errorMessage != nil
            }, set: { newValue in
                if !newValue { errorMessage = nil }
            })) {
                Button(String(localized: "action.ok"), role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func isValidWeekId(_ value: String) -> Bool {
        let pattern = #"^\d{4}-W\d{2}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
