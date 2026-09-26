import SwiftData
import SwiftUI

// MARK: - Habit Detail View - 习惯详情页

struct HabitDetailView: View {
    let habit: HabitModel
    let viewModel: HabitViewModel

    @State private var showingEditor = false
    @State private var showingDeleteConfirm = false
    @State private var alertMessage: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                identitySection(stats: stats)
                actionSection(stats: stats)
                statisticsCard(stats: stats)
                timelineSection
            }
            .padding(.horizontal, WeekSpacing.base)
            .padding(.vertical, WeekSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("habitDetailView")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditor = true
                    } label: {
                        Label(String(localized: "action.edit"), systemImage: "pencil")
                    }
                    .accessibilityIdentifier("habitDetailEditButton")

                    Button {
                        toggleActive()
                    } label: {
                        Label(
                            habit.isActive
                                ? String(localized: "habit.action.archive", defaultValue: "停用")
                                : String(localized: "habit.action.restore", defaultValue: "恢复"),
                            systemImage: habit.isActive ? "archivebox" : "arrow.uturn.backward"
                        )
                    }
                    .accessibilityIdentifier("habitDetailArchiveButton")

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label(String(localized: "habit.detail.delete", defaultValue: "删除习惯"), systemImage: "trash")
                    }
                    .accessibilityIdentifier("habitDetailDeleteButton")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Color.textPrimary)
                }
                .accessibilityIdentifier("habitDetailMenu")
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            viewModel.refresh()
        }) {
            HabitEditorSheet(viewModel: viewModel, habit: habit)
        }
        .confirmationDialog(
            String(localized: "habit.detail.delete", defaultValue: "删除习惯"),
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "habit.detail.delete", defaultValue: "删除习惯"), role: .destructive) {
                deleteHabit()
            }
            Button(String(localized: "action.cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "habit.detail.delete_confirm", defaultValue: "删除后未开始日期中的该习惯任务会被移除，已开始的日期仅解除关联；全部打卡记录与统计将一并删除。"))
        }
        .onAppear {
            viewModel.refresh()
        }
        .refreshOnStateTransitions(using: appState) {
            viewModel.refresh()
            if habit.isDeleted { dismiss() }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let newValue { alertMessage = newValue }
        }
        .alert(String(localized: "alert.title"), isPresented: Binding(get: {
            alertMessage != nil
        }, set: { newValue in
            if !newValue { alertMessage = nil }
        })) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Identity

    private var stats: HabitStatistics {
        viewModel.statistics(for: habit)
    }

    private func identitySection(stats: HabitStatistics) -> some View {
        WeekCard(accentColor: habit.habitColor) {
            HStack(alignment: .top, spacing: WeekSpacing.md) {
                Image(systemName: habit.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(habit.habitColor)
                    .frame(width: 58, height: 58)
                    .background(habit.habitColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(habit.name)
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    Text("\(habit.category.displayName) · \(habit.scheduleSummary)")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)

                    if habit.startDate != nil {
                        Text(startsOnText)
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                HabitTodayStatusChip(status: stats.todayStatus)
            }
        }
    }


    // MARK: - Actions

    @ViewBuilder
    private func actionSection(stats: HabitStatistics) -> some View {
        if stats.todayStatus != .notScheduled && !stats.hasTodayTask {
            Button {
                addToday()
            } label: {
                HStack(spacing: WeekSpacing.xs) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(String(localized: "habit.detail.add_today", defaultValue: "加入今日"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WeekSpacing.md)
                .background(Color.accentGreen)
                .clipShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityIdentifier("habitDetailAddTodayButton")
        }
    }

    // MARK: - Statistics

    private func statisticsCard(stats: HabitStatistics) -> some View {
        WeekCard(accentColor: habit.habitColor) {
            VStack(alignment: .leading, spacing: WeekSpacing.md) {
                Text(String(localized: "habit.stats.title", defaultValue: "统计"))
                    .font(.titleSmall)
                    .foregroundColor(.textPrimary)

                HStack(spacing: 0) {
                    statColumn(
                        title: String(localized: "habit.stats.current_streak", defaultValue: "当前连续"),
                        value: "\(stats.currentStreak)"
                    )
                    Divider().frame(height: 36)
                    statColumn(
                        title: String(localized: "habit.stats.longest_streak", defaultValue: "最长连续"),
                        value: "\(stats.longestStreak)"
                    )
                    Divider().frame(height: 36)
                    statColumn(
                        title: String(localized: "habit.stats.completion_rate", defaultValue: "完成率"),
                        value: stats.completionRatePercent.map { "\($0)%" }
                            ?? String(localized: "habit.stats.placeholder", defaultValue: "—")
                    )
                    Divider().frame(height: 36)
                    statColumn(
                        title: String(localized: "habit.stats.total_completed", defaultValue: "累计完成"),
                        value: "\(stats.completedCount)"
                    )
                }
                .animation(.snappy(duration: 0.25), value: stats)
            }
        }
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(habit.habitColor)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }


    // MARK: - Timeline

    private var timelineSection: some View {
        let groups = timelineGroups
        return VStack(alignment: .leading, spacing: WeekSpacing.md) {
            Text(String(localized: "habit.timeline.title", defaultValue: "时间线"))
                .font(.titleMedium)
                .foregroundColor(.textPrimary)

            if groups.isEmpty {
                Text(startsOnText)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .weekPaddingVertical(WeekSpacing.lg)
            } else {
                LazyVStack(alignment: .leading, spacing: WeekSpacing.md) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.textSecondary)
                                .padding(.leading, WeekSpacing.xs)

                            VStack(spacing: 0) {
                                ForEach(group.nodes) { node in
                                    timelineRow(node)
                                    if node.id != group.nodes.last?.id {
                                        Divider()
                                            .padding(.leading, 22)
                                    }
                                }
                            }
                            .background(Color.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                                    .stroke(Color.backgroundTertiary, lineWidth: 1)
                            )
                        }
                    }
                }
            }

            // Footer note - wrapped in a subtle info chip
            HStack(alignment: .top, spacing: WeekSpacing.xs) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
                Text(String(localized: "habit.timeline.footer", defaultValue: "「中断」= 当日已生成但未完成；「未记录」= 当日未生成（未打开 App 或已过截止时间）。"))
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, WeekSpacing.sm)
            .padding(.vertical, WeekSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.small))
        }
    }


    private func timelineRow(_ node: HabitTimelineNode) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            timelineDot(node.state)

            Text(node.date, format: .dateTime.month().day().weekday())
                .font(.bodyMedium)
                .foregroundColor(node.state == .unrecorded ? .textSecondary : .textPrimary)

            Spacer(minLength: WeekSpacing.sm)

            Text(statusText(node))
                .font(.caption.weight(.medium))
                .foregroundColor(statusColor(node.state))
        }
        .padding(.horizontal, WeekSpacing.md)
        .padding(.vertical, WeekSpacing.sm + 2)
    }


    @ViewBuilder
    private func timelineDot(_ state: HabitTimelineNodeState) -> some View {
        switch state {
        case .completed:
            Circle()
                .fill(habit.habitColor)
                .frame(width: 10, height: 10)
        case .missed:
            Circle()
                .strokeBorder(Color.taskDDL, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        case .pending:
            ZStack {
                Circle()
                    .fill(habit.habitColor.opacity(0.18))
                Circle()
                    .strokeBorder(habit.habitColor, lineWidth: 1.5)
            }
            .frame(width: 10, height: 10)
        case .unrecorded:
            Circle()
                .strokeBorder(Color.textTertiary.opacity(0.45), lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
    }

    private func statusText(_ node: HabitTimelineNode) -> String {
        switch node.state {
        case .completed:
            guard let completedAt = node.completedAt else {
                return String(localized: "habit.record.status.completed", defaultValue: "已完成")
            }
            let time = Self.timeFormatter.string(from: completedAt)
            return String(
                format: String(localized: "habit.record.completed_at %@", defaultValue: "完成于 %@"),
                locale: Locale.current,
                time
            )
        case .missed:
            return String(localized: "habit.record.status.missed", defaultValue: "中断")
        case .pending:
            return String(localized: "habit.record.status.pending", defaultValue: "待完成")
        case .unrecorded:
            return String(localized: "habit.record.unrecorded", defaultValue: "未记录")
        }
    }

    private func statusColor(_ state: HabitTimelineNodeState) -> Color {
        switch state {
        case .completed, .pending: return habit.habitColor
        case .missed: return .taskDDL
        case .unrecorded: return .textTertiary
        }
    }

    private var timelineGroups: [TimelineGroup] {
        let nodes = HabitStatisticsCalculator.timeline(for: habit)
        guard !nodes.isEmpty else { return [] }

        let calendar = Calendar(identifier: .iso8601)
        var groups: [TimelineGroup] = []
        for node in nodes {
            let components = calendar.dateComponents([.year, .month], from: node.date)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)"
            if groups.last?.id == key {
                groups[groups.count - 1].nodes.append(node)
            } else {
                groups.append(TimelineGroup(id: key, monthStart: node.date, nodes: [node]))
            }
        }
        return groups
    }

    private struct TimelineGroup: Identifiable {
        let id: String
        let monthStart: Date
        var nodes: [HabitTimelineNode]

        var title: String {
            monthStart.formatted(.dateTime.year().month())
        }
    }

    // MARK: - Helpers

    private var startsOnText: String {
        guard let startDate = habit.startDate else { return "" }
        return String(
            format: String(localized: "habit.timeline.starts_on %@", defaultValue: "将于 %@ 开始"),
            locale: Locale.current,
            startDate.formatted(date: .abbreviated, time: .omitted)
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - Actions

    private func addToday() {
        do {
            let outcome = try viewModel.assignToday(habit)
            switch outcome {
            case .created:
                break
            case .alreadyExists:
                alertMessage = String(
                    localized: "habit.detail.add_today.result.exists",
                    defaultValue: "今日已存在该习惯任务"
                )
            case .dayLocked:
                alertMessage = String(localized: "habit.error.day_locked", defaultValue: "日期已锁定")
            case .pastKillTime:
                alertMessage = String(
                    localized: "habit.error.past_kill_time",
                    defaultValue: "已过今日截止时间，明天会自动加入"
                )
            case .notScheduledToday:
                alertMessage = String(
                    localized: "habit.error.not_scheduled_today",
                    defaultValue: "今天不在该习惯的重复计划内"
                )
            case .failed:
                break
            }
        } catch {
            if viewModel.errorMessage == nil {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func toggleActive() {
        do {
            try viewModel.setActive(habit, !habit.isActive)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deleteHabit() {
        do {
            try viewModel.deleteHabit(habit)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
