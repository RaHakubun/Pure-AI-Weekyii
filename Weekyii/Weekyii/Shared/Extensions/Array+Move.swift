import Foundation

extension Array {
    mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.map { self[$0] }
        var remaining: [Element] = []
        remaining.reserveCapacity(count - offsets.count)
        for (index, element) in enumerated() where !offsets.contains(index) {
            remaining.append(element)
        }
        let insertIndex = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: insertIndex)
        self = remaining
    }
}
