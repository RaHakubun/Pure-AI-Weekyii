import SwiftUI

/// 让首页模块在用户停留时轮换真实内容；不写入任何业务状态。
/// WP8.1 磁贴式：卡片外壳（背景/圆角/描边/阴影）由本容器持有且全程静止，
/// 内容面只在固定框内纵向滚动切换——离场面向上滚出、新面自下方滚入，卡槽永不空白。
/// Decorative motifs are confined to the Quenya theme and carry no interaction.
enum QuenyaHubMotif {
    case star, rings, inscription, tree
}

struct LiveModuleTile<Item: Identifiable, Content: View, EmptyContent: View>: View where Item.ID: Hashable {
    let items: [Item]
    let initialDelay: Duration
    let isActive: Bool
    let accessibilityIdentifier: String
    /// 非 nil 时卡片为固定比例框（原 HubSquareSurface 的几何）。
    var aspectRatio: CGFloat? = nil
    var minHeight: CGFloat = 0
    /// 拉伸卡：容器高度 = max(minHeight, 当前内容自然高度)，内容永不被裁切。
    var stretches: Bool = false
    let tint: (Item) -> Color
    let emptyTint: Color
    var quenyaMotif: QuenyaHubMotif? = nil
    @ViewBuilder let content: (Item) -> Content
    @ViewBuilder let emptyContent: () -> EmptyContent

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.weekyiiReduceMotion) private var appReduceMotion
    @Environment(\.themeSkin) private var skin
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex = 0
    @State private var rotationQueue: [Int] = []
    @State private var naturalHeight: CGFloat = 0

    /// System “reduce motion” and Weekyii's own switch both degrade the roll to an instant swap.
    private var reduceMotion: Bool {
        systemReduceMotion || appReduceMotion
    }

    private var itemIDs: [Item.ID] { items.map(\.id) }

    private var rotationIdentity: String {
        "\(isActive)-\(itemIDs.map { String(describing: $0) }.joined(separator: "|"))"
    }

    private var selectedItem: Item? {
        guard items.indices.contains(selectedIndex) else { return items.first }
        return items[selectedIndex]
    }

    /// 描边色跟随当前内容面，只随换面事务做颜色过渡，不产生任何运动。
    private var currentTint: Color {
        guard let selectedItem else { return emptyTint }
        return tint(selectedItem)
    }

    private var faceTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    var body: some View {
        tileSurface
            .contentShape(Rectangle())
            .overlay { naturalHeightProbe }
            .accessibilityIdentifier(accessibilityIdentifier)
            .task(id: rotationIdentity) {
                normalizeSelection()
                await rotateWhileVisible()
            }
    }

    /// 红皮书把模块瓦片画成书页上的一块（与 WeekCard 相同的皮肤），
    /// 其他主题保持原来的圆角卡片与内容色描边。
    @ViewBuilder
    private var tileSurface: some View {
        if skin.isQuenya, let card = skin.card {
            shapedFaces
                .background {
                    if let quenyaMotif {
                        QuenyaHubDecoration(motif: quenyaMotif)
                    }
                }
                .themedSurface(card)
        } else if skin.glyphs == .cat, let card = skin.card {
            // 猫猫：软垫卡片用模块自己的颜色淡淡染一层，不加色条。
            shapedFaces.themedSurface(
                card,
                tint: currentTint,
                tintOpacity: colorScheme == .dark ? 0.10 : 0.09
            )
        } else if skin.glyphs == .lotr, let card = skin.card {
            // The selected basalt design uses one quiet surface across modules.
            shapedFaces.themedSurface(card)
        } else {
            shapedFaces
                .background(Color.backgroundSecondary)
                .clipShape(.rect(cornerRadius: WeekRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                        .stroke(currentTint.opacity(0.16), lineWidth: 1)
                }
                .weekSoftShadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        }
    }

    @ViewBuilder
    private var shapedFaces: some View {
        if let aspectRatio {
            faceStack
                .frame(maxWidth: .infinity)
                .aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            // 拉伸卡用 topLeading 保持原 ProjectEmptyLiveTile 的顶对齐；其余沿用原 Surface 的 .leading。
            faceStack
                .frame(
                    maxWidth: .infinity,
                    minHeight: resolvedMinHeight,
                    alignment: stretches ? .topLeading : .leading
                )
        }
    }

    private var resolvedMinHeight: CGFloat {
        guard stretches else { return minHeight }
        return max(minHeight, naturalHeight)
    }

    @ViewBuilder
    private var faceStack: some View {
        ZStack {
            if let selectedItem {
                content(selectedItem)
                    .id(selectedItem.id)
                    .transition(faceTransition)
            } else {
                emptyContent()
                    .transition(faceTransition)
            }
        }
    }

    /// 隐藏副本测量当前面的自然高度，保证拉伸 frame 永不小于内容。
    @ViewBuilder
    private var naturalHeightProbe: some View {
        if stretches, let selectedItem {
            content(selectedItem)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(
                        key: HubTileNaturalHeightKey.self,
                        value: proxy.size.height
                    )
                })
                .onPreferenceChange(HubTileNaturalHeightKey.self) { newValue in
                    naturalHeight = newValue
                }
                .opacity(0)
                .allowsHitTesting(false)
        }
    }

    @MainActor
    private func normalizeSelection() {
        guard !items.isEmpty else {
            selectedIndex = 0
            rotationQueue = []
            return
        }
        if !items.indices.contains(selectedIndex) {
            selectedIndex = 0
        }
        rotationQueue.removeAll { !items.indices.contains($0) || $0 == selectedIndex }
    }

    private func rotateWhileVisible() async {
        guard isActive, items.count > 1 else { return }
        guard await pause(for: initialDelay) else { return }

        while !Task.isCancelled {
            guard await advanceToRandomItem() else { return }
            guard await pause(for: .seconds(Double.random(in: 6...10))) else { return }
        }
    }

    private func pause(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    @MainActor
    private func advanceToRandomItem() async -> Bool {
        guard items.count > 1 else { return false }

        let currentIndex = items.indices.contains(selectedIndex) ? selectedIndex : 0
        let nextIndex = nextRotationIndex(excluding: currentIndex)

        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedIndex = nextIndex
            }
            return true
        }

        withAnimation(.easeInOut(duration: 0.4)) {
            selectedIndex = nextIndex
        }
        return true
    }

    @MainActor
    private func nextRotationIndex(excluding currentIndex: Int) -> Int {
        if rotationQueue.isEmpty {
            rotationQueue = items.indices.filter { $0 != currentIndex }.shuffled()
        }

        let nextIndex = rotationQueue.removeFirst()
        return nextIndex
    }
}

