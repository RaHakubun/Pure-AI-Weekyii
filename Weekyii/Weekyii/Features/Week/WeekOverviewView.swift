import SwiftUI
import SwiftData

enum WeekOverviewDisplayMode: String, CaseIterable, Identifiable {
    case cards
    case strips
    case collapsed

    var id: String { rawValue }

    var next: Self {
        switch self {
        case .cards:
            return .strips
        case .strips:
            return .collapsed
        case .collapsed:
            return .cards
        }
    }

    var title: String {
        switch self {
        case .cards:
            return "当前状态"
        case .strips:
            return "信息横条"
        case .collapsed:
            return "折叠"
        }
    }

    var iconName: String {
        switch self {
        case .cards:
            return "square.grid.2x2.fill"
        case .strips:
            return "rectangle.grid.1x2.fill"
        case .collapsed:
            return "rectangle.compress.vertical"
        }
    }
}

enum WeekOverviewDayHighlight: Equatable {
    case focus(String)
    case draft(String)
    case frozen(String)
    case completed(String)
    case expired(String)
    case empty(String)

    var title: String {
        switch self {
        case .focus:
            return "当前专注"
        case .draft:
            return "首条草稿"
        case .frozen:
            return "冻结队列"
        case .completed:
            return "完成回顾"
        case .expired:
            return "过期提醒"
        case .empty:
            return "暂无任务"
        }
    }

    var detail: String {
        switch self {
        case .focus(let text),
             .draft(let text),
             .frozen(let text),
             .completed(let text),
             .expired(let text),
             .empty(let text):
            return text
        }
    }

    var iconName: String {
        switch self {
        case .focus:
            return "scope"
        case .draft:
            return "pencil.line"
        case .frozen:
            return "snowflake"
        case .completed:
            return "checkmark.circle.fill"
        case .expired:
            return "exclamationmark.circle.fill"
        case .empty:
            return "tray"
        }
    }
}

struct WeekOverviewDayStripSummary: Equatable {
    let highlight: WeekOverviewDayHighlight
    let draftCount: Int
    let remainingCount: Int
    let completedCount: Int
    let expiredCount: Int
    let totalCount: Int

    init(day: DayModel) {
        draftCount = day.sortedDraftTasks.count
        completedCount = day.completedTasks.count
        expiredCount = day.expiredCount
        totalCount = day.tasks.count
        remainingCount = day.sortedDraftTasks.count + day.frozenTasks.count + (day.focusTask == nil ? 0 : 1)

        if let focusTask = day.focusTask {
            highlight = .focus(focusTask.title)
        } else if let draftTask = day.sortedDraftTasks.first {
            highlight = .draft(draftTask.title)
        } else if let frozenTask = day.frozenTasks.first {
            highlight = .frozen(frozenTask.title)
        } else if completedCount > 0 {
            highlight = .completed("\(completedCount) 项已完成")
        } else if expiredCount > 0 {
            highlight = .expired("\(expiredCount) 项已过期")
        } else {
            highlight = .empty("当天暂无可展示内容")
        }
    }
}

struct WeekOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WeekViewModel?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let week = viewModel?.presentWeek {
                    VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                        // 周统计卡片
                        WeekStatCard(week: week)
                        
