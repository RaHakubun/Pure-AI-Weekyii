import Foundation
import SwiftData

@Model
final class TaskAttachment {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var data: Data?
    var fileName: String = ""
    var fileType: String = "application/octet-stream"
    var createdAt: Date = Date()
    var task: TaskItem?
    var suspendedTask: SuspendedTaskItem?
    
    /// Creates an attachment.
    ///
    /// `id` and `createdAt` are the attachment's **business identity** — they are
    /// what the sync layer addresses this resource by. Callers that *move* or
    /// *edit* an existing attachment must pass the existing values through;
    /// only callers that genuinely create a new resource may let both default.
    ///
    /// This signature change adds no persisted property, so the schema stays at
    /// V8 (see `WeekyiiPersistence.swift` `WeekyiiSchemaV8`).
    init(
        id: UUID = UUID(),
        data: Data?,
        fileName: String,
        fileType: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.data = data
        self.fileName = fileName
        self.fileType = fileType
        self.createdAt = createdAt
    }
}