/// 上报当前内容面的自然高度，保证拉伸框永不小于内容。
private struct HubTileNaturalHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Background-only engravings: their GeometryReader takes the existing tile
/// bounds, never reserves space, and is excluded from touch and accessibility.
private struct QuenyaHubDecoration: View {
    let motif: QuenyaHubMotif
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            switch motif {
            case .star:
                QuenyaEightPointStar()
                    .stroke(Color.weekyiiPrimary.opacity(0.25), lineWidth: 0.8)
                    .frame(width: 50, height: 50)
                    .position(x: proxy.size.width - 33, y: 59)
            case .rings:
                ZStack {
                    Circle().stroke(lineWidth: 0.8)
                    Circle().inset(by: 7).stroke(lineWidth: 0.8)
                }
                .foregroundStyle(Color.weekyiiPrimary.opacity(0.18))
                .frame(width: 47, height: 47)
                .position(x: proxy.size.width - 36, y: 67)
            case .inscription:
                if proxy.size.width >= 240 {
                    Text("\u{E02E}\u{E046}\u{E022}\u{E046}\u{E010} \u{E024}\u{E02C}\u{E044}\u{E022}\u{E040} \u{E022}\u{E02C}\u{E04C}\u{E011}\u{E046}\u{E010}\u{E051} \u{E02E}\u{E04A}\u{E011}\u{E046}\u{E00C}\u{E044}\u{E02E}\u{E046}\u{E022}\u{E015}\u{E04A}")
                        .font(.custom("AlcarinTengwar-Regular", size: 13))
                        .foregroundStyle(Color.weekyiiPrimary.opacity(0.38))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: 132, alignment: .trailing)
                        .position(x: proxy.size.width - 80, y: 52)
                }
            case .tree:
                Image("QuenyaWhiteTree")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.weekyiiPrimary)
                    .opacity(0.26)
                    .frame(width: min(proxy.size.width * 0.34, 112), height: 132)
                    .position(x: proxy.size.width - 69, y: min(proxy.size.height * 0.56, 150))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Eight-point star, drawn as linework to match the approved preview.
private struct QuenyaEightPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (0.50, 0.04), (0.56, 0.40), (0.82, 0.18), (0.60, 0.44),
            (0.96, 0.50), (0.60, 0.56), (0.82, 0.82), (0.56, 0.60),
            (0.50, 0.96), (0.44, 0.60), (0.18, 0.82), (0.40, 0.56),
            (0.04, 0.50), (0.40, 0.44), (0.18, 0.18), (0.44, 0.40)
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + point.0 * rect.width,
                            y: rect.minY + point.1 * rect.height)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: rect.midX - rect.width * 0.1,
                                   y: rect.midY - rect.height * 0.1,
                                   width: rect.width * 0.2, height: rect.height * 0.2))
        return path
    }
}
