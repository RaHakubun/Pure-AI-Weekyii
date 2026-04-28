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

enum PostponePresentationStyle {
    case sheet
    case centeredSquare
}

struct PostponeTaskSheet: View {
    let taskTitle: String
    let onSubmit: (Date) -> Void
    var presentationStyle: PostponePresentationStyle = .sheet
    var onCancel: (() -> Void)?

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
        Group {
            if presentationStyle == .sheet {
                content
                    .background(Color.backgroundPrimary)
            } else {
                content
                    .background(Color.backgroundPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: WeekRadius.large))
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                            Text("后移任务")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.textPrimary)
                            Text(taskTitle)
                                .font(.bodyLarge)
                                .foregroundColor(.textSecondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        if presentationStyle == .centeredSquare {
                            Button {
                                dismissAction()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Picker("后移方式", selection: $mode) {
                        ForEach(PostponeMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .font(.bodyMedium.weight(.semibold))
                    .frame(height: 44)

                    if mode == .relative {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            Text("快捷选择")
                                .font(.bodySmall.weight(.semibold))
                                .foregroundColor(.textSecondary)

                            HStack(spacing: WeekSpacing.sm) {
                                ForEach(quickRelativeOptions, id: \.self) { value in
                                    Button {
                                        relativeDays = value
                                    } label: {
                                        Text(value == 1 ? "明天" : "+\(value)天")
                                            .font(.bodySmall.weight(.semibold))
                                            .foregroundColor(relativeDays == value ? .white : .weekyiiPrimary)
                                            .padding(.vertical, WeekSpacing.sm)
                                            .padding(.horizontal, WeekSpacing.md)
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
                                    .font(.titleSmall.weight(.semibold))
                                    .foregroundColor(.textPrimary)
                            }
                            .controlSize(.large)
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
                            .font(.bodySmall.weight(.semibold))
                            .foregroundColor(.textSecondary)
                        Text(resolvedTargetDateText)
                            .font(.titleSmall.weight(.semibold))
                            .foregroundColor(.textPrimary)
                    }
                    .padding(WeekSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: WeekRadius.medium)
                            .fill(Color.backgroundSecondary)
                    )
                }
                .padding(.horizontal, WeekSpacing.lg)
                .padding(.top, WeekSpacing.lg)
                .padding(.bottom, WeekSpacing.base)
            }

            VStack(spacing: 0) {
                Divider()
                HStack(spacing: WeekSpacing.sm) {
                    WeekButton("取消", style: .outline) {
                        dismissAction()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)

                    WeekButton("继续", style: .primary) {
                        onSubmit(resolvedTargetDate)
                        dismissAction()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .padding(.horizontal, WeekSpacing.lg)
                .padding(.top, WeekSpacing.md)
                .padding(.bottom, WeekSpacing.lg)
                .background(Color.backgroundPrimary)
            }
        }
    }

    private func dismissAction() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }
}

struct CenteredSquareSizing {
    static func squareSide(for size: CGSize, scale: CGFloat = 0.7) -> CGFloat {
        min(size.width, size.height) * scale
    }
}

struct CenteredSquareModal<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let side = CenteredSquareSizing.squareSide(for: proxy.size, scale: 0.7)
            ZStack {
                Button(action: onDismiss) {
                    Color.black.opacity(0.45)
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()

                content()
                    .frame(width: side, height: side)
                    .shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: 10)
            }
        }
    }
}
