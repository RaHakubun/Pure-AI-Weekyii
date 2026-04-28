import Foundation
import SwiftData
import CryptoKit

enum WeekyiiPersistence {
    enum LaunchState {
        case ready(ModelContainer)
        case failed(String)
    }

    static let currentSchema = Schema(versionedSchema: WeekyiiSchemaV4.self)

    static func bootstrapPersistentContainer() -> LaunchState {
        let storeURL = persistentStoreURL()
        backupPersistentStoreIfExists(storeURL: storeURL)

        do {
            let container = try makeModelContainer(storeURL: storeURL)
            try validateContainerConsistency(container: container)
            return .ready(container)
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
        let snapshotFolder = backupFolder.appendingPathComponent("snapshot-\(timestamp)", isDirectory: true)
        try? fileManager.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)

        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
        ]

        var manifestFiles: [BackupManifest.FileEntry] = []
        for source in candidates where fileManager.fileExists(atPath: source.path) {
            let destination = snapshotFolder.appendingPathComponent(source.lastPathComponent)
            try? fileManager.copyItem(at: source, to: destination)
            if let entry = makeFileEntry(for: destination) {
                manifestFiles.append(entry)
            }
        }
        writeManifest(for: snapshotFolder, files: manifestFiles)
        pruneBackups(in: backupFolder)
    }

    static func failureDiagnostics() -> String {
        let storeURL = persistentStoreURL()
        let snapshots = BackupRecoveryService.listSnapshots(storeURL: storeURL)
        let recent = snapshots.prefix(5).map { snapshot in
            "\(snapshot.folderName) verified=\(snapshot.isValid ? "yes" : "no") files=\(snapshot.fileCount)"
        }

        return [
            "store=\(storeURL.path)",
            "schema=4.0.0",
            "snapshot_count=\(snapshots.count)",
            "recent=\n\(recent.joined(separator: "\n"))"
        ].joined(separator: "\n")
    }

    private static func validateContainerConsistency(container: ModelContainer) throws {
        let context = container.mainContext
        let weeks = (try? context.fetch(FetchDescriptor<WeekModel>())) ?? []
        let presentWeeks = weeks.filter { $0.status == .present }
        if presentWeeks.count > 1 {
            throw WeekyiiPersistenceError.inconsistentState("Detected \(presentWeeks.count) present weeks.")
        }
    }

    private static func makeFileEntry(for fileURL: URL) -> BackupManifest.FileEntry? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let hash = SHA256.hash(data: data)
        let digest = hash.map { String(format: "%02x", $0) }.joined()
        return BackupManifest.FileEntry(
            fileName: fileURL.lastPathComponent,
            fileSize: Int64(data.count),
            sha256: digest
        )
    }

    private static func writeManifest(for folder: URL, files: [BackupManifest.FileEntry]) {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let manifest = BackupManifest(
            createdAt: Date(),
            schemaVersion: "4.0.0",
            appVersion: appVersion,
            files: files
        )
        guard let encoded = try? JSONEncoder().encode(manifest) else { return }
        let manifestURL = folder.appendingPathComponent("manifest.json")
        try? encoded.write(to: manifestURL, options: .atomic)
    }

    private static func pruneBackups(in backupFolder: URL) {
        let fileManager = FileManager.default
        let snapshots = ((try? fileManager.contentsOfDirectory(
            at: backupFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter { $0.lastPathComponent.hasPrefix("snapshot-") }
        .sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        var keep = Set<URL>(snapshots.prefix(40))
        var dailyBuckets = Set<String>()
        var weeklyBuckets = Set<String>()
        let calendar = Calendar(identifier: .iso8601)
        for snapshot in snapshots {
            guard let date = (try? snapshot.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) else { continue }
            let day = "\(calendar.component(.year, from: date))-\(calendar.ordinality(of: .day, in: .year, for: date) ?? 0)"
            if dailyBuckets.count < 14 && !dailyBuckets.contains(day) {
                keep.insert(snapshot)
                dailyBuckets.insert(day)
            }
            let week = "\(calendar.component(.yearForWeekOfYear, from: date))-\(calendar.component(.weekOfYear, from: date))"
            if weeklyBuckets.count < 8 && !weeklyBuckets.contains(week) {
                keep.insert(snapshot)
                weeklyBuckets.insert(week)
            }
        }

        for snapshot in snapshots where !keep.contains(snapshot) {
            try? fileManager.removeItem(at: snapshot)
        }
    }
}

enum WeekyiiPersistenceError: LocalizedError {
    case inconsistentState(String)

    var errorDescription: String? {
        switch self {
        case .inconsistentState(let message):
            return message
        }
    }
}

private struct BackupManifest: Codable {
    struct FileEntry: Codable {
        let fileName: String
        let fileSize: Int64
        let sha256: String
    }

    let createdAt: Date
    let schemaVersion: String
    let appVersion: String
    let files: [FileEntry]
}

enum BackupRecoveryService {
    struct SnapshotSummary: Equatable {
        let folderName: String
        let createdAt: Date
        let fileCount: Int
        let isValid: Bool
    }

    static func listSnapshots(storeURL: URL) -> [SnapshotSummary] {
        let backupFolder = storeURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        let fileManager = FileManager.default
        let folders = ((try? fileManager.contentsOfDirectory(
            at: backupFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter { $0.lastPathComponent.hasPrefix("snapshot-") }

        return folders.compactMap { folder in
            let manifestURL = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) else {
                return SnapshotSummary(
                    folderName: folder.lastPathComponent,
                    createdAt: .distantPast,
                    fileCount: 0,
                    isValid: false
                )
            }
            return SnapshotSummary(
                folderName: folder.lastPathComponent,
                createdAt: manifest.createdAt,
                fileCount: manifest.files.count,
                isValid: verifySnapshot(folder: folder)
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func verifySnapshot(folder: URL) -> Bool {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) else {
            return false
        }

        for file in manifest.files {
            let fileURL = folder.appendingPathComponent(file.fileName)
            guard let content = try? Data(contentsOf: fileURL) else { return false }
            let digest = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
            guard digest == file.sha256, Int64(content.count) == file.fileSize else { return false }
        }
        return true
    }

    static func restoreSnapshot(named folderName: String, to storeURL: URL) throws {
        let fileManager = FileManager.default
        let backupFolder = storeURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        let snapshotFolder = backupFolder.appendingPathComponent(folderName, isDirectory: true)
        guard verifySnapshot(folder: snapshotFolder) else {
            throw WeekyiiPersistenceError.inconsistentState("Snapshot verification failed.")
        }

        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
        ]
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            try? fileManager.removeItem(at: candidate)
        }

        let sourceFiles = [
            snapshotFolder.appendingPathComponent(storeURL.lastPathComponent),
            snapshotFolder.appendingPathComponent(storeURL.lastPathComponent + "-wal"),
            snapshotFolder.appendingPathComponent(storeURL.lastPathComponent + "-shm"),
        ]
        let targets = candidates
        for (source, target) in zip(sourceFiles, targets) where fileManager.fileExists(atPath: source.path) {
            try fileManager.copyItem(at: source, to: target)
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
            WeekyiiSchemaV3.self,
            WeekyiiSchemaV4.self,
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
            ),
            .lightweight(fromVersion: WeekyiiSchemaV2.self, toVersion: WeekyiiSchemaV3.self),
            .lightweight(fromVersion: WeekyiiSchemaV3.self, toVersion: WeekyiiSchemaV4.self),
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

enum WeekyiiSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            WeekModel.self,
            DayModel.self,
            TaskItem.self,
            TaskStep.self,
            TaskAttachment.self,
            ProjectModel.self,
            MindStampItem.self,
            SuspendedTaskItem.self,
        ]
    }

    @Model
    final class SuspendedTaskItem {
        @Attribute(.unique) var id: UUID = UUID()

        var title: String
        var taskDescription: String
        var taskType: TaskType
        var createdAt: Date
        var decisionDeadline: Date
        var preferredCountdownDays: Int
        var snoozeCount: Int
        var statusRaw: String

        init(
            title: String,
            taskDescription: String = "",
            taskType: TaskType = .regular,
            createdAt: Date = Date(),
            decisionDeadline: Date,
            preferredCountdownDays: Int,
            snoozeCount: Int = 0,
            statusRaw: String = SuspendedTaskStatus.active.rawValue
        ) {
            self.title = title
            self.taskDescription = taskDescription
            self.taskType = taskType
            self.createdAt = createdAt
            self.decisionDeadline = decisionDeadline
            self.preferredCountdownDays = preferredCountdownDays
            self.snoozeCount = snoozeCount
            self.statusRaw = statusRaw
        }
    }
}

enum WeekyiiSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            WeekModel.self,
            DayModel.self,
            TaskItem.self,
            TaskStep.self,
            TaskAttachment.self,
            ProjectModel.self,
            MindStampItem.self,
            SuspendedTaskItem.self,
        ]
    }
}