                        // 日期网格
                        LazyVGrid(columns: columns, spacing: WeekSpacing.md) {
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
                } else if let message = viewModel?.errorMessage {
                    errorState(message: message) {
                        viewModel?.refresh()
                    }
                } else {
                    ProgressView()
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
    @State private var displayMode: WeekOverviewDisplayMode = .cards

    var body: some View {
        ScrollView {
            if let week = viewModel?.presentWeek {
                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                    WeekStatCard(week: week)
                    WeekTimelineView(week: week)
                    WeekOverviewDetailSection(week: week, displayMode: $displayMode)
                }
                .weekPadding(WeekSpacing.base)
            } else if let message = viewModel?.errorMessage {
                errorState(message: message) {
                    viewModel?.refresh()
                }
            } else {
                ProgressView()
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

private struct WeekOverviewDetailSection: View {
    let week: WeekModel
    @Binding var displayMode: WeekOverviewDisplayMode

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var sortedDays: [DayModel] {
        week.days.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            Text("本周详情")
                .font(.titleSmall)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    Button {
                        displayMode = displayMode.next
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.weekyiiPrimary)
                            .frame(width: 46, height: 46)
                            .background(
                                Circle()
                                    .fill(Color.backgroundSecondary)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.backgroundTertiary, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weekOverviewModeCycleButton")
                }

            WeekOverviewModeSwitcher(displayMode: $displayMode)

            Group {
                switch displayMode {
                case .cards:
                    LazyVGrid(columns: columns, spacing: WeekSpacing.md) {
                        ForEach(Array(sortedDays.enumerated()), id: \.element.dayId) { index, day in
                            NavigationLink {
                                DayDetailView(day: day)
                            } label: {
                                DayCard(day: day)
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .accessibilityIdentifier("weekDayCard_\(index)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("weekOverviewCardsGrid")

                case .strips:
                    VStack(spacing: WeekSpacing.sm) {
                        ForEach(Array(sortedDays.enumerated()), id: \.element.dayId) { index, day in
                            NavigationLink {
                                DayDetailView(day: day)
                            } label: {
                                WeekOverviewStripRow(day: day)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("weekStripRow_\(index)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("weekOverviewStripList")

                case .collapsed:
                    WeekCard(accentColor: .weekyiiPrimary) {
                        HStack(alignment: .top, spacing: WeekSpacing.md) {
                            Image(systemName: "rectangle.compress.vertical")
                                .font(.title3)
                                .foregroundStyle(Color.weekyiiPrimary)

                            VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                                Text("七天详情已折叠")
                                    .font(.bodyMedium.weight(.semibold))
            .foregroundStyle(Color.textPrimary)
                                Text("上方时间线仍然保留；需要展开时，切回“当前状态”或“信息横条”。")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("weekOverviewCollapsedState")
                }
            }
        }
    }
}

private struct WeekOverviewModeSwitcher: View {
    @Binding var displayMode: WeekOverviewDisplayMode

    var body: some View {
        HStack(spacing: WeekSpacing.xs) {
            ForEach(WeekOverviewDisplayMode.allCases) { mode in
                Button {
                    displayMode = mode
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.iconName)
                            .font(.callout.weight(.semibold))
                        Text(mode.title)
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(displayMode == mode ? Color.white : Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WeekSpacing.md)
                    .background(
                        Capsule()
                            .fill(displayMode == mode ? Color.weekyiiPrimary : Color.backgroundSecondary)
                    )
                    .overlay(
                        Capsule()
                            .stroke(displayMode == mode ? Color.clear : Color.backgroundTertiary, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("weekOverviewMode_\(mode.rawValue)")
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: displayMode)
    }
}

private struct WeekOverviewStripRow: View {
    let day: DayModel
    private let summary: WeekOverviewDayStripSummary

    init(day: DayModel) {
        self.day = day
        self.summary = WeekOverviewDayStripSummary(day: day)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE Md")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HStack(alignment: .center, spacing: WeekSpacing.sm) {
                Text(Self.weekdayFormatter.string(from: day.date))
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 0)

                StatusBadge(status: day.status)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            HStack(alignment: .top, spacing: WeekSpacing.sm) {
                Image(systemName: summary.highlight.iconName)
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(highlightTint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.highlight.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(summary.highlight.detail)
                        .font(.bodyMedium.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: WeekSpacing.xs) {
                metricPill(label: "总", value: summary.totalCount, tint: .weekyiiPrimary)
                metricPill(label: "剩余", value: summary.remainingCount, tint: .accentOrange)
                metricPill(label: "完成", value: summary.completedCount, tint: .accentGreen)
                if summary.expiredCount > 0 {
                    metricPill(label: "过期", value: summary.expiredCount, tint: .taskDDL)
                }
            }
        }
        .padding(WeekSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .stroke(Color.backgroundTertiary, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var highlightTint: Color {
        switch summary.highlight {
        case .focus:
            return .weekyiiPrimary
        case .draft:
            return .accentOrange
        case .frozen:
            return .taskLeisure
        case .completed:
            return .accentGreen
        case .expired:
            return .taskDDL
        case .empty:
            return .textSecondary
        }
    }

    private func metricPill(label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text("\(value)")
                .fontWeight(.semibold)
        }
        .font(.caption2)
        .foregroundStyle(tint)
        .padding(.horizontal, WeekSpacing.sm)
        .padding(.vertical, WeekSpacing.xs)
        .background(tint.opacity(0.12), in: Capsule())
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
