import Foundation
import SwiftData
#if DEBUG
import CoreData
#endif
import CryptoKit

enum WeekyiiPersistence {
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.fluentdesign.Weekyii"

    enum StoreMode: Equatable {
        case production
        case localOnly
        case inMemory

        var cloudKitContainerIdentifier: String? {
            switch self {
            case .production:
                return WeekyiiPersistence.cloudKitContainerIdentifier
            case .localOnly, .inMemory:
                return nil
            }
        }
    }

    enum LaunchState {
        case ready(ModelContainer)
        case failed(String)
    }

    static let currentSchema = Schema(versionedSchema: WeekyiiSchemaV7.self)

    static func shouldInitializeCloudKitSchema(arguments: [String]) -> Bool {
        #if DEBUG
        arguments.contains("-initializeCloudKitSchema")
        #else
        false
        #endif
    }

    #if DEBUG
    static func initializeCloudKitDevelopmentSchema() throws {
        guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(
            for: WeekyiiSchemaV7.models
        ) else {
            throw WeekyiiPersistenceError.inconsistentState(
                "Unable to synthesize the CloudKit managed object model."
            )
        }

        let fileManager = FileManager.default
        let schemaFolder = fileManager.temporaryDirectory
            .appendingPathComponent("WeekyiiCloudKitSchema", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: schemaFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: schemaFolder) }

        try autoreleasepool {
            let storeURL = schemaFolder.appendingPathComponent("Schema.store")
            let description = NSPersistentStoreDescription(url: storeURL)
            description.shouldAddStoreAsynchronously = false
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerIdentifier
            )

            let container = NSPersistentCloudKitContainer(
                name: "WeekyiiCloudKitSchema",
                managedObjectModel: managedObjectModel
            )
            container.persistentStoreDescriptions = [description]

            var loadError: Error?
            container.loadPersistentStores { _, error in
                loadError = error
            }
            if let loadError { throw loadError }

            defer {
                if let store = container.persistentStoreCoordinator.persistentStores.first {
                    try? container.persistentStoreCoordinator.remove(store)
                }
            }

