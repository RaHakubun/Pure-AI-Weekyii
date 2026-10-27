import SwiftUI

// MARK: - WeekCard - 增强版卡片组件

struct WeekCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeSkin) private var skin
    let content: Content
    let useGradient: Bool
    let accentColor: Color?
    let shadow: WeekShadow
    
    init(
        useGradient: Bool = false,
        accentColor: Color? = nil,
        shadow: WeekShadow = .light,
        @ViewBuilder content: () -> Content
    ) {
        self.useGradient = useGradient
        self.accentColor = accentColor
        self.shadow = shadow
        self.content = content()
    }
    
    var body: some View {
        if useGradient, let feature = skin.feature {
            featureBody(feature)
        } else if !useGradient, let card = skin.card {
            stack
                .themedSurface(card)
                .overlay(themedAccentBar(card), alignment: .top)
        } else {
            classicBody
        }
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
            .overlay(alignment: .leading) { marginRule(feature.marginRule) }
            .themedSurface(feature.surface)
            .overlay(themedAccentBar(feature.surface), alignment: .top)
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

    @ViewBuilder
    private func themedAccentBar(_ surface: ThemeSurfaceSkin) -> some View {
        if let color = accentColor, surface.ribbonAccent {
            // A silk bookmark hanging from the top rule.
            BookmarkRibbonShape()
                .fill(color)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.black.opacity(0.18)).frame(height: 1.5)
                }
                .frame(width: 9, height: 18)
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
                } else {
                    Rectangle()
                        .fill(rule.color)
                        .frame(height: section.ruleWidth)
                }
            }
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
        if let section = skin.section, section.showsIcon {
            ThemedSymbol(systemName: systemName, size: 17)
                .foregroundColor(section.iconInk?.color ?? tint)
        } else {
            Image(systemName: systemName)
                .foregroundColor(tint)
        }
    }
}
