import SwiftUI

struct CreateProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ExtensionsViewModel

    @State private var name = ""
    @State private var description = ""
    @State private var selectedColor = "#C46A1A"
    @State private var selectedIcon = "folder.fill"
    @State private var startDate = Date()
    @State private var endDate = Date().addingDays(7)
    @State private var errorMessage: String?

    private let colorOptions = [
        "#C46A1A", "#3FA67A", "#D05C3E", "#8C6AD9",
        "#2F7E79", "#F08A3C", "#D97A6C", "#6B5A4F"
    ]

    private let iconOptions = [
        "folder.fill", "doc.text.fill", "star.fill", "bolt.fill",
        "flag.fill", "book.fill", "hammer.fill", "puzzlepiece.fill",
        "lightbulb.fill", "chart.bar.fill", "graduationcap.fill", "airplane"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                    // Live preview card
                    previewCard

                    // 名称
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            Text(String(localized: "project.create.name"))
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)
                            TextField(String(localized: "project.create.name.placeholder"), text: $name)
                                .font(.bodyLarge)
                                .padding(WeekSpacing.md)
                                .background(Color.backgroundTertiary)
                                .cornerRadius(WeekRadius.small)
                        }
                    }

                    // 描述
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            Text(String(localized: "project.create.description"))
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)
                            TextField(String(localized: "project.create.description.placeholder"), text: $description, axis: .vertical)
                                .font(.bodyMedium)
                                .lineLimit(3...6)
                                .padding(WeekSpacing.md)
                                .background(Color.backgroundTertiary)
                                .cornerRadius(WeekRadius.small)
                        }
                    }

                    // 颜色选择
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            Text(String(localized: "project.create.color"))
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: WeekSpacing.sm) {
                                ForEach(colorOptions, id: \.self) { hex in
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 32, height: 32)

                                        if selectedColor == hex {
                                            Circle()
                                                .stroke(Color.textPrimary, lineWidth: 2.5)
                                                .scaleEffect(1.25)
                                                .frame(width: 32, height: 32)

                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedColor = hex
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 图标选择
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            Text(String(localized: "project.create.icon"))
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: WeekSpacing.sm) {
                                ForEach(iconOptions, id: \.self) { icon in
                                    ZStack {
                                        RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous)
                                            .fill(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.15) : Color.backgroundTertiary)
                                            .frame(width: 44, height: 44)
                                        Image(systemName: icon)
                                            .font(.system(size: 18))
                                            .foregroundColor(selectedIcon == icon ? Color(hex: selectedColor) : .textTertiary)
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous)
                                            .stroke(selectedIcon == icon ? Color(hex: selectedColor) : .clear, lineWidth: 1.5)
                                    )
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedIcon = icon
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 日期范围
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            Text(String(localized: "project.create.date_range"))
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)

                            DatePicker(String(localized: "project.create.start_date"), selection: $startDate, displayedComponents: .date)
                                .font(.bodyMedium)
                            DatePicker(String(localized: "project.create.end_date"), selection: $endDate, in: startDate..., displayedComponents: .date)
                                .font(.bodyMedium)
                        }
                    }
                }
                .weekPadding(WeekSpacing.base)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle(String(localized: "project.create.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.create")) {
                        let project = viewModel.createProject(
                            name: name,
                            description: description,
                            color: selectedColor,
                            icon: selectedIcon,
                            startDate: startDate,
                            endDate: endDate
                        )
                        if project != nil {
                            dismiss()
                        } else {
                            errorMessage = viewModel.errorMessage
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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

    // MARK: - Live Preview Card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Gradient color bar
            LinearGradient(
                colors: [Color(hex: selectedColor), Color(hex: selectedColor).opacity(0.6)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 5)

            HStack(spacing: WeekSpacing.sm) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(Color(hex: selectedColor).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: selectedIcon)
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: selectedColor))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? String(localized: "project.create.name.placeholder") : name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(name.isEmpty ? .textTertiary : .textPrimary)
                        .lineLimit(1)

                    if !description.isEmpty {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Mini date range
                VStack(alignment: .trailing, spacing: 2) {
                    Text(startDate, format: .dateTime.month().day())
                        .font(.system(size: 10))
                    Text("~")
                        .font(.system(size: 9))
                    Text(endDate, format: .dateTime.month().day())
                        .font(.system(size: 10))
                }
                .foregroundColor(.textTertiary)
            }
            .padding(WeekSpacing.md)
        }
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .stroke(Color(hex: selectedColor).opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.2), value: selectedColor)
        .animation(.easeInOut(duration: 0.2), value: selectedIcon)
    }
}
