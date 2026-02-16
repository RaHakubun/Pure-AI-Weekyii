import Foundation
import SwiftData

@Model
final class MindStampItem {
    @Attribute(.unique) var id: UUID = UUID()

    var text: String
    @Attribute(.externalStorage) var imageBlob: Data?
    var createdAt: Date

    init(text: String = "", imageBlob: Data? = nil) {
        self.text = text
        self.imageBlob = imageBlob
        self.createdAt = Date()
    }

    /// Whether this stamp has any content
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageBlob != nil
    }
}
