import SwiftUI

// MARK: - KillTimeEditor - Kill Time 编辑器

struct KillTimeEditor: View {
    let hour: Int
    let minute: Int
    let isEditable: Bool
    let onChange: (Int, Int) -> Void
    
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
    
    // 计算滑动条的实际最小值（确保不超过当前选择值）
    private var sliderMinValue: Double {
        Double(min(minTimeInMinutes, selectedTimeInMinutes))
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
        return marks.filter { $0.minutes >= Int(sliderMinValue) }
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
                    // 滑动条
                    Slider(
                        value: Binding(
                            get: { Double(selectedTimeInMinutes) },
                            set: { newValue in
                                let totalMinutes = Int(newValue)
                                let newHour = totalMinutes / 60
                                let newMinute = totalMinutes % 60
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    onChange(newHour, newMinute)
                                }
                            }
                        ),
                        in: sliderMinValue...Double(endOfDayInMinutes),
                        step: 1
                    )
                    .tint(.weekyiiPrimary)
                    
                    // 刻度标记
                    GeometryReader { geometry in
                        let totalRange = Double(endOfDayInMinutes) - sliderMinValue
                        
                        ZStack(alignment: .topLeading) {
                            ForEach(scaleMarks, id: \.minutes) { mark in
                                let position = totalRange > 0 
                                    ? (Double(mark.minutes) - sliderMinValue) / totalRange * geometry.size.width
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
            onChange: { h, m in
                print("Time changed: \(h):\(m)")
            }
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}
