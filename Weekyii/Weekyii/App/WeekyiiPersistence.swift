import Foundation
import SwiftData

enum WeekyiiPersistence {
    enum LaunchState {
        case ready(ModelContainer)
        case failed(String)
    }

    static let currentSchema = Schema(versionedSchema: WeekyiiSchemaV2.self)

    static func bootstrapPersistentContainer() -> LaunchState {
        let storeURL = persistentStoreURL()
        backupPersistentStoreIfExists(storeURL: storeURL)

        do {
            return .ready(try makeModelContainer(storeURL: storeURL))
        } catch {
            print("Weekyii: persistent ModelContainer init failed: \(error.localizedDescription)")
            return .failed("本地数据库无法打开。应用已停止写入，避免数据进一步受损。请先导出 Application Support/Weekyii 下的文件，再联系处理迁移。")
        }
    }

    static func makeModelContainer(storeURL: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration("Weekyii", schema: currentSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let url = storeURL ?? persistentStoreURL()
            config = ModelConfiguration("Weekyii", schema: currentSchema, url: url, allowsSave: true, cloudKitDatabase: .none)
        }

        return try ModelContainer(
            for: currentSchema,
            migrationPlan: WeekyiiMigrationPlan.self,
            configurations: config
        )
    }

    static func persistentStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Weekyii", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Weekyii.store")
    }

    static func backupPersistentStoreIfExists(storeURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        let backupFolder = storeURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try? fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let candidates = [
            (source: storeURL, suffix: ".store"),
            (source: URL(fileURLWithPath: storeURL.path + "-wal"), suffix: ".store-wal"),
            (source: URL(fileURLWithPath: storeURL.path + "-shm"), suffix: ".store-shm"),
        ]

        for candidate in candidates where fileManager.fileExists(atPath: candidate.source.path) {
            let destination = backupFolder.appendingPathComponent("Weekyii-\(timestamp)\(candidate.suffix)")
            try? fileManager.copyItem(at: candidate.source, to: destination)
        }

        let backups = (try? fileManager.contentsOfDirectory(
            at: backupFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = backups.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        for stale in sorted.dropFirst(30) {
            try? fileManager.removeItem(at: stale)
        }
    }
}

enum WeekyiiSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            WeekModel.self,
            DayModel.self,
            TaskItem.self,
            TaskStep.self,
            TaskAttachment.self,
            ProjectModel.self,
            MindStampItem.self,
        ]
    }

    @Model
    final class WeekModel {
        @Attribute(.unique) var weekId: String
        var startDate: Date
        var endDate: Date
        var status: WeekStatus
        @Relationship(deleteRule: .cascade, inverse: \DayModel.week) var days: [DayModel] = []
        var completedTasksCount: Int = 0
        var expiredTasksCount: Int = 0
        var totalStartedDays: Int = 0

        init(weekId: String, startDate: Date, endDate: Date, status: WeekStatus = .pending) {
            self.weekId = weekId
            self.startDate = startDate
            self.endDate = endDate
            self.status = status
        }
    }

    @Model
    final class DayModel {
        @Attribute(.unique) var dayId: String
        var date: Date
        var dayOfWeek: String
        var status: DayStatus
        var killTimeHour: Int = 23
        var killTimeMinute: Int = 45
        var followsDefaultKillTime: Bool = true
        var initiatedAt: Date?
        var closedAt: Date?
        var week: WeekModel?
        @Relationship(deleteRule: .cascade, inverse: \TaskItem.day) var tasks: [TaskItem] = []
        var expiredCount: Int = 0

        init(dayId: String, date: Date, dayOfWeek: String = "Mon", status: DayStatus = .empty) {
            self.dayId = dayId
            self.date = date
            self.dayOfWeek = dayOfWeek
            self.status = status
        }
    }

    @Model
    final class TaskItem {
        @Attribute(.unique) var id: UUID
        var title: String
        var taskType: TaskType
        var order: Int
        var zone: TaskZone
        var taskDescription: String = ""
        @Relationship(deleteRule: .cascade) var steps: [TaskStep] = []
        @Relationship(deleteRule: .cascade) var attachments: [TaskAttachment] = []
        var startedAt: Date?
        var endedAt: Date?
        var completedOrder: Int = 0
        var day: DayModel?
        var project: ProjectModel?

        init(id: UUID = UUID(), title: String, taskType: TaskType = .regular, order: Int, zone: TaskZone = .draft) {
            self.id = id
            self.title = title
            self.taskType = taskType
            self.order = order
            self.zone = zone
        }
    }

    @Model
    final class TaskStep {
        var title: String
        var isCompleted: Bool
        var sortOrder: Int
        var createdAt: Date

        init(title: String, isCompleted: Bool = false, sortOrder: Int = 0, createdAt: Date = Date()) {
            self.title = title
            self.isCompleted = isCompleted
            self.sortOrder = sortOrder
            self.createdAt = createdAt
        }
    }

    @Model
    final class TaskAttachment {
        var id: UUID
        @Attribute(.externalStorage) var data: Data?
        var fileName: String
        var fileType: String
        var createdAt: Date

        init(id: UUID = UUID(), data: Data? = nil, fileName: String, fileType: String, createdAt: Date = Date()) {
            self.id = id
            self.data = data
            self.fileName = fileName
            self.fileType = fileType
            self.createdAt = createdAt
        }
    }

    @Model
    final class ProjectModel {
        @Attribute(.unique) var id: UUID
        var name: String
        var projectDescription: String
        var color: String
        var icon: String
        var status: ProjectStatus
        var startDate: Date
        var endDate: Date
        var createdAt: Date
        @Relationship(deleteRule: .nullify, inverse: \TaskItem.project) var tasks: [TaskItem] = []

        init(
            id: UUID = UUID(),
            name: String,
            projectDescription: String = "",
            color: String = "#C46A1A",
            icon: String = "folder.fill",
            status: ProjectStatus = .planning,
            startDate: Date = .now,
            endDate: Date = .now,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.projectDescription = projectDescription
            self.color = color
            self.icon = icon
            self.status = status
            self.startDate = startDate
            self.endDate = endDate
            self.createdAt = createdAt
        }
    }

    @Model
    final class MindStampItem {
        @Attribute(.unique) var id: UUID
        var text: String
        @Attribute(.externalStorage) var imageBlob: Data?
        var createdAt: Date

        init(id: UUID = UUID(), text: String = "", imageBlob: Data? = nil, createdAt: Date = Date()) {
            self.id = id
            self.text = text
            self.imageBlob = imageBlob
            self.createdAt = createdAt
        }
    }
}

enum WeekyiiSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            WeekModel.self,
            DayModel.self,
            TaskItem.self,
            TaskStep.self,
            TaskAttachment.self,
            ProjectModel.self,
            MindStampItem.self,
        ]
    }
}

enum WeekyiiMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            WeekyiiSchemaV1.self,
            WeekyiiSchemaV2.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: WeekyiiSchemaV1.self,
                toVersion: WeekyiiSchemaV2.self,
                willMigrate: nil,
                didMigrate: { context in
                    try normalizeProjectTiles(in: context)
                }
            )
        ]
    }

    private static func normalizeProjectTiles(in context: ModelContext) throws {
        let projects = try context.fetch(FetchDescriptor<ProjectModel>())
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        for (index, project) in projects.enumerated() {
            if project.tileSizeRaw.isEmpty {
                project.tileSizeRaw = ProjectTileSize.medium.rawValue
            } else if let normalized = ProjectTileSize(storedValue: project.tileSizeRaw) {
                project.tileSizeRaw = normalized.rawValue
            }
            project.tileOrder = index
        }

        if context.hasChanges {
            try context.save()
        }
    }
}
