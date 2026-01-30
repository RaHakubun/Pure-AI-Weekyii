import Foundation
import SwiftData

@Model
final class TaskAttachment {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var data: Data?
    var fileName: String
    var fileType: String // e.g., "image/jpeg", "application/pdf"
    var createdAt: Date
    
    init(data: Data?, fileName: String, fileType: String) {
        self.data = data
        self.fileName = fileName
        self.fileType = fileType
        self.createdAt = Date()
    }
}
