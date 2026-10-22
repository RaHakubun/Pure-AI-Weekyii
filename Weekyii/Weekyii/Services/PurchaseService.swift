import Foundation
import Observation
import StoreKit

// MARK: - Product catalog

/// Every StoreKit product Weekyii sells. The identifiers must match App Store Connect
/// and `Resources/Weekyii.storekit` exactly; they can never be changed once created.
enum WeekyiiProduct: String, CaseIterable, Identifiable, Sendable {
    case monthly = "com.fluentdesign.Weekyii.vip.monthly"
    case quarterly = "com.fluentdesign.Weekyii.vip.quarterly"
    case yearly = "com.fluentdesign.Weekyii.vip.yearly"
    case lifetime = "com.fluentdesign.Weekyii.vip.lifetime"

    var id: String { rawValue }

    static let allIDs = Set(allCases.map(\.rawValue))

    /// Display order on the VIP page: the recommended plan first.
    static let displayOrder: [WeekyiiProduct] = [.yearly, .quarterly, .monthly, .lifetime]

    var isSubscription: Bool { self != .lifetime }

    /// Length of one billing period in months; `nil` for the one-time purchase.
    var months: Int? {
        switch self {
        case .monthly: return 1
        case .quarterly: return 3
        case .yearly: return 12
        case .lifetime: return nil
        }
    }

    /// The plan that carries the 14-day free trial (an introductory offer).
    static let trialProduct: WeekyiiProduct = .yearly
    static let trialDays = 14
}

/// Paid capabilities. Everything not listed here stays free.
enum VIPFeature: String, Identifiable, Sendable {
    case cloudSync
    case flexibleMode
    case themes

    var id: String { rawValue }
}

extension WeekTheme {
    /// Themes that require VIP (or, later, a one-time theme purchase).
    /// Deliberately separate from `isPremiumTheme`, which only drives the
    /// Lord of the Rings theme's decorative styling.
    var requiresVIP: Bool {
        switch self {
        case .lotr, .brutal, .neon, .paper, .terminal:
            return true
        default:
            return false
        }
    }

    static var vipThemes: [WeekTheme] { allCases.filter(\.requiresVIP) }
    static var freeThemes: [WeekTheme] { allCases.filter { !$0.requiresVIP } }
}

// MARK: - Access state

struct VIPAccess: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// No active purchase.
        case none
        /// An active auto-renewable subscription (possibly in its free trial).
        case subscription
        /// The one-time lifetime purchase.
        case lifetime
        /// A TestFlight / App Review build of the Beta configuration.
        case betaTester
        /// DEBUG builds only: the developer switch or UI tests.
        case developer
    }

    var source: Source = .none
    var product: WeekyiiProduct?
    var expirationDate: Date?
    var isInTrial = false
    /// True when the user once had a subscription that is no longer active.
    var hasExpiredSubscription = false
    var verificationFailure: String?

    var isActive: Bool { source != .none }

    var cloudSyncState: CloudSyncEntitlementState {
        if isActive { return .entitled }
        if let verificationFailure { return .verificationFailed(verificationFailure) }
        return hasExpiredSubscription ? .expired : .notPurchased
    }

    static let inactive = VIPAccess()
}

/// Reads the current entitlement straight from StoreKit's verified transactions.
/// This is the only source of truth for paid access; cached flags such as
/// `UserSettings.premiumThemeUnlocked` are display mirrors written from its result.
enum VIPEntitlementResolver {
    static let developerOverrideKey = "weekyii.debug.vipOverride"

    static func resolve() async -> VIPAccess {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting")
            || UserDefaults.standard.bool(forKey: developerOverrideKey) {
            return VIPAccess(source: .developer)
        }
        #endif

        var best = VIPAccess.inactive
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard let product = WeekyiiProduct(rawValue: transaction.productID),
                      transaction.revocationDate == nil,
                      !transaction.isUpgraded else { continue }
                if product == .lifetime {
                    return VIPAccess(source: .lifetime, product: .lifetime)
                }
                if let expiration = transaction.expirationDate, expiration < Date() { continue }
                let candidate = VIPAccess(
                    source: .subscription,
                    product: product,
                    expirationDate: transaction.expirationDate,
                    isInTrial: transaction.offer?.type == .introductory
                )
                if best.source == .none
                    || (candidate.expirationDate ?? .distantFuture) > (best.expirationDate ?? .distantPast) {
                    best = candidate
                }
            case .unverified(let transaction, let error):
                if WeekyiiProduct.allIDs.contains(transaction.productID) {
                    best.verificationFailure = error.localizedDescription
                }
            }
        }
        if best.isActive { return best }

        if await isBetaTesterBuild() {
            return VIPAccess(source: .betaTester)
        }

        best.hasExpiredSubscription = await hadSubscriptionBefore()
        return best
    }

    /// Beta testers get VIP automatically, but only when BOTH hold:
    /// 1. the binary was built with the `Beta` configuration (`WEEKYII_BETA`), and
    /// 2. StoreKit reports the sandbox environment (TestFlight / App Review).
    /// Release builds never compile this path in, so App Store users are unaffected.
    static func isBetaTesterBuild() async -> Bool {
        #if WEEKYII_BETA
        guard let verification = try? await AppTransaction.shared,
              case .verified(let appTransaction) = verification else { return false }
        return appTransaction.environment == .sandbox
        #else
        return false
        #endif
    }

    static var isBetaConfiguration: Bool {
        #if WEEKYII_BETA
        return true
        #else
        return false
        #endif
    }

    private static func hadSubscriptionBefore() async -> Bool {
        for product in WeekyiiProduct.allCases where product.isSubscription {
            if case .verified? = await Transaction.latest(for: product.rawValue) {
                return true
            }
        }
        return false
    }
}

