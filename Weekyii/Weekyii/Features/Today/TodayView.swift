import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var viewModel: TodayViewModel?
    @State private var showingDraftEditor = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel, let day = viewModel.today {
                    content(for: day, viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "today.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let day = viewModel?.today, day.status == .draft {
                        EditButton()
                    }
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
        .onAppear {
            if viewModel == nil {
                let model = TodayViewModel(
                    modelContext: modelContext,
                    timeProvider: TimeProvider(),
                    notificationService: .shared,
                    appState: appState
                )
                viewModel = model
            }
            viewModel?.refresh()
        }
    }

    @ViewBuilder
    private func content(for day: DayModel, viewModel: TodayViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(for: day)

                KillTimeEditor(
                    hour: day.killTimeHour,
                    minute: day.killTimeMinute,
                    isEditable: day.status == .draft || day.status == .execute,
                    onChange: { newHour, newMinute in
                        do {
                            try viewModel.changeKillTime(hour: newHour, minute: newMinute)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
                .weekyiiCard()

                switch day.status {
                case .empty:
                    EmptyStateView(
                        title: String(localized: "today.empty.title"),
                        subtitle: String(localized: "today.empty.subtitle"),
                        systemImage: "square.and.pencil"
                    )
                    .weekyiiCard()

                    Button(action: { showingDraftEditor = true }) {
                        Label(String(localized: "action.create"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .sheet(isPresented: $showingDraftEditor) {
                        NavigationStack {
                            DraftEditorView(day: day, viewModel: viewModel)
                        }
                    }

                case .draft:
                    DraftEditorView(day: day, viewModel: viewModel)
                        .weekyiiCard()

                    Button(action: {
                        do {
                            try viewModel.startDay()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }) {
                        Text(String(localized: "action.start"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(day.sortedDraftTasks.isEmpty)

                case .execute:
                    FocusZoneView(task: day.focusTask)
                        .weekyiiCard()

                    FrozenZoneView(tasks: day.frozenTasks)
                        .weekyiiCard()

                    CompleteZoneView(tasks: day.completedTasks)
                        .weekyiiCard()

                    Button(action: {
                        do {
                            try viewModel.doneFocus()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }) {
                        Text(String(localized: "action.done_focus"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(day.focusTask == nil)

                case .completed:
                    CompleteZoneView(tasks: day.completedTasks)
                        .weekyiiCard()

                case .expired:
                    CompleteZoneView(tasks: day.completedTasks)
                        .weekyiiCard()

                    HStack {
                        Text(String(localized: "expired.count"))
                        Spacer()
                        Text("\(day.expiredCount)")
                            .fontWeight(.semibold)
                    }
                    .weekyiiCard()
                }
            }
            .padding()
        }
    }

    private func header(for day: DayModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "today.status"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                StatusBadge(status: day.status)
            }
            HStack {
                Text(String(localized: "today.days_started"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(appState.daysStartedCount)")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .weekyiiCard()
    }
}
