import SwiftUI

// MARK: - WeekCard - 增强版卡片组件

struct WeekCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeSkin) private var skin
    let content: Content
    let useGradient: Bool
    let accentColor: Color?
    let shadow: WeekShadow
    let quenyaStatus: Bool
    
    init(
        useGradient: Bool = false,
        accentColor: Color? = nil,
        shadow: WeekShadow = .light,
        quenyaStatus: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.useGradient = useGradient
        self.accentColor = accentColor
        self.shadow = shadow
        self.quenyaStatus = quenyaStatus
        self.content = content()
    }
    
    var body: some View {
        if useGradient, let feature = skin.feature {
            featureBody(feature)
        } else if !useGradient, let card = skin.card {
            stack
                .themedSurface(statusSurface(card), tint: cardTint, tintOpacity: cardTintOpacity)
                .overlay(themedAccentBar(card), alignment: ribbonAlignment(card))
        } else {
            classicBody
        }
    }

    private func statusSurface(_ card: ThemeSurfaceSkin) -> ThemeSurfaceSkin {
        var result = card
        result.translucentBottom = quenyaStatus && skin.isQuenya
        return result
    }

    /// Skins that tint their paper take the caller's accent as a wash, so the
    /// cards on one page stop looking like one flat sheet.
    private var cardTint: Color? {
        guard let card = skin.card, card.tintsWithAccent else { return nil }
        // A cushion takes the accent as it is; paper takes it as a dye.
        return card.hidesAccentBar ? accentColor : accentColor?.weekPaperDye
    }

    /// Dark paper needs a heavier wash to read at all; light paper turns muddy
    /// past about a quarter.
    private var cardTintOpacity: Double {
        if skin.card?.hidesAccentBar == true {
            // A soft wash on a cushion, not a dyed sheet.
            return colorScheme == .dark ? 0.10 : 0.09
        }
        return colorScheme == .dark ? 0.18 : 0.22
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.base) {
            content
        }
        .weekPadding(WeekSpacing.lg)
    }

    // MARK: Themed (personalised skins)

    /// Leading inset that makes room for the notebook margin rule.
    private static var marginInset: CGFloat { 12 }

    private func featureBody(_ feature: ThemeFeatureSkin) -> some View {
        stack
            .padding(.leading, feature.marginRule == nil ? 0 : Self.marginInset)
            .padding(.top, feature.inscription == nil ? 0 : Self.inscriptionInset)
            .overlay(alignment: .leading) { marginRule(feature.marginRule) }
            .themedSurface(feature.surface)
            .overlay(alignment: .top) { inscriptionBand(feature.inscription) }
            .overlay(themedAccentBar(feature.surface), alignment: ribbonAlignment(feature.surface))
            // Behind the panel, so only the tips of the ears and the loop of the
            // tail show past its edges. Backgrounds are not clipped to the panel.
            .background(alignment: .topTrailing) { catEars(feature.catEars) }
            .background(alignment: .bottomTrailing) { catTail(feature.catEars) }
    }

    /// Two ears peeking over the top trailing edge of the panel (猫猫).
    @ViewBuilder
    private func catEars(_ cat: ThemeCatEars?) -> some View {
        if let cat {
            ZStack {
                CatEarPairShape().fill(cat.fur.color)
                CatEarPairShape(inner: true).fill(cat.innerEar.color)
            }
            .frame(width: 74, height: 20)
            .padding(.trailing, 34)
            .offset(y: -16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A tail that drops out from under the bottom edge and curls back up (猫猫).
    @ViewBuilder
    private func catTail(_ cat: ThemeCatEars?) -> some View {
        if let cat {
            CatTailShape()
                .stroke(cat.tail.color, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .frame(width: 60, height: 30)
                .padding(.trailing, 26)
                .offset(y: 24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Room above the content for the inscription band.
    private static var inscriptionInset: CGFloat { 8 }

    /// Ring-letter band tooled along the top of the cover, inside the gilt frame.
    @ViewBuilder
    private func inscriptionBand(_ ink: ThemeHexPair?) -> some View {
        if let ink {
            ElvishInscriptionBand(seed: 7, color: ink.color, opacity: 0.55, lineWidth: 0.85)
            .frame(height: 10)
            .padding(.horizontal, 22)
            .padding(.top, 13)
        }
    }

    @ViewBuilder
    private func marginRule(_ rule: ThemeHexPair?) -> some View {
        if let rule {
            HStack(spacing: 2) {
                Rectangle().frame(width: 1)
                Rectangle().frame(width: 1)
            }
            .foregroundStyle(rule.color.opacity(0.7))
            .padding(.leading, Self.marginInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func ribbonAlignment(_ surface: ThemeSurfaceSkin) -> Alignment {
        guard surface.ribbonAccent else { return .top }
        return surface.ribbonTrailing ? .topTrailing : .topLeading
    }

    @ViewBuilder
    private func themedAccentBar(_ surface: ThemeSurfaceSkin) -> some View {
        if skin.glyphs == .lotr {
            // The basalt design keeps cards quiet; task type is shown in its chip.
            EmptyView()
        } else if surface.hidesAccentBar && surface.tintsWithAccent {
            // The accent is already the surface wash.
            EmptyView()
        } else if let color = accentColor, surface.ribbonAccent {
            // A silk bookmark hanging from the top rule.
            BookmarkRibbonShape()
                .fill(color)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.black.opacity(0.18)).frame(height: 1.5)
                }
                .frame(width: 13, height: 21)
                .padding(surface.ribbonTrailing ? .trailing : .leading, surface.ribbonTrailing ? 48 : 18)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if let color = accentColor {
            VStack {
                RoundedRectangle(cornerRadius: min(2, surface.cornerRadius))
                    .fill(color)
                    .frame(width: 40, height: 4)
                    .padding(.top, WeekSpacing.md)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Classic

    /// The original WeekCard drawing, unchanged for the ten classic themes.
    private var classicBody: some View {
        let isPremiumTheme = WeekTheme.activeTheme.isPremiumTheme

        return stack
            .background(backgroundView)
            .clipShape(.rect(cornerRadius: WeekRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.large)
                    .stroke(borderColor(isPremiumTheme: isPremiumTheme), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            .overlay(accentBar(isPremiumTheme: isPremiumTheme), alignment: .top)
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        let isPremiumTheme = WeekTheme.activeTheme.isPremiumTheme

        if useGradient {
            ZStack {
                Color.weekyiiGradient
                if isPremiumTheme {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        } else {
            ZStack {
                Color.backgroundSecondary
                if isPremiumTheme {
                    LinearGradient(
                        colors: [
                            Color.weekyiiPrimary.opacity(0.10),
                            Color.clear,
                            Color.accentOrange.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)
                }
                if colorScheme == .dark {
                    Color.backgroundTertiary.opacity(0.28)
                }
            }
        }
    }

    private func borderColor(isPremiumTheme: Bool) -> Color {
        if useGradient {
            return isPremiumTheme
                ? Color.white.opacity(colorScheme == .dark ? 0.32 : 0.22)
                : Color.white.opacity(colorScheme == .dark ? 0.24 : 0.18)
        }
        if isPremiumTheme {
            return Color.weekyiiPrimary.opacity(colorScheme == .dark ? 0.30 : 0.22)
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.backgroundTertiary
    }
    
    @ViewBuilder
    private func accentBar(isPremiumTheme: Bool) -> some View {
        if let color = accentColor {
            let barStyle: AnyShapeStyle = isPremiumTheme
                ? AnyShapeStyle(
                    LinearGradient(
                        colors: [Color.weekyiiPrimary, Color.weekyiiPrimaryLight, color],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                : AnyShapeStyle(color)

            VStack {
                RoundedRectangle(cornerRadius: WeekRadius.full)
                    .fill(barStyle)
                    .frame(width: isPremiumTheme ? 56 : 40, height: 4)
                    .padding(.top, WeekSpacing.md)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }
}

/// A row of round dots filling the rect, `dotSize` across with a gap of the
/// same size between them (猫猫 section rule).
struct DottedRuleShape: Shape {
    var dotSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let d = max(1, min(dotSize, rect.height))
        let step = d * 2.2
        var x = rect.minX
        while x + d <= rect.maxX {
            path.addEllipse(in: CGRect(x: x, y: rect.midY - d / 2, width: d, height: d))
            x += step
        }
        return path
    }
}

/// A ribbon bookmark with a swallow-tail notch at the bottom.
struct BookmarkRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notch = min(rect.width * 0.5, rect.height * 0.3)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Feature panel parts

/// Heading of a feature panel ("专注任务"). Classic themes keep the white
/// icon + serif title; personalised skins draw their own label.
struct WeekFeatureLabel: View {
    let systemImage: String
    let title: String
    @Environment(\.themeSkin) private var skin

    var body: some View {
        if let label = skin.feature?.label {
            themed(label)
        } else {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.white)
                Text(title)
                    .font(.titleSmall)
                    .foregroundColor(.white)
            }
        }
    }

    @ViewBuilder
    private func themed(_ label: ThemeLabelSkin) -> some View {
        if skin.glyphs != nil {
            HStack(spacing: 7) {
                ThemedSymbol(systemName: systemImage, size: 18)
                    .foregroundColor(label.ink.color)
                labelText(label)
            }
        } else {
            labelText(label)
        }
    }

    @ViewBuilder
    private func labelText(_ label: ThemeLabelSkin) -> some View {
        switch label.kind {
        case .plain:
            Text(title)
                .font(.titleSmall)
                .foregroundColor(label.ink.color)
        case .block:
            Text(title)
                .font(.captionSmall.weight(.black))
                .foregroundColor(label.ink.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(label.fill?.color ?? .clear)
        case .spaced:
            Text(title)
                .font(.captionSmall.weight(.bold))
                .tracking(2)
                .foregroundColor(label.ink.color)
        case .prompt:
            Text(verbatim: "> " + title)
                .font(.captionSmall.weight(.semibold))
                .foregroundColor(label.ink.color)
        }
    }
}

/// Block cursor drawn after the feature title (terminal). Nothing for other skins.
struct WeekFeatureCursor: View {
    @Environment(\.themeSkin) private var skin

    var body: some View {
        if let cursor = skin.feature?.cursor {
            Rectangle()
                .fill(cursor.color)
                .frame(width: 9, height: 17)
                .shadow(color: cursor.color.opacity(0.8), radius: 3)
                .accessibilityHidden(true)
        }
    }
}

/// Button chrome on the feature panel. Classic themes keep the white label on
/// a 20 % white capsule exactly as before.
struct WeekFeatureActionModifier: ViewModifier {
    let isPrimary: Bool
    @Environment(\.themeSkin) private var skin

    @ViewBuilder
    func body(content: Content) -> some View {
        if let feature = skin.feature {
            themed(content, look: isPrimary ? feature.primaryAction : feature.action)
        } else {
            content
                .foregroundColor(.white)
                .background(.white.opacity(0.2), in: Capsule())
        }
    }

    @ViewBuilder
    private func themed(_ content: Content, look: ThemeActionLook) -> some View {
        let ink = look.ink.color
        let fill = look.fill?.color ?? .clear
        let border = look.border?.color ?? .clear
        switch look.kind {
        case .capsule:
            content
                .foregroundColor(ink)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(border, lineWidth: look.borderWidth))
                .shadow(
                    color: look.fill == nil || !look.glows ? .clear : fill.opacity(0.7),
                    radius: look.fill == nil || !look.glows ? 0 : 5
                )
        case .rect:
            content
                .foregroundColor(ink)
                .background(fill)
                .overlay(Rectangle().strokeBorder(border, lineWidth: look.borderWidth))
                .background(
                    Rectangle()
                        .fill(look.hardShadow?.color ?? .clear)
                        .offset(x: 2, y: 2)
                )
        case .underline:
            content
                .foregroundColor(ink)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(border)
                        .frame(height: look.borderWidth)
                        .padding(.horizontal, WeekSpacing.sm)
                }
        case .stamp:
            content
                .foregroundColor(ink)
                .background(fill)
                .overlay(Rectangle().strokeBorder(border, lineWidth: look.borderWidth))
                .rotationEffect(.degrees(-4))
        case .roundedRect:
            content
                .foregroundColor(ink)
                .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(border, lineWidth: look.borderWidth)
                )
        case .bracket:
            HStack(spacing: 0) {
                Text(verbatim: "[")
                content
                Text(verbatim: "]")
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(ink)
            .background(fill)
        }
    }
}

extension View {
    /// Styles a button that sits on a `WeekCard(useGradient: true)` feature panel.
    func weekyiiFeatureAction(isPrimary: Bool = false) -> some View {
        modifier(WeekFeatureActionModifier(isPrimary: isPrimary))
    }
}

// MARK: - Section header

/// Card section header: icon, title and count ("冻结任务 3"). Classic themes keep
/// the original row; personalised skins drop the icon and restyle the count.
struct WeekSectionHeader: View {
    let systemImage: String
    let title: String
    let count: Int
    let tint: Color
    @Environment(\.themeSkin) private var skin

    var body: some View {
        if let section = skin.section {
            themed(section)
        } else {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(tint)
                Text(title)
                    .font(.titleSmall)
                    .foregroundColor(.textPrimary)

                Spacer()

                Text("\(count)")
                    .font(.titleSmall)
                    .foregroundColor(tint)
            }
        }
    }

    private func themed(_ section: ThemeSectionSkin) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: section.showsIcon ? .center : .firstTextBaseline, spacing: WeekSpacing.sm) {
                if section.showsIcon {
                    let iconColor = section.iconInk?.color ?? tint
                    ThemedSymbol(systemName: systemImage, size: 17)
                        .foregroundColor(iconColor)
                        .shadow(color: section.iconInk == nil ? tint.opacity(0.45) : .clear, radius: section.iconInk == nil ? 3 : 0)
                }
                titleText(section)
                    .font(.titleSmall)
                    .tracking(section.titleTracking)

                Spacer(minLength: WeekSpacing.sm)

                countView(section.count)
            }
            if let rule = section.rule {
                if section.ruleFades {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [rule.color, rule.color.opacity(0.35), rule.color.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                } else if let mark = section.ruleEndMark {
                    // The rule runs out into a small mark: a ring, or a filled paw for the cat skin.
                    HStack(spacing: 5) {
                        ruleLine(section, color: rule.color)
                        if skin.glyphs == .cat {
                            CatGlyphView(glyph: .paw)
                                .frame(width: 12, height: 12)
                                .foregroundStyle(mark.color)
                        } else {
                            Ellipse()
                                .strokeBorder(mark.color, lineWidth: 1.2)
                                .frame(width: 10, height: 7)
                        }
                    }
                    .accessibilityHidden(true)
                } else {
                    ruleLine(section, color: rule.color)
                }
            }
        }
    }

    /// The header rule: a solid line, or a row of round dots (猫猫).
    @ViewBuilder
    private func ruleLine(_ section: ThemeSectionSkin, color: Color) -> some View {
        if section.ruleDotted {
            DottedRuleShape(dotSize: section.ruleWidth)
                .fill(color)
                .frame(height: section.ruleWidth)
        } else {
            Rectangle()
                .fill(color)
                .frame(height: section.ruleWidth)
        }
    }

    /// The title, with a rubricated first character when the skin asks for one.
    private func titleText(_ section: ThemeSectionSkin) -> Text {
        Self.rubricText(title, section: section)
    }

    static func rubricText(_ title: String, section: ThemeSectionSkin, ink: Color = .textPrimary) -> Text {
        let full = (section.titlePrefix ?? "") + title
        guard let rubric = section.rubric, let first = full.first else {
            return Text(verbatim: full).foregroundColor(ink)
        }
        let initial = Text(verbatim: String(first)).foregroundColor(rubric.color)
        let rest = Text(verbatim: String(full.dropFirst())).foregroundColor(ink)
        return Text("\(initial)\(rest)")
    }

    @ViewBuilder
    private func countView(_ kind: ThemeCountKind) -> some View {
        let tint = skin.section?.countInk?.color ?? self.tint
        switch kind {
        case .plain:
            Text(verbatim: "\(count)")
                .font(.titleSmall)
                .foregroundColor(tint)
        case .block:
            Text(verbatim: "\(count)")
                .font(.titleSmall)
                .foregroundColor(.backgroundSecondary)
                .padding(.horizontal, 7)
                .background(Color.textPrimary)
        case .bracket:
            Text(verbatim: "[\(count)]")
                .font(.titleSmall)
                .foregroundColor(tint)
        case .italic:
            Text(verbatim: "\(count)")
                .font(.titleSmall)
                .italic()
                .foregroundColor(tint)
        case .serif:
            Text(verbatim: "\(count)")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .monospacedDigit()
                .foregroundColor(tint)
        case .capsule:
            Text(verbatim: "\(count)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(tint.opacity(0.14), in: Capsule())
        case .itemCaption:
            Text(Self.itemCaption(count))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(skin.section?.countInk?.color ?? .textSecondary)
        }
    }

    /// "3 项" / "3 items".
    static func itemCaption(_ count: Int) -> String {
        String(
            format: String(localized: "section.count.items", defaultValue: "%lld 项"),
            locale: Locale.current,
            Int64(count)
        )
    }
}

/// The count beside a custom section title (draft area). It follows the same
/// skin rule as `WeekSectionHeader`; classic themes keep the primary numeral.
struct ThemedSectionCount: View {
    let count: Int
    @Environment(\.themeSkin) private var skin

    var body: some View {
        if skin.section?.count == .itemCaption {
            Text(WeekSectionHeader.itemCaption(count))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(skin.section?.countInk?.color ?? .textSecondary)
        } else {
            Text("\(count)")
                .font(.titleSmall)
                .foregroundColor(.weekyiiPrimary)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        WeekCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("普通卡片")
                    .font(.titleSmall)
                Text("这是一个普通的卡片示例")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
        }
        
        WeekCard(useGradient: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("渐变卡片")
                    .font(.titleSmall)
                    .foregroundColor(.white)
                Text("这是一个带渐变背景的卡片")
                    .font(.bodyMedium)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        
        WeekCard(accentColor: .accentOrange) {
            VStack(alignment: .leading, spacing: 8) {
                Text("带装饰条的卡片")
                    .font(.titleSmall)
                Text("顶部有橙色装饰条")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
        }
    }
    .padding()
    .background(Color.backgroundPrimary)
}

/// A section title drawn outside `WeekSectionHeader` (draft area, kill time …).
/// It follows the same skin rules (rubricated first character, tracking), so
/// every visible header on a page speaks the same language.
struct ThemedSectionTitle: View {
    let title: String
    @Environment(\.themeSkin) private var skin

    /// Only the rubric and tracking carry over; a skin's title prefix stays on
    /// `WeekSectionHeader`, so these headers keep reading as before.
    private var headerSection: ThemeSectionSkin? {
        guard var section = skin.section else { return nil }
        section.titlePrefix = nil
        return section
    }

    var body: some View {
        if let section = headerSection {
            WeekSectionHeader.rubricText(title, section: section)
                .font(.titleSmall)
                .tracking(section.titleTracking)
        } else {
            Text(verbatim: title)
                .font(.titleSmall)
                .foregroundColor(.textPrimary)
        }
    }
}

/// The small icon in front of a custom section title. Skinned themes draw the
/// skin glyph in the section's icon ink; classic themes keep the SF Symbol tint.
struct ThemedSectionIcon: View {
    let systemName: String
    let tint: Color
    @Environment(\.themeSkin) private var skin

    var body: some View {
        if skin.section?.count == .itemCaption {
            // 魔戒 · 玄铁与古金: section titles stand alone, like the cards' headers.
            EmptyView()
        } else if let section = skin.section, section.showsIcon {
            ThemedSymbol(systemName: systemName, size: 17)
                .foregroundColor(section.iconInk?.color ?? tint)
        } else {
            Image(systemName: systemName)
                .foregroundColor(tint)
        }
    }
}
