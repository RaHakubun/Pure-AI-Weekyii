import Foundation

protocol CloudSyncEntitlementProviding: Sendable {
    func currentState() async -> CloudSyncEntitlementState
}

/// Current product policy: iCloud sync is available to every user.
/// Replace or inject a verified entitlement provider when monetization is added.
struct OpenAccessCloudSyncEntitlementProvider: CloudSyncEntitlementProviding {
    func currentState() async -> CloudSyncEntitlementState {
        .entitled
    }
}

/// Applies explicit sync preference changes without coupling preference migration
/// to entitlement resolution or local persistence availability.
@MainActor
struct CloudSyncPreferenceController {
    private let entitlementProvider: any CloudSyncEntitlementProviding

    init() {
        self.entitlementProvider = OpenAccessCloudSyncEntitlementProvider()
    }

    init(entitlementProvider: any CloudSyncEntitlementProviding) {
        self.entitlementProvider = entitlementProvider
    }

    @discardableResult
    func setRequested(_ requested: Bool, for settings: UserSettings) async -> Bool {
        if requested {
            guard await entitlementProvider.currentState() == .entitled else { return false }
        }

        settings.setCloudSyncRequested(requested)
        return true
    }
}
