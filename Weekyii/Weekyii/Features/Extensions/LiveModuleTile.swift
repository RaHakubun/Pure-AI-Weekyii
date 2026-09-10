import SwiftUI

/// 让首页模块在用户停留时轮换真实内容；不写入任何业务状态。
struct LiveModuleTile<Item: Identifiable, Content: View, EmptyContent: View>: View where Item.ID: Hashable {
    let items: [Item]
    let initialDelay: Duration
    let isActive: Bool
    let accessibilityIdentifier: String
    @ViewBuilder let content: (Item) -> Content
    @ViewBuilder let emptyContent: () -> EmptyContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIndex = 0
    @State private var rotation = 0.0
    @State private var rotationQueue: [Int] = []

    private var itemIDs: [Item.ID] { items.map(\.id) }

    private var rotationIdentity: String {
        "\(isActive)-\(itemIDs.map { String(describing: $0) }.joined(separator: "|"))"
    }

    private var selectedItem: Item? {
        guard items.indices.contains(selectedIndex) else { return items.first }
        return items[selectedIndex]
    }

    var body: some View {
        Group {
            if let selectedItem {
                content(selectedItem)
                    .id(selectedItem.id)
            } else {
                emptyContent()
            }
        }
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : rotation),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.72
        )
        .accessibilityIdentifier(accessibilityIdentifier)
        .task(id: rotationIdentity) {
            normalizeSelection()
            await rotateWhileVisible()
        }
        .onChange(of: reduceMotion) { _, isReducedMotionEnabled in
            guard isReducedMotionEnabled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                rotation = 0
            }
        }
    }

    @MainActor
    private func normalizeSelection() {
        guard !items.isEmpty else {
            selectedIndex = 0
            rotation = 0
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
            rotation = 0
            withAnimation(.easeInOut(duration: 0.24)) {
                selectedIndex = nextIndex
            }
            return true
        }

        withAnimation(.easeIn(duration: 0.18)) {
            rotation = 90
        }
        guard await pause(for: .seconds(0.18)) else { return false }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedIndex = nextIndex
            rotation = -90
        }

        withAnimation(.easeOut(duration: 0.22)) {
            rotation = 0
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
