import SwiftUI

enum MonthRestriction {
    case none       // 无限制
    case pastOnly   // 只能看过去和当前月份（用于「过去」视图）
    case futureOnly // 只能看未来和当前月份（用于「未来」视图）
}

struct MonthPickerView: View {
    @Binding var month: Date
    var restriction: MonthRestriction = .none
    private let calendar = Calendar(identifier: .iso8601)
    
    // 当前月份的第一天（用于比较）
    private var currentMonthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: components) ?? Date()
    }
    
    // 选中月份的第一天
    private var selectedMonthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: month)
        return calendar.date(from: components) ?? month
    }
    
    // 是否可以往前（更早的月份）
    private var canGoPrevious: Bool {
        switch restriction {
        case .none, .pastOnly:
            return true
        case .futureOnly:
            // 未来视图：不能往前于当前月份
            return selectedMonthStart > currentMonthStart
        }
    }
    
    // 是否可以往后（更晚的月份）
    private var canGoNext: Bool {
        switch restriction {
        case .none, .futureOnly:
            return true
        case .pastOnly:
            // 过去视图：不能往后于当前月份
            return selectedMonthStart < currentMonthStart
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: { month = previousMonth(from: month) }) {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoPrevious)
            .opacity(canGoPrevious ? 1 : 0.3)

            Text(month, format: Date.FormatStyle().year().month())
                .font(.headline)
                .frame(maxWidth: .infinity)

            Button(action: { month = nextMonth(from: month) }) {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoNext)
            .opacity(canGoNext ? 1 : 0.3)
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

