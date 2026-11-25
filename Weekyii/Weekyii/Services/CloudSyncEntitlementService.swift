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

// The former `CloudSyncPreferenceController` lived here with a no-argument
// initialiser that granted access through `OpenAccessCloudSyncEntitlementProvider`.
// Production never called it, so it was a ready-made way to flip the sync
// preference while bypassing the paywall. Gating now happens in
// `CloudSyncCoordinator.setRequested` against the real provider.
