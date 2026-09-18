import SwiftUI

// MARK: - Habits Full View - 习惯管理页

struct HabitsFullView: View {
    @State private var viewModel: HabitViewModel
    @State private var showingEditor = false
    @State private var errorMessage: String?
    @EnvironmentObject private var appState: AppState

    init(viewModel: HabitViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WeekSpacing.lg) {
                progressCard

                if viewModel.activeHabits.isEmpty && viewModel.archivedHabits.isEmpty {
                    emptyState
                } else {
                    if !viewModel.activeHabits.isEmpty {
                        habitSection(
                            title: String(localized: "habits.section.active", defaultValue: "进行中"),
                            habits: viewModel.activeHabits
                        )
                    }
                    if !viewModel.archivedHabits.isEmpty {
                        habitSection(
                            title: String(localized: "habits.archived.section", defaultValue: "已停用"),
                            habits: viewModel.archivedHabits
                        )
                    }
                }
            }
            .padding(.horizontal, WeekSpacing.base)
            .padding(.vertical, WeekSpacing.md)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "habits.title", defaultValue: "我的习惯"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("habitsFullView")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentGreen)
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel(String(localized: "habits.empty.action", defaultValue: "新建习惯"))
                .accessibilityIdentifier("habitsToolbarCreateButton")
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            viewModel.refresh()
        }) {
            HabitEditorSheet(viewModel: viewModel)
        }
        .onAppear {
            viewModel.refresh()
        }
        .refreshOnStateTransitions(using: appState) {
            viewModel.refresh()
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let newValue { errorMessage = newValue }
        }
        .alert(String(localized: "alert.title"), isPresented: Binding(get: {
            errorMessage != nil
        }, set: { newValue in
            if !newValue { errorMessage = nil }
        })) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Today Progress

    private var todayProgress: (completed: Int, scheduled: Int) {
        var completed = 0
        var scheduled = 0
        for habit in viewModel.activeHabits {
            let status = viewModel.statistics(for: habit).todayStatus
            guard status != .notScheduled else { continue }
            scheduled += 1
            if status == .completed { completed += 1 }
        }
        return (completed, scheduled)
    }

    private var progressCard: some View {
        let progress = todayProgress
        return WeekCard(accentColor: .accentGreen) {
            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(localized: "habits.title", defaultValue: "我的习惯"))
                        .font(.titleSmall)
                        .foregroundColor(.textPrimary)

                    Spacer(minLength: WeekSpacing.sm)

                    Text(
                        String(
                            format: String(localized: "habits.today.progress", defaultValue: "今日完成 %lld/%lld"),
                            locale: Locale.current,
                            Int64(progress.completed),
                            Int64(progress.scheduled)
                        )
                    )
                    .font(.captionBold)
                    .foregroundColor(.accentGreen)
                }

                ProgressView(
                    value: progress.scheduled == 0
                        ? 0
                        : Double(progress.completed) / Double(progress.scheduled)
                )
                .tint(.accentGreen)

                Text(String(localized: "habits.subtitle", defaultValue: "习惯按重复计划在当天自动加入草稿区"))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    // MARK: - Sections

    private func habitSection(title: String, habits: [HabitModel]) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            Text(title)
                .font(.titleSmall)
                .foregroundColor(.textPrimary)

            VStack(spacing: 0) {
                ForEach(habits) { habit in
                    habitRow(habit)
                    if habit.id != habits.last?.id {
                        Divider()
                            .padding(.leading, 54)
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

    private func habitRow(_ habit: HabitModel) -> some View {
        let stats = viewModel.statistics(for: habit)
        return NavigationLink {
            HabitDetailView(habit: habit, viewModel: viewModel)
        } label: {
            HStack(spacing: WeekSpacing.sm) {
                Image(systemName: habit.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(habit.habitColor)
                    .frame(width: 34, height: 34)
                    .background(habit.habitColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.bodyMedium)
                        .foregroundColor(habit.isActive ? .textPrimary : .textSecondary)
                        .lineLimit(1)

                    Text(habit.scheduleSummary)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: WeekSpacing.sm)

                streakChip(stats.currentStreak)
                HabitTodayStatusChip(status: stats.todayStatus)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, WeekSpacing.md)
            .padding(.vertical, WeekSpacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("habitRow_\(habit.id.uuidString)")
    }

    @ViewBuilder
    private func streakChip(_ streak: Int) -> some View {
        if streak > 0 {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(
                    String(
                        format: String(localized: "habit.stats.days %lld", defaultValue: "%lld 天"),
                        locale: Locale.current,
                        Int64(streak)
                    )
                )
                .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.accentOrange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentOrange.opacity(0.12), in: Capsule())
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "repeat.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentGreen)

                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "habits.empty.title", defaultValue: "还没有习惯"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)

                    Text(String(localized: "habits.subtitle", defaultValue: "习惯按重复计划在当天自动加入草稿区"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showingEditor = true
                } label: {
                    HStack(spacing: WeekSpacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text(String(localized: "habits.empty.action", defaultValue: "新建习惯"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, WeekSpacing.xl)
                    .padding(.vertical, WeekSpacing.md)
                    .background(Color.accentGreen)
                    .clipShape(Capsule())
                    .shadow(color: Color.accentGreen.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .accessibilityIdentifier("habitsEmptyCreateButton")
                .buttonStyle(ScaleButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habitsEmptyState")
    }
}

// MARK: - HabitTodayStatusChip

/// 今日状态 chip，HabitsFullView 与 HabitDetailView 共用。
struct HabitTodayStatusChip: View {
    let status: HabitTodayStatus

    var body: some View {
        let presentation = presentation
        return Text(presentation.text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(presentation.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(presentation.tint.opacity(0.12), in: Capsule())
    }

    private var presentation: (text: String, tint: Color) {
        switch status {
        case .completed:
            return (String(localized: "habit.today.completed", defaultValue: "今日已完成"), .accentGreen)
        case .pending:
            return (String(localized: "habit.today.pending", defaultValue: "今日待完成"), .accentOrange)
        case .notGenerated:
            return (String(localized: "habit.today.not_generated", defaultValue: "今日未生成"), .textTertiary)
        case .notScheduled:
            return (String(localized: "habit.today.not_scheduled", defaultValue: "今日无需"), .textTertiary)
        }
    }
}
