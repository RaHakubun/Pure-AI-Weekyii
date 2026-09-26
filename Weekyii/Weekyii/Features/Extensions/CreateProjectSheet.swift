import SwiftUI

struct CreateProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: UserSettings
    let viewModel: ExtensionsViewModel
    let projectToEdit: ProjectModel?

    @State private var name = ""
    @State private var description = ""
    @State private var selectedColor = CreateProjectSheet.defaultColorHex
    @State private var selectedIcon = "folder.fill"
    @State private var startDate = Date()
    @State private var endDate = Date().addingDays(7)
    @State private var errorMessage: String?
    @State private var hasAppliedProjectDefaults = false

    /// Shared with the project settings page so both surfaces offer the same palette.
    /// 只列轻量色系：旧项目存储的深色系原样保留（编辑时不选新色就不会被改），
    /// 但不再作为选项出现，因此这里没有兼容旧 hex 的分支。
    static let colorOptions = [
        "#E39A3F", "#43B07F", "#EE8462", "#A98CF0",
        "#46A9A2", "#4D9DE0", "#E8749F", "#9A8577",
        "#F7D3A8", "#B6E0BE", "#F6C2C6", "#D3C4F2",
        "#A9DAD2", "#A8CBF0", "#F6E3A1", "#E3DAD2"
    ]

    static let defaultColorHex = "#E39A3F"

    static let iconOptions = [
        "folder.fill", "doc.text.fill", "star.fill", "bolt.fill",
        "flag.fill", "book.fill", "hammer.fill", "puzzlepiece.fill",
        "lightbulb.fill", "chart.bar.fill", "graduationcap.fill", "airplane"
    ]

    init(viewModel: ExtensionsViewModel, projectToEdit: ProjectModel? = nil) {
        self.viewModel = viewModel
        self.projectToEdit = projectToEdit
        _name = State(initialValue: projectToEdit?.name ?? "")
        _description = State(initialValue: projectToEdit?.projectDescription ?? "")
        _selectedColor = State(initialValue: projectToEdit?.color ?? Self.defaultColorHex)
        _selectedIcon = State(initialValue: projectToEdit?.icon ?? "folder.fill")
        _startDate = State(initialValue: projectToEdit?.startDate ?? Date())
        _endDate = State(initialValue: projectToEdit?.endDate ?? Date().addingDays(7))
    }

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
                                ForEach(Self.colorOptions, id: \.self) { hex in
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
                                                .foregroundColor(.weekyiiTileInk)
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
                                ForEach(Self.iconOptions, id: \.self) { icon in
                                    ZStack {
                                        RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous)
                                            .fill(selectedIcon == icon ? accentColor.opacity(0.15) : Color.backgroundTertiary)
                                            .frame(width: 44, height: 44)
                                        Image(systemName: icon)
                                            .font(.system(size: 18))
                                            .foregroundColor(selectedIcon == icon ? accentColor : .textTertiary)
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous)
                                            .stroke(selectedIcon == icon ? accentColor : .clear, lineWidth: 1.5)
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
            .navigationTitle(projectToEdit == nil ? String(localized: "project.create.title") : "编辑项目")
            .onAppear {
                guard projectToEdit == nil, !hasAppliedProjectDefaults else { return }
                startDate = Date()
                endDate = Date().addingDays(max(settings.defaultProjectDurationDays, 1))
                // Only adopt a stored default that is actually part of the palette,
                // otherwise nothing would render as selected.
                if Self.colorOptions.contains(settings.defaultProjectColorHex) {
                    selectedColor = settings.defaultProjectColorHex
                }
                if Self.iconOptions.contains(settings.defaultProjectIconName) {
                    selectedIcon = settings.defaultProjectIconName
                }
                hasAppliedProjectDefaults = true
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(projectToEdit == nil ? String(localized: "action.create") : "保存") {
                        if let projectToEdit {
                            if viewModel.updateProject(
                                projectToEdit,
                                name: name,
                                description: description,
                                color: selectedColor,
                                icon: selectedIcon,
                                startDate: startDate,
                                endDate: endDate
                            ) {
                                dismiss()
                            } else {
                                errorMessage = viewModel.errorMessage
                            }
                        } else {
                            let project = viewModel.createProject(
                                name: name,
                                description: description,
                                color: selectedColor,
                                icon: selectedIcon,
                                startDate: startDate,
                                endDate: endDate,
                                tileSize: settings.defaultProjectTileSize
                            )
                            if project != nil {
                                dismiss()
                            } else {
                                errorMessage = viewModel.errorMessage
                            }
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

    /// 与项目列表卡片一致：色条/图标/描边都是浅底前景，走 emphasis 才读得清。
    private var accentColor: Color { Color.weekyiiEmphasis(hex: selectedColor) }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Gradient color bar
            LinearGradient(
                colors: [accentColor, accentColor.opacity(0.6)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 5)

            HStack(spacing: WeekSpacing.sm) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: selectedIcon)
                        .font(.system(size: 20))
                        .foregroundColor(accentColor)
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
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.2), value: selectedColor)
        .animation(.easeInOut(duration: 0.2), value: selectedIcon)
    }
}