            try container.initializeCloudKitSchema()
        }
    }
    #endif

    static func launchStoreMode(environment: [String: String]) -> StoreMode {
        environment["XCTestConfigurationFilePath"] == nil ? .production : .localOnly
    }

    static func bootstrapPersistentContainer(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        storeURL: URL? = nil,
        storeMode: StoreMode? = nil,
        referenceDate: Date = Date()
    ) -> LaunchState {
        let resolvedStoreURL = storeURL ?? persistentStoreURL()
        backupPersistentStoreIfExists(storeURL: resolvedStoreURL)

        do {
            let container = try makeModelContainer(
                storeURL: resolvedStoreURL,
                storeMode: storeMode ?? launchStoreMode(environment: environment)
            )
            _ = DataInvariantRepairService(modelContainer: container).repair(referenceDate: referenceDate)
            try validateContainerConsistency(container: container)
            return .ready(container)
        } catch {
            print("Weekyii: persistent ModelContainer init failed: \(error.localizedDescription)")
            return .failed("本地数据库无法打开。应用已停止写入，避免数据进一步受损。请先导出 Application Support/Weekyii 下的文件，再联系处理迁移。")
        }
    }

    static func makeModelContainer(
        storeURL: URL? = nil,
        inMemory: Bool = false,
        storeMode: StoreMode? = nil
    ) throws -> ModelContainer {
        let resolvedMode = storeMode ?? (inMemory ? .inMemory : .localOnly)
        let config: ModelConfiguration
        if resolvedMode == .inMemory {
            config = ModelConfiguration("Weekyii", schema: currentSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let url = storeURL ?? persistentStoreURL()
            let cloudKitDatabase = resolvedMode.cloudKitContainerIdentifier.map {
                ModelConfiguration.CloudKitDatabase.private($0)
            } ?? .none
            config = ModelConfiguration(
                "Weekyii",
                schema: currentSchema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: cloudKitDatabase
            )
        }

        let container = try ModelContainer(
            for: currentSchema,
            migrationPlan: WeekyiiMigrationPlan.self,
            configurations: config
        )
        try TaskTypeCatalog.seedBuiltInTypesIfNeeded(in: container.mainContext)
        return container
    }

    static func persistentStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Weekyii", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Weekyii.store")
    }

    static func backupPersistentStoreIfExists(storeURL: URL) {
        let preflightReason = "preflight-v7"
        let alreadyProtected = BackupRecoveryService.listSnapshots(storeURL: storeURL)
            .contains { $0.isValid && $0.folderName.contains(preflightReason) }
        guard !alreadyProtected else { return }
        _ = try? BackupRecoveryService.createSnapshot(
            storeURL: storeURL,
            reason: preflightReason
        )
    }

    fileprivate static func pruneSnapshots(in backupFolder: URL) {
        pruneBackups(in: backupFolder)
    }

    fileprivate static func fileEntry(
        for fileURL: URL,
        relativePath: String? = nil
    ) -> BackupManifest.FileEntry? {
        makeFileEntry(for: fileURL, relativePath: relativePath)
    }

    fileprivate static func persistManifest(in folder: URL, files: [BackupManifest.FileEntry]) {
        writeManifest(for: folder, files: files)
    }

    static func failureDiagnostics() -> String {
        let storeURL = persistentStoreURL()
        let snapshots = BackupRecoveryService.listSnapshots(storeURL: storeURL)
        let recent = snapshots.prefix(5).map { snapshot in
            "\(snapshot.folderName) verified=\(snapshot.isValid ? "yes" : "no") files=\(snapshot.fileCount)"
        }

        return [
            "store=\(storeURL.path)",
            "schema=7.0.0",
            "snapshot_count=\(snapshots.count)",
            "recent=\n\(recent.joined(separator: "\n"))"
        ].joined(separator: "\n")
    }

    private static func validateContainerConsistency(container: ModelContainer) throws {
        let context = container.mainContext
        let weeks = try context.fetch(FetchDescriptor<WeekModel>())
        let presentWeeks = weeks.filter { $0.status == .present }
        if presentWeeks.count > 1 {
            throw WeekyiiPersistenceError.inconsistentState("Detected \(presentWeeks.count) present weeks.")
        }
    }

    private static func makeFileEntry(
        for fileURL: URL,
        relativePath: String? = nil
    ) -> BackupManifest.FileEntry? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        var fileSize: Int64 = 0
        do {
            while true {
                let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
                guard !chunk.isEmpty else { break }
                fileSize += Int64(chunk.count)
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return BackupManifest.FileEntry(
            fileName: relativePath ?? fileURL.lastPathComponent,
            fileSize: fileSize,
            sha256: digest
        )
    }

    private static func writeManifest(for folder: URL, files: [BackupManifest.FileEntry]) {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let manifest = BackupManifest(
            createdAt: Date(),
            schemaVersion: "7.0.0",
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

        let keep = Set<URL>(snapshots.prefix(8))

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

fileprivate struct BackupManifest: Codable {
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

    @discardableResult
    static func createSnapshot(storeURL: URL, reason: String? = nil) throws -> SnapshotSummary? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return nil }

        let backupFolder = storeURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        var backupFolderValues = URLResourceValues()
        backupFolderValues.isExcludedFromBackup = true
        var mutableBackupFolder = backupFolder
        try mutableBackupFolder.setResourceValues(backupFolderValues)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let suffix = reason.map { "-\($0)" } ?? ""
        let uniqueID = UUID().uuidString.prefix(8)
        let snapshotFolder = backupFolder.appendingPathComponent(
            "snapshot-\(timestamp)\(suffix)-\(uniqueID)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)

        do {
            var candidates = [
                storeURL,
                URL(fileURLWithPath: storeURL.path + "-wal"),
                URL(fileURLWithPath: storeURL.path + "-shm"),
            ]
            candidates.append(contentsOf: supportDirectoryCandidates(for: storeURL))

            for source in candidates where fileManager.fileExists(atPath: source.path) {
                let destination = snapshotFolder.appendingPathComponent(source.lastPathComponent)
                try fileManager.copyItem(at: source, to: destination)
            }

            var entries: [BackupManifest.FileEntry] = []
            for fileURL in regularFiles(recursivelyUnder: snapshotFolder) {
                let relativePath = relativePath(of: fileURL, under: snapshotFolder)
                guard let entry = WeekyiiPersistence.fileEntry(
                    for: fileURL,
                    relativePath: relativePath
                ) else {
                    throw WeekyiiPersistenceError.inconsistentState("无法计算恢复点校验摘要。")
                }
                entries.append(entry)
            }
            guard !entries.isEmpty else {
                throw WeekyiiPersistenceError.inconsistentState("没有可写入恢复点的数据库文件。")
            }
            WeekyiiPersistence.persistManifest(in: snapshotFolder, files: entries)
            guard verifySnapshot(folder: snapshotFolder) else {
                throw WeekyiiPersistenceError.inconsistentState("导入前恢复点校验失败。")
            }
            WeekyiiPersistence.pruneSnapshots(in: backupFolder)
            return SnapshotSummary(
                folderName: snapshotFolder.lastPathComponent,
                createdAt: Date(),
                fileCount: entries.count,
                isValid: true
            )
        } catch {
            try? fileManager.removeItem(at: snapshotFolder)
            throw error
        }
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
            guard let fileURL = safeURL(for: file.fileName, under: folder),
                  let current = WeekyiiPersistence.fileEntry(
                    for: fileURL,
                    relativePath: file.fileName
                  ),
                  current.sha256 == file.sha256,
                  current.fileSize == file.fileSize else {
                return false
            }
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

        let manifestURL = snapshotFolder.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)

        var candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
        ]
        candidates.append(contentsOf: supportDirectoryCandidates(for: storeURL).filter { directory in
            let prefix = directory.lastPathComponent + "/"
            return manifest.files.contains { $0.fileName.hasPrefix(prefix) }
        })
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }

        for file in manifest.files {
            guard let source = safeURL(for: file.fileName, under: snapshotFolder),
                  let target = safeURL(for: file.fileName, under: storeURL.deletingLastPathComponent()) else {
                throw WeekyiiPersistenceError.inconsistentState("Snapshot contains an invalid file path.")
            }
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: target)
        }
    }

    @discardableResult
    static func restoreLatestValidSnapshot(to storeURL: URL) throws -> SnapshotSummary? {
        guard let snapshot = listSnapshots(storeURL: storeURL).first(where: \.isValid) else {
            return nil
        }
        try restoreSnapshot(named: snapshot.folderName, to: storeURL)
        return snapshot
    }

    private static func supportDirectoryCandidates(for storeURL: URL) -> [URL] {
        let parent = storeURL.deletingLastPathComponent()
        let baseName = storeURL.deletingPathExtension().lastPathComponent
        return [
            parent.appendingPathComponent(".\(baseName)_SUPPORT", isDirectory: true),
            parent.appendingPathComponent("\(storeURL.lastPathComponent)_SUPPORT", isDirectory: true),
        ]
    }

    private static func regularFiles(recursivelyUnder folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: nil
        ) else { return [] }

        return enumerator.compactMap { element in
            guard let url = element as? URL,
                  (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }

    private static func relativePath(of fileURL: URL, under folder: URL) -> String {
        String(fileURL.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
    }

    private static func safeURL(for relativePath: String, under folder: URL) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let root = folder.standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
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
            WeekyiiSchemaV4.WeekModel.self,
            WeekyiiSchemaV4.DayModel.self,
            WeekyiiSchemaV4.TaskItem.self,
            WeekyiiSchemaV4.TaskStep.self,
            WeekyiiSchemaV4.TaskAttachment.self,
            WeekyiiSchemaV4.ProjectModel.self,
            WeekyiiSchemaV4.MindStampItem.self,
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
            WeekyiiSchemaV5.self,
            WeekyiiSchemaV6.self,
            WeekyiiSchemaV7.self,
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
            .lightweight(fromVersion: WeekyiiSchemaV4.self, toVersion: WeekyiiSchemaV5.self),
            .lightweight(fromVersion: WeekyiiSchemaV5.self, toVersion: WeekyiiSchemaV6.self),
            .lightweight(fromVersion: WeekyiiSchemaV6.self, toVersion: WeekyiiSchemaV7.self),
        ]
    }

    private static func normalizeProjectTiles(in context: ModelContext) throws {
        let projects = try context.fetch(FetchDescriptor<WeekyiiSchemaV4.ProjectModel>())
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
            WeekyiiSchemaV4.WeekModel.self,
            WeekyiiSchemaV4.DayModel.self,
            WeekyiiSchemaV4.TaskItem.self,
            WeekyiiSchemaV4.TaskStep.self,
            WeekyiiSchemaV4.TaskAttachment.self,
            WeekyiiSchemaV4.ProjectModel.self,
            WeekyiiSchemaV4.MindStampItem.self,
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

        init(dayId: String, date: Date, dayOfWeek: String, status: DayStatus = .empty) {
            self.dayId = dayId
            self.date = date
            self.dayOfWeek = dayOfWeek
            self.status = status
        }
    }

    @Model
    final class TaskItem {
        @Attribute(.unique) var id: UUID = UUID()
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

        init(title: String, taskType: TaskType = .regular, order: Int, zone: TaskZone = .draft) {
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
        var id: UUID = UUID()
        @Attribute(.externalStorage) var data: Data?
        var fileName: String
        var fileType: String
        var createdAt: Date

        init(data: Data? = nil, fileName: String, fileType: String, createdAt: Date = Date()) {
            self.data = data
            self.fileName = fileName
            self.fileType = fileType
            self.createdAt = createdAt
        }
    }

    @Model
    final class ProjectModel {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String
        var projectDescription: String
        var color: String
        var icon: String
        var status: ProjectStatus
        var startDate: Date
        var endDate: Date
        var createdAt: Date
        var tileSizeRaw: String = ProjectTileSize.medium.rawValue
        var tileOrder: Int = 0
        @Relationship(deleteRule: .nullify, inverse: \TaskItem.project) var tasks: [TaskItem] = []

        init(
            name: String,
            projectDescription: String = "",
            color: String = "#C46A1A",
            icon: String = "folder.fill",
            status: ProjectStatus = .planning,
            startDate: Date,
            endDate: Date,
            createdAt: Date = Date()
        ) {
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
        @Attribute(.unique) var id: UUID = UUID()
        var text: String
        @Attribute(.externalStorage) var imageBlob: Data?
        var createdAt: Date

        init(text: String = "", imageBlob: Data? = nil, createdAt: Date = Date()) {
            self.text = text
            self.imageBlob = imageBlob
            self.createdAt = createdAt
        }
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
        @Relationship(deleteRule: .cascade) var steps: [TaskStep] = []
        @Relationship(deleteRule: .cascade) var attachments: [TaskAttachment] = []

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

enum WeekyiiSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(5, 0, 0) }

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
        var executionModeRaw: String = ExecutionMode.strict.rawValue
        var isDraftZoneUnlocked: Bool = false
        var week: WeekModel?
        @Relationship(deleteRule: .cascade, inverse: \TaskItem.day) var tasks: [TaskItem] = []
        var expiredCount: Int = 0

        init(dayId: String, date: Date, dayOfWeek: String, status: DayStatus = .empty) {
            self.dayId = dayId
            self.date = date
            self.dayOfWeek = dayOfWeek
            self.status = status
        }
    }

    @Model
    final class TaskItem {
        @Attribute(.unique) var id: UUID = UUID()
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

        init(title: String, taskType: TaskType = .regular, order: Int, zone: TaskZone = .draft) {
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
        var id: UUID = UUID()
        @Attribute(.externalStorage) var data: Data?
        var fileName: String
        var fileType: String
        var createdAt: Date

        init(data: Data? = nil, fileName: String, fileType: String, createdAt: Date = Date()) {
            self.data = data
            self.fileName = fileName
            self.fileType = fileType
            self.createdAt = createdAt
        }
    }

    @Model
    final class ProjectModel {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String
        var projectDescription: String
        var color: String
        var icon: String
        var status: ProjectStatus
        var startDate: Date
        var endDate: Date
        var createdAt: Date
        var tileSizeRaw: String = ProjectTileSize.medium.rawValue
        var tileOrder: Int = 0
        @Relationship(deleteRule: .nullify, inverse: \TaskItem.project) var tasks: [TaskItem] = []

        init(
            name: String,
            projectDescription: String = "",
            color: String = "#C46A1A",
            icon: String = "folder.fill",
            status: ProjectStatus = .planning,
            startDate: Date,
            endDate: Date,
            createdAt: Date = Date()
        ) {
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
        @Attribute(.unique) var id: UUID = UUID()
        var text: String
        @Attribute(.externalStorage) var imageBlob: Data?
        var createdAt: Date

        init(text: String = "", imageBlob: Data? = nil, createdAt: Date = Date()) {
            self.text = text
            self.imageBlob = imageBlob
            self.createdAt = createdAt
        }
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
        @Relationship(deleteRule: .cascade) var steps: [TaskStep] = []
        @Relationship(deleteRule: .cascade) var attachments: [TaskAttachment] = []

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

enum WeekyiiSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(6, 0, 0) }

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
            TaskTypeDefinition.self,
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
        var executionModeRaw: String = ExecutionMode.strict.rawValue
        var isDraftZoneUnlocked: Bool = false
        var week: WeekModel?
        @Relationship(deleteRule: .cascade, inverse: \TaskItem.day) var tasks: [TaskItem] = []
        var expiredCount: Int = 0

        init(dayId: String, date: Date, status: DayStatus = .empty) {
            self.dayId = dayId
            self.date = date
            self.dayOfWeek = date.dayOfWeekShort
            self.status = status
        }
    }

    @Model
    final class TaskItem {
        @Attribute(.unique) var id: UUID = UUID()
        var title: String
        var taskType: TaskType
        var taskTypeIdRaw: String = TaskType.regular.rawValue
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

        init(title: String, taskDescription: String = "", taskType: TaskType = .regular, order: Int, zone: TaskZone = .draft) {
            self.title = title
            self.taskDescription = taskDescription
            self.taskType = taskType
            self.taskTypeIdRaw = taskType.rawValue
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

        init(title: String, isCompleted: Bool = false, sortOrder: Int = 0) {
            self.title = title
            self.isCompleted = isCompleted
            self.sortOrder = sortOrder
            self.createdAt = Date()
        }
    }

    @Model
    final class TaskAttachment {
        var id: UUID = UUID()
        @Attribute(.externalStorage) var data: Data?
        var fileName: String
        var fileType: String
        var createdAt: Date

        init(data: Data?, fileName: String, fileType: String) {
            self.data = data
            self.fileName = fileName
            self.fileType = fileType
            self.createdAt = Date()
        }
    }

    @Model
    final class ProjectModel {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String
        var projectDescription: String
        var color: String
        var icon: String
        var status: ProjectStatus
        var startDate: Date
        var endDate: Date
        var createdAt: Date
        var tileSizeRaw: String = ProjectTileSize.medium.rawValue
        var tileOrder: Int = 0
        @Relationship(deleteRule: .nullify, inverse: \TaskItem.project) var tasks: [TaskItem] = []

        init(
            name: String,
            projectDescription: String = "",
            color: String = "#C46A1A",
            icon: String = "folder.fill",
            status: ProjectStatus = .planning,
            startDate: Date,
            endDate: Date
        ) {
            self.name = name
            self.projectDescription = projectDescription
            self.color = color
            self.icon = icon
            self.status = status
            self.startDate = startDate
            self.endDate = endDate
            self.createdAt = Date()
        }
    }

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
    }

    @Model
    final class SuspendedTaskItem {
        @Attribute(.unique) var id: UUID = UUID()
        var title: String
        var taskDescription: String
        var taskType: TaskType
        var taskTypeIdRaw: String = TaskType.regular.rawValue
        var createdAt: Date
        var decisionDeadline: Date
        var preferredCountdownDays: Int
        var snoozeCount: Int
        var statusRaw: String
        @Relationship(deleteRule: .cascade) var steps: [TaskStep] = []
        @Relationship(deleteRule: .cascade) var attachments: [TaskAttachment] = []

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
            self.taskTypeIdRaw = taskType.rawValue
            self.createdAt = createdAt
            self.decisionDeadline = decisionDeadline
            self.preferredCountdownDays = preferredCountdownDays
            self.snoozeCount = snoozeCount
            self.statusRaw = statusRaw
        }
    }

    @Model
    final class TaskTypeDefinition {
        @Attribute(.unique) var idRaw: String
        var name: String
        var iconName: String
        var colorHex: String
        var baseKindRaw: String
        var sortOrder: Int
        var isBuiltIn: Bool
        var isArchived: Bool

        init(
            idRaw: String = UUID().uuidString,
            name: String,
            iconName: String,
            colorHex: String,
            baseKindRaw: String,
            sortOrder: Int,
            isBuiltIn: Bool = false,
            isArchived: Bool = false
        ) {
            self.idRaw = idRaw
            self.name = name
            self.iconName = iconName
            self.colorHex = colorHex
            self.baseKindRaw = baseKindRaw
            self.sortOrder = sortOrder
            self.isBuiltIn = isBuiltIn
            self.isArchived = isArchived
        }
    }
}

enum WeekyiiSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(7, 0, 0) }

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
            TaskTypeDefinition.self,
        ]
    }
}
