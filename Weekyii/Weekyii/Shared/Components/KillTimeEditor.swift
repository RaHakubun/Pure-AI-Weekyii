import SwiftUI

// MARK: - KillTimeEditor - Kill Time 编辑器

struct KillTimeEditor: View {
    let hour: Int
    let minute: Int
    let isEditable: Bool
    let onChange: (Int, Int) -> Void
    var onEditingChanged: ((Bool) -> Void)? = nil
    @State private var flamePulse = false
    @State private var editingSliderLowerBound: Double?
    
    // 计算当前时间+1小时对应的分钟数（作为滑动条最小值，避免立即过期）
    private var minTimeInMinutes: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        // 当前时间 + 1小时，但不超过23:59
        return min(currentMinutes + 60, 23 * 60 + 59)
    }
    
    // 23:59 对应的分钟数（作为滑动条最大值）
    private let endOfDayInMinutes: Int = 23 * 60 + 59
    
    // 当前选择的时间对应的分钟数
    private var selectedTimeInMinutes: Int {
        hour * 60 + minute
    }

    // 防御性钳制，避免历史脏值导致 Slider 崩溃
    private var clampedSelectedTimeInMinutes: Int {
        min(max(selectedTimeInMinutes, 0), endOfDayInMinutes)
    }

    private var minutesLeft: Int {
        let now = Date()
        let selectedDate = composeDate(hour: hour, minute: minute)
        return Int(selectedDate.timeIntervalSince(now) / 60)
    }

    private var fireLevel: Double {
        let left = max(0, minutesLeft)
        if left <= 5 { return 1.0 }
        if left <= 15 { return 0.85 }
        if left <= 30 { return 0.65 }
        if left <= 60 { return 0.45 }
        if left <= 120 { return 0.25 }
        return 0
    }
    
    // 滑动条基础下界：最少为当前时间+1小时，但允许保留已选旧值
    private var sliderBaseLowerBound: Double {
        Double(min(minTimeInMinutes, clampedSelectedTimeInMinutes))
    }

    // 拖动过程中固定下界，避免 range 与 value 同步抖动导致内部断言
    private var sliderLowerBound: Double {
        let raw = editingSliderLowerBound ?? sliderBaseLowerBound
        return min(max(raw, 0), Double(endOfDayInMinutes))
    }

    private var sliderUpperBound: Double {
        Double(endOfDayInMinutes)
    }

    private var isSliderRangeValid: Bool {
        sliderLowerBound < sliderUpperBound
    }

    private var sliderDisplayValue: Double {
        min(max(Double(clampedSelectedTimeInMinutes), sliderLowerBound), sliderUpperBound)
    }
    
    // 刻度标记的类型别名
    private struct ScaleMark {
        let minutes: Int
        let label: String
    }
    
    // 生成刻度标记的时间点
    private var scaleMarks: [ScaleMark] {
        let marks = [
            ScaleMark(minutes: 18 * 60, label: "18:00"),
            ScaleMark(minutes: 20 * 60, label: "20:00"),
            ScaleMark(minutes: 22 * 60, label: "22:00"),
            ScaleMark(minutes: 23 * 60 + 59, label: "23:59")
        ]
        // 只显示在有效范围内的刻度
        return marks.filter { $0.minutes >= Int(sliderLowerBound) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HStack(spacing: WeekSpacing.md) {
                // 时间显示
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
                
                // 时间选择器（备用精确选择）
                if isEditable {
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
                    .tint(.weekyiiPrimary)
                }
            }
            
            // 时间滑动条
            if isEditable {
                VStack(spacing: WeekSpacing.xs) {
                    if isSliderRangeValid {
                        // 滑动条
                        Slider(
                            value: Binding(
                                get: { sliderDisplayValue },
                                set: { newValue in
                                    let clampedValue = min(max(newValue, sliderLowerBound), sliderUpperBound)
                                    let totalMinutes = Int(clampedValue.rounded())
                                    let newHour = totalMinutes / 60
                                    let newMinute = totalMinutes % 60
                                    withAnimation(.easeInOut(duration: 0.1)) {
                                        onChange(newHour, newMinute)
                                    }
                                }
                            ),
                            in: sliderLowerBound...sliderUpperBound,
                            step: 1,
                            onEditingChanged: { editing in
                                if editing {
                                    editingSliderLowerBound = sliderBaseLowerBound
                                } else {
                                    editingSliderLowerBound = nil
                                }
                                onEditingChanged?(editing)
                            }
                        )
                        .tint(.weekyiiPrimary)
                    } else {
                        Text("当前仅可选择 23:59，请使用时间选择器确认。")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    
                    // 刻度标记
                    GeometryReader { geometry in
                        let totalRange = sliderUpperBound - sliderLowerBound
                        
                        ZStack(alignment: .topLeading) {
                            ForEach(scaleMarks, id: \.minutes) { mark in
                                let position = totalRange > 0 
                                    ? (Double(mark.minutes) - sliderLowerBound) / totalRange * geometry.size.width
                                    : 0
                                
                                VStack(spacing: 2) {
                                    Rectangle()
                                        .fill(Color.textSecondary.opacity(0.5))
                                        .frame(width: 1, height: 6)
                                    
                                    Text(mark.label)
                                        .font(.system(size: 10))
                                        .foregroundColor(.textSecondary)
                                }
                                .position(x: position, y: 12)
                            }
                        }
                    }
                    .frame(height: 24)
                }
            }

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
