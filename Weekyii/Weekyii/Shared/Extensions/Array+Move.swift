import Foundation

extension Array {
    mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard offsets.isEmpty == false else { return }

        let validOffsets = IndexSet(offsets.filter { indices.contains($0) })
        guard validOffsets.isEmpty == false else { return }

        let normalizedDestination = Swift.min(Swift.max(destination, 0), count)
        let moving = validOffsets.map { self[$0] }
        var remaining: [Element] = []
        remaining.reserveCapacity(count - validOffsets.count)
        for (index, element) in enumerated() where !validOffsets.contains(index) {
            remaining.append(element)
        }

        let adjustedDestination = normalizedDestination - validOffsets.filter { $0 < normalizedDestination }.count
        let insertIndex = Swift.min(Swift.max(adjustedDestination, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: insertIndex)
        self = remaining
    }
}
