import SwiftUI
import SwiftData

private enum MainTab: Hashable {
    case past
    case today
    case pending
    case extensions
    case settings
}

private struct AccountResolutionPresentation: Identifiable, Equatable {
    let id = UUID()
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var userSettings: UserSettings
    @Environment(CloudSyncCoordinator.self) private var cloudSyncCoordinator
    @Query(sort: \TaskTypeDefinition.sortOrder) private var taskTypeDefinitions: [TaskTypeDefinition]
    @State private var selectedTab: MainTab = .today
    @State private var accountResolutionPresentation: AccountResolutionPresentation?

    private var visualIdentity: String {
        "\(userSettings.selectedTheme.rawValue)-\(userSettings.appearanceModeRaw)"
    }

    /// A single switch that silences every app-driven animation: the system setting
    /// and Weekyii's own “减少动效” both funnel into one value.
    private var reduceMotion: Bool {
        systemReduceMotion || userSettings.reduceMotionEnabled
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            PastView()
                .id(visualIdentity)
                .tabItem {
                    tabLabel(String(localized: "tab.past"), systemImage: "clock.arrow.circlepath")
                }
                .tag(MainTab.past)
            
            TodayView(animationsActive: selectedTab == .today && scenePhase == .active && !reduceMotion)
                .id(visualIdentity)
                .tabItem {
                    tabLabel(String(localized: "tab.today"), systemImage: "sun.max")
                }
                .tag(MainTab.today)

            PendingView()
                .id(visualIdentity)
                .tabItem {
                    tabLabel(String(localized: "tab.pending"), systemImage: "calendar")
                }
                .tag(MainTab.pending)

            ExtensionsHubView(animationsActive: selectedTab == .extensions && scenePhase == .active && !reduceMotion)
                .id(visualIdentity)
                .tabItem {
                    tabLabel(String(localized: "tab.extensions"), systemImage: "square.grid.2x2")
                }
                .tag(MainTab.extensions)

            SettingsView()
                .tabItem {
                    tabLabel(String(localized: "tab.settings"), systemImage: "gearshape")
                }
                .tag(MainTab.settings)
        }
        .environment(\.weekyiiReduceMotion, reduceMotion)
        // Theme and appearance changes already invalidate this view through UserSettings.
        // Keeping them in the identity destroys every tab's NavigationStack on selection.
        .id(appState.dataRevision)
        .environment(
            \.taskTypePresentationCatalog,
            TaskTypePresentationCatalog(definitions: taskTypeDefinitions)
        )
        .tint(.weekyiiPrimary)
        .safeAreaInset(edge: .top, spacing: 0) {
            cloudSyncStatusBanner
        }
        .sheet(item: $accountResolutionPresentation, onDismiss: {
            cloudSyncCoordinator.deferAccountResolutionPresentation()
        }) { _ in
            CloudAccountResolutionSheet(coordinator: cloudSyncCoordinator)
        }
        .onChange(of: cloudSyncCoordinator.status) { _, status in
            if case .accountDecisionRequired = status {
                presentAccountResolution()
            }
        }
        .onChange(of: cloudSyncCoordinator.accountResolutionPresentationRequest) { _, _ in
            presentAccountResolution()
        }
        .task {
            if isAccountResolutionRequired {
                presentAccountResolution()
            }
        }
        .alert(String(localized: "alert.title"), isPresented: Binding(
            get: { appState.runtimeErrorMessage != nil },
            set: { newValue in
                if !newValue { appState.runtimeErrorMessage = nil }
            }
        )) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(appState.runtimeErrorMessage ?? "")
        }
        .onOpenURL { url in
            guard LiveActivityAction.parse(url: url) != nil else { return }
            selectedTab = .today
            LiveActivityActionRouter.handle(
                url: url,
                modelContext: modelContext,
                appState: appState,
                userSettings: userSettings
            )
        }
    }

    private func tabLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .symbolVariant(.none)
        }
    }

    private var isAccountResolutionRequired: Bool {
        cloudSyncCoordinator.diagnosticsSnapshot.accountResolutionRequired
    }

    @ViewBuilder
    private var cloudSyncStatusBanner: some View {
        let diagnostics = cloudSyncCoordinator.diagnosticsSnapshot
        if let kind = CloudSyncDiagnosticsSnapshot.bannerKind(
            for: diagnostics.status,
            requested: diagnostics.requested,
            requiresAccountResolution: diagnostics.accountResolutionRequired
        ) {
            HStack(spacing: 10) {
                if kind == .syncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: bannerSymbol(for: kind))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }

                Text(bannerMessage(for: kind, failure: diagnostics.lastFailure))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if kind == .accountDecision {
                    Button(String(localized: "settings.icloud.banner.account.open")) {
                        presentAccountResolution()
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("cloud.sync.banner.review")
                } else if diagnostics.manualSyncAllowed {
                    Button {
                        Task { await cloudSyncCoordinator.syncNow() }
                    } label: {
                        Text(String(localized: "settings.icloud.sync_now"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("cloud.sync.banner.syncNow")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .accessibilityIdentifier("cloud.sync.statusBanner")
        }
    }

    private func bannerMessage(for kind: CloudSyncBannerKind, failure: CloudSyncFailurePresentation?) -> String {
        switch kind {
        case .accountDecision: String(localized: "settings.icloud.banner.account_decision")
        case .quotaExceeded: String(localized: "settings.icloud.banner.quota")
        case .paused: failure?.localizedDescription ?? CloudSyncFailurePresentation(reason: .other).localizedDescription
        case .offline: String(localized: "settings.icloud.banner.offline")
        case .accountUnavailable: String(localized: "settings.icloud.banner.account_unavailable")
        case .locked: String(localized: "settings.icloud.banner.locked")
        case .syncing: String(localized: "settings.icloud.banner.syncing")
        }
    }

    private func bannerSymbol(for kind: CloudSyncBannerKind) -> String {
        switch kind {
        case .accountDecision: "person.crop.circle.badge.exclamationmark"
        case .quotaExceeded, .paused: "exclamationmark.icloud"
        case .offline: "wifi.slash"
        case .accountUnavailable, .locked: "icloud.slash"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        }
    }

    private func presentAccountResolution() {
        guard isAccountResolutionRequired else { return }
        if accountResolutionPresentation == nil {
            accountResolutionPresentation = AccountResolutionPresentation()
        }
    }
}

private struct CloudAccountResolutionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let coordinator: CloudSyncCoordinator
    @State private var isResolving = false

    private var context: CloudAccountResolutionContext? { coordinator.accountResolutionContext }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("cloud.accountSwitch.message")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    contextSummary

                    if context?.targetCloudIsEmpty == true {
                        Label(
                            String(localized: "cloud.accountSwitch.emptyCloudWarning"),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("cloud.accountSwitch.emptyCloudWarning")
                    }

                    if case .failed(let failure) = context?.progress {
                        Text(LocalizedStringKey(failure.localizationKey))
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("cloud.accountSwitch.failure")
                    }

                    if coordinator.accountResolutionJournalUnavailable {
                        Text("cloud.accountSwitch.error.journalUnavailable")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("cloud.accountSwitch.journalFailure")
                    }

                    resolutionActions
                }
                .padding(24)
            }
            .navigationTitle("cloud.accountSwitch.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cloud.accountSwitch.later") {
                        coordinator.deferAccountResolutionPresentation()
                        dismiss()
                    }
                    .accessibilityIdentifier("cloud.accountSwitch.later")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            await coordinator.prepareAccountResolutionContext()
        }
    }

    @ViewBuilder
    private var contextSummary: some View {
        if let context {
            VStack(alignment: .leading, spacing: 8) {
                Text(String.localizedStringWithFormat(
                    String(localized: "cloud.accountSwitch.localCount"),
                    context.localEntityCount
                ))
                if let cloudCount = context.targetCloudEntityCount {
                    Text(String.localizedStringWithFormat(
                        String(localized: "cloud.accountSwitch.cloudCount"),
                        cloudCount
                    ))
                } else if context.progress == .inspecting {
                    Label("cloud.accountSwitch.inspecting", systemImage: "icloud")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if case .resolving = context.progress {
                    Label("cloud.accountSwitch.resolving", systemImage: "arrow.triangle.2.circlepath.icloud")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("cloud.accountSwitch.summary")
        } else {
            ProgressView("cloud.accountSwitch.inspecting")
                .accessibilityIdentifier("cloud.accountSwitch.progress")
        }
    }

    private var resolutionActions: some View {
        VStack(spacing: 10) {
            Button {
                resolve(.useLocal)
            } label: {
                Label("cloud.accountSwitch.useLocal", systemImage: "iphone")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isResolving || !canResolveTarget)
            .accessibilityIdentifier("cloud.accountSwitch.useLocal")

            Button {
                resolve(.useCloud)
            } label: {
                Label("cloud.accountSwitch.useCloud", systemImage: "icloud")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isResolving || !canResolveTarget)
            .accessibilityIdentifier("cloud.accountSwitch.useCloud")

            Button {
                resolve(.merge)
            } label: {
                Label("cloud.accountSwitch.merge", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isResolving || !canResolveTarget)
            .accessibilityIdentifier("cloud.accountSwitch.merge")

            Button(role: .destructive) {
                resolve(.disable)
            } label: {
                Label("cloud.accountSwitch.disable", systemImage: "icloud.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isResolving)
            .accessibilityIdentifier("cloud.accountSwitch.disable")
        }
    }

    private var canResolveTarget: Bool {
        context?.targetAccountAvailable == true && !coordinator.accountResolutionJournalUnavailable
    }

    private func resolve(_ choice: CloudAccountResolutionChoice) {
        isResolving = true
        Task {
            await coordinator.resolveAccountSwitch(choice)
            if case .accountDecisionRequired = coordinator.status {
                if coordinator.accountResolutionContext == nil {
                    await coordinator.prepareAccountResolutionContext()
                }
                isResolving = false
            } else {
                dismiss()
            }
        }
    }
}
