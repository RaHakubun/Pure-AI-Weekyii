import SwiftUI

// MARK: - TaskZoneBadge - 任务区域徽章

struct TaskZoneBadge: View {
    let zone: TaskZone
    
    var body: some View {
        Text(zoneName)
            .font(.captionBold)
            .foregroundColor(zoneColor)
            .padding(.horizontal, WeekSpacing.sm)
            .padding(.vertical, WeekSpacing.xs)
            .background(zoneColor.opacity(0.15))
            .cornerRadius(WeekRadius.small)
    }
    
    private var zoneName: String {
        switch zone {
        case .draft: return String(localized: "zone.draft")
        case .focus: return String(localized: "zone.focus")
        case .frozen: return String(localized: "zone.frozen")
        case .complete: return String(localized: "zone.complete")
        }
    }
    
    private var zoneColor: Color {
        switch zone {
        case .draft: return .textSecondary
        case .focus: return .accentOrange
        case .frozen: return .weekyiiPrimary
        case .complete: return .accentGreen
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 12) {
        TaskZoneBadge(zone: .draft)
        TaskZoneBadge(zone: .focus)
        TaskZoneBadge(zone: .frozen)
        TaskZoneBadge(zone: .complete)
    }
    .padding()
    .background(Color.backgroundPrimary)
}
