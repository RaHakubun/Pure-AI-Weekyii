import SwiftUI
import SwiftData

struct WeekOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WeekViewModel?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    if let week = viewModel?.presentWeek {
                        VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                            // 周统计卡片
                            WeekStatCard(week: week)

                            // 日期网格
                            LazyVGrid(
                                columns: WeekLayoutMetrics.dayGridColumns(containerWidth: geometry.size.width),
                                spacing: WeekSpacing.md
                            ) {
                                ForEach(week.days.sorted(by: { $0.date < $1.date })) { day in
                                    NavigationLink {
                                        DayDetailView(day: day)
                                    } label: {
                                        DayCard(day: day)
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                        }
                        .weekPadding(WeekSpacing.base)
                        .padding(.bottom, WeekSpacing.xl)
                    } else if let message = viewModel?.errorMessage {
                        errorState(message: message) {
                            viewModel?.refresh()
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: WeekSpacing.sm) {
                        WeekLogo(size: .small, animated: false)
                        if let week = viewModel?.presentWeek {
                            Text(week.weekId)
                                .font(.titleSmall)
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = WeekViewModel(modelContext: modelContext, timeProvider: TimeProvider())
            }
            viewModel?.refresh()
        }
    }

    @ViewBuilder
    private func errorState(message: String, onRetry: @escaping () -> Void) -> some View {
        WeekCard(accentColor: .taskDDL) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(spacing: WeekSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.taskDDL)
                    Text(String(localized: "alert.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                Text(message)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                WeekButton("重试", icon: "arrow.clockwise", style: .secondary, action: onRetry)
            }
        }
        .weekPadding(WeekSpacing.base)
    }
}

struct WeekOverviewContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WeekViewModel?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if let week = viewModel?.presentWeek {
                    VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                        WeekStatCard(week: week)
                        WeekTimelineView(week: week)

                        LazyVGrid(
                            columns: WeekLayoutMetrics.dayGridColumns(containerWidth: geometry.size.width),
                            spacing: WeekSpacing.md
                        ) {
                            ForEach(week.days.sorted(by: { $0.date < $1.date })) { day in
                                NavigationLink {
                                    DayDetailView(day: day)
                                } label: {
                                    DayCard(day: day)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                    }
                    .weekPadding(WeekSpacing.base)
                    .padding(.bottom, WeekSpacing.xl)
                } else if let message = viewModel?.errorMessage {
                    errorState(message: message) {
                        viewModel?.refresh()
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = WeekViewModel(modelContext: modelContext, timeProvider: TimeProvider())
            }
            viewModel?.refresh()
        }
    }

    @ViewBuilder
    private func errorState(message: String, onRetry: @escaping () -> Void) -> some View {
        WeekCard(accentColor: .taskDDL) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(spacing: WeekSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.taskDDL)
                    Text(String(localized: "alert.title"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }
                Text(message)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                WeekButton("重试", icon: "arrow.clockwise", style: .secondary, action: onRetry)
            }
        }
        .weekPadding(WeekSpacing.base)
    }
}

private struct WeekTimelineView: View {
    let week: WeekModel
    @State private var expandedDayId: String?
    @State private var hasAppeared = false
    private static let weekdayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE Md")
        return formatter
    }()

    private var sortedDays: [DayModel] {
        week.days.sorted { $0.date < $1.date }
    }

    var body: some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(spacing: WeekSpacing.sm) {
                    Image(systemName: "timeline.selection")
                        .foregroundColor(.weekyiiPrimary)
                    Text("本周时间线")
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)
                }

                VStack(spacing: WeekSpacing.sm) {
                    ForEach(Array(sortedDays.enumerated()), id: \.element.dayId) { index, day in
                        timelineRow(day: day, index: index)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 8)
                            .animation(
                                .easeOut(duration: 0.22).delay(Double(index) * 0.03),
                                value: hasAppeared
                            )
                    }
                }
            }
        }
        .onAppear {
            hasAppeared = true
        }
    }

    private func timelineRow(day: DayModel, index: Int) -> some View {
        let isExpanded = expandedDayId == day.dayId
        let isToday = Calendar(identifier: .iso8601).isDateInToday(day.date)
        let isLast = index == sortedDays.count - 1
        let tasks = displayTasks(for: day)

        return VStack(alignment: .leading, spacing: WeekSpacing.xs) {
            HStack(alignment: .top, spacing: WeekSpacing.md) {
                timelineMarker(
                    color: day.status.color,
                    isToday: isToday,
                    isLast: isLast
                )

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        expandedDayId = isExpanded ? nil : day.dayId
                    }
                } label: {
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        HStack {
                            Text(weekdayAndDate(day.date))
                                .font(.bodyMedium.weight(.semibold))
                                .foregroundColor(.textPrimary)

                            Spacer()

                            StatusBadge(status: day.status)
                        }

                        HStack(spacing: WeekSpacing.md) {
                            labelMetric("完成 \(day.completedTasks.count)")
                            labelMetric("过期 \(day.expiredCount)")
                            labelMetric("专注 \(focusDurationText(day))")
                        }
                    }
                    .padding(WeekSpacing.md)
                    .background(Color.backgroundSecondary)
                    .clipShape(.rect(cornerRadius: WeekRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: WeekRadius.medium)
                            .stroke(isExpanded ? day.status.color.opacity(0.35) : Color.backgroundTertiary, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                    ForEach(tasks) { task in
                        TaskRowView(task: task)
                    }
                    if tasks.isEmpty {
                        Text(String(localized: "day.empty.title"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .padding(.leading, 4)
                    }
                }
                .padding(.leading, 38)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func timelineMarker(color: Color, isToday: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if isToday {
                    Circle()
                        .stroke(color.opacity(0.45), lineWidth: 3)
                        .frame(width: 16, height: 16)
                }
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            }

            if !isLast {
                Rectangle()
                    .fill(Color.backgroundTertiary)
                    .frame(width: 2, height: 56)
                    .padding(.top, 4)
            }
        }
        .frame(width: 22)
    }

    private func labelMetric(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.textSecondary)
    }

    private func weekdayAndDate(_ date: Date) -> String {
        Self.weekdayDateFormatter.string(from: date)
    }

    private func focusDurationText(_ day: DayModel) -> String {
        var total: TimeInterval = day.completedTasks.reduce(0) { partial, task in
            guard let start = task.startedAt, let end = task.endedAt, end >= start else { return partial }
            return partial + end.timeIntervalSince(start)
        }

        if day.status == .execute, let focus = day.focusTask, let start = focus.startedAt {
            total += max(0, Date().timeIntervalSince(start))
        }

        let minutes = Int(total / 60)
        if minutes <= 0 { return "--" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h\(minutes % 60)m"
    }

    private func displayTasks(for day: DayModel) -> [TaskItem] {
        day.tasks.sorted { lhs, rhs in
            let left = taskSortKey(lhs)
            let right = taskSortKey(rhs)
            if left == right {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return left < right
        }
    }

    private func taskSortKey(_ task: TaskItem) -> Int {
        switch task.zone {
        case .focus:
            return 0
        case .frozen:
            return 1_000 + task.order
        case .draft:
            return 2_000 + task.order
        case .complete:
            return 3_000 + task.completedOrder
        }
    }
}
