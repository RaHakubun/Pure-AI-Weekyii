import SwiftUI
import SwiftData

struct PendingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var viewModel: PendingViewModel?
    @State private var selectedMonth = Date()
    @State private var showingCreateSheet = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let viewModel {
                    VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                        // 月份选择器（限制只能看未来和当前月份）
                        MonthPickerView(month: $selectedMonth, restriction: .futureOnly)
                        
                        // 周列表
                        let weeks = viewModel.weeks(in: selectedMonth)
                        if weeks.isEmpty {
                            emptyStateView
                        } else {
                            weeksList(weeks: weeks)
                        }
                    }
                    .weekPadding(WeekSpacing.base)
                } else {
                    ProgressView()
                }
            }
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WeekLogo(size: .small, animated: false)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    addWeekButton
                }
            }
            .sheet(isPresented: $showingCreateSheet, onDismiss: {
                viewModel?.refresh()
            }) {
                if let viewModel {
                    CreateWeekSheet(viewModel: viewModel)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = PendingViewModel(modelContext: modelContext)
            }
            viewModel?.refresh()
            viewModel?.seedPendingWeekForUITestsIfNeeded()
        }
        .refreshOnStateTransitions(using: appState) {
            viewModel?.refresh()
        }
        .onChange(of: viewModel?.errorMessage) { _, newValue in
            if let newValue {
                errorMessage = newValue
            }
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

    private var addWeekButton: some View {
        Button {
            showingCreateSheet = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.weekyiiGradient)
                    .shadow(color: WeekShadow.medium.color, radius: 6, x: 0, y: 3)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.weekyiiPrimary.opacity(0.22), lineWidth: 1)
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.backgroundSecondary)
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "pending.add_week"))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.weekyiiGradient)
                
                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "pending.empty.title"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                    
                    Text(String(localized: "pending.empty.subtitle"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
    }
    
    // MARK: - Weeks List
    
    private func weeksList(weeks: [WeekModel]) -> some View {
        VStack(spacing: WeekSpacing.md) {
            // 统计信息
            WeekCard(accentColor: .accentOrange) {
                HStack {
                    VStack(alignment: .leading, spacing: WeekSpacing.xs) {
                        Text(String(localized: "pending.total_weeks"))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text("\(weeks.count)")
                            .font(.titleLarge)
                            .foregroundColor(.accentOrange)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 40))
                        .foregroundColor(.accentOrange.opacity(0.3))
                }
            }
            
            // 周卡片列表
            ForEach(weeks) { week in
                PendingWeekCard(week: week)
            }
        }
    }
}
