import SwiftUI
import StoreKit

/// Placeholder legal links. Replace with the published URLs before App Review;
/// App Store guideline 3.1.2 requires both on the purchase page.
enum VIPLegalLinks {
    static let termsOfUse: URL? = nil
    static let privacyPolicy: URL? = nil
}

/// Settings › VIP 服务. Also presented as the paywall sheet whenever a free user
/// taps a paid feature (`highlightedFeature` tells which one).
struct VIPServiceView: View {
    var highlightedFeature: VIPFeature?
    var showsCloseButton = false

    @Environment(PurchaseService.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var showingManageSubscriptions = false
    @State private var alertMessage: String?

    var body: some View {
        List {
            statusSection
            if purchases.showsTrialOffer {
                trialSection
            }
            featuresSection
            plansSection
            pricingNotesSection
            afterExpirySection
            renewalTermsSection
            actionsSection
            legalSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "vip.title", defaultValue: "VIP 服务"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "vip.close", defaultValue: "关闭")) { dismiss() }
                }
            }
        }
        .task {
            if purchases.products.isEmpty { await purchases.loadProducts() }
            await purchases.refreshAccess()
        }
        .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
        .alert(
            String(localized: "vip.title", defaultValue: "VIP 服务"),
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button(String(localized: "action.ok")) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            if let highlightedFeature, !purchases.hasVIP {
                Label {
                    Text(Self.lockedMessage(for: highlightedFeature))
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color.weekyiiPrimary)
                }
            }
            HStack(spacing: 12) {
                SettingsIcon(icon: "crown.fill", color: purchases.hasVIP ? .orange : .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statusTitle: String {
        let access = purchases.access
        switch access.source {
        case .betaTester:
            return String(localized: "vip.status.beta", defaultValue: "测试版 · 已自动开通 VIP")
        case .developer:
            return String(localized: "vip.status.developer", defaultValue: "开发调试 · 模拟 VIP")
        case .lifetime:
            return String(localized: "vip.status.lifetime", defaultValue: "VIP 永久版 · 已开通")
        case .subscription:
            let plan = access.product.map(Self.planName) ?? ""
            return String(format: String(localized: "vip.status.subscription", defaultValue: "%@ VIP · 已开通"), plan)
        case .none:
            return access.hasExpiredSubscription
                ? String(localized: "vip.status.expired", defaultValue: "VIP 已到期")
                : String(localized: "vip.status.none", defaultValue: "尚未开通 VIP")
        }
    }

    private var statusDetail: String {
        let access = purchases.access
        switch access.source {
        case .betaTester:
            return String(localized: "vip.status.beta.detail", defaultValue: "TestFlight 测试版可免费使用全部 VIP 功能，不会产生任何费用。正式版需要购买。")
        case .developer:
            return String(localized: "vip.status.developer.detail", defaultValue: "仅在开发版本中出现，不代表真实购买状态。")
        case .lifetime:
            return String(localized: "vip.status.lifetime.detail", defaultValue: "已一次买断，永久使用全部 VIP 功能。")
        case .subscription:
            guard let date = access.expirationDate else { return "" }
            let dateText = date.formatted(date: .abbreviated, time: .omitted)
            if access.isInTrial {
                return String(format: String(localized: "vip.status.trial.detail", defaultValue: "免费试用中，%@ 结束；之后自动续费，可随时取消。"), dateText)
            }
            return String(format: String(localized: "vip.status.subscription.detail", defaultValue: "当前周期至 %@，到期自动续费。"), dateText)
        case .none:
            return access.hasExpiredSubscription
                ? String(localized: "vip.status.expired.detail", defaultValue: "iCloud 同步已暂停，灵动模式和 VIP 主题已停用。你的数据和选择都已保留，续费后自动恢复。")
                : String(localized: "vip.status.none.detail", defaultValue: "开通后即可使用 iCloud 同步、灵动模式和全部 VIP 主题。")
        }
    }

    // MARK: Trial

    private var trialSection: some View {
        Section {
            Button {
                Task { await buy(WeekyiiProduct.trialProduct) }
            } label: {
                HStack {
                    Spacer()
                    if purchases.purchasingProduct == WeekyiiProduct.trialProduct {
                        ProgressView().tint(.white)
                    } else {
                        Text(String(format: String(localized: "vip.trial.cta", defaultValue: "免费试用 %d 天"), WeekyiiProduct.trialDays))
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(Color.weekyiiPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(purchases.purchasingProduct != nil)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } footer: {
            Text(trialFooter)
        }
    }

    private var trialFooter: String {
        if let yearly = purchases.products[.yearly] {
            return String(
                format: String(localized: "vip.trial.footer", defaultValue: "试用 %1$d 天，结束后按 %2$@/年 自动续费；试用期内随时取消不收费。每个 Apple ID 仅可试用一次。"),
                WeekyiiProduct.trialDays,
                yearly.displayPrice
            )
        }
        return String(
            format: String(localized: "vip.trial.footer.noprice", defaultValue: "试用 %d 天，结束后按年度订阅自动续费；试用期内随时取消不收费。每个 Apple ID 仅可试用一次。"),
            WeekyiiProduct.trialDays
        )
    }

    // MARK: Features

    private var featuresSection: some View {
        Section {
            featureRow(
                .cloudSync,
                icon: "arrow.triangle.2.circlepath.icloud",
                tint: .blue,
                title: String(localized: "vip.feature.cloud.title", defaultValue: "iCloud 同步"),
                detail: String(localized: "vip.feature.cloud.detail", defaultValue: "在你的 iPhone 和 iPad 之间同步周计划、任务、项目与习惯。数据存放在你自己的 iCloud 中。")
            )
            featureRow(
                .flexibleMode,
                icon: "arrow.triangle.2.circlepath",
                tint: .weekyiiPrimary,
                title: ExecutionMode.flexible.displayName,
                detail: String(localized: "vip.feature.flexible.detail", defaultValue: "开始后仍只专注一件事，但可以主动解冻今日队列，增改、排序和交换任务。")
            )
            featureRow(
                .themes,
                icon: "paintpalette.fill",
                tint: .purple,
                title: String(localized: "vip.feature.themes.title", defaultValue: "VIP 主题"),
                detail: String(
                    format: String(localized: "vip.feature.themes.detail", defaultValue: "%@，每套主题都有独立的色彩、形态与印象画，小组件和灵动岛同步生效。"),
                    WeekTheme.vipThemes.map(\.displayName).joined(separator: "、")
                )
            )
        } header: {
            Text(String(localized: "vip.features.header", defaultValue: "VIP 包含"))
        } footer: {
            Text(String(localized: "vip.features.footer", defaultValue: "其余功能永久免费：周计划与今日任务、严格模式、灵动岛与实时活动、桌面和锁屏小组件、数据导出与恢复等。"))
        }
    }

    private func featureRow(_ feature: VIPFeature, icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIcon(icon: icon, color: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if purchases.hasVIP {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(highlightedFeature == feature && !purchases.hasVIP ? Color.weekyiiPrimary.opacity(0.10) : nil)
    }

    // MARK: Plans

    private var plansSection: some View {
        Section {
            if purchases.products.isEmpty {
                if purchases.isLoadingProducts {
                    HStack {
                        ProgressView()
                        Text(String(localized: "vip.plans.loading", defaultValue: "正在获取价格…"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "vip.error.products_unavailable", defaultValue: "暂时无法连接 App Store，请稍后再试。"))
                            .font(.subheadline)
                        Button(String(localized: "vip.plans.retry", defaultValue: "重新获取价格")) {
                            Task { await purchases.loadProducts() }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            } else {
                ForEach(WeekyiiProduct.displayOrder) { item in
                    if let product = purchases.products[item] {
                        planRow(item, product: product)
                    }
                }
            }
        } header: {
            Text(String(localized: "vip.plans.header", defaultValue: "选择方案"))
        } footer: {
            Text(String(localized: "vip.plans.footer", defaultValue: "价格以 App Store 显示的当地货币为准，不同国家和地区的价格可能不同。"))
        }
    }

    private func planRow(_ item: WeekyiiProduct, product: Product) -> some View {
        let pricing = VIPPlanPricing(item: item, product: product, monthlyProduct: purchases.products[.monthly])
        let isCurrent = purchases.access.product == item && purchases.access.isActive
        let ownsLifetime = purchases.access.source == .lifetime
        return Button {
            Task { await buy(item) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(Self.planName(item))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if item == .yearly {
                            Text(String(localized: "vip.plan.recommended", defaultValue: "推荐"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white)
                                .background(Color.orange, in: Capsule())
                        }
                    }
                    Text(planDetail(item, pricing: pricing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if purchases.purchasingProduct == item {
                    ProgressView()
                } else if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(pricing.displayPrice)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(Self.periodLabel(item))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent || ownsLifetime || purchases.purchasingProduct != nil)
    }

    private func planDetail(_ item: WeekyiiProduct, pricing: VIPPlanPricing) -> String {
        var parts: [String] = []
        if let perMonth = pricing.perMonthText {
            parts.append(String(format: String(localized: "vip.plan.per_month", defaultValue: "折合每月 %@"), perMonth))
        }
        if let savings = pricing.savingsPercent {
            parts.append(String(format: String(localized: "vip.plan.savings", defaultValue: "比按月省 %d%%"), savings))
        }
        switch item {
        case .monthly:
            parts.append(String(localized: "vip.plan.monthly.detail", defaultValue: "随用随停，最灵活"))
        case .yearly where purchases.showsTrialOffer:
            parts.append(String(format: String(localized: "vip.plan.yearly.trial", defaultValue: "含 %d 天免费试用"), WeekyiiProduct.trialDays))
        case .lifetime:
            parts.append(String(localized: "vip.plan.lifetime.detail", defaultValue: "一次买断，永久使用，不自动续费"))
        default:
            break
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Pricing notes

    private var pricingNotesSection: some View {
        Section {
            ForEach(pricingNotes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(String(localized: "vip.pricing.header", defaultValue: "定价说明"))
        }
    }

    private var pricingNotes: [String] {
        let products = purchases.products
        let monthly = products[.monthly]
        func pricing(_ item: WeekyiiProduct) -> VIPPlanPricing? {
            products[item].map { VIPPlanPricing(item: item, product: $0, monthlyProduct: monthly) }
        }
        var notes: [String] = []
        if let yearly = pricing(.yearly), let perMonth = yearly.perMonthText, let savings = yearly.savingsPercent {
            notes.append(String(format: String(localized: "vip.pricing.yearly", defaultValue: "年度 %1$@：最划算的订阅，折合每月 %2$@，比按月付省 %3$d%%。首次订阅可先免费试用 14 天。"), yearly.displayPrice, perMonth, savings))
        } else {
            notes.append(String(localized: "vip.pricing.yearly.noprice", defaultValue: "年度：最划算的订阅，首次订阅可先免费试用 14 天。"))
        }
        if let quarterly = pricing(.quarterly), let perMonth = quarterly.perMonthText, let savings = quarterly.savingsPercent {
            notes.append(String(format: String(localized: "vip.pricing.quarterly", defaultValue: "季度 %1$@：折合每月 %2$@，比按月付省 %3$d%%，适合想先用一段时间再决定的人。"), quarterly.displayPrice, perMonth, savings))
        } else {
            notes.append(String(localized: "vip.pricing.quarterly.noprice", defaultValue: "季度：比按月付更省，适合想先用一段时间再决定的人。"))
        }
        if let monthlyProduct = monthly {
            notes.append(String(format: String(localized: "vip.pricing.monthly", defaultValue: "月度 %@：随用随停，按月扣费，最灵活。"), monthlyProduct.displayPrice))
        } else {
            notes.append(String(localized: "vip.pricing.monthly.noprice", defaultValue: "月度：随用随停，按月扣费，最灵活。"))
        }
        if let lifetime = products[.lifetime] {
            if let years = VIPPlanPricing.lifetimeYears(lifetime: lifetime, yearly: products[.yearly]) {
                notes.append(String(format: String(localized: "vip.pricing.lifetime", defaultValue: "永久 %1$@：一次付费，永久使用全部 VIP 功能，约等于 %2$@ 年的年度订阅，之后不再扣费。"), lifetime.displayPrice, years))
            } else {
                notes.append(String(format: String(localized: "vip.pricing.lifetime.noyears", defaultValue: "永久 %@：一次付费，永久使用全部 VIP 功能，之后不再扣费。"), lifetime.displayPrice))
            }
        } else {
            notes.append(String(localized: "vip.pricing.lifetime.noprice", defaultValue: "永久：一次付费，永久使用全部 VIP 功能，之后不再扣费。"))
        }
        notes.append(String(localized: "vip.pricing.same_features", defaultValue: "四种方案包含的功能完全相同，区别只在付费方式。"))
        notes.append(String(localized: "vip.pricing.trial_rule", defaultValue: "免费试用只适用于订阅，每个 Apple ID 仅一次；试用期内取消不会扣费，试用结束后自动转为年度订阅。永久版不提供试用。"))
        notes.append(String(localized: "vip.pricing.switch", defaultValue: "订阅期间更换方案，由 App Store 按剩余时间自动处理，不会重复扣费。"))
        return notes
    }

    private var afterExpirySection: some View {
        Section {
            ForEach([
                String(localized: "vip.expiry.cloud", defaultValue: "iCloud 同步：暂停同步。本机和 iCloud 中的数据都不会被删除或修改，续费后从暂停处继续同步。"),
                String(localized: "vip.expiry.flexible", defaultValue: "灵动模式：当天已开始的任务流不受影响；之后启动的日子使用严格模式，你的偏好会保留。"),
                String(localized: "vip.expiry.themes", defaultValue: "VIP 主题：界面、小组件和灵动岛切回琥珀主题，你选的主题会保留，续费后自动恢复。"),
            ], id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(String(localized: "vip.expiry.header", defaultValue: "到期后会怎样"))
        }
    }

    private var renewalTermsSection: some View {
        Section {
            Text(String(localized: "vip.renewal.terms", defaultValue: "确认购买后将从你的 Apple ID 账户扣款。订阅会自动续期，除非在当前周期结束前至少 24 小时关闭自动续期；续期费用会在周期结束前 24 小时内扣除。你可以随时在 iPhone 的「设置 › Apple ID › 订阅」中管理或取消订阅。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(String(localized: "vip.renewal.header", defaultValue: "自动续费说明"))
        }
    }

    // MARK: Actions

    private var actionsSection: some View {
        Section {
            Button {
                Task {
                    await purchases.restorePurchases()
                    if purchases.hasVIP {
                        alertMessage = String(localized: "vip.restore.success", defaultValue: "已恢复 VIP。")
                    } else if let message = purchases.lastErrorMessage {
                        alertMessage = message
                    }
                    purchases.lastErrorMessage = nil
                }
            } label: {
                HStack {
                    Text(String(localized: "vip.restore", defaultValue: "恢复购买"))
                    if purchases.isRestoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(purchases.isRestoring)

            if purchases.access.source == .subscription {
                Button(String(localized: "vip.manage", defaultValue: "管理订阅")) {
                    showingManageSubscriptions = true
                }
            }
        }
    }

    private var legalSection: some View {
        Section {
            legalRow(String(localized: "vip.legal.terms", defaultValue: "用户协议"), url: VIPLegalLinks.termsOfUse)
            legalRow(String(localized: "vip.legal.privacy", defaultValue: "隐私政策"), url: VIPLegalLinks.privacyPolicy)
        }
    }

    @ViewBuilder
    private func legalRow(_ title: String, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
        } else {
            LabeledContent(title) {
                Text(String(localized: "vip.legal.pending", defaultValue: "即将提供"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Helpers

    private func buy(_ item: WeekyiiProduct) async {
        let outcome = await purchases.purchase(item)
        switch outcome {
        case .purchased:
            if showsCloseButton { dismiss() }
        case .pending:
            alertMessage = String(localized: "vip.purchase.pending", defaultValue: "购买正在等待批准，完成后会自动开通。")
        case .failed(let message):
            alertMessage = message
            purchases.lastErrorMessage = nil
        case .cancelled:
            break
        }
    }

    static func planName(_ item: WeekyiiProduct) -> String {
        switch item {
        case .monthly: return String(localized: "vip.plan.monthly", defaultValue: "月度")
        case .quarterly: return String(localized: "vip.plan.quarterly", defaultValue: "季度")
        case .yearly: return String(localized: "vip.plan.yearly", defaultValue: "年度")
        case .lifetime: return String(localized: "vip.plan.lifetime", defaultValue: "永久")
        }
    }

    static func periodLabel(_ item: WeekyiiProduct) -> String {
        switch item {
        case .monthly: return String(localized: "vip.period.month", defaultValue: "每月")
        case .quarterly: return String(localized: "vip.period.quarter", defaultValue: "每 3 个月")
        case .yearly: return String(localized: "vip.period.year", defaultValue: "每年")
        case .lifetime: return String(localized: "vip.period.once", defaultValue: "一次性")
        }
    }

    static func lockedMessage(for feature: VIPFeature) -> String {
        switch feature {
        case .cloudSync:
            return String(localized: "vip.locked.cloud", defaultValue: "iCloud 同步是 VIP 功能")
        case .flexibleMode:
            return String(localized: "vip.locked.flexible", defaultValue: "灵动模式是 VIP 功能")
        case .themes:
            return String(localized: "vip.locked.themes", defaultValue: "这套主题是 VIP 主题")
        }
    }
}

/// Small "VIP" capsule used next to paid options.
struct VIPBadge: View {
    var body: some View {
        Text(verbatim: "VIP")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(.white)
            .background(Color.orange, in: Capsule())
            .accessibilityLabel(Text(verbatim: "VIP"))
    }
}
