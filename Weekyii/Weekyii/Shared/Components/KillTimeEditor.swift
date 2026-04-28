import SwiftUI

// MARK: - KillTimeEditor

struct KillTimeEditor: View {
    let hour: Int
    let minute: Int
    let isEditable: Bool
    let onChange: (Int, Int) -> Void
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var flamePulse = false

    // MARK: - Computed Properties

    /// 当前时间 + 1 小时，作为滑动条可选下界（最大不超过 23:59）
    private var minTimeInMinutes: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return min((c.hour ?? 0) * 60 + (c.minute ?? 0) + 60, endOfDayInMinutes)
    }

    private let endOfDayInMinutes: Int = 23 * 60 + 59

    private var clampedSelectedTimeInMinutes: Int {
        min(max(hour * 60 + minute, 0), endOfDayInMinutes)
    }

    private var minutesLeft: Int {
        Int(composeDate(hour: hour, minute: minute).timeIntervalSince(Date()) / 60)
    }

    private var fireLevel: Double {
        let left = max(0, minutesLeft)
        if left <= 5   { return 1.0 }
        if left <= 15  { return 0.85 }
        if left <= 30  { return 0.65 }
        if left <= 60  { return 0.45 }
        if left <= 120 { return 0.25 }
        return 0
    }

    /// 允许历史旧值低于当前 minTime，避免已设定的时间在展示时被强制上移
    private var sliderLowerBound: Double {
        Double(min(minTimeInMinutes, clampedSelectedTimeInMinutes))
    }

    private var isSliderRangeValid: Bool {
        sliderLowerBound < Double(endOfDayInMinutes)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            // 时间显示 + DatePicker 精确输入
            HStack(spacing: WeekSpacing.md) {
                HStack(spacing: WeekSpacing.xs) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(isEditable ? .accentOrange : .textSecondary)
                        .font(.title3)

                    Text(String(format: "%02d:%02d", hour, minute))
                        .font(.titleLarge)
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                }

                Spacer()

                if isEditable {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { composeDate(hour: hour, minute: minute) },
                            set: { newDate in
                                let c = Calendar(identifier: .iso8601)
                                    .dateComponents([.hour, .minute], from: newDate)
                                onChange(c.hour ?? hour, c.minute ?? minute)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .tint(.weekyiiPrimary)
                }
            }

            // 滑动条（含上下刻度尺）
            if isEditable {
                if isSliderRangeValid {
                    KillTimeSlider(
                        value: Double(clampedSelectedTimeInMinutes),
                        lowerBound: sliderLowerBound,
                        upperBound: Double(endOfDayInMinutes),
                        onChange: { newValue in
                            let total = Int(newValue.rounded())
                            onChange(total / 60, total % 60)
                        },
                        onEditingChanged: onEditingChanged
                    )
                } else {
                    Text("当前仅可选择 23:59，请使用时间选择器确认。")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }

            // 临近截止提示
            if fireLevel > 0 {
                HStack(spacing: WeekSpacing.xs) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.red.opacity(0.9), Color.orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(flamePulse ? 1.15 : 0.9)

                    Text("临近截止")
                        .font(.captionBold)
                        .foregroundColor(.accentOrange)

                    Spacer()

                    Text("\(max(0, minutesLeft)) 分钟")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.textSecondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: WeekRadius.medium)
                        .fill(Color.red.opacity(0.08 + 0.15 * fireLevel))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: WeekRadius.medium)
                        .stroke(Color.orange.opacity(0.35 + 0.45 * fireLevel), lineWidth: 1)
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        flamePulse = true
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func composeDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar(identifier: .iso8601)
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }
}

// MARK: - Preview

#Preview {
    WeekCard {
        KillTimeEditor(
            hour: 20,
            minute: 30,
            isEditable: true,
            onChange: { _, _ in }
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}
