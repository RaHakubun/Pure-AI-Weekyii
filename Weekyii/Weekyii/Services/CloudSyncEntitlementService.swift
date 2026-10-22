import Foundation

protocol CloudSyncEntitlementProviding: Sendable {
    func currentState() async -> CloudSyncEntitlementState
}

/// Production policy: iCloud sync is a VIP feature. The state is resolved from
/// StoreKit 2 verified transactions on every check (never from a cached flag), so an
/// expired subscription pauses sync without touching local or cloud data.
struct StoreKitCloudSyncEntitlementProvider: CloudSyncEntitlementProviding {
    func currentState() async -> CloudSyncEntitlementState {
        await VIPEntitlementResolver.resolve().cloudSyncState
    }
}

/// Grants sync unconditionally. Kept for tests and as the coordinator's injectable
/// default; the app injects `StoreKitCloudSyncEntitlementProvider`.
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
