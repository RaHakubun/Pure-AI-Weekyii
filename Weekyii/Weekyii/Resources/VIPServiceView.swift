import SwiftUI
import StoreKit

/// Placeholder legal links. Replace with the published URLs before App Review;
/// App Store guideline 3.1.2 requires both on the purchase page.
enum VIPLegalLinks {
    static let termsOfUse: URL? = nil
    static let privacyPolicy: URL? = nil
}

/// Settings › VIP 服务. Also presented as the paywall sheet whenever a free user
/// taps a paid feature (`highlightedFeature` moves that benefit to the front).
///
/// Layout, top to bottom: theme showcase → title → three benefit cards → plan
/// picker (or the member card once VIP is active) → collapsed FAQ. The purchase
/// button is pinned to the bottom edge together with the renewal line and the
/// legal links that App Review expects next to it.
///
/// The page always uses the amber palette (light or dark, following the system)
/// so it looks the same whichever theme the user currently has selected.
struct VIPServiceView: View {
    var highlightedFeature: VIPFeature?
    var showsCloseButton = false

    @Environment(PurchaseService.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPlan: WeekyiiProduct = .yearly
    @State private var showsFAQ = false
    @State private var showingManageSubscriptions = false
    @State private var alertMessage: String?

    private var palette: VIPPagePalette { VIPPagePalette(isDark: colorScheme == .dark) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VIPThemeCarousel(palette: palette)
                    .padding(.top, 4)
                header
                    .padding(.top, 14)
                benefits
                    .padding(.top, 20)
                    .padding(.horizontal, 16)
                if purchases.hasVIP {
                    memberCard
                        .padding(.top, 22)
                        .padding(.horizontal, 16)
                } else {
                    if purchases.access.hasExpiredSubscription {
                        expiredNotice
                            .padding(.top, 22)
                            .padding(.horizontal, 16)
                    }
                    plans
                        .padding(.top, 22)
                        .padding(.horizontal, 16)
                }
                faq
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                if purchases.hasVIP {
                    legalLinks
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background { pageBackground }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !purchases.hasVIP {
                purchaseBar
            }
        }
        .navigationTitle(String(localized: "vip.title", defaultValue: "VIP 服务"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarContent }
        .tint(palette.primary)
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

    // MARK: Chrome

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // The hero title already names the page; keep the bar itself clean.
        ToolbarItem(placement: .principal) {
            Text(verbatim: "")
                .accessibilityHidden(true)
        }
        if showsCloseButton {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(palette.textPrimary.opacity(0.07), in: Circle())
                }
                .accessibilityLabel(String(localized: "vip.close", defaultValue: "关闭"))
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if purchases.isRestoring {
                ProgressView()
            } else {
                Button(String(localized: "vip.restore", defaultValue: "恢复购买")) {
                    Task { await restore() }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.primary)
            }
        }
    }

    private var pageBackground: some View {
        ZStack(alignment: .top) {
            palette.background
            RadialGradient(
                colors: [palette.glow, palette.glow.opacity(0)],
                center: .top,
                startRadius: 0,
                endRadius: 340
            )
            .frame(height: 460)
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            Text(verbatim: "Weekyii VIP")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: palette.titleGradient, startPoint: .leading, endPoint: .trailing)
                )
                .accessibilityAddTraits(.isHeader)
            Text(String(localized: "vip.hero.tagline", defaultValue: "让每一周，都有自己的样子"))
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }

    // MARK: Benefits

    private var orderedFeatures: [VIPFeature] {
        let base: [VIPFeature] = [.themes, .flexibleMode, .cloudSync]
        guard let highlightedFeature else { return base }
        return [highlightedFeature] + base.filter { $0 != highlightedFeature }
    }