// MARK: - Purchase service

/// Loads products, performs purchases and keeps the resolved VIP access current.
/// On every change it mirrors the access into `UserSettings` (themes, flexible mode,
/// widgets) and tells the cloud sync coordinator to re-check its entitlement.
@Observable
@MainActor
final class PurchaseService {
    static let shared = PurchaseService()

    enum PurchaseOutcome: Equatable {
        case purchased
        case pending
        case cancelled
        case failed(String)
    }

    private(set) var access: VIPAccess = .inactive
    private(set) var hasResolvedAccess = false
    private(set) var products: [WeekyiiProduct: Product] = [:]
    private(set) var isLoadingProducts = false
    private(set) var productLoadFailed = false
    private(set) var isTrialEligible = true
    private(set) var purchasingProduct: WeekyiiProduct?
    private(set) var isRestoring = false
    var lastErrorMessage: String?

    @ObservationIgnored private weak var settings: UserSettings?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored var onAccessChanged: (@MainActor (VIPAccess) async -> Void)?

    private init() {}

    var hasVIP: Bool { access.isActive }

    func canUse(_ feature: VIPFeature) -> Bool { hasVIP }

    /// Future one-time theme purchases plug in here without changing callers.
    func canUse(_ theme: WeekTheme) -> Bool {
        !theme.requiresVIP || hasVIP
    }

    /// Whether the paywall should lead with "14 days free".
    var showsTrialOffer: Bool {
        !hasVIP && isTrialEligible
    }

    func start(settings: UserSettings) {
        self.settings = settings
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshAccess()
            }
        }
        Task {
            await refreshAccess()
            await loadProducts()
        }
    }

    func refreshAccess() async {
        let resolved = await VIPEntitlementResolver.resolve()
        let changed = resolved != access || !hasResolvedAccess
        access = resolved
        hasResolvedAccess = true
        if let settings, settings.premiumThemeUnlocked != resolved.isActive {
            settings.premiumThemeUnlocked = resolved.isActive
        }
        await refreshTrialEligibility()
        if changed {
            await onAccessChanged?(resolved)
        }
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: WeekyiiProduct.allIDs)
            var map: [WeekyiiProduct: Product] = [:]
            for product in loaded {
                if let id = WeekyiiProduct(rawValue: product.id) { map[id] = product }
            }
            products = map
            productLoadFailed = map.isEmpty
        } catch {
            productLoadFailed = true
        }
        await refreshTrialEligibility()
    }

    func purchase(_ item: WeekyiiProduct) async -> PurchaseOutcome {
        guard purchasingProduct == nil else { return .cancelled }
        if products[item] == nil { await loadProducts() }
        guard let product = products[item] else {
            let message = String(localized: "vip.error.products_unavailable", defaultValue: "暂时无法连接 App Store，请稍后再试。")
            lastErrorMessage = message
            return .failed(message)
        }
        purchasingProduct = item
        defer { purchasingProduct = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    let message = String(localized: "vip.error.verification", defaultValue: "购买凭证校验失败，未开通 VIP。")
                    lastErrorMessage = message
                    return .failed(message)
                }
                await transaction.finish()
                await refreshAccess()
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        await refreshAccess()
        if !hasVIP, lastErrorMessage == nil {
            lastErrorMessage = String(localized: "vip.restore.none", defaultValue: "没有找到可恢复的购买记录。")
        }
    }

    #if DEBUG
    var developerOverrideEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: VIPEntitlementResolver.developerOverrideKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: VIPEntitlementResolver.developerOverrideKey)
            Task { await refreshAccess() }
        }
    }
    #endif

    private func refreshTrialEligibility() async {
        guard let subscription = products[WeekyiiProduct.trialProduct]?.subscription else { return }
        isTrialEligible = await subscription.isEligibleForIntroOffer
    }
}

// MARK: - Price presentation

/// Derived, locale-correct price copy for the VIP page. All amounts come from
/// StoreKit, so every storefront shows its own currency.
struct VIPPlanPricing {
    let item: WeekyiiProduct
    let product: Product
    let monthlyProduct: Product?

    var displayPrice: String { product.displayPrice }

    /// e.g. "¥5.67" — price per month for subscriptions.
    var perMonthText: String? {
        guard let months = item.months, months > 1 else { return nil }
        let perMonth = product.price / Decimal(months)
        return perMonth.formatted(product.priceFormatStyle.precision(.fractionLength(0...2)))
    }

    /// Whole-percent saving against paying monthly for the same period.
    var savingsPercent: Int? {
        guard let months = item.months, months > 1, let monthlyProduct, monthlyProduct.price > 0 else { return nil }
        let fullPrice = monthlyProduct.price * Decimal(months)
        guard fullPrice > product.price else { return nil }
        let ratio = (fullPrice - product.price) / fullPrice * 100
        return Int(NSDecimalNumber(decimal: ratio).doubleValue.rounded())
    }

    /// For the lifetime plan: how many years of the yearly plan it equals.
    static func lifetimeYears(lifetime: Product, yearly: Product?) -> String? {
        guard let yearly, yearly.price > 0 else { return nil }
        let years = NSDecimalNumber(decimal: lifetime.price / yearly.price).doubleValue
        return years.formatted(.number.precision(.fractionLength(1)))
    }
}
