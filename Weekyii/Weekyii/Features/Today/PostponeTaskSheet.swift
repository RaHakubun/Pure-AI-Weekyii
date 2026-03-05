import SwiftUI

private enum PostponeMode: String, CaseIterable, Identifiable {
    case relative
    case absolute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relative:
            return "后移天数"
        case .absolute:
            return "指定日期"
        }
    }
}

struct PostponeTaskSheet: View {
    let taskTitle: String
    let onSubmit: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mode: PostponeMode = .relative
    @State private var relativeDays: Int = 1
    @State private var absoluteDate: Date = Date().addingDays(1)

    private let quickRelativeOptions = [1, 2, 3, 7, 14]

    private var todayStart: Date {
        Date().startOfDay
    }

    private var minimumDate: Date {
        todayStart.addingDays(1)
    }

    private var resolvedTargetDate: Date {
        switch mode {
        case .relative:
            return todayStart.addingDays(max(1, relativeDays))
        case .absolute:
            return max(absoluteDate.startOfDay, minimumDate)
        }
    }

    private var resolvedTargetDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd EEEE"
        return formatter.string(from: resolvedTargetDate)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                    Text("后移任务")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.textPrimary)
                    Text(taskTitle)
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }

                Picker("后移方式", selection: $mode) {
                    ForEach(PostponeMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .relative {
                    VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                        Text("快捷选择")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textSecondary)

                        HStack(spacing: WeekSpacing.sm) {
                            ForEach(quickRelativeOptions, id: \.self) { value in
                                Button {
                                    relativeDays = value
                                } label: {
                                    Text(value == 1 ? "明天" : "+\(value)天")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(relativeDays == value ? .white : .weekyiiPrimary)
                                        .padding(.vertical, WeekSpacing.xs)
                                        .padding(.horizontal, WeekSpacing.sm)
                                        .background(
                                            Capsule()
                                                .fill(relativeDays == value ? Color.weekyiiPrimary : Color.weekyiiPrimary.opacity(0.12))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Stepper(value: $relativeDays, in: 1...365) {
                            Text("后移 \(relativeDays) 天")
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)
                        }
                    }
                } else {
                    DatePicker(
                        "目标日期",
                        selection: $absoluteDate,
                        in: minimumDate...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(.weekyiiPrimary)
                }

                VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                    Text("将移动到")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textSecondary)
                    Text(resolvedTargetDateText)
                        .font(.bodyLarge.weight(.semibold))
                        .foregroundColor(.textPrimary)
                }
                .padding(WeekSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: WeekRadius.medium)
                        .fill(Color.backgroundSecondary)
                )

                Spacer(minLength: 0)

                HStack(spacing: WeekSpacing.sm) {
                    WeekButton("取消", style: .outline) {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)

                    WeekButton("继续", style: .primary) {
                        onSubmit(resolvedTargetDate)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(WeekSpacing.base)
            .navigationTitle("任务后移")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.backgroundPrimary)
        }
        .presentationDragIndicator(.visible)
    }
}