    private var benefits: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(orderedFeatures) { feature in
                VIPBenefitCard(
                    feature: feature,
                    isHighlighted: feature == highlightedFeature && !purchases.hasVIP,
                    isUnlocked: purchases.hasVIP,
                    palette: palette
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Plans

    @ViewBuilder
    private var plans: some View {
        if purchases.products.isEmpty {
            productsPlaceholder
        } else {
            VStack(spacing: 10) {
                if let yearly = purchases.products[.yearly] {
                    featuredPlanCard(product: yearly)
                }
                HStack(spacing: 10) {
                    ForEach([WeekyiiProduct.quarterly, .monthly, .lifetime]) { item in
                        if let product = purchases.products[item] {
                            compactPlanCard(item, product: product)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear(perform: ensureSelectionIsAvailable)
            .onChange(of: purchases.products.count) { _, _ in ensureSelectionIsAvailable() }
        }
    }

    private var productsPlaceholder: some View {
        VStack(spacing: 10) {
            if purchases.isLoadingProducts {
                ProgressView()
                Text(String(localized: "vip.plans.loading", defaultValue: "正在获取价格…"))
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text(String(localized: "vip.error.products_unavailable", defaultValue: "暂时无法连接 App Store，请稍后再试。"))
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "vip.plans.retry", defaultValue: "重新获取价格")) {
                    Task { await purchases.loadProducts() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .vipCard(palette)
    }

    private func featuredPlanCard(product: Product) -> some View {
        let pricing = VIPPlanPricing(item: .yearly, product: product, monthlyProduct: purchases.products[.monthly])
        let isSelected = selectedPlan == .yearly
        return Button {
            selectedPlan = .yearly
        } label: {
            HStack(spacing: 12) {
                selectionMark(isSelected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.planName(.yearly))
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                    if let perMonth = pricing.perMonthText {
                        Text(String(format: String(localized: "vip.plan.about_per_month", defaultValue: "约 %@ / 月"), perMonth))
                            .font(.caption)
                            .foregroundStyle(palette.primaryDark)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(pricing.displayPrice)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(Self.periodLabel(.yearly))
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(palette.selectedFill) : AnyShapeStyle(palette.surface))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? palette.primary : palette.border, lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                featuredBadge(pricing: pricing)
                    .offset(x: -14, y: -11)
            }
            .compositingGroup()
            .shadow(color: palette.primary.opacity(isSelected ? 0.15 : 0), radius: 12, y: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(purchases.purchasingProduct != nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func featuredBadge(pricing: VIPPlanPricing) -> some View {
        var parts: [String] = []
        if let savings = pricing.savingsPercent {
            parts.append(String(format: String(localized: "vip.plan.badge.savings", defaultValue: "省 %d%%"), savings))
        }
        if purchases.showsTrialOffer {
            parts.append(String(format: String(localized: "vip.plan.badge.trial", defaultValue: "试用 %d 天"), trialDays))
        }
        let text = parts.isEmpty
            ? String(localized: "vip.plan.recommended", defaultValue: "推荐")
            : parts.joined(separator: " · ")
        return Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(palette.primary, in: Capsule())
    }

    private func compactPlanCard(_ item: WeekyiiProduct, product: Product) -> some View {
        let isSelected = selectedPlan == item
        return Button {
            selectedPlan = item
        } label: {
            VStack(spacing: 4) {
                Text(Self.planName(item))
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                Text(product.displayPrice)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(item == .lifetime
                     ? String(localized: "vip.plan.lifetime.short", defaultValue: "一次买断")
                     : Self.periodLabel(item))
                    .font(.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(palette.selectedFill) : AnyShapeStyle(palette.surface))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? palette.primary : palette.border, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(purchases.purchasingProduct != nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionMark(_ isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isSelected ? palette.primary : palette.textTertiary)
    }

    /// Falls back to the first loaded plan when the selected one isn't sold here.
    private func ensureSelectionIsAvailable() {
        guard purchases.products[selectedPlan] == nil,
              let first = WeekyiiProduct.displayOrder.first(where: { purchases.products[$0] != nil })
        else { return }
        selectedPlan = first
    }

    // MARK: Purchase bar

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            Button {
                Task { await buy(selectedPlan) }
            } label: {
                ZStack {
                    if purchases.purchasingProduct != nil {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaTitle)
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(colors: [palette.accent, palette.primary], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .compositingGroup()
                .shadow(color: palette.primary.opacity(0.30), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(purchases.purchasingProduct != nil || purchases.products[selectedPlan] == nil)

            if let finePrint = ctaFinePrint {
                Text(finePrint)
                    .font(.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            legalLinks
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background {
            palette.background
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            // Content scrolling underneath fades out instead of showing through.
            LinearGradient(colors: [palette.background.opacity(0), palette.background], startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
                .offset(y: -24)
                .allowsHitTesting(false)
        }
    }

    private var ctaTitle: String {
        if selectedPlan == .yearly, purchases.showsTrialOffer {
            return String(format: String(localized: "vip.trial.cta", defaultValue: "免费试用 %d 天"), trialDays)
        }
        return String(format: String(localized: "vip.cta.subscribe", defaultValue: "开通%@ VIP"), Self.planName(selectedPlan))
    }

    /// Price and renewal terms right under the button (guideline 3.1.2).
    private var ctaFinePrint: String? {
        guard let product = purchases.products[selectedPlan] else { return nil }
        if selectedPlan == .lifetime {
            return String(format: String(localized: "vip.cta.fine.lifetime", defaultValue: "%@ 一次性付费，不会自动续费"), product.displayPrice)
        }
        if selectedPlan == .yearly, purchases.showsTrialOffer {
            return String(format: String(localized: "vip.cta.fine.trial", defaultValue: "试用结束后 %@/年 自动续费，可随时取消"), product.displayPrice)
        }
        return String(
            format: String(localized: "vip.cta.fine.subscription", defaultValue: "%1$@ %2$@，自动续费，可随时取消"),
            product.displayPrice,
            Self.periodLabel(selectedPlan)
        )
    }

    private var legalLinks: some View {
        HStack(spacing: 6) {
            legalLink(String(localized: "vip.legal.terms", defaultValue: "用户协议"), url: VIPLegalLinks.termsOfUse)
            Text(verbatim: "·")
            legalLink(String(localized: "vip.legal.privacy", defaultValue: "隐私政策"), url: VIPLegalLinks.privacyPolicy)
        }
        .font(.caption2)
        .foregroundStyle(palette.textTertiary)
    }

    @ViewBuilder
    private func legalLink(_ title: String, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
                .foregroundStyle(palette.textSecondary)
        } else {
            Text(title)
        }
    }

    // MARK: Status

    private var memberCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        LinearGradient(colors: [palette.accent, palette.primary], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if purchases.access.source == .subscription {
                Button(String(localized: "vip.manage", defaultValue: "管理订阅")) {
                    showingManageSubscriptions = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.primary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.selectedFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.primary.opacity(0.5), lineWidth: 1.5)
        }
    }

    private var expiredNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .vipCard(palette)
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
            let plan = access.product.map { Self.planName($0) } ?? ""
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

    // MARK: FAQ

    private struct FAQItem: Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }

    private var faqItems: [FAQItem] {
        var items: [FAQItem] = [
            FAQItem(
                question: String(localized: "vip.faq.plans.q", defaultValue: "四种方案有什么区别？"),
                answer: String(localized: "vip.faq.plans.a", defaultValue: "功能完全相同，只是付费方式不同。")
            ),
        ]
        if let days = purchases.trialDays {
            items.append(FAQItem(
                question: String(localized: "vip.faq.trial.q", defaultValue: "免费试用怎么算？"),
                answer: String(format: String(localized: "vip.faq.trial.a", defaultValue: "首次订阅年度可免费试用 %d 天，每个 Apple ID 一次；试用期内取消不扣费。"), days)
            ))
        }
        if let lifetime = purchases.products[.lifetime],
           let years = VIPPlanPricing.lifetimeYears(lifetime: lifetime, yearly: purchases.products[.yearly]) {
            items.append(FAQItem(
                question: String(localized: "vip.faq.lifetime.q", defaultValue: "永久版划算吗？"),
                answer: String(format: String(localized: "vip.faq.lifetime.a", defaultValue: "%1$@ 一次付费永久使用，约等于 %2$@ 年的年度订阅。"), lifetime.displayPrice, years)
            ))
        }
        items.append(contentsOf: [
            FAQItem(
                question: String(localized: "vip.faq.expiry.q", defaultValue: "到期后会怎样？"),
                answer: String(localized: "vip.faq.expiry.a", defaultValue: "iCloud 同步暂停，灵动模式和 VIP 主题停用；数据和你的选择都会保留，续费后自动恢复。")
            ),
            FAQItem(
                question: String(localized: "vip.faq.cancel.q", defaultValue: "怎么取消自动续费？"),
                answer: String(localized: "vip.faq.cancel.a", defaultValue: "在 iPhone「设置 › Apple ID › 订阅」中随时取消，需在周期结束前至少 24 小时操作。")
            ),
            FAQItem(
                question: String(localized: "vip.faq.switch.q", defaultValue: "可以更换方案吗？"),
                answer: String(localized: "vip.faq.switch.a", defaultValue: "可以，App Store 会按剩余时间自动处理，不会重复扣费。")
            ),
            FAQItem(
                question: String(localized: "vip.faq.free.q", defaultValue: "哪些功能是免费的？"),
                answer: String(localized: "vip.faq.free.a", defaultValue: "周计划与今日任务、严格模式、灵动岛、小组件和数据导出等都永久免费。")
            ),
        ])
        return items
    }

    private var faq: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { showsFAQ.toggle() }
            } label: {
                HStack {
                    Text(String(localized: "vip.faq.title", defaultValue: "常见问题"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textTertiary)
                        .rotationEffect(.degrees(showsFAQ ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showsFAQ ? .isSelected : [])

            if showsFAQ {
                Divider()
                    .overlay(palette.border)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(faqItems) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.question)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                            Text(item.answer)
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(String(localized: "vip.renewal.terms", defaultValue: "确认购买后将从你的 Apple ID 账户扣款。订阅会自动续期，除非在当前周期结束前至少 24 小时关闭自动续期；续期费用会在周期结束前 24 小时内扣除。你可以随时在 iPhone 的「设置 › Apple ID › 订阅」中管理或取消订阅。"))
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .transition(.opacity)
            }
        }
        .vipCard(palette)
    }

    // MARK: Actions

    /// Only read while `showsTrialOffer` is true, which guarantees StoreKit's value.
    private var trialDays: Int {
        purchases.trialDays ?? WeekyiiProduct.trialDays
    }

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

    private func restore() async {
        await purchases.restorePurchases()
        if purchases.hasVIP {
            alertMessage = String(localized: "vip.restore.success", defaultValue: "已恢复 VIP。")
        } else if let message = purchases.lastErrorMessage {
            alertMessage = message
        }
        purchases.lastErrorMessage = nil
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
}

// MARK: - Palette

/// Fixed amber palette for the VIP page, resolved for the current light/dark scheme.
private struct VIPPagePalette {
    let background: Color
    let surface: Color
    let border: Color
    let primary: Color
    let primaryDark: Color
    let accent: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let glow: Color
    let selectedFill: LinearGradient
    let titleGradient: [Color]
    let isDark: Bool

    init(isDark: Bool) {
        let amber = WeekTheme.amber.palette(for: .system, systemIsDark: isDark)
        let primary = Color(hex: amber.primary)
        self.isDark = isDark
        self.primary = primary
        background = Color(hex: amber.backgroundPrimary)
        surface = Color(hex: amber.backgroundSecondary)
        border = isDark ? Color.white.opacity(0.10) : primary.opacity(0.14)
        primaryDark = isDark ? Color(hex: amber.primaryLight) : Color(hex: amber.primaryDark)
        accent = Color(hex: amber.accentOrange)
        textPrimary = Color(hex: amber.textPrimary)
        textSecondary = Color(hex: amber.textSecondary)
        textTertiary = Color(hex: amber.textTertiary)
        glow = Color(hex: amber.accentOrange).opacity(isDark ? 0.18 : 0.22)
        selectedFill = LinearGradient(
            colors: [primary.opacity(isDark ? 0.22 : 0.12), Color(hex: amber.backgroundSecondary)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        titleGradient = isDark
            ? [Color(hex: amber.primaryLight), primary]
            : [Color(hex: amber.primaryDark), primary, Color(hex: amber.accentOrange)]
    }
}

private extension View {
    func vipCard(_ palette: VIPPagePalette) -> some View {
        background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
            .compositingGroup()
            .shadow(color: Color.black.opacity(palette.isDark ? 0 : 0.05), radius: 10, y: 4)
    }
}

// MARK: - Benefits

private struct VIPBenefitCard: View {
    let feature: VIPFeature
    let isHighlighted: Bool
    let isUnlocked: Bool
    let palette: VIPPagePalette

    var body: some View {
        VStack(spacing: 8) {
            illustration
                .frame(height: 38)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            isHighlighted ? AnyShapeStyle(palette.selectedFill) : AnyShapeStyle(palette.surface),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isHighlighted ? palette.primary : palette.border, lineWidth: isHighlighted ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(8)
            }
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(palette.isDark ? 0 : 0.05), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch feature {
        case .themes: return String(localized: "vip.feature.themes.title", defaultValue: "VIP 主题")
        case .flexibleMode: return String(localized: "vip.feature.flexible.title", defaultValue: "灵动模式")
        case .cloudSync: return String(localized: "vip.feature.cloud.title", defaultValue: "iCloud 同步")
        }
    }

    private var detail: String {
        switch feature {
        case .themes:
            return String(format: String(localized: "vip.benefit.themes", defaultValue: "%d 套主题，小组件同步"), WeekTheme.vipThemes.count)
        case .flexibleMode:
            return String(localized: "vip.benefit.flexible", defaultValue: "专注之余，也能随时调整")
        case .cloudSync:
            return String(localized: "vip.benefit.cloud", defaultValue: "iPhone 与 iPad 无缝同步")
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch feature {
        case .themes:
            HStack(alignment: .center, spacing: 3) {
                swatch(.lotr, height: 30)
                swatch(.neon, height: 38)
                swatch(.paper, height: 30)
            }
        case .flexibleMode:
            VStack(spacing: 4) {
                Capsule().fill(palette.primary.opacity(0.16)).frame(width: 40, height: 9)
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.primary)
                    Capsule().fill(palette.primary).frame(width: 40, height: 10)
                }
                .offset(x: 3)
                Capsule().fill(palette.primary.opacity(0.16)).frame(width: 40, height: 9)
            }
        case .cloudSync:
            Image(systemName: "ipad.and.iphone")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Color.blue)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.primary)
                        .offset(x: 8, y: -6)
                }
        }
    }

    private func swatch(_ theme: WeekTheme, height: CGFloat) -> some View {
        let colors = theme.palette(for: .system, systemIsDark: palette.isDark)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(hex: colors.primary))
            .frame(width: 15, height: height)
    }
}

// MARK: - Theme showcase

/// Horizontally paged previews of the VIP themes; the centred card is full size.
private struct VIPThemeCarousel: View {
    let palette: VIPPagePalette

    /// Lotr sits second so the first screen shows a neighbour on both sides.
    private let themes: [WeekTheme] = {
        var list = WeekTheme.vipThemes
        if let index = list.firstIndex(of: .lotr), list.count > 1 {
            list.remove(at: index)
            list.insert(.lotr, at: 1)
        }
        return list
    }()

    @State private var current: WeekTheme?

    private let cardSize = CGSize(width: 136, height: 226)

    /// Until the scroll view reports a position, the leading card is the one on screen.
    private var displayedTheme: WeekTheme? { current ?? themes.first }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(themes) { theme in
                            VIPThemePreviewCard(theme: theme)
                                .frame(width: cardSize.width, height: cardSize.height)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                        .opacity(phase.isIdentity ? 1 : 0.85)
                                }
                                .id(theme)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, max(0, (proxy.size.width - cardSize.width) / 2), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $current)
                .onAppear {
                    // The initial binding value is ignored before the lazy stack has
                    // laid out, so centre the flagship theme on the next run loop.
                    guard current == nil else { return }
                    Task { @MainActor in current = .lotr }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .frame(height: cardSize.height + 8)

            Text(displayedTheme?.displayName ?? "")
                .font(.footnote.weight(.semibold))
                .tracking(2)
                .foregroundStyle(palette.primaryDark)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: current)

            HStack(spacing: 6) {
                ForEach(themes) { theme in
                    Capsule()
                        .fill(theme == displayedTheme ? palette.primary : palette.textPrimary.opacity(0.15))
                        .frame(width: theme == displayedTheme ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy, value: current)
            .accessibilityHidden(true)
        }
    }
}

/// A miniature "Today" screen drawn with a theme's real palette, card style and artwork.
private struct VIPThemePreviewCard: View {
    let theme: WeekTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let colors = theme.palette(for: .system, systemIsDark: isDark)
        let style = theme.visualStyle
        let artworkRadius = min(style.cornerRadius, 14)

        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Date.now.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: colors.textTertiary))
                Text(String(localized: "vip.preview.today", defaultValue: "今日"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: colors.textPrimary))
            }
            ThemeStatusArtwork(theme: theme, renderingMode: .staticImage)
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: artworkRadius, style: .continuous))
                .overlay {
                    if let border = style.borderColor(isDark: isDark) {
                        RoundedRectangle(cornerRadius: artworkRadius, style: .continuous)
                            .strokeBorder(border, lineWidth: min(style.borderWidth, 2))
                    }
                }
            taskRow(
                String(localized: "vip.preview.task.reading", defaultValue: "整理读书笔记"),
                progress: 0.45,
                colors: colors,
                style: style,
                isDark: isDark
            )
            taskRow(
                String(localized: "vip.preview.task.walk", defaultValue: "晚间散步"),
                time: "19:30",
                colors: colors,
                style: style,
                isDark: isDark
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: colors.backgroundPrimary))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.16), radius: 16, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.displayName)
    }

    private func taskRow(
        _ title: String,
        progress: Double? = nil,
        time: String? = nil,
        colors: WeekThemePalette,
        style: ThemeVisualStyle,
        isDark: Bool
    ) -> some View {
        let radius = min(style.cornerRadius, 12)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let shadow = style.shadow ?? .classic
        let barHeight = 4 * style.barScale
        let barRadius = style.barCornerRadius ?? barHeight / 2

        return VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: colors.textPrimary))
                .lineLimit(1)
            if let progress {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: barRadius)
                        .fill(Color(hex: colors.backgroundTertiary))
                    RoundedRectangle(cornerRadius: barRadius)
                        .fill(Color(hex: colors.primary))
                        .scaleEffect(x: progress, anchor: .leading)
                }
                .frame(height: barHeight)
            }
            if let time {
                Text(verbatim: time)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: colors.textTertiary))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: colors.backgroundSecondary), in: shape)
        .overlay {
            shape.strokeBorder(
                style.borderColor(isDark: isDark) ?? Color(hex: colors.textPrimary).opacity(0.06),
                lineWidth: min(style.borderWidth, 2)
            )
        }
        .compositingGroup()
        .shadow(
            color: shadow.color,
            radius: shadow.radius * 0.6,
            x: shadow.x * 0.75,
            y: shadow.y * 0.75
        )
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
