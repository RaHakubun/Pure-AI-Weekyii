import XCTest
import SwiftData
import Photos
import SwiftUI
@testable import Weekyii

final class ModelTests: XCTestCase {
    private static var retainedUserSettings: [UserSettings] = []

    override func tearDown() {
        // `UserSettings.save()` pushes its reminder rhythm into the shared
        // `NotificationService` singleton. Without this reset, a settings test
        // that changes the morning time or disables suspended reminders would
        // leak that rhythm into `NotificationServiceTests`, which relies on the
        // historical defaults when it does not pass an explicit configuration.
        NotificationService.shared.configuration = .default
        super.tearDown()
    }

    func test_cloudSyncSchema_isCloudKitCompatible() {
        let schema = WeekyiiPersistence.currentSchema

        XCTAssertEqual(schema.version, Schema.Version(7, 0, 0))

        let entitiesWithUniqueConstraints = schema.entities.compactMap { entity in
            entity.uniquenessConstraints.isEmpty ? nil : entity.name
        }
        XCTAssertTrue(
            entitiesWithUniqueConstraints.isEmpty,
            "CloudKit does not support unique constraints: \(entitiesWithUniqueConstraints)"
        )

        let requiredRelationships = schema.entities.flatMap { entity in
            entity.relationships.compactMap { relationship in
                relationship.isOptional ? nil : "\(entity.name).\(relationship.name)"
            }
        }
        XCTAssertTrue(
            requiredRelationships.isEmpty,
            "CloudKit requires optional relationships: \(requiredRelationships)"
        )

        let relationshipsWithoutInverse = schema.entities.flatMap { entity in
            entity.relationships.compactMap { relationship in
                relationship.inverseName == nil ? "\(entity.name).\(relationship.name)" : nil
            }
        }
        XCTAssertTrue(
            relationshipsWithoutInverse.isEmpty,
            "CloudKit requires relationship inverses: \(relationshipsWithoutInverse)"
        )

        let deniedRelationships = schema.entities.flatMap { entity in
            entity.relationships.compactMap { relationship in
                relationship.deleteRule == .deny ? "\(entity.name).\(relationship.name)" : nil
            }
        }
        XCTAssertTrue(
            deniedRelationships.isEmpty,
            "CloudKit does not support deny delete rules: \(deniedRelationships)"
        )
    }

    func test_persistenceMode_usesPrivateCloudForProductionOnly() {
        XCTAssertEqual(
            WeekyiiPersistence.StoreMode.production.cloudKitContainerIdentifier,
            "iCloud.com.fluentdesign.Weekyii"
        )
        XCTAssertNil(WeekyiiPersistence.StoreMode.localOnly.cloudKitContainerIdentifier)
        XCTAssertNil(WeekyiiPersistence.StoreMode.inMemory.cloudKitContainerIdentifier)
        XCTAssertEqual(
            WeekyiiPersistence.launchStoreMode(environment: [:]),
            .production
        )
        XCTAssertEqual(
            WeekyiiPersistence.launchStoreMode(environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"]),
            .localOnly
        )
    }

    func test_cloudKitSchemaInitialization_requiresExplicitDevelopmentLaunchFlag() {
        XCTAssertFalse(WeekyiiPersistence.shouldInitializeCloudKitSchema(arguments: []))
        XCTAssertFalse(WeekyiiPersistence.shouldInitializeCloudKitSchema(arguments: ["-uiTesting"]))
        XCTAssertTrue(
            WeekyiiPersistence.shouldInitializeCloudKitSchema(
                arguments: ["-initializeCloudKitSchema"]
            )
        )
    }

    func test_cloudSyncState_explainsAutomaticSyncAndAccountProblems() {
        XCTAssertFalse(CloudSyncState.available.detail.isEmpty)
        XCTAssertFalse(CloudSyncState.syncing.detail.isEmpty)
        XCTAssertTrue(CloudSyncState.unavailable(.noAccount).detail.contains("iCloud"))
        XCTAssertTrue(CloudSyncState.failed("网络不可用").detail.contains("网络不可用"))
    }

    @MainActor
    func test_cloudSyncDisplayStatePrioritizesCurrentAccountAvailability() {
        XCTAssertEqual(
            CloudSyncState.resolve(
                account: .unavailable(.noAccount),
                event: .synced(Date())
            ),
            .unavailable(.noAccount)
        )
        XCTAssertEqual(
            CloudSyncState.resolve(
                account: .available,
                event: .syncing
            ),
            .syncing
        )
    }

    @MainActor
    func test_cloudSyncMonitorDebouncesBurstImports() async throws {
        let monitor = CloudSyncMonitor(importDebounceDuration: .milliseconds(20))

        monitor.scheduleImportedChanges()
        monitor.scheduleImportedChanges()
        monitor.scheduleImportedChanges()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(monitor.importRevision, 1)
    }

    @MainActor
    func test_weekDataStoreUpsertsWeekAndDayByDeterministicKeys() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let date = makeDate(2026, 9, 14)
        let store = WeekDataStore(modelContext: context)

        let first = try store.resolveDay(on: date, weekStatus: .present)
        let second = try store.resolveDay(on: date, weekStatus: .present)
        try context.save()

        let weeks = try context.fetch(FetchDescriptor<WeekModel>())
            .filter { $0.weekId == date.weekId }
        let days = try context.fetch(FetchDescriptor<DayModel>())
            .filter { $0.dayId == date.dayId }
        XCTAssertTrue(first.createdWeek)
        XCTAssertFalse(second.createdWeek)
        XCTAssertTrue(first.day === second.day)
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(days.count, 1)
    }

    func test_cloudSyncMonitor_startsOnlyForNormalAppLaunches() {
        XCTAssertTrue(CloudSyncMonitor.shouldStart(isRunningTests: false, isUITesting: false))
        XCTAssertFalse(CloudSyncMonitor.shouldStart(isRunningTests: true, isUITesting: false))
        XCTAssertFalse(CloudSyncMonitor.shouldStart(isRunningTests: false, isUITesting: true))
    }

    func test_backupSnapshotPreservesAndRestoresExternalStorageFiles() throws {
        let storeURL = try makeTemporaryStoreURL()
        let fileManager = FileManager.default
        let supportFolder = storeURL.deletingLastPathComponent()
            .appendingPathComponent(".Weekyii_SUPPORT", isDirectory: true)
        let externalDataFolder = supportFolder
            .appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
        let externalFile = externalDataFolder.appendingPathComponent("attachment.bin")

        try Data("database".utf8).write(to: storeURL)
        try fileManager.createDirectory(at: externalDataFolder, withIntermediateDirectories: true)
        try Data(repeating: 0xA5, count: 1024 * 1024).write(to: externalFile)

        let snapshot = try XCTUnwrap(
            BackupRecoveryService.createSnapshot(storeURL: storeURL, reason: "external-storage-test")
        )
        let snapshotFolder = storeURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(snapshot.folderName, isDirectory: true)
        let snapshottedExternalFile = snapshotFolder
            .appendingPathComponent(".Weekyii_SUPPORT/_EXTERNAL_DATA/attachment.bin")

        XCTAssertTrue(fileManager.fileExists(atPath: snapshottedExternalFile.path))
        XCTAssertTrue(BackupRecoveryService.verifySnapshot(folder: snapshotFolder))

        try Data("damaged".utf8).write(to: storeURL)
        try fileManager.removeItem(at: supportFolder)
        try BackupRecoveryService.restoreSnapshot(named: snapshot.folderName, to: storeURL)

        XCTAssertEqual(try Data(contentsOf: storeURL), Data("database".utf8))
        XCTAssertEqual(
            try Data(contentsOf: externalFile),
            Data(repeating: 0xA5, count: 1024 * 1024)
        )
    }

    func test_backupFolderIsExcludedFromSystemBackup() throws {
        let storeURL = try makeTemporaryStoreURL()
        try Data("database".utf8).write(to: storeURL)

        _ = try BackupRecoveryService.createSnapshot(storeURL: storeURL, reason: "exclusion-test")

        let backupFolder = storeURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        let values = try backupFolder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func test_preflightSnapshotIsCreatedOnlyOncePerSchemaVersion() throws {
        let storeURL = try makeTemporaryStoreURL()
        try Data("original".utf8).write(to: storeURL)

        WeekyiiPersistence.backupPersistentStoreIfExists(storeURL: storeURL)
        try Data("newer data".utf8).write(to: storeURL)
        WeekyiiPersistence.backupPersistentStoreIfExists(storeURL: storeURL)

        let snapshots = BackupRecoveryService.listSnapshots(storeURL: storeURL)
            .filter { $0.folderName.contains("preflight-v7") }
        XCTAssertEqual(snapshots.count, 1)
    }

    func test_preflightLookupVerifiesOnlyMatchingSnapshots() throws {
        let storeURL = try makeTemporaryStoreURL()
        let backupFolder = storeURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        let unrelated = backupFolder.appendingPathComponent(
            "snapshot-2026-09-13T10-00-00Z-manual-AAAAAAAA",
            isDirectory: true
        )
        let matching = backupFolder.appendingPathComponent(
            "snapshot-2026-09-13T11-00-00Z-preflight-v7-BBBBBBBB",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: matching, withIntermediateDirectories: true)

        var verifiedFolders: [String] = []
        let found = BackupRecoveryService.hasValidSnapshot(
            storeURL: storeURL,
            reason: "preflight-v7"
        ) { folder in
            verifiedFolders.append(folder.lastPathComponent)
            return true
        }

        XCTAssertTrue(found)
        XCTAssertEqual(verifiedFolders, [matching.lastPathComponent])
    }

    func test_restoreLatestValidSnapshotSkipsNewerCorruptSnapshot() throws {
        let storeURL = try makeTemporaryStoreURL()
        try Data("recover me".utf8).write(to: storeURL)
        let valid = try XCTUnwrap(
            BackupRecoveryService.createSnapshot(storeURL: storeURL, reason: "valid")
        )
        let validFolder = storeURL.deletingLastPathComponent()
            .appendingPathComponent("Backups/\(valid.folderName)", isDirectory: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -60)],
            ofItemAtPath: validFolder.path
        )

        try Data("newer".utf8).write(to: storeURL)
        let corrupt = try XCTUnwrap(
            BackupRecoveryService.createSnapshot(storeURL: storeURL, reason: "corrupt")
        )
        let corruptFolder = storeURL.deletingLastPathComponent()
            .appendingPathComponent("Backups/\(corrupt.folderName)", isDirectory: true)
        try Data("tampered".utf8).write(
            to: corruptFolder.appendingPathComponent(storeURL.lastPathComponent)
        )
        try Data("broken current store".utf8).write(to: storeURL)

        let restored = try BackupRecoveryService.restoreLatestValidSnapshot(to: storeURL)

        XCTAssertEqual(restored?.folderName, valid.folderName)
        XCTAssertEqual(try Data(contentsOf: storeURL), Data("recover me".utf8))
    }

    @MainActor
    func test_bootstrapRepairsDuplicateCloudWeeksBeforeConsistencyValidation() throws {
        let storeURL = try makeTemporaryStoreURL()
        let today = makeDate(2026, 9, 13)

        do {
            let container = try WeekyiiPersistence.makeModelContainer(
                storeURL: storeURL,
                storeMode: .localOnly
            )
            let context = container.mainContext
            let firstWeek = WeekCalculator().makeWeek(for: today, status: .present)
            let secondWeek = WeekCalculator().makeWeek(for: today, status: .present)
            firstWeek.days.first { $0.dayId == today.dayId }?.tasks.append(
                TaskItem(title: "来自 iPhone", order: 1)
            )
            secondWeek.days.first { $0.dayId == today.dayId }?.tasks.append(
                TaskItem(title: "来自 iPad", order: 1)
            )
            context.insert(firstWeek)
            context.insert(secondWeek)
            try context.save()
        }

        let launchState = WeekyiiPersistence.bootstrapPersistentContainer(
            environment: [:],
            storeURL: storeURL,
            storeMode: .localOnly,
            referenceDate: today
        )

        guard case .ready(let container) = launchState else {
            XCTFail("A recoverable CloudKit merge must not block app launch")
            return
        }
        let weeks = try container.mainContext.fetch(FetchDescriptor<WeekModel>())
            .filter { $0.weekId == today.weekId }
        let days = try container.mainContext.fetch(FetchDescriptor<DayModel>())
            .filter { $0.dayId == today.dayId }
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(Set(days[0].tasks.map(\.title)), ["来自 iPhone", "来自 iPad"])
    }

    @MainActor
    func test_bootstrapNormalizesCompetingPresentWeeksFromDifferentDevices() throws {
        let storeURL = try makeTemporaryStoreURL()
        let today = makeDate(2026, 9, 13)
        let previousWeekDate = Calendar(identifier: .iso8601).date(
            byAdding: .day,
            value: -7,
            to: today
        )!

        do {
            let container = try WeekyiiPersistence.makeModelContainer(
                storeURL: storeURL,
                storeMode: .localOnly
            )
            let context = container.mainContext
            context.insert(WeekCalculator().makeWeek(for: previousWeekDate, status: .present))
            context.insert(WeekCalculator().makeWeek(for: today, status: .present))
            try context.save()
        }

        let launchState = WeekyiiPersistence.bootstrapPersistentContainer(
            environment: [:],
            storeURL: storeURL,
            storeMode: .localOnly,
            referenceDate: today
        )

        guard case .ready(let container) = launchState else {
            XCTFail("Competing present-week updates must be repaired during launch")
            return
        }
        let weeks = try container.mainContext.fetch(FetchDescriptor<WeekModel>())
        let presentWeeks = weeks.filter { $0.status == .present }
        XCTAssertEqual(presentWeeks.map(\.weekId), [today.weekId])
        XCTAssertEqual(weeks.first { $0.weekId == previousWeekDate.weekId }?.status, .past)
    }

    @MainActor
    func test_publishedV6FixtureMigratesToV7() throws {
        let storeURL = try makeTemporaryStoreURL()
        do {
            let legacySchema = Schema(versionedSchema: WeekyiiSchemaV6.self)
            let legacyConfiguration = ModelConfiguration(
                "Weekyii",
                schema: legacySchema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)
            let context = legacyContainer.mainContext
            let week = WeekyiiSchemaV6.WeekModel(
                weekId: "2026-W37",
                startDate: Date(timeIntervalSince1970: 1_789_000_000),
                endDate: Date(timeIntervalSince1970: 1_789_518_400),
                status: .present
            )
            let day = WeekyiiSchemaV6.DayModel(
                dayId: "2026-09-07",
                date: Date(timeIntervalSince1970: 1_789_000_000),
                status: .execute
            )
            let project = WeekyiiSchemaV6.ProjectModel(
                name: "Cloud migration",
                startDate: Date(timeIntervalSince1970: 1_789_000_000),
                endDate: Date(timeIntervalSince1970: 1_789_518_400)
            )
            let task = WeekyiiSchemaV6.TaskItem(
                title: "Keep local data",
                taskDescription: "V6 payload",
                taskType: .ddl,
                order: 1,
                zone: .focus
            )
            task.steps.append(WeekyiiSchemaV6.TaskStep(title: "Preserve step", isCompleted: true, sortOrder: 1))
            task.attachments.append(WeekyiiSchemaV6.TaskAttachment(data: Data([1, 2, 3]), fileName: "proof.bin", fileType: "application/octet-stream"))
            task.project = project
            day.tasks.append(task)
            week.days.append(day)
            context.insert(week)
            context.insert(project)
            context.insert(WeekyiiSchemaV6.MindStampItem(text: "V6 stamp", imageBlob: Data([4, 5, 6])))
            context.insert(WeekyiiSchemaV6.SuspendedTaskItem(title: "V6 suspended", decisionDeadline: Date(timeIntervalSince1970: 1_789_600_000), preferredCountdownDays: 3))
            context.insert(WeekyiiSchemaV6.TaskTypeDefinition(idRaw: "custom-v6", name: "V6 Type", iconName: "cloud", colorHex: "#336699", baseKindRaw: TaskType.regular.rawValue, sortOrder: 10))
            try context.save()
        }

        let container = try WeekyiiPersistence.makeModelContainer(storeURL: storeURL)
        let context = container.mainContext
        let weeks = try context.fetch(FetchDescriptor<WeekModel>())
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let projects = try context.fetch(FetchDescriptor<ProjectModel>())
        let stamps = try context.fetch(FetchDescriptor<MindStampItem>())
        let suspended = try context.fetch(FetchDescriptor<SuspendedTaskItem>())
        let taskTypes = try context.fetch(FetchDescriptor<TaskTypeDefinition>())

        XCTAssertEqual(weeks.map(\.weekId), ["2026-W37"])
        XCTAssertEqual(tasks.map(\.title), ["Keep local data"])
        XCTAssertEqual(tasks.first?.steps.map(\.title), ["Preserve step"])
        XCTAssertEqual(tasks.first?.attachments.first?.data, Data([1, 2, 3]))
        XCTAssertEqual(projects.map(\.name), ["Cloud migration"])
        XCTAssertEqual(stamps.map(\.text), ["V6 stamp"])
        XCTAssertEqual(suspended.map(\.title), ["V6 suspended"])
        XCTAssertTrue(taskTypes.contains { $0.idRaw == "custom-v6" })
    }

    @MainActor
    func test_userSettings_defaultsToStrictExecutionModeAndPersistsSelection() {
        let suiteName = "ModelTests.ExecutionMode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)
        XCTAssertEqual(settings.defaultExecutionMode, .strict)

        settings.defaultExecutionMode = .flexible
        XCTAssertEqual(defaults.string(forKey: "defaultExecutionMode"), ExecutionMode.flexible.rawValue)
    }

    @MainActor
    func test_userSettings_defaultTaskTypeIdPersistsSelection() {
        let suiteName = "ModelTests.TaskTypeId.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)
        XCTAssertEqual(settings.defaultTaskTypeIdRaw, TaskType.regular.rawValue)

        settings.defaultTaskTypeIdRaw = "custom-focus"
        XCTAssertEqual(defaults.string(forKey: "defaultTaskTypeId"), "custom-focus")
    }

    @MainActor
    func test_userSettings_projectDefaultsPersistWithoutSchemaChanges() {
        let suiteName = "ModelTests.ProjectDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)
        XCTAssertEqual(settings.defaultProjectDurationDays, 7)
        XCTAssertEqual(settings.defaultProjectTileSize.rawValue, ProjectTileSize.medium.rawValue)

        settings.defaultProjectDurationDays = 21
        settings.defaultProjectTileSize = .wide

        XCTAssertEqual(defaults.integer(forKey: "defaultProjectDurationDays"), 21)
        XCTAssertEqual(defaults.string(forKey: "defaultProjectTileSize"), ProjectTileSize.wide.rawValue)
    }

    @MainActor
    func test_userSettings_reminderRhythmDefaultsAndPersistence() {
        let suiteName = "ModelTests.ReminderRhythm.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)

        XCTAssertEqual(settings.morningReminderHour, 9)
        XCTAssertEqual(settings.morningReminderMinute, 0)
        XCTAssertTrue(settings.suspendedReminderEnabled)
        XCTAssertEqual(settings.suspendedReminderIntensity, .full)
        XCTAssertEqual(settings.suspendedReminderAdvanceDays, 3)
        XCTAssertEqual(settings.suspendedReminderEveningHour, 19)
        XCTAssertEqual(settings.suspendedReminderEveningMinute, 30)

        settings.morningReminderHour = 7
        settings.suspendedReminderIntensity = .minimal
        settings.suspendedReminderEveningHour = 21

        XCTAssertEqual(defaults.integer(forKey: "morningReminderHour"), 7)
        XCTAssertEqual(defaults.string(forKey: "suspendedReminderIntensity"), SuspendedReminderIntensity.minimal.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "suspendedReminderEveningHour"), 21)
    }

    @MainActor
    func test_userSettings_notificationConfigurationMirrorsRhythmAndClampsAdvanceDays() {
        let suiteName = "ModelTests.NotificationConfig.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)

        settings.morningReminderHour = 6
        settings.morningReminderMinute = 30
        settings.suspendedReminderIntensity = .standard
        settings.suspendedReminderAdvanceDays = 99
        settings.suspendedReminderEnabled = false
        settings.suspendedExpiryPolicy = .keepOverdue

        let configuration = settings.notificationConfiguration
        XCTAssertEqual(configuration.morningHour, 6)
        XCTAssertEqual(configuration.morningMinute, 30)
        XCTAssertEqual(configuration.suspendedReminderIntensity, .standard)
        XCTAssertEqual(configuration.suspendedAdvanceDays, 14)
        XCTAssertFalse(configuration.suspendedReminderEnabled)
        // The due-day reminder body depends on this, so it must be mirrored.
        XCTAssertEqual(configuration.suspendedExpiryPolicy, .keepOverdue)
    }

    @MainActor
    func test_userSettings_motionLanguageAndDataDefaults() {
        let suiteName = "ModelTests.MotionLanguage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)

        XCTAssertFalse(settings.reduceMotionEnabled)
        XCTAssertTrue(settings.moduleTileRotationEnabled)
        XCTAssertTrue(settings.startRitualEnabled)
        XCTAssertEqual(settings.languageOverride, .system)
        XCTAssertEqual(settings.recoveryPointRetentionCount, 8)
        XCTAssertEqual(settings.effectiveRecoveryPointRetentionCount, 8)

        settings.reduceMotionEnabled = true
        settings.moduleTileRotationEnabled = false
        settings.startRitualEnabled = false
        settings.setLanguageOverride(.simplifiedChinese)

        XCTAssertTrue(defaults.bool(forKey: "reduceMotionEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "moduleTileRotationEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "startRitualEnabled"))
        XCTAssertEqual(defaults.string(forKey: "languageOverride"), LanguageOverride.simplifiedChinese.rawValue)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])
    }

    @MainActor
    func test_userSettings_projectDefaultsAreClampedAndPersisted() {
        let suiteName = "ModelTests.ProjectBoardDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)

        XCTAssertEqual(settings.defaultProjectColorHex, "#C46A1A")
        XCTAssertEqual(settings.defaultProjectIconName, "folder.fill")
        XCTAssertEqual(settings.suspendedDefaultCountdownDays, 10)
        XCTAssertEqual(settings.effectiveBoardColumnCount, 4)

        settings.boardColumnCount = 99
        XCTAssertEqual(settings.effectiveBoardColumnCount, 6)
        settings.boardColumnCount = 1
        XCTAssertEqual(settings.effectiveBoardColumnCount, 2)

        settings.recoveryPointRetentionCount = 0
        XCTAssertEqual(settings.effectiveRecoveryPointRetentionCount, 1)
        settings.recoveryPointRetentionCount = 999
        XCTAssertEqual(settings.effectiveRecoveryPointRetentionCount, 50)

        settings.defaultProjectColorHex = "#3FA67A"
        settings.defaultProjectIconName = "star.fill"
        settings.suspendedDefaultCountdownDays = 21

        XCTAssertEqual(defaults.string(forKey: "defaultProjectColor"), "#3FA67A")
        XCTAssertEqual(defaults.string(forKey: "defaultProjectIcon"), "star.fill")
        XCTAssertEqual(defaults.integer(forKey: "suspendedDefaultCountdownDays"), 21)
        XCTAssertEqual(defaults.integer(forKey: "boardColumnCount"), 1)
        XCTAssertEqual(defaults.integer(forKey: "recoveryPointRetentionCount"), 999)
    }

    @MainActor
    func test_userSettings_suspendedExpiryPolicyDefaultsToAutoDeleteAndPersists() {
        let suiteName = "ModelTests.SuspendedExpiry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)

        // The historical behaviour must stay the default so existing installs
        // do not silently start retaining tasks they used to lose.
        XCTAssertEqual(settings.suspendedExpiryPolicy, .autoDelete)
        XCTAssertNil(defaults.string(forKey: "suspendedExpiryPolicy"))

        settings.suspendedExpiryPolicy = .keepOverdue

        XCTAssertEqual(defaults.string(forKey: "suspendedExpiryPolicy"), SuspendedExpiryPolicy.keepOverdue.rawValue)
        XCTAssertEqual(settings.suspendedExpiryPolicy, .keepOverdue)

        // An unknown raw value degrades to the safe historical default.
        defaults.set("something-else", forKey: "suspendedExpiryPolicy")
        let reloaded = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(reloaded)
        XCTAssertEqual(reloaded.suspendedExpiryPolicy, .autoDelete)
    }

    @MainActor
    func test_taskTypeCatalogSeedsBuiltInDefinitions() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext

        try TaskTypeCatalog.seedBuiltInTypesIfNeeded(in: context)
        let definitions = try context.fetch(FetchDescriptor<TaskTypeDefinition>())
            .sorted { $0.sortOrder < $1.sortOrder }

        XCTAssertEqual(definitions.map(\.idRaw), ["regular", "ddl", "leisure"])
        XCTAssertEqual(definitions.map(\.baseKind), [.regular, .ddl, .leisure])
        XCTAssertTrue(definitions.allSatisfy(\.isBuiltIn))
    }

    @MainActor
    func test_taskTypeCatalogResolvesCustomDefinitionAndFallback() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try TaskTypeCatalog.seedBuiltInTypesIfNeeded(in: context)
        let custom = TaskTypeDefinition(
            idRaw: "custom-writing",
            name: "写作",
            iconName: "pencil.line",
            colorHex: "#4D9DE0",
            baseKind: .ddl,
            sortOrder: 10,
            isBuiltIn: false
        )
        context.insert(custom)
        try context.save()

        let catalog = try TaskTypeCatalog.load(in: context)

        XCTAssertEqual(catalog.definition(for: "custom-writing").name, "写作")
        XCTAssertEqual(catalog.baseKind(for: "custom-writing"), .ddl)
        XCTAssertEqual(catalog.definition(for: "missing").idRaw, TaskType.regular.rawValue)
    }

    @MainActor
    func test_taskMutationStoresCustomTaskTypeIdAndBaseKind() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try TaskTypeCatalog.seedBuiltInTypesIfNeeded(in: context)

        let day = DayModel(dayId: "2026-06-28", date: Date(timeIntervalSince1970: 1), status: .empty)
        context.insert(day)
        let service = TaskMutationService(modelContext: context)
        let payload = TaskDraftPayload(
            title: "Write launch note",
            description: "",
            type: .ddl,
            taskTypeIdRaw: "custom-writing"
        )

        let task = try service.createTask(in: day, payload: payload, zone: .draft, project: nil)

        XCTAssertEqual(task.taskTypeIdRaw, "custom-writing")
        XCTAssertEqual(task.taskType, .ddl)

        let customDefinition = TaskTypeDefinition(
            idRaw: "custom-writing",
            name: "写作",
            iconName: "pencil.line",
            colorHex: "#AA5500",
            baseKind: .ddl,
            sortOrder: 10
        )
        let presentation = TaskTypePresentationCatalog(definitions: [customDefinition])
            .resolve(idRaw: task.taskTypeIdRaw, fallback: task.taskType)

        XCTAssertEqual(presentation.name, "写作")
        XCTAssertEqual(presentation.iconName, "pencil.line")
        XCTAssertEqual(presentation.baseKind, .ddl)
    }

    @MainActor
    func test_persistentContainer_migratesV4DayToStrictLockedV5Defaults() throws {
        let storeURL = try makeTemporaryStoreURL()
        let legacySchema = Schema(versionedSchema: WeekyiiSchemaV4.self)
        let legacyConfig = ModelConfiguration(
            "Weekyii",
            schema: legacySchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfig)
        let legacyContext = legacyContainer.mainContext
        let date = Date().startOfDay
        let week = WeekyiiSchemaV4.WeekModel(
            weekId: date.weekId,
            startDate: date.startOfWeek,
            endDate: date.startOfWeek.addingDays(6),
            status: .present
        )
        let day = WeekyiiSchemaV4.DayModel(
            dayId: date.dayId,
            date: date,
            dayOfWeek: date.dayOfWeekShort,
            status: .execute
        )
        week.days.append(day)
        legacyContext.insert(week)
        try legacyContext.save()

        let migratedContainer = try WeekyiiPersistence.makeModelContainer(storeURL: storeURL)
        let days = try migratedContainer.mainContext.fetch(FetchDescriptor<DayModel>())

        XCTAssertFalse(days.isEmpty)
        XCTAssertTrue(days.allSatisfy { $0.executionMode == .strict })
        XCTAssertTrue(days.allSatisfy { !$0.isDraftZoneUnlocked })
    }

    @MainActor
    func test_persistentContainer_migratesV2StoreThroughFrozenHistoricalSchemas() throws {
        let storeURL = try makeTemporaryStoreURL()
        let legacySchema = Schema(versionedSchema: WeekyiiSchemaV2.self)
        let legacyConfig = ModelConfiguration(
            "Weekyii",
            schema: legacySchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfig)
        let project = WeekyiiSchemaV4.ProjectModel(
            name: "V2 Project",
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 200)
        )
        legacyContainer.mainContext.insert(project)
        try legacyContainer.mainContext.save()

        let migratedContainer = try WeekyiiPersistence.makeModelContainer(storeURL: storeURL)
        let projects = try migratedContainer.mainContext.fetch(FetchDescriptor<ProjectModel>())

        XCTAssertEqual(projects.map(\.name), ["V2 Project"])
    }

    @MainActor
    func test_persistentContainer_migratesV3SuspendedTaskStoreToV5() throws {
        let storeURL = try makeTemporaryStoreURL()
        let legacySchema = Schema(versionedSchema: WeekyiiSchemaV3.self)
        let legacyConfig = ModelConfiguration(
            "Weekyii",
            schema: legacySchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfig)
        let suspended = WeekyiiSchemaV3.SuspendedTaskItem(
            title: "V3 Suspended",
            decisionDeadline: Date(timeIntervalSince1970: 300),
            preferredCountdownDays: 3
        )
        legacyContainer.mainContext.insert(suspended)
        try legacyContainer.mainContext.save()

        let migratedContainer = try WeekyiiPersistence.makeModelContainer(storeURL: storeURL)
        let tasks = try migratedContainer.mainContext.fetch(FetchDescriptor<SuspendedTaskItem>())

        XCTAssertEqual(tasks.map(\.title), ["V3 Suspended"])
        XCTAssertTrue(tasks.allSatisfy { $0.steps.isEmpty && $0.attachments.isEmpty })
    }

    @MainActor
    func test_persistentContainer_migratesLegacyProjectTilesStore() throws {
        let storeURL = try makeTemporaryStoreURL()
        let legacySchema = Schema(versionedSchema: WeekyiiSchemaV1.self)
        let legacyConfig = ModelConfiguration("Weekyii", schema: legacySchema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfig)
        let legacyContext = legacyContainer.mainContext

        let older = WeekyiiSchemaV1.ProjectModel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Older",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newer = WeekyiiSchemaV1.ProjectModel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Newer",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        legacyContext.insert(older)
        legacyContext.insert(newer)
        try legacyContext.save()

        let migratedContainer = try WeekyiiPersistence.makeModelContainer(storeURL: storeURL)
        let descriptor = FetchDescriptor<ProjectModel>(sortBy: [SortDescriptor(\ProjectModel.tileOrder)])
        let projects: [ProjectModel] = try migratedContainer.mainContext.fetch(descriptor)

        XCTAssertEqual(projects.map(\.name), ["Newer", "Older"])
        XCTAssertEqual(projects.map(\.tileSize), [ProjectTileSize.medium, ProjectTileSize.medium])
        XCTAssertEqual(projects.map(\.tileOrder), [0, 1])
    }

    func test_projectTileSize_defaultIsMedium() {
        let project = ProjectModel(name: "P", startDate: Date(), endDate: Date())
        XCTAssertEqual(project.tileSize, .medium)
    }

    func test_projectTileOrder_defaultIsZero() {
        let project = ProjectModel(name: "P", startDate: Date(), endDate: Date())
        XCTAssertEqual(project.tileOrder, 0)
    }

    func test_projectTileSize_cycleOrder() {
        XCTAssertEqual(ProjectTileSize.mini.next, .small)
        XCTAssertEqual(ProjectTileSize.small.next, .medium)
        XCTAssertEqual(ProjectTileSize.medium.next, .wide)
        XCTAssertEqual(ProjectTileSize.wide.next, .mini)
    }

    func test_projectTileSize_mapsLegacyStoredValue() {
        XCTAssertEqual(ProjectTileSize(storedValue: "small"), .small)
        XCTAssertEqual(ProjectTileSize(storedValue: "wide"), .wide)
        XCTAssertEqual(ProjectTileSize(storedValue: "large"), .wide)
    }

    func test_suspendedModulePalette_usesPrimaryThemeTint() {
        for theme in WeekTheme.allCases {
            let palette = theme.suspendedModulePalette
            XCTAssertEqual(palette.tintHex, theme.primaryThemeHex)
        }
    }

    func test_suspendedModulePalette_usesPrimaryThemeGradientLightStop() {
        for theme in WeekTheme.allCases {
            let palette = theme.suspendedModulePalette
            XCTAssertEqual(palette.tintLightHex, theme.primaryThemeLightHex)
        }
    }

    func test_weekThemeIncludesLotrPremiumCase() {
        XCTAssertTrue(WeekTheme.allCases.contains(.lotr))
        XCTAssertTrue(WeekTheme.lotr.isPremiumTheme)
    }

    func test_lotrThemeRequiresUnlockBeforeUse() {
        XCTAssertEqual(
            WeekTheme.resolvedTheme(rawValue: WeekTheme.lotr.rawValue, premiumThemeUnlocked: false),
            .amber
        )
        XCTAssertEqual(
            WeekTheme.resolvedTheme(rawValue: WeekTheme.lotr.rawValue, premiumThemeUnlocked: true),
            .lotr
        )
    }

    func test_projectTilePresentation_miniEditingStaysCompact() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            nextTaskTitle: "下一步"
        )

        let presentation = ProjectTilePresentation(
            snapshot: snapshot,
            size: .mini,
            isEditing: true,
            liveTick: 0
        )

        XCTAssertEqual(presentation.titleLineLimit, 1)
        XCTAssertFalse(presentation.showsStatusChip)
        XCTAssertFalse(presentation.showsNextTaskDate)
        XCTAssertFalse(presentation.showsTitle)
        XCTAssertEqual(presentation.secondaryContent, .none)
        XCTAssertGreaterThan(presentation.contentInsets.trailing, presentation.contentInsets.leading)
    }

    func test_projectTilePresentation_miniPrioritizesRemainingCountStory() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            nextTaskTitle: "下一步"
        )

        let presentation = ProjectTilePresentation(snapshot: snapshot, size: .mini, isEditing: false, liveTick: 0)

        XCTAssertEqual(presentation.livePanel, .metrics)
    }

    func test_projectTilePresentation_smallPrioritizesProgressStoryWhenTasksExist() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            nextTaskTitle: "下一步"
        )

        let presentation = ProjectTilePresentation(snapshot: snapshot, size: .small, isEditing: false, liveTick: 0)

        XCTAssertEqual(presentation.livePanel, .progress)
    }

    func test_projectTilePresentation_smallEditingRemovesSecondaryStrip() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
            nextTaskTitle: "下一步"
        )

        let browse = ProjectTilePresentation(snapshot: snapshot, size: .small, isEditing: false, liveTick: 0)
        let edit = ProjectTilePresentation(snapshot: snapshot, size: .small, isEditing: true, liveTick: 0)

        XCTAssertEqual(browse.secondaryContent, .microStatsStrip)
        XCTAssertEqual(edit.secondaryContent, .none)
        XCTAssertTrue(edit.showsTitle)
    }

    func test_projectTilePresentation_wideRemainsStableAcrossLiveTicks() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            nextTaskTitle: "明天交付"
        )

        let first = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 0)
        let second = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 1)

        XCTAssertEqual(first.livePanel, second.livePanel)
        XCTAssertTrue(first.showsStatusChip)
        XCTAssertEqual(first.livePanel, .nextTask)
    }

    func test_projectTilePresentation_wideWithoutUpcomingTaskStaysStableAcrossLiveTicks() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            nextTaskTitle: nil
        )

        let first = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 0)
        let second = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 1)

        XCTAssertEqual(first.livePanel, second.livePanel)
    }

    func test_projectTilePresentation_mediumUsesSquareContract() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            nextTaskTitle: "整理材料"
        )

        let presentation = ProjectTilePresentation(
            snapshot: snapshot,
            size: .medium,
            isEditing: true,
            liveTick: 0
        )

        XCTAssertEqual(presentation.titleLineLimit, 1)
        XCTAssertTrue(presentation.showsStatusChip)
        XCTAssertFalse(presentation.showsNextTaskDate)
        XCTAssertEqual(presentation.livePanel, .progress)
        XCTAssertEqual(presentation.secondaryContent, .compactPills)
    }

    func test_projectTilePresentation_mediumBrowseUsesMetricCards() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
            nextTaskTitle: "整理材料"
        )

        let presentation = ProjectTilePresentation(
            snapshot: snapshot,
            size: .medium,
            isEditing: false,
            liveTick: 0
        )

        XCTAssertEqual(presentation.titleLineLimit, 2)
        XCTAssertTrue(presentation.showsNextTaskDate)
        XCTAssertEqual(presentation.secondaryContent, .metricCards)
    }

    func test_projectTilePresentation_wideEditingKeepsTimelineStoryButUsesCompactStrip() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
            nextTaskTitle: "明天交付"
        )

        let presentation = ProjectTilePresentation(
            snapshot: snapshot,
            size: .wide,
            isEditing: true,
            liveTick: 0
        )

        XCTAssertEqual(presentation.livePanel, .nextTask)
        XCTAssertFalse(presentation.showsNextTaskDate)
        XCTAssertEqual(presentation.secondaryContent, .compactPills)
    }

    func test_taskNumberFormatting() {
        let task = TaskItem(title: "Test", order: 3)
        XCTAssertEqual(task.taskNumber, "T03")
    }

    func test_dayFocusUniqueness() {
        let day = DayModel(dayId: Date().dayId, date: Date())
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "B", order: 2, zone: .focus))
        XCTAssertFalse(day.hasSingleFocus)
    }

    func test_startFlowCoordinator_transitionsFromWarningToRitual() {
        var coordinator = TodayStartFlowCoordinator()
        coordinator.present()
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.step, .warning)

        coordinator.chooseDirectEnter()
        XCTAssertEqual(coordinator.step, .ritual)
    }

    func test_startFlowCoordinator_cancelResetsFlow() {
        var coordinator = TodayStartFlowCoordinator()
        coordinator.present()
        coordinator.chooseDirectEnter()
        coordinator.cancel()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertEqual(coordinator.step, .warning)
    }

    func test_weekOverviewDisplayMode_cycleOrder() {
        XCTAssertEqual(WeekOverviewDisplayMode.cards.next, .strips)
        XCTAssertEqual(WeekOverviewDisplayMode.strips.next, .collapsed)
        XCTAssertEqual(WeekOverviewDisplayMode.collapsed.next, .cards)
    }

    func test_weekOverviewDayStripSummary_prefersFocusTask() {
        let day = DayModel(dayId: "2026-03-15", date: makeDate(2026, 3, 15, 9, 0), status: .execute)
        day.tasks.append(TaskItem(title: "Write outline", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "Backlog follow-up", order: 2, zone: .draft))

        let summary = WeekOverviewDayStripSummary(day: day)

        XCTAssertEqual(summary.highlight, .focus("Write outline"))
    }

    func test_weekOverviewDayStripSummary_fallsBackToDraftTask() {
        let day = DayModel(dayId: "2026-03-16", date: makeDate(2026, 3, 16, 9, 0), status: .draft)
        day.tasks.append(TaskItem(title: "Draft landing copy", order: 2, zone: .draft))
        day.tasks.append(TaskItem(title: "Review assets", order: 1, zone: .draft))

        let summary = WeekOverviewDayStripSummary(day: day)

        XCTAssertEqual(summary.highlight, .draft("Review assets"))
    }

    func test_weekOverviewDayStripSummary_usesCompletedFallbackWhenNoActiveTasks() {
        let day = DayModel(dayId: "2026-03-17", date: makeDate(2026, 3, 17, 9, 0), status: .completed)
        let task = TaskItem(title: "Ship build", order: 1, zone: .complete)
        task.completedOrder = 1
        day.tasks.append(task)

        let summary = WeekOverviewDayStripSummary(day: day)

        XCTAssertEqual(summary.highlight, .completed("1 项已完成"))
    }

    func test_weekTopologySnapshot_mapsResultCountsAndStableIDs() {
        let start = makeDate(2026, 6, 15)
        let week = WeekModel(
            weekId: start.weekId,
            startDate: start,
            endDate: start.addingDays(6),
            status: .present
        )
        let day = DayModel(dayId: start.dayId, date: start, status: .execute)
        day.expiredCount = 2
        day.tasks.append(TaskItem(title: "Focus", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "Frozen", order: 2, zone: .frozen))
        day.tasks.append(TaskItem(title: "Draft", order: 3, zone: .draft))
        let completed = TaskItem(title: "Done", order: 4, zone: .complete)
        completed.completedOrder = 1
        day.tasks.append(completed)
        week.days.append(day)

        let snapshot = WeekTopologySnapshot(week: week)
        let topologyDay = try! XCTUnwrap(snapshot.days.first)

        XCTAssertEqual(topologyDay.id, "day:\(day.dayId)")
        XCTAssertEqual(topologyDay.remainingCount, 3)
        XCTAssertEqual(topologyDay.completedCount, 1)
        XCTAssertEqual(topologyDay.forgottenCount, 2)
        XCTAssertEqual(topologyDay.totalCount, 6)
        XCTAssertEqual(snapshot.totalCount, 6)
    }

    func test_weekTopologySnapshot_hasContentOnlyWhenWeekContainsTasks() {
        let start = makeDate(2026, 6, 15)
        let week = WeekModel(
            weekId: start.weekId,
            startDate: start,
            endDate: start.addingDays(6),
            status: .present
        )

        XCTAssertFalse(WeekTopologySnapshot(week: week).hasContent)

        let day = DayModel(dayId: start.dayId, date: start, status: .draft)
        day.tasks.append(TaskItem(title: "Plan the week", order: 1, zone: .draft))
        week.days.append(day)

        XCTAssertTrue(WeekTopologySnapshot(week: week).hasContent)
    }

    func test_weekTopologySnapshot_ordersRemainingAndCompletedTasks() {
        let start = makeDate(2026, 6, 15)
        let week = WeekModel(
            weekId: start.weekId,
            startDate: start,
            endDate: start.addingDays(6),
            status: .present
        )
        let day = DayModel(dayId: start.dayId, date: start, status: .execute)
        day.tasks.append(TaskItem(title: "Draft 2", order: 4, zone: .draft))
        day.tasks.append(TaskItem(title: "Frozen 2", order: 3, zone: .frozen))
        day.tasks.append(TaskItem(title: "Focus", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "Frozen 1", order: 2, zone: .frozen))
        day.tasks.append(TaskItem(title: "Draft 1", order: 3, zone: .draft))
        let doneSecond = TaskItem(title: "Done 2", order: 6, zone: .complete)
        doneSecond.completedOrder = 2
        let doneFirst = TaskItem(title: "Done 1", order: 5, zone: .complete)
        doneFirst.completedOrder = 1
        day.tasks.append(contentsOf: [doneSecond, doneFirst])
        week.days.append(day)

        let topologyDay = WeekTopologySnapshot(week: week).days[0]

        XCTAssertEqual(topologyDay.remainingTasks.map(\.title), [
            "Focus", "Frozen 1", "Frozen 2", "Draft 1", "Draft 2"
        ])
        XCTAssertEqual(topologyDay.completedTasks.map(\.title), ["Done 1", "Done 2"])
    }

    func test_weekTopologySnapshot_createsAnonymousForgottenNodesOnly() {
        let start = makeDate(2026, 6, 15)
        let week = WeekModel(
            weekId: start.weekId,
            startDate: start,
            endDate: start.addingDays(6),
            status: .present
        )
        let day = DayModel(dayId: start.dayId, date: start, status: .expired)
        day.expiredCount = 3
        week.days.append(day)

        let topologyDay = WeekTopologySnapshot(week: week).days[0]

        XCTAssertEqual(topologyDay.forgottenNodes.map(\.id), [
            "forgotten:\(day.dayId):0",
            "forgotten:\(day.dayId):1",
            "forgotten:\(day.dayId):2"
        ])
        XCTAssertTrue(topologyDay.forgottenNodes.allSatisfy { $0.title == nil })
    }

    func test_weekTopologySnapshot_hasContentProbeMatchesBuiltSnapshot() {
        let start = makeDate(2026, 6, 15)

        // 空周。
        let empty = WeekCalculator().makeWeek(for: start, status: .present)
        XCTAssertFalse(WeekTopologySnapshot.hasContent(in: empty))
        XCTAssertEqual(
            WeekTopologySnapshot.hasContent(in: empty),
            WeekTopologySnapshot(week: empty).hasContent
        )

        // 只有草稿任务（remaining 侧）。
        let withDraft = WeekCalculator().makeWeek(for: start, status: .present)
        withDraft.days.first?.tasks.append(TaskItem(title: "Draft", order: 1, zone: .draft))
        XCTAssertTrue(WeekTopologySnapshot.hasContent(in: withDraft))
        XCTAssertEqual(
            WeekTopologySnapshot.hasContent(in: withDraft),
            WeekTopologySnapshot(week: withDraft).hasContent
        )

        // 只有已完成任务：remaining 为空，容易漏判。
        let withCompleted = WeekCalculator().makeWeek(for: start, status: .present)
        let done = TaskItem(title: "Done", order: 1, zone: .complete)
        done.completedOrder = 1
        withCompleted.days.first?.tasks.append(done)
        XCTAssertTrue(WeekTopologySnapshot.hasContent(in: withCompleted))
        XCTAssertEqual(
            WeekTopologySnapshot.hasContent(in: withCompleted),
            WeekTopologySnapshot(week: withCompleted).hasContent
        )

        // 只有遗忘计数，没有任何任务实体。
        let withExpired = WeekCalculator().makeWeek(for: start, status: .present)
        withExpired.days.first?.expiredCount = 2
        XCTAssertTrue(WeekTopologySnapshot.hasContent(in: withExpired))
        XCTAssertEqual(
            WeekTopologySnapshot.hasContent(in: withExpired),
            WeekTopologySnapshot(week: withExpired).hasContent
        )
    }

    func test_weekTopologySemanticLevel_derivesThresholdsFromNodeGeometry() {
        // 阈值不再手写倍数，而是由「节点尺寸 + 间距」推导，卡片一变阈值就跟着变。
        let groupScale = WeekTopologyMetrics.groupClearEffectiveScale
        let taskScale = WeekTopologyMetrics.taskClearEffectiveScale

        XCTAssertGreaterThan(taskScale, groupScale)

        XCTAssertEqual(WeekTopologySemanticLevel(effectiveScale: groupScale * 0.99), .overview)
        XCTAssertEqual(WeekTopologySemanticLevel(effectiveScale: groupScale), .groups)
        XCTAssertEqual(WeekTopologySemanticLevel(effectiveScale: taskScale * 0.99), .groups)
        XCTAssertEqual(WeekTopologySemanticLevel(effectiveScale: taskScale), .tasks)
    }

    func test_weekTopologyMetrics_taskClearScaleKeepsCardsApart() {
        let scale = WeekTopologyMetrics.taskClearEffectiveScale
        let slack: CGFloat = 0.001

        // 同一天内：相邻两行任务卡不能压叠。
        XCTAssertGreaterThanOrEqual(
            WeekTopologyMetrics.taskVerticalSpacing * scale,
            WeekTopologyMetrics.taskCardHeight + WeekTopologyMetrics.minimumNodeGap - slack
        )

        // 相邻日期之间：同一行的两张任务卡不能压叠。
        XCTAssertGreaterThanOrEqual(
            WeekTopologyMetrics.taskPitch * scale,
            WeekTopologyMetrics.taskCardWidth + WeekTopologyMetrics.minimumNodeGap - slack
        )
    }

    /// 每一层的门槛都必须让**纵向**堆叠的卡片也不压叠。
    ///
    /// 之前的门槛只检查了相邻日期之间的横向间距，于是组层（eff 0.5–0.86）
    /// 里日期节点和它自己的组节点会重叠 12pt——同一列上下的卡片同样会撞。
    func test_weekTopologyMetrics_tierGatesLeaveVerticalClearance() {
        let slack: CGFloat = 0.001

        let stacks: [(name: String, gate: CGFloat, distance: CGFloat, upper: CGFloat, lower: CGFloat)] = [
            (
                "日期→组",
                WeekTopologyMetrics.groupClearEffectiveScale,
                WeekTopologyMetrics.groupTopOffset,
                WeekTopologyMetrics.dayNodeExpandedHeight,
                WeekTopologyMetrics.groupCardHeight
            ),
            (
                "组→任务",
                WeekTopologyMetrics.taskClearEffectiveScale,
                WeekTopologyMetrics.taskFirstRowOffset,
                WeekTopologyMetrics.groupCardHeight,
                WeekTopologyMetrics.taskCardHeight
            ),
            (
                "任务→任务",
                WeekTopologyMetrics.taskClearEffectiveScale,
                WeekTopologyMetrics.taskVerticalSpacing,
                WeekTopologyMetrics.taskCardHeight,
                WeekTopologyMetrics.taskCardHeight
            )
        ]

        for stack in stacks {
            let gap = stack.distance * stack.gate - stack.upper / 2 - stack.lower / 2
            XCTAssertGreaterThanOrEqual(
                gap,
                WeekTopologyMetrics.minimumNodeGap - slack,
                "\(stack.name) 在门槛尺度下会压叠（净空 \(gap)pt）"
            )
        }
    }

    func test_weekTopologyMetrics_tiersStayDistinguishable() {
        // 组层与任务层必须落在不同的尺度上，否则组层永远看不到。
        XCTAssertLessThan(
            WeekTopologyMetrics.groupClearEffectiveScale,
            WeekTopologyMetrics.taskClearEffectiveScale
        )
    }

    /// 连线端点必须落在两张卡片的边界之外。
    ///
    /// 这是「线条穿过框」那个 bug 的回归守卫：按中心到中心画线时，同一列的
    /// 日期 / 组 / 任务全部共线，整棵子树会被一根签子串起来。
    func test_weekTopologyEdgeSpan_stopsAtCardBorders() throws {
        let gap = WeekTopologyMetrics.edgeGap

        let pairs: [(name: String, gate: CGFloat, distance: CGFloat, upper: CGFloat, lower: CGFloat)] = [
            (
                "日期→组",
                WeekTopologyMetrics.taskClearEffectiveScale,
                WeekTopologyMetrics.groupTopOffset,
                WeekTopologyMetrics.dayNodeExpandedHeight,
                WeekTopologyMetrics.groupCardHeight
            ),
            (
                "组→任务",
                WeekTopologyMetrics.taskClearEffectiveScale,
                WeekTopologyMetrics.taskFirstRowOffset,
                WeekTopologyMetrics.groupCardHeight,
                WeekTopologyMetrics.taskCardHeight
            ),
            (
                "任务→任务",
                WeekTopologyMetrics.taskClearEffectiveScale,
                WeekTopologyMetrics.taskVerticalSpacing,
                WeekTopologyMetrics.taskCardHeight,
                WeekTopologyMetrics.taskCardHeight
            )
        ]

        for pair in pairs {
            // 上方卡片中心放在 0，下方卡片按渲染尺度摆位。
            let bottomCenterY = pair.distance * pair.gate
            let span = WeekTopologyEdgeSpan(
                topCenterY: 0,
                bottomCenterY: bottomCenterY,
                topClearance: WeekTopologyEdgeSpan.clearance(cardHeight: pair.upper),
                bottomClearance: WeekTopologyEdgeSpan.clearance(cardHeight: pair.lower)
            )

            let unwrapped = try XCTUnwrap(
                span,
                "\(pair.name)：两张卡片之间没有给连线留下任何空间"
            )

            XCTAssertGreaterThanOrEqual(
                unwrapped.startY,
                pair.upper / 2,
                "\(pair.name) 的连线起点落进了上方卡片里"
            )
            XCTAssertLessThanOrEqual(
                unwrapped.endY,
                bottomCenterY - pair.lower / 2,
                "\(pair.name) 的连线终点落进了下方卡片里"
            )
            XCTAssertGreaterThan(
                unwrapped.startY,
                0,
                "\(pair.name) 的连线起点不该超过上方卡片的中心"
            )
            XCTAssertLessThan(
                unwrapped.endY,
                bottomCenterY,
                "\(pair.name) 的连线终点不该超过下方卡片的中心"
            )
            XCTAssertEqual(unwrapped.startY, pair.upper / 2 + gap, accuracy: 0.001)
            XCTAssertEqual(unwrapped.endY, bottomCenterY - pair.lower / 2 - gap, accuracy: 0.001)

            // 只把两端各让出 edgeGap、中间一点不剩，等于把线裁没了。
            // 「非 nil」还不够，剩下的那截必须真的看得见。
            XCTAssertGreaterThanOrEqual(
                unwrapped.endY - unwrapped.startY,
                WeekTopologyMetrics.minimumConnectorLength - 0.001,
                "\(pair.name) 在门槛尺度下连线被裁得看不见了"
            )
        }
    }

    func test_weekTopologyFocus_everyEdgeStaysDrawableAtTheFramedScale() throws {
        // 端到端复核用户截图里的那个毛病：一条线从头穿到尾，把整棵子树串成糖葫芦。
        //
        // 这里不手算几何，直接拿真实布局在取景尺度上走一遍——如果「门槛」和
        // 「取景上限」交叉，这条测试会先于截图发现：要么连线被判成没有空间，
        // 要么子树已经超出画布。
        let start = makeDate(2026, 6, 15)
        let week = WeekCalculator().makeWeek(for: start, status: .present)
        let days = week.days.sorted { $0.date < $1.date }
        let target = try XCTUnwrap(days.first)
        for order in 1...2 {
            target.tasks.append(TaskItem(title: "R\(order)", order: order, zone: .draft))
        }

        let snapshot = WeekTopologySnapshot(week: week)
        let layout = WeekTopologyLayout(snapshot: snapshot)
        let topologyDay = try XCTUnwrap(snapshot.days.first)
        let box = try XCTUnwrap(layout.subtreeBounds(for: topologyDay))

        let canvas = CGSize(width: 321, height: 220)
        let scale = WeekTopologyViewportState.focusEffectiveScale(
            subtreeSize: box.size,
            canvasSize: canvas
        )

        // 门槛不能越过取景上限，否则「任务层可见」和「子树装得下」无法同时成立。
        XCTAssertLessThanOrEqual(
            box.height * scale,
            canvas.height - WeekTopologyMetrics.focusPadding * 2 + 0.001,
            "任务层门槛已经高过紧凑画布能取景的上限"
        )
        XCTAssertEqual(
            WeekTopologySemanticLevel(effectiveScale: scale),
            .tasks,
            "取景尺度进不了任务层"
        )

        // 取景是等比缩放加平移，两点间距只受缩放影响，所以直接按 scale 摆位即可。
        let dayPoint = try XCTUnwrap(layout.positions[topologyDay.id])
        let groupPoint = try XCTUnwrap(
            layout.positions[topologyDay.groupID(for: .remaining)]
        )
        let taskPoints = topologyDay.remainingTasks.compactMap { layout.positions[$0.id] }
        XCTAssertEqual(taskPoints.count, 2, "这一天应该挂两个任务节点")

        var edges: [(name: String, top: CGFloat, bottom: CGFloat, upper: CGFloat, lower: CGFloat)] = [
            (
                "日期→组",
                dayPoint.y * scale,
                groupPoint.y * scale,
                WeekTopologyMetrics.dayNodeExpandedHeight,
                WeekTopologyMetrics.groupCardHeight
            )
        ]
        for (index, point) in taskPoints.enumerated() {
            edges.append((
                index == 0 ? "组→任务1" : "任务1→任务2",
                (index == 0 ? groupPoint.y : taskPoints[index - 1].y) * scale,
                point.y * scale,
                index == 0
                    ? WeekTopologyMetrics.groupCardHeight
                    : WeekTopologyMetrics.taskCardHeight,
                WeekTopologyMetrics.taskCardHeight
            ))
        }

        for edge in edges {
            let span = try XCTUnwrap(
                WeekTopologyEdgeSpan(
                    topCenterY: edge.top,
                    bottomCenterY: edge.bottom,
                    topClearance: WeekTopologyEdgeSpan.clearance(cardHeight: edge.upper),
                    bottomClearance: WeekTopologyEdgeSpan.clearance(cardHeight: edge.lower)
                ),
                "\(edge.name)：取景尺度下两张卡片之间没有给连线留下空间"
            )

            XCTAssertGreaterThanOrEqual(
                span.startY,
                edge.top + edge.upper / 2 - 0.001,
                "\(edge.name) 的连线起点落进了上方卡片里"
            )
            XCTAssertLessThanOrEqual(
                span.endY,
                edge.bottom - edge.lower / 2 + 0.001,
                "\(edge.name) 的连线终点落进了下方卡片里"
            )
            XCTAssertGreaterThanOrEqual(
                span.endY - span.startY,
                WeekTopologyMetrics.minimumConnectorLength - 0.001,
                "\(edge.name) 在取景尺度下被裁得看不见了"
            )
        }
    }

    func test_weekTopologyEdgeSpan_returnsNilWhenCardsAreTooClose() {
        // 空间不足时宁可不画线，也不要画一条穿进卡片的线。
        XCTAssertNil(
            WeekTopologyEdgeSpan(
                topCenterY: 0,
                bottomCenterY: 10,
                topClearance: 20,
                bottomClearance: 20
            )
        )
    }

    func test_weekTopologyMetrics_verticalInsetClearsRootCard() {
        // 根节点在两种形态下都不能被画布上边缘裁掉。
        XCTAssertGreaterThanOrEqual(
            WeekTopologyMetrics.verticalInset,
            WeekTopologyMetrics.rootNodeExpandedHeight / 2
        )
        XCTAssertGreaterThanOrEqual(
            WeekTopologyMetrics.verticalInset,
            WeekTopologyMetrics.rootNodeCompactHeight / 2
        )
    }

    func test_weekTopologyMetrics_taskRowStaysInsideDayPitch() {
        // 一天的整行任务不能宽过日间距，否则相邻日期必然压叠。
        // 三列网格的行宽是 276pt，而日间距只有 152pt——这就是 P2 无法靠调间距
        // 修好的结构性原因，也是这里把列数收敛到 1 的原因。
        let rowWidth = CGFloat(WeekTopologyMetrics.taskColumnCount - 1)
            * WeekTopologyMetrics.taskColumnSpacing
            + WeekTopologyMetrics.taskCardWidth

        XCTAssertLessThanOrEqual(
            rowWidth,
            WeekTopologyMetrics.daySpacing,
            "任务行比日间距还宽，相邻日期的任务卡必然互相压叠"
        )
    }

    func test_weekTopologyLayout_buildsTreeLevelsAndStableDayOrder() throws {
        let start = makeDate(2026, 6, 15)
        let week = WeekCalculator().makeWeek(for: start, status: .present)
        let firstDay = try XCTUnwrap(week.days.sorted { $0.date < $1.date }.first)
        firstDay.tasks.append(TaskItem(title: "Root task", order: 1, zone: .draft))
        let snapshot = WeekTopologySnapshot(week: week)

        let layout = WeekTopologyLayout(snapshot: snapshot)
        let dayPoints = snapshot.days.compactMap { layout.positions[$0.id] }
        let rootPoint = try XCTUnwrap(layout.positions[snapshot.rootNodeID])
        let groupPoint = try XCTUnwrap(layout.positions[snapshot.days[0].groupID(for: .remaining)])
        let taskID = try XCTUnwrap(snapshot.days.first?.remainingTasks.first?.id)
        let taskPoint = try XCTUnwrap(layout.positions[taskID])

        XCTAssertEqual(dayPoints.count, 7)
        XCTAssertEqual(Set(dayPoints.map(\.y)).count, 1)
        XCTAssertTrue(zip(dayPoints, dayPoints.dropFirst()).allSatisfy { $0.x < $1.x })
        XCTAssertEqual(rootPoint.x, layout.contentBounds.midX, accuracy: 0.001)
        XCTAssertGreaterThan(dayPoints[0].y - rootPoint.y, 160)
        XCTAssertLessThan(dayPoints[0].y, groupPoint.y)
        XCTAssertLessThan(groupPoint.y, taskPoint.y)
        XCTAssertGreaterThan(layout.contentBounds.height, 300)
    }

    func test_weekTopologyLayout_rootRailSpansEveryDayColumn() throws {
        let start = makeDate(2026, 6, 15)
        let week = WeekCalculator().makeWeek(for: start, status: .present)
        let snapshot = WeekTopologySnapshot(week: week)
        let layout = WeekTopologyLayout(snapshot: snapshot)
        let rail = try XCTUnwrap(layout.rootRail)

        let dayPoints = try snapshot.days.map { try XCTUnwrap(layout.positions[$0.id]) }
        let minDayX = try XCTUnwrap(dayPoints.map(\.x).min())
        let maxDayX = try XCTUnwrap(dayPoints.map(\.x).max())
        let minDayY = try XCTUnwrap(dayPoints.map(\.y).min())

        XCTAssertEqual(rail.trunkX, layout.contentBounds.midX, accuracy: 0.001)
        XCTAssertLessThanOrEqual(rail.railStartX, minDayX, "横杆没有覆盖到最左一天")
        XCTAssertGreaterThanOrEqual(rail.railEndX, maxDayX, "横杆没有覆盖到最右一天")
        XCTAssertGreaterThan(rail.railY, rail.trunkTopY)
        XCTAssertLessThan(rail.railY, minDayY)
    }

    func test_weekTopologyLayout_taskRowsNeverCollideWithNextGroupBand() throws {
        let start = makeDate(2026, 6, 15)
        let week = WeekModel(
            weekId: start.weekId,
            startDate: start,
            endDate: start.addingDays(6),
            status: .present
        )
        let day = DayModel(dayId: start.dayId, date: start, status: .execute)
        for order in 1...7 {
            day.tasks.append(TaskItem(title: "Remaining \(order)", order: order, zone: .focus))
        }
        for order in 8...11 {
            let done = TaskItem(title: "Done \(order)", order: order, zone: .complete)
            done.completedOrder = order - 7
            day.tasks.append(done)
        }
        day.expiredCount = 3
        week.days.append(day)

        let snapshot = WeekTopologySnapshot(week: week)
        let layout = WeekTopologyLayout(snapshot: snapshot)
        let topologyDay = try XCTUnwrap(snapshot.days.first)

        // 三行剩余 + 两行完成，正好是旧实现里写死的 88pt 组带间距撑不住的情形。
        XCTAssertEqual(topologyDay.remainingCount, 7)
        XCTAssertEqual(topologyDay.completedCount, 4)
        XCTAssertEqual(topologyDay.forgottenCount, 3)

        try assertNoVerticalCollision(
            in: layout,
            taskIDs: topologyDay.remainingTasks.map(\.id),
            above: topologyDay.groupID(for: .completed)
        )
        try assertNoVerticalCollision(
            in: layout,
            taskIDs: topologyDay.completedTasks.map(\.id),
            above: topologyDay.groupID(for: .forgotten)
        )
    }

    func test_weekTopologyLayout_taskCardsSeparateAtTaskTierZoom() throws {
        let start = makeDate(2026, 6, 15)
        let week = WeekModel(
            weekId: start.weekId,
            startDate: start,
            endDate: start.addingDays(6),
            status: .present
        )
        for offset in 0..<7 {
            let date = start.addingDays(offset)
            let day = DayModel(dayId: date.dayId, date: date, status: .execute)
            for order in 1...3 {
                day.tasks.append(TaskItem(title: "Task \(order)", order: order, zone: .frozen))
            }
            week.days.append(day)
        }

        let snapshot = WeekTopologySnapshot(week: week)
        let layout = WeekTopologyLayout(snapshot: snapshot)
        let points = try snapshot.days
            .flatMap(\.remainingTasks)
            .map { try XCTUnwrap(layout.positions[$0.id]) }

        // 任务层只在有效缩放越过推导出的下限之后才出现，所以「不重叠」要在渲染
        // 尺度下成立，而不是在内容坐标下成立——节点尺寸并不随缩放变化。
        let tierScale = WeekTopologyMetrics.taskClearEffectiveScale
        for (index, point) in points.enumerated() {
            for other in points.dropFirst(index + 1) where abs(point.y - other.y) < 0.001 {
                XCTAssertGreaterThanOrEqual(
                    abs(point.x - other.x) * tierScale,
                    WeekTopologyMetrics.taskCardWidth,
                    "任务层刚出现时同一行的两个任务卡就已经重叠"
                )
            }
        }
    }

    /// 卡片在渲染空间的矩形，尺寸按当前层级取——和画布读的是同一套 metrics。
    private func topologyCardRects(
        layout: WeekTopologyLayout,
        snapshot: WeekTopologySnapshot,
        semanticLevel: WeekTopologySemanticLevel,
        scale: CGFloat
    ) -> [(id: String, rect: CGRect)] {
        let isOverview = semanticLevel == .overview
        let rootSize = CGSize(
            width: 58,
            height: isOverview
                ? WeekTopologyMetrics.rootNodeCompactHeight
                : WeekTopologyMetrics.rootNodeExpandedHeight
        )
        let daySize = CGSize(
            width: isOverview
                ? WeekTopologyMetrics.dayNodeCompactWidth
                : WeekTopologyMetrics.dayNodeExpandedWidth,
            height: isOverview
                ? WeekTopologyMetrics.dayNodeCompactHeight
                : WeekTopologyMetrics.dayNodeExpandedHeight
        )
        let groupSize = CGSize(
            width: WeekTopologyMetrics.groupCardWidth,
            height: WeekTopologyMetrics.groupCardHeight
        )
        let taskSize = CGSize(
            width: WeekTopologyMetrics.taskCardWidth,
            height: WeekTopologyMetrics.taskCardHeight
        )
        let forgottenSize = CGSize(
            width: WeekTopologyMetrics.forgottenCardWidth,
            height: WeekTopologyMetrics.forgottenCardHeight
        )

        func rect(_ id: String, _ size: CGSize) -> (id: String, rect: CGRect)? {
            guard let point = layout.positions[id] else { return nil }
            let center = CGPoint(x: point.x * scale, y: point.y * scale)
            return (id, CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ))
        }

        var out: [(id: String, rect: CGRect)] = []
        if let entry = rect(snapshot.rootNodeID, rootSize) { out.append(entry) }

        for day in snapshot.days {
            if let entry = rect(day.id, daySize) { out.append(entry) }
            guard semanticLevel != .overview else { continue }

            for kind in WeekTopologyResultKind.allCases where day.count(for: kind) > 0 {
                if let entry = rect(day.groupID(for: kind), groupSize) { out.append(entry) }
            }
            guard semanticLevel == .tasks else { continue }

            for kind in WeekTopologyResultKind.allCases where day.count(for: kind) > 0 {
                let size = kind == .forgotten ? forgottenSize : taskSize
                for nodeID in day.nodeIDs(for: kind) {
                    if let entry = rect(nodeID, size) { out.append(entry) }
                }
            }
        }
        return out
    }

    /// 一天挂三个带、每个带多张卡，用来覆盖「跨带」与「带内跨任务」两种穿越。
    private func makeThreeBandDay() throws -> (
        snapshot: WeekTopologySnapshot,
        layout: WeekTopologyLayout,
        day: WeekTopologyDaySnapshot
    ) {
        let start = makeDate(2026, 6, 15)
        let week = WeekModel(
            weekId: start.weekId,
            startDate: start,
            endDate: start.addingDays(6),
            status: .present
        )
        let day = DayModel(dayId: start.dayId, date: start, status: .execute)
        for order in 1...3 {
            day.tasks.append(TaskItem(title: "Remaining \(order)", order: order, zone: .draft))
        }
        for order in 4...5 {
            let done = TaskItem(title: "Done \(order)", order: order, zone: .complete)
            done.completedOrder = order - 3
            day.tasks.append(done)
        }
        day.expiredCount = 2
        week.days.append(day)

        let snapshot = WeekTopologySnapshot(week: week)
        return (
            snapshot,
            WeekTopologyLayout(snapshot: snapshot),
            try XCTUnwrap(snapshot.days.first)
        )
    }

    func test_weekTopologyGeometry_cardsNeverOverlapAndLinksNeverCrossACard() throws {
        // 用户截图里的毛病是「线穿过框」。这条用例把两类关系一次钉死：
        //   1. 任何两张卡片都不压叠；
        //   2. 任何一条连线的线段，都不穿过它两端以外的任何卡片。
        //
        // 第 2 条是这次真正的收获：`WeekTopologyEdgeSpan` 只保证线段*两端*有余量，
        // 中间夹着的卡片它管不了。「组 → 每个任务」的扇出画法正是这样把线画回
        // 它上面的任务卡里的，而那条线两端的余量看起来完全正常——
        // 所以只断言端点的用例抓不到它。
        let fixture = try makeThreeBandDay()
        let snapshot = fixture.snapshot
        let layout = fixture.layout
        let topologyDay = fixture.day

        XCTAssertEqual(topologyDay.remainingCount, 3)
        XCTAssertEqual(topologyDay.completedCount, 2)
        XCTAssertEqual(topologyDay.forgottenCount, 2)

        let levels: [(name: String, scale: CGFloat)] = [
            ("overview", 0.5),
            ("groups 门槛", WeekTopologyMetrics.groupClearEffectiveScale),
            ("tasks 门槛", WeekTopologyMetrics.taskClearEffectiveScale),
            ("放大上限", WeekTopologyViewportState.maximumEffectiveScale)
        ]

        for entry in levels {
            let level = WeekTopologySemanticLevel(effectiveScale: entry.scale)
            let cards = topologyCardRects(
                layout: layout,
                snapshot: snapshot,
                semanticLevel: level,
                scale: entry.scale
            )
            XCTAssertFalse(cards.isEmpty, "[\(entry.name)] 一张卡片都没画出来")

            // 1. 卡片之间不能压叠。
            for i in cards.indices {
                for j in cards.indices where j > i {
                    let overlap = cards[i].rect.intersection(cards[j].rect)
                    XCTAssertTrue(
                        overlap.isNull || overlap.height <= 0.001,
                        "[\(entry.name)] \(cards[i].id) 与 \(cards[j].id) 压叠了 \(overlap.height)pt"
                    )
                }
            }

            guard level != .overview else { continue }

            // 2. 连线不能穿过任何一张卡片。
            for link in layout.subtreeLinks(for: topologyDay, semanticLevel: level) {
                let parent = try XCTUnwrap(layout.positions[link.parentID])
                let child = try XCTUnwrap(layout.positions[link.childID])
                let span = try XCTUnwrap(
                    WeekTopologyEdgeSpan(
                        topCenterY: parent.y * entry.scale,
                        bottomCenterY: child.y * entry.scale,
                        topClearance: link.parentHeight / 2 + WeekTopologyMetrics.edgeGap,
                        bottomClearance: link.childHeight / 2 + WeekTopologyMetrics.edgeGap
                    ),
                    "[\(entry.name)] \(link.parentID) → \(link.childID) 没有给连线留下空间"
                )

                let x = parent.x * entry.scale
                let stroke = CGRect(
                    x: x - 0.7,
                    y: span.startY,
                    width: 1.4,
                    height: span.endY - span.startY
                )

                for card in cards where card.id != link.parentID && card.id != link.childID {
                    let hit = card.rect.intersection(stroke)
                    XCTAssertTrue(
                        hit.isNull || hit.height <= 0.001,
                        "[\(entry.name)] \(link.parentID) → \(link.childID) 的连线穿过了 \(card.id)（\(hit.height)pt）"
                    )
                }
            }
        }
    }

    func test_weekTopologyFanOutLinks_wouldRunThroughTheCardsBetweenThem() throws {
        // 上面那条不变量的反面证据，说明它为什么必须有牙齿。
        //
        // 修复前的画法是「组 → 每一个任务」扇出，于是「组 → 第 3 个任务」这条边
        // 会笔直穿过它上面的第 1、2 张任务卡，而这条边两端的余量完全正常。
        // `test_weekTopologyEdgeSpan_stopsAtCardBorders` 只检查端点，抓不到它。
        let fixture = try makeThreeBandDay()
        let layout = fixture.layout
        let topologyDay = fixture.day
        let scale = WeekTopologyMetrics.taskClearEffectiveScale

        let groupPoint = try XCTUnwrap(layout.positions[topologyDay.groupID(for: .remaining)])
        let taskPoints = try topologyDay.remainingTasks.map { try XCTUnwrap(layout.positions[$0.id]) }
        XCTAssertEqual(taskPoints.count, 3)

        // 扇出到第 3 个任务（下标 2）。
        let target = taskPoints[2]
        let span = try XCTUnwrap(
            WeekTopologyEdgeSpan(
                topCenterY: groupPoint.y * scale,
                bottomCenterY: target.y * scale,
                topClearance: WeekTopologyMetrics.groupCardHeight / 2 + WeekTopologyMetrics.edgeGap,
                bottomClearance: WeekTopologyMetrics.taskCardHeight / 2 + WeekTopologyMetrics.edgeGap
            ),
            "扇出的场景没构造对：这条边本身应当是有空间的"
        )

        // 两端余量确实正常——这正是它骗过端点断言的原因。
        XCTAssertGreaterThanOrEqual(span.startY, groupPoint.y * scale, "起点应当已经在组卡下方")

        // 但它穿过了中间那张卡（下标 1）。
        let middle = taskPoints[1]
        let middleRect = CGRect(
            x: middle.x * scale - WeekTopologyMetrics.taskCardWidth / 2,
            y: middle.y * scale - WeekTopologyMetrics.taskCardHeight / 2,
            width: WeekTopologyMetrics.taskCardWidth,
            height: WeekTopologyMetrics.taskCardHeight
        )
        let stroke = CGRect(
            x: middle.x * scale - 0.7,
            y: span.startY,
            width: 1.4,
            height: span.endY - span.startY
        )
        let hit = middleRect.intersection(stroke)

        XCTAssertFalse(hit.isNull, "扇出画法应当穿过中间那张卡——场景没构造对")
        XCTAssertGreaterThan(
            hit.height,
            0,
            "扇出画法应当真的穿进中间那张卡，否则「改成链」就没有必要"
        )
    }

    func test_weekTopologyLayout_subtreeBoundsCoversItsOwnDayOnly() throws {
        let start = makeDate(2026, 6, 15)
        let week = WeekCalculator().makeWeek(for: start, status: .present)
        let days = week.days.sorted { $0.date < $1.date }
        let target = try XCTUnwrap(days.first)
        for order in 1...4 {
            target.tasks.append(TaskItem(title: "R\(order)", order: order, zone: .focus))
        }
        for order in 5...7 {
            let done = TaskItem(title: "C\(order)", order: order, zone: .complete)
            done.completedOrder = order - 4
            target.tasks.append(done)
        }
        target.expiredCount = 2

        let snapshot = WeekTopologySnapshot(week: week)
        let layout = WeekTopologyLayout(snapshot: snapshot)
        let topologyDay = try XCTUnwrap(snapshot.days.first)
        let box = try XCTUnwrap(layout.subtreeBounds(for: topologyDay))

        // 这一天自己的每个节点都必须落在盒子里。
        var ownNodeIDs = [topologyDay.id]
        for kind in WeekTopologyResultKind.allCases where topologyDay.count(for: kind) > 0 {
            ownNodeIDs.append(topologyDay.groupID(for: kind))
        }
        ownNodeIDs.append(contentsOf: topologyDay.remainingTasks.map(\.id))
        ownNodeIDs.append(contentsOf: topologyDay.completedTasks.map(\.id))
        ownNodeIDs.append(contentsOf: topologyDay.forgottenNodes.map(\.id))

        for nodeID in ownNodeIDs {
            let point = try XCTUnwrap(layout.positions[nodeID])
            XCTAssertTrue(box.contains(point), "\(nodeID) 落在子树包围盒之外")
        }

        // 而且不能把邻近日期也圈进来，否则取景会缩得没有意义。
        for other in snapshot.days.dropFirst() {
            let point = try XCTUnwrap(layout.positions[other.id])
            XCTAssertFalse(box.contains(point), "子树包围盒圈进了别的日期")
        }
    }

    func test_weekTopologyFocus_framesDaySubtreeInsideCompactCanvas() throws {
        // 复刻紧凑卡片：7 天整周、画布 321x220。
        let start = makeDate(2026, 6, 15)
        let week = WeekCalculator().makeWeek(for: start, status: .present)
        let days = week.days.sorted { $0.date < $1.date }
        let target = try XCTUnwrap(days.first)
        for order in 1...2 {
            target.tasks.append(TaskItem(title: "R\(order)", order: order, zone: .draft))
        }

        let snapshot = WeekTopologySnapshot(week: week)
        let layout = WeekTopologyLayout(snapshot: snapshot)
        let topologyDay = try XCTUnwrap(snapshot.days.first)
        let box = try XCTUnwrap(layout.subtreeBounds(for: topologyDay))

        let canvas = CGSize(width: 321, height: 220)
        let effectiveScale = WeekTopologyViewportState.focusEffectiveScale(
            subtreeSize: box.size,
            canvasSize: canvas
        )

        // 取景后的缩放必须已经进入任务层，否则轻点日期只能看到孤零零的日期节点。
        XCTAssertEqual(
            WeekTopologySemanticLevel(effectiveScale: effectiveScale),
            .tasks,
            "紧凑卡片里 focus 后的有效缩放进不了任务层"
        )

        // 而且整棵子树要真的装得进画布（含四周留白）。
        let rendered = CGSize(
            width: box.width * effectiveScale,
            height: box.height * effectiveScale
        )
        XCTAssertLessThanOrEqual(
            rendered.height,
            canvas.height - WeekTopologyMetrics.focusPadding * 2 + 0.001,
            "取景后子树的上下两端会超出紧凑画布"
        )
        XCTAssertLessThanOrEqual(
            rendered.width,
            canvas.width - WeekTopologyMetrics.focusPadding * 2 + 0.001,
            "取景后子树的左右两端会超出紧凑画布"
        )

        // 任务卡在取景尺度下不能压叠。
        XCTAssertGreaterThanOrEqual(
            WeekTopologyMetrics.taskVerticalSpacing * effectiveScale,
            WeekTopologyMetrics.taskCardHeight,
            "取景尺度下相邻两行任务卡会压叠"
        )
    }

    func test_weekTopologyFocus_keepsTaskRowsReachableForLongDays() throws {
        // 一天 7 个任务时子树装不进紧凑画布，取景必须退到「任务层下限」而不是
        // 无限缩小——否则任务卡会挤成一团。
        let canvas = CGSize(width: 321, height: 220)
        let tallSubtree = CGSize(width: 88, height: 400)
        let effectiveScale = WeekTopologyViewportState.focusEffectiveScale(
            subtreeSize: tallSubtree,
            canvasSize: canvas
        )

        XCTAssertEqual(effectiveScale, WeekTopologyMetrics.taskClearEffectiveScale, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(
            WeekTopologyMetrics.taskVerticalSpacing * effectiveScale,
            WeekTopologyMetrics.taskCardHeight,
            "任务多的日子取景后任务卡会压叠"
        )
    }

    func test_weekTopologyViewport_clampsZoomToRenderedCeiling() {
        var viewport = WeekTopologyViewportState()
        let fitScale: CGFloat = 0.282

        // 上限按画布适配比例反算：紧凑卡片的 0.282 与全屏的 0.392 应该得到
        // 不同的 scale 上限，但同一个「渲染尺度」上限。
        viewport.applyScale(100, fitScale: fitScale)
        XCTAssertEqual(
            viewport.effectiveScale(fitScale: fitScale),
            WeekTopologyViewportState.maximumEffectiveScale,
            accuracy: 0.0001
        )

        viewport.applyScale(0.1, fitScale: fitScale)
        XCTAssertEqual(viewport.scale, WeekTopologyViewportState.minimumScale)
    }

    func test_weekTopologyLayout_dayNodesSeparateAtOverviewZoom() {
        let contentWidth = WeekTopologyMetrics.contentWidth(dayCount: 7)

        // 屏宽 375 / 393 / 430，各自减去页面内边距 32 与卡片内边距 40。
        for canvasWidth in [CGFloat(303), 321, 358] {
            let fitScale = WeekTopologyMetrics.fitScale(
                viewportWidth: canvasWidth,
                contentWidth: contentWidth
            )
            XCTAssertGreaterThanOrEqual(
                WeekTopologyMetrics.daySpacing * fitScale,
                WeekTopologyMetrics.dayNodeCompactWidth,
                "画布宽 \(canvasWidth) 时 overview 层的日期节点会首尾相贴"
            )
        }
    }

    func test_weekTopologyViewport_reachesTaskTierAtCompactCardFitScale() {
        let contentWidth = WeekTopologyMetrics.contentWidth(dayCount: 7)
        let fitScale = WeekTopologyMetrics.fitScale(viewportWidth: 321, contentWidth: contentWidth)

        var viewport = WeekTopologyViewportState()
        XCTAssertEqual(viewport.semanticLevel(fitScale: fitScale), .overview)

        // 上限必须按画布适配比例反算，否则紧凑卡片永远进不了任务层。
        viewport.applyScale(viewport.clampedScale(100, fitScale: fitScale), fitScale: fitScale)

        XCTAssertEqual(viewport.semanticLevel(fitScale: fitScale), .tasks)
        XCTAssertGreaterThanOrEqual(
            viewport.effectiveScale(fitScale: fitScale),
            WeekTopologyViewportState.tasksReachEffectiveScale
        )
    }

    private func assertNoVerticalCollision(
        in layout: WeekTopologyLayout,
        taskIDs: [String],
        above groupID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let group = try XCTUnwrap(layout.positions[groupID], file: file, line: line)
        let groupTop = group.y - WeekTopologyMetrics.groupCardHeight / 2

        for id in taskIDs {
            let point = try XCTUnwrap(layout.positions[id], file: file, line: line)
            XCTAssertLessThan(
                point.y + WeekTopologyMetrics.taskCardHeight / 2,
                groupTop,
                "任务 \(id) 的底边压到了 \(groupID) 的顶边",
                file: file,
                line: line
            )
        }
    }

    func test_suspendedCountdownPreset_defaults() {
        XCTAssertEqual(SuspendedCountdownPreset.defaultOptions, [1, 2, 3, 5, 7, 10, 30])
    }

    func test_suspendedCountdownPreset_includesCustomDefaultOnlyWhenMissing() {
        // A preset value must not be duplicated.
        XCTAssertEqual(SuspendedCountdownPreset.options(includingDefault: 7), SuspendedCountdownPreset.defaultOptions)

        // A custom default outside the presets is appended and kept sorted.
        XCTAssertEqual(SuspendedCountdownPreset.options(includingDefault: 21), [1, 2, 3, 5, 7, 10, 21, 30])
        XCTAssertEqual(SuspendedCountdownPreset.options(includingDefault: 4), [1, 2, 3, 4, 5, 7, 10, 30])

        // Non-positive values are normalized to the smallest usable preset.
        XCTAssertEqual(SuspendedCountdownPreset.options(includingDefault: 0), SuspendedCountdownPreset.defaultOptions)
        XCTAssertEqual(SuspendedCountdownPreset.options(includingDefault: -5), SuspendedCountdownPreset.defaultOptions)

        // The configured default is always selectable.
        for candidate in [1, 4, 21, 60] {
            XCTAssertTrue(
                SuspendedCountdownPreset.options(includingDefault: candidate).contains(candidate),
                "Expected the configured default \(candidate) to be selectable"
            )
        }
    }

    func test_centeredSquareSizing_usesMinDimension() {
        let size = CenteredSquareSizing.squareSide(for: CGSize(width: 390, height: 844), scale: 0.7)
        XCTAssertEqual(size, 273, accuracy: 0.01)
    }

    func test_photoLibraryAccess_canSave_onlyWhenAuthorizedOrLimited() {
        XCTAssertTrue(PhotoLibraryAccess.canSave(status: .authorized))
        XCTAssertTrue(PhotoLibraryAccess.canSave(status: .limited))
        XCTAssertFalse(PhotoLibraryAccess.canSave(status: .denied))
        XCTAssertFalse(PhotoLibraryAccess.canSave(status: .restricted))
        XCTAssertFalse(PhotoLibraryAccess.canSave(status: .notDetermined))
    }

    func test_suspendedTaskMetaFormatter_buildsDeadlineAndCounters() {
        XCTAssertEqual(SuspendedTaskMetaFormatter.deadlineText(remainingDays: 0), "今日到期")
        XCTAssertEqual(SuspendedTaskMetaFormatter.deadlineText(remainingDays: 10), "10 天后到期")
        XCTAssertEqual(SuspendedTaskMetaFormatter.stepsText(count: 3), "3 步骤")
        XCTAssertEqual(SuspendedTaskMetaFormatter.attachmentsText(count: 2), "2 附件")
    }

    func test_suspendedTaskMetaFormatter_marksOverdueSeparatelyFromDueToday() {
        let dueToday = SuspendedTaskMetaFormatter.deadlineText(remainingDays: 0)
        let overdue = SuspendedTaskMetaFormatter.deadlineText(remainingDays: -3)

        // Overdue tasks are reachable once the expiry policy keeps them, so they
        // must not be mislabelled as due today.
        XCTAssertNotEqual(overdue, dueToday)
        XCTAssertTrue(overdue.contains("3"), "Expected the overdue text to carry the day count, got: \(overdue)")

        // A single day overdue is still overdue, not due today.
        XCTAssertNotEqual(SuspendedTaskMetaFormatter.deadlineText(remainingDays: -1), dueToday)
    }

    // MARK: - Theme system

    func test_themeVisualStyle_originalThemesKeepTheClassicForm() {
        // The ten original themes must render exactly as they always have.
        // Any change here is a regression for existing users.
        let originals: [WeekTheme] = [
            .amber, .ocean, .forest, .rose, .lavender,
            .graphite, .sunset, .mint, .midnight, .lotr
        ]
        for theme in originals {
            XCTAssertEqual(theme.visualStyle, .classic, "\(theme.rawValue) must keep the classic form")
            XCTAssertEqual(theme.visualStyle.symbolVariant, .none, "\(theme.rawValue) must keep outline icons")
            XCTAssertNil(theme.visualStyle.borderColorHexLight, "\(theme.rawValue) must not set a custom border")
        }
    }

    func test_themeVisualStyle_personalisedThemesOverrideTheForm() {
        XCTAssertEqual(WeekTheme.brutal.visualStyle, .brutalist)
        XCTAssertEqual(WeekTheme.neon.visualStyle, .neon)
        XCTAssertEqual(WeekTheme.paper.visualStyle, .paper)
        XCTAssertEqual(WeekTheme.terminal.visualStyle, .terminal)

        // Brutalist is defined by a hard (unblurred) offset shadow.
        XCTAssertEqual(WeekTheme.brutal.visualStyle.shadow?.radius, 0)
        // Flat themes must not silently fall back to the classic diffuse shadow.
        XCTAssertEqual(WeekTheme.paper.visualStyle.shadow, .flat)
        XCTAssertEqual(WeekTheme.terminal.visualStyle.shadow, .flat)

        XCTAssertEqual(WeekTheme.brutal.visualStyle.symbolVariant, .fill)
        XCTAssertEqual(WeekTheme.neon.visualStyle.symbolVariant, .fill)
        XCTAssertEqual(WeekTheme.paper.visualStyle.symbolVariant, .none)
        XCTAssertEqual(WeekTheme.terminal.visualStyle.symbolVariant, .fill)

        // Every personalised theme must differ from the classic form,
        // otherwise it is just a recolour wearing a new name.
        for theme in WeekTheme.allCases where theme.visualStyle != .classic {
            XCTAssertTrue(
                [.brutal, .neon, .paper, .terminal].contains(theme),
                "\(theme.rawValue) changed the visual form without being a personalised theme"
            )
        }
    }

    /// `barScale` is a multiplier precisely so `.classic` stays untouched:
    /// call sites pass 4, 8 and 12 points and all three must come back unchanged.
    func test_themeVisualStyle_classicBarScalePreservesOriginalThickness() {
        let style = ThemeVisualStyle.classic

        XCTAssertEqual(style.barThickness(8), 8, accuracy: 0.001)
        XCTAssertEqual(style.barThickness(12), 12, accuracy: 0.001)
        XCTAssertEqual(style.barThickness(4), 4, accuracy: 0.001)
        // nil corner radius keeps the original pill shape.
        XCTAssertEqual(style.barCornerRadius(for: 8), 4, accuracy: 0.001)
    }

    /// The settings picker swatch is derived from the card form. The factors are
    /// tuned so `.classic` reproduces the 7pt / 0.5pt swatch it has always had —
    /// if someone retunes them, the originals change appearance in the picker.
    func test_themeVisualStyle_classicSwatchKeepsOriginalMetrics() {
        let style = ThemeVisualStyle.classic
        XCTAssertEqual(style.swatchRadius, 7, accuracy: 0.001)
        XCTAssertEqual(style.swatchBorderWidth, 0.5, accuracy: 0.001)
    }

    func test_themeVisualStyle_personalisedThemesReshapeBars() {
        let brutal = WeekTheme.brutal.visualStyle
        XCTAssertEqual(brutal.barThickness(8), 12, accuracy: 0.001)
        XCTAssertEqual(brutal.barCornerRadius(for: 12), 0, accuracy: 0.001)

        let paper = WeekTheme.paper.visualStyle
        XCTAssertEqual(paper.barThickness(8), 4.8, accuracy: 0.001)
        XCTAssertEqual(paper.barCornerRadius(for: 4.8), 0.5, accuracy: 0.001)

        let terminal = WeekTheme.terminal.visualStyle
        XCTAssertEqual(terminal.barThickness(8), 6.4, accuracy: 0.001)
        XCTAssertEqual(terminal.barCornerRadius(for: 6.4), 0, accuracy: 0.001)
    }

    /// `.circle` and `.square` are not used by any shipped theme yet, but they
    /// are part of the mechanism — pin the mapping so adding one is a one-liner.
    func test_themeSymbolVariant_mapsToSwiftUISymbolVariants() {
        XCTAssertEqual(ThemeSymbolVariant.none.symbolVariants, .none)
        XCTAssertEqual(ThemeSymbolVariant.fill.symbolVariants, .fill)
        XCTAssertEqual(ThemeSymbolVariant.circle.symbolVariants, .circle)
        XCTAssertEqual(ThemeSymbolVariant.square.symbolVariants, .square)
    }

    func test_themePalette_everyThemeHasCompleteHexValuesInBothAppearances() {
        // Adding a theme means hand-writing 40 hex values; this catches typos
        // and missed fields across every theme, past and future.
        for theme in WeekTheme.allCases {
            for mode in AppearanceMode.allCases {
                let palette = theme.palette(for: mode, systemIsDark: mode == .dark)
                let values = Mirror(reflecting: palette).children.compactMap { $0.value as? String }

                XCTAssertEqual(
                    values.count, 20,
                    "\(theme.rawValue)/\(mode.rawValue): expected 20 palette fields, got \(values.count)"
                )
                for value in values {
                    XCTAssertTrue(
                        value.hasPrefix("#") && value.count == 7,
                        "\(theme.rawValue)/\(mode.rawValue): '\(value)' is not a #RRGGBB colour"
                    )
                }
            }
        }
    }

    func test_arrayMove_ignoresOutOfRangeInputs() {
        var values = ["A", "B", "C"]
        values.move(fromOffsets: IndexSet(integer: 4), toOffset: 10)
        XCTAssertEqual(values, ["A", "B", "C"])

        values.move(fromOffsets: IndexSet(integer: 1), toOffset: -1)
        XCTAssertEqual(values, ["B", "A", "C"])
    }

    @MainActor
    func test_createProjectAppliesRequestedDefaultTileSize() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        let viewModel = ExtensionsViewModel(modelContext: context)

        let project = viewModel.createProject(
            name: "Wide project",
            description: "",
            color: "#C46A1A",
            icon: "folder.fill",
            startDate: today,
            endDate: today.addingDays(7),
            tileSize: .wide
        )

        XCTAssertEqual(project?.tileSize.rawValue, ProjectTileSize.wide.rawValue)
    }

    @MainActor
    func test_projectCannotReceiveTasksAfterCompletion() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        let project = ProjectModel(name: "Closed", status: .completed, startDate: today, endDate: today.addingDays(7))
        context.insert(project)
        try context.save()

        let viewModel = ExtensionsViewModel(modelContext: context)
        let result = viewModel.addTask(to: project, title: "Should not exist", taskType: .regular, on: today)

        XCTAssertNil(result)
        XCTAssertEqual(project.tasks.count, 0)
        XCTAssertEqual(viewModel.errorMessage, WeekyiiError.projectReadOnly.localizedDescription)
    }

    @MainActor
    func test_projectCannotInsertDraftTaskIntoExecutingDay() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        let week = WeekCalculator().makeWeek(for: today, status: .present)
        let day = try XCTUnwrap(week.days.first { $0.dayId == today.dayId })
        day.status = .execute
        let focus = TaskItem(title: "Focus", order: 1, zone: .focus)
        focus.day = day
        day.tasks.append(focus)
        let project = ProjectModel(name: "Active", status: .active, startDate: today, endDate: today.addingDays(7))
        context.insert(week)
        context.insert(project)
        try context.save()

        let viewModel = ExtensionsViewModel(modelContext: context)
        let result = viewModel.addTask(to: project, title: "Late draft", taskType: .regular, on: today)

        XCTAssertNil(result)
        XCTAssertEqual(day.sortedDraftTasks.count, 0)
        XCTAssertEqual(viewModel.errorMessage, WeekyiiError.projectTaskStateLocked.localizedDescription)
    }

    @MainActor
    func test_projectCannotCompleteWithOpenTasks() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        let project = ProjectModel(name: "Active", status: .active, startDate: today, endDate: today.addingDays(7))
        let task = TaskItem(title: "Open", order: 1, zone: .draft)
        task.project = project
        project.tasks = [task]
        context.insert(project)
        try context.save()

        let viewModel = ExtensionsViewModel(modelContext: context)
        viewModel.updateStatus(project, to: .completed)

        XCTAssertEqual(project.status, .active)
        XCTAssertEqual(viewModel.errorMessage, WeekyiiError.projectHasOpenTasks.localizedDescription)
    }

    @MainActor
    func test_projectDetailSnapshot_countsAndNextTaskFromUpcomingDate() throws {
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        let yesterday = today.addingDays(-1)
        let tomorrow = today.addingDays(1)

        let project = ProjectModel(name: "Launch", startDate: yesterday, endDate: tomorrow.addingDays(5))

        let pastDay = DayModel(dayId: yesterday.dayId, date: yesterday, status: .draft)
        let todayDay = DayModel(dayId: today.dayId, date: today, status: .draft)
        let tomorrowDay = DayModel(dayId: tomorrow.dayId, date: tomorrow, status: .draft)

        let completed = TaskItem(title: "Done", order: 1, zone: .complete)
        completed.day = pastDay
        completed.project = project

        let pastPending = TaskItem(title: "Past pending", order: 2, zone: .draft)
        pastPending.day = pastDay
        pastPending.project = project

        let nextTask = TaskItem(title: "Ship release", order: 3, zone: .draft)
        nextTask.day = tomorrowDay
        nextTask.project = project

        let todayTask = TaskItem(title: "Review docs", order: 1, zone: .draft)
        todayTask.day = todayDay
        todayTask.project = project

        project.tasks = [completed, pastPending, nextTask, todayTask]

        let snapshot = ProjectDetailComposer.projectDetailSnapshot(
            project: project,
            calendar: Calendar(identifier: .iso8601),
            referenceDate: today
        )

        XCTAssertEqual(snapshot.totalCount, 4)
        XCTAssertEqual(snapshot.completedCount, 1)
        XCTAssertEqual(snapshot.remainingCount, 3)
        XCTAssertEqual(snapshot.nextTaskTitle, "Review docs")
        XCTAssertEqual(snapshot.nextTaskDate?.dayId, today.dayId)
    }

    @MainActor
    func test_projectTaskLedgerSections_expandsTodayAndFutureByDefault() throws {
        let today = Calendar(identifier: .iso8601).startOfDay(for: Date())
        let yesterday = today.addingDays(-1)
        let tomorrow = today.addingDays(1)

        let project = ProjectModel(name: "Ledger", startDate: yesterday, endDate: tomorrow.addingDays(5))

        let pastDay = DayModel(dayId: yesterday.dayId, date: yesterday, status: .draft)
        let todayDay = DayModel(dayId: today.dayId, date: today, status: .draft)
        let tomorrowDay = DayModel(dayId: tomorrow.dayId, date: tomorrow, status: .draft)

        let pastTask = TaskItem(title: "Past", order: 1, zone: .draft)
        pastTask.day = pastDay
        let todayTask = TaskItem(title: "Today", order: 1, zone: .draft)
        todayTask.day = todayDay
        let futureTask = TaskItem(title: "Future", order: 1, zone: .draft)
        futureTask.day = tomorrowDay

        project.tasks = [pastTask, todayTask, futureTask]

        let sections = ProjectDetailComposer.projectTaskLedgerSections(
            project: project,
            calendar: Calendar(identifier: .iso8601),
            referenceDate: today
        )

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].date.dayId, yesterday.dayId)
        XCTAssertEqual(sections[1].date.dayId, today.dayId)
        XCTAssertEqual(sections[2].date.dayId, tomorrow.dayId)
        XCTAssertFalse(sections[0].isExpandedByDefault)
        XCTAssertTrue(sections[1].isExpandedByDefault)
        XCTAssertTrue(sections[2].isExpandedByDefault)
    }

    func test_widgetSnapshotComposer_buildsPriorityOrderedPreviewAndTheme() {
        let now = makeDate(2026, 3, 16, 9, 30)
        let day = DayModel(dayId: "2026-03-16", date: now, status: .execute)
        day.killTimeHour = 23
        day.killTimeMinute = 45

        day.tasks.append(TaskItem(title: "Focus task", order: 1, zone: .focus))
        day.tasks.append(TaskItem(title: "Frozen task", order: 2, zone: .frozen))
        day.tasks.append(TaskItem(title: "Draft task", order: 3, zone: .draft))
        let completed = TaskItem(title: "Done task", order: 4, zone: .complete)
        completed.completedOrder = 1
        day.tasks.append(completed)

        let week = WeekModel(
            weekId: now.weekId,
            startDate: now.startOfWeek,
            endDate: now.startOfWeek.addingDays(6),
            status: .present
        )
        week.days = [day]

        let snapshot = WidgetSnapshotComposer.makeSnapshot(
            now: now,
            selectedTheme: WeekTheme.rose,
            appearanceMode: .dark,
            today: day,
            presentWeek: week
        )

        XCTAssertEqual(snapshot.today.totalCount, 4)
        XCTAssertEqual(snapshot.today.completedCount, 1)
        XCTAssertEqual(snapshot.today.completionPercent, 25)
        XCTAssertEqual(snapshot.today.focusTitle, "Focus task")
        XCTAssertEqual(snapshot.today.previewTasks.map(\.title), ["Focus task", "Frozen task", "Draft task"])
        XCTAssertEqual(snapshot.theme.primaryHex, WeekTheme.rose.primaryThemeHex)
        XCTAssertEqual(snapshot.theme.appearanceMode, .dark)
        XCTAssertEqual(snapshot.weekDays.count, 7)
    }

    func test_widgetThemeSnapshot_decodesLegacyPayloadWithoutDarkFields() throws {
        let legacyJSON = """
        {
          "primaryHex":"#111111",
          "primaryLightHex":"#222222",
          "accentHex":"#333333",
          "backgroundHex":"#444444",
          "textPrimaryHex":"#555555",
          "textSecondaryHex":"#666666"
        }
        """

        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(WidgetThemeSnapshot.self, from: data)

        XCTAssertEqual(decoded.darkPrimaryHex, "#111111")
        XCTAssertEqual(decoded.darkBackgroundHex, "#444444")
        XCTAssertEqual(decoded.appearanceMode, .system)
    }

    func test_widgetThemeSnapshot_resolvesPaletteForForcedDarkMode() {
        let theme = WidgetThemeSnapshot(
            primaryHex: "#101010",
            primaryLightHex: "#202020",
            accentHex: "#303030",
            backgroundHex: "#404040",
            textPrimaryHex: "#505050",
            textSecondaryHex: "#606060",
            darkPrimaryHex: "#AAAAAA",
            darkPrimaryLightHex: "#BBBBBB",
            darkAccentHex: "#CCCCCC",
            darkBackgroundHex: "#DDDDDD",
            darkTextPrimaryHex: "#EEEEEE",
            darkTextSecondaryHex: "#FFFFFF",
            appearanceModeRaw: AppearanceMode.dark.rawValue
        )

        let palette = theme.resolvedPalette(isDarkSystem: false)

        XCTAssertEqual(palette.primaryHex, "#AAAAAA")
        XCTAssertEqual(palette.backgroundHex, "#DDDDDD")
    }

    func test_lotrWidgetThemeSnapshot_usesPremiumPalette() {
        let snapshot = WeekTheme.lotr.widgetThemeSnapshot(appearanceMode: .system)

        XCTAssertEqual(snapshot.primaryHex, WeekTheme.lotr.primaryThemeHex)
        XCTAssertEqual(snapshot.darkBackgroundHex, "#101411")
        XCTAssertEqual(snapshot.darkTextPrimaryHex, "#E6DECf")
    }

    func test_liveActivityThemeSnapshot_resolvesLockPaletteForForcedDarkMode() {
        let theme = LiveActivityThemeSnapshot(
            islandTextPrimaryHex: "#111111",
            islandTextSecondaryHex: "#222222",
            islandAccentHex: "#333333",
            islandWarningHex: "#444444",
            islandSuccessHex: "#555555",
            islandChipPrimaryHex: "#666666",
            islandChipSecondaryHex: "#777777",
            islandKeylineHex: "#888888",
            lockBackgroundHex: "#AAAAAA",
            lockSurfaceHex: "#BBBBBB",
            lockTextPrimaryHex: "#CCCCCC",
            lockTextSecondaryHex: "#DDDDDD",
            lockAccentHex: "#EEEEEE",
            lockProgressTrackHex: "#999999",
            darkLockBackgroundHex: "#101010",
            darkLockSurfaceHex: "#202020",
            darkLockTextPrimaryHex: "#EFEFEF",
            darkLockTextSecondaryHex: "#DFDFDF",
            darkLockAccentHex: "#CFCFCF",
            darkLockProgressTrackHex: "#303030",
            appearanceModeRaw: AppearanceMode.dark.rawValue
        )

        let palette = theme.resolvedLockPalette(prefersDarkLock: true)

        XCTAssertEqual(palette.backgroundHex, "#101010")
        XCTAssertEqual(palette.textPrimaryHex, "#EFEFEF")
        XCTAssertEqual(palette.progressTrackHex, "#303030")
    }

    func test_lotrLiveActivityThemeSnapshot_usesDarkIslandContrastAndResolvedLockPalette() {
        let snapshot = WeekTheme.lotr.liveActivityThemeSnapshot(appearanceMode: .system)
        let darkLockPalette = snapshot.resolvedLockPalette(prefersDarkLock: true)

        XCTAssertEqual(snapshot.islandTextPrimaryHex, "#E6DECf")
        XCTAssertEqual(snapshot.islandKeylineHex, "#C6AA79")
        XCTAssertEqual(darkLockPalette.backgroundHex, "#101411")
        XCTAssertEqual(darkLockPalette.textPrimaryHex, "#E6DECf")
    }

    func test_widgetSnapshotStore_roundTrip() throws {
        let snapshot = WidgetSnapshot(
            generatedAt: makeDate(2026, 3, 16, 10, 0),
            theme: .init(primaryHex: "#111111", primaryLightHex: "#222222", accentHex: "#333333", backgroundHex: "#444444", textPrimaryHex: "#555555", textSecondaryHex: "#666666"),
            today: .init(
                dayId: "2026-03-16",
                weekdaySymbol: "Mon",
                statusRaw: DayStatus.execute.rawValue,
                killTimeText: "23:45",
                focusTitle: "Ship widget",
                totalCount: 5,
                completedCount: 2,
                draftCount: 1,
                frozenCount: 2,
                completionPercent: 40,
                previewTasks: [
                    .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!, title: "Ship widget", taskTypeRaw: TaskType.regular.rawValue, zoneRaw: TaskZone.focus.rawValue)
                ]
            ),
            weekDays: []
        )

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let store = WidgetSnapshotStore(directoryURL: dir)
        try store.save(snapshot)
        let loaded = try XCTUnwrap(store.load())

        XCTAssertEqual(loaded, snapshot)
    }

    @MainActor
    func test_pendingWeekOutlook_relaxedTone() {
        let week = makeOutlookWeek(
            regular: [1, 1, 1, 0, 0, 0, 0],
            ddl: [0, 0, 0, 0, 0, 0, 0],
            leisure: [0, 0, 0, 0, 0, 0, 0]
        )

        let outlook = PendingViewModel.buildWeekOutlook(for: week)

        XCTAssertEqual(outlook.tone, .relaxed)
        XCTAssertEqual(outlook.typeCounts.regular, 3)
        XCTAssertEqual(outlook.dayLoadSeries.count, 7)
    }

    @MainActor
    func test_pendingWeekOutlook_overloadByPeakThreshold() {
        let week = makeOutlookWeek(
            regular: [0, 0, 0, 0, 0, 0, 0],
            ddl: [4, 0, 0, 0, 0, 0, 0],
            leisure: [0, 0, 0, 0, 0, 0, 0]
        )

        let outlook = PendingViewModel.buildWeekOutlook(for: week)

        XCTAssertEqual(outlook.tone, .overloadWarning)
        XCTAssertEqual(outlook.typeCounts.ddl, 4)
    }

    @MainActor
    func test_pendingWeekOutlook_belowPeakThresholdDoesNotTriggerOverload() {
        let week = makeOutlookWeek(
            regular: [7, 0, 0, 0, 0, 0, 0],
            ddl: [0, 0, 0, 0, 0, 0, 0],
            leisure: [1, 0, 0, 0, 0, 0, 0]
        )

        let outlook = PendingViewModel.buildWeekOutlook(for: week)

        XCTAssertEqual(outlook.tone, .steady)
    }

    @MainActor
    func test_pendingWeekOutlook_deadlineRushRequiresTwoDayCluster() {
        let clusteredWeek = makeOutlookWeek(
            regular: [0, 0, 0, 0, 0, 0, 0],
            ddl: [2, 2, 0, 0, 0, 0, 0],
            leisure: [0, 0, 0, 0, 0, 0, 0]
        )
        let distributedWeek = makeOutlookWeek(
            regular: [0, 0, 0, 0, 0, 0, 0],
            ddl: [1, 0, 1, 0, 1, 0, 1],
            leisure: [0, 0, 0, 0, 0, 0, 0]
        )

        let clusteredOutlook = PendingViewModel.buildWeekOutlook(for: clusteredWeek)
        let distributedOutlook = PendingViewModel.buildWeekOutlook(for: distributedWeek)

        XCTAssertEqual(clusteredOutlook.tone, .deadlineRush)
        XCTAssertEqual(distributedOutlook.tone, .steady)
    }

    @MainActor
    func test_pendingWeekOutlook_midweekCongestionTone() {
        let week = makeOutlookWeek(
            regular: [1, 0, 5, 5, 4, 0, 0],
            ddl: [0, 0, 0, 0, 0, 0, 0],
            leisure: [0, 0, 0, 0, 0, 0, 0]
        )

        let outlook = PendingViewModel.buildWeekOutlook(for: week)

        XCTAssertEqual(outlook.tone, .midweekCongestion)
    }

    @MainActor
    func test_pendingWeekOutlook_frontLooseBackTightTone() {
        let week = makeOutlookWeek(
            regular: [1, 1, 1, 2, 2, 2, 2],
            ddl: [0, 0, 0, 0, 0, 0, 0],
            leisure: [0, 0, 0, 0, 0, 0, 0]
        )

        let outlook = PendingViewModel.buildWeekOutlook(for: week)

        XCTAssertEqual(outlook.tone, .frontLooseBackTight)
    }

    private func makeTemporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("Weekyii.store")
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date ?? Date()
    }

    private func makeOutlookWeek(regular: [Int], ddl: [Int], leisure: [Int]) -> WeekModel {
        precondition(regular.count == 7 && ddl.count == 7 && leisure.count == 7)
        let start = makeDate(2026, 3, 30)
        let week = WeekModel(
            weekId: start.weekId,
            startDate: start,
            endDate: start.addingDays(6),
            status: .pending
        )

        for index in 0..<7 {
            let dayDate = start.addingDays(index)
            let day = DayModel(dayId: dayDate.dayId, date: dayDate, status: .draft)
            day.week = week

            var order = 1
            for _ in 0..<regular[index] {
                day.tasks.append(TaskItem(title: "R\(order)", taskType: .regular, order: order, zone: .draft))
                order += 1
            }
            for _ in 0..<ddl[index] {
                day.tasks.append(TaskItem(title: "D\(order)", taskType: .ddl, order: order, zone: .draft))
                order += 1
            }
            for _ in 0..<leisure[index] {
                day.tasks.append(TaskItem(title: "L\(order)", taskType: .leisure, order: order, zone: .draft))
                order += 1
            }

            week.days.append(day)
        }
        return week
    }

    private func makeTileSnapshot(projectID: UUID, nextTaskTitle: String?) -> ProjectTileSnapshot {
        ProjectTileSnapshot(
            projectID: projectID,
            name: "Project",
            icon: "folder.fill",
            colorHex: "#C46A1A",
            progress: 0.4,
            completedCount: 2,
            totalCount: 5,
            remainingCount: 3,
            expiredCount: 1,
            nextTaskTitle: nextTaskTitle,
            nextTaskDate: nextTaskTitle == nil ? nil : Date(timeIntervalSince1970: 1_762_444_800)
        )
    }
}

@MainActor
final class TaskPostponeServiceTests: XCTestCase {
    private static var retainedUserSettings: [UserSettings] = []
    private var container: ModelContainer!

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: WeekyiiSchemaV4.self)
        let config = ModelConfiguration(
            "TaskPostponeServiceTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: config)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try Self.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    func test_preview_requiresWeekCreationWhenTargetWeekMissing() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft
        let task = TaskItem(title: "Read", order: 1, zone: .draft)
        todayDay.tasks.append(task)
        try context.save()

        let targetDate = today.addingDays(10)
        let preview = try service.preview(taskID: task.id, targetDate: targetDate, today: today)

        XCTAssertTrue(preview.requiresWeekCreation)
        XCTAssertEqual(preview.targetWeekId, targetDate.weekId)
        XCTAssertEqual(preview.targetDayId, targetDate.dayId)
    }

    func test_preview_rejectsProjectTaskBeyondProjectEndDate() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let week = WeekCalculator().makeWeek(for: today, status: .present)
        let day = requireDay(in: week, date: today)
        day.status = .draft
        let project = ProjectModel(name: "Bounded", status: .active, startDate: today, endDate: today.addingDays(2))
        let task = TaskItem(title: "Project task", order: 1, zone: .draft)
        task.project = project
        day.tasks.append(task)
        context.insert(week)
        context.insert(project)
        try context.save()

        XCTAssertThrowsError(try service.preview(taskID: task.id, targetDate: today.addingDays(3), today: today)) { error in
            guard let weekyiiError = error as? WeekyiiError else {
                return XCTFail("Expected WeekyiiError, received \(error)")
            }
            XCTAssertEqual(weekyiiError, .projectDateOutOfRange)
        }
    }

    func test_serviceLifecycle_withoutUsage() throws {
        let context = container.mainContext
        _ = TaskPostponeService(modelContext: context)
    }

    func test_emptySmoke() {
        XCTAssertTrue(true)
    }

    func test_execute_movesDraftTaskToTargetDraftTailAndPreservesMetadata() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 10, 15)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft

        let project = ProjectModel(
            name: "P",
            startDate: today.addingDays(-1),
            endDate: today.addingDays(30)
        )
        context.insert(project)

        let sourceTask = TaskItem(title: "Source", order: 1, zone: .draft)
        sourceTask.steps.append(TaskStep(title: "S1", sortOrder: 0))
        sourceTask.project = project
        sourceTask.startedAt = makeDate(2026, 3, 5, 8, 30)
        sourceTask.endedAt = makeDate(2026, 3, 5, 9, 0)
        sourceTask.completedOrder = 99
        todayDay.tasks.append(sourceTask)

        let targetDate = today.addingDays(1)
        let targetDay = requireDay(in: todayWeek, date: targetDate)
        targetDay.status = .draft
        targetDay.tasks.append(TaskItem(title: "Existing", order: 1, zone: .draft))
        try context.save()

        let preview = try service.preview(taskID: sourceTask.id, targetDate: targetDate, today: today)
        let result = try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)

        XCTAssertFalse(result.createdWeek)
        XCTAssertEqual(result.sourceDayId, today.dayId)
        XCTAssertEqual(result.targetDayId, targetDate.dayId)
        XCTAssertEqual(todayDay.status, .empty)
        XCTAssertTrue(todayDay.tasks.isEmpty)

        let movedTask = targetDay.sortedDraftTasks.last
        XCTAssertNotNil(movedTask)
        XCTAssertEqual(movedTask?.title, "Source")
        XCTAssertEqual(movedTask?.zone, .draft)
        XCTAssertEqual(movedTask?.order, 2)
        XCTAssertEqual(movedTask?.startedAt, nil)
        XCTAssertEqual(movedTask?.endedAt, nil)
        XCTAssertEqual(movedTask?.completedOrder, 0)
        XCTAssertEqual(movedTask?.steps.count, 1)
        XCTAssertEqual(movedTask?.steps.first?.title, "S1")
        XCTAssertTrue(movedTask?.project === project)
    }

    func test_execute_fromFocusPromotesNextFrozenToFocus() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 14, 20)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .execute

        let focus = TaskItem(title: "Focus", order: 1, zone: .focus)
        focus.startedAt = makeDate(2026, 3, 5, 13, 0)
        let frozen = TaskItem(title: "FrozenNext", order: 2, zone: .frozen)
        todayDay.tasks.append(focus)
        todayDay.tasks.append(frozen)

        let targetDate = today.addingDays(1)
        let targetDay = requireDay(in: todayWeek, date: targetDate)
        targetDay.status = .draft
        try context.save()

        let preview = try service.preview(taskID: focus.id, targetDate: targetDate, today: today)
        _ = try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)

        XCTAssertEqual(todayDay.status, .execute)
        XCTAssertTrue(todayDay.focusTask === frozen)
        XCTAssertEqual(todayDay.focusTask?.zone, .focus)
        XCTAssertEqual(todayDay.focusTask?.order, 1)
        XCTAssertEqual(todayDay.focusTask?.startedAt, now)
        XCTAssertTrue(todayDay.frozenTasks.isEmpty)
        XCTAssertTrue(targetDay.sortedDraftTasks.contains(where: { $0.title == "Focus" }))
    }

    func test_execute_fromFrozenRenumbersRemainingExecutionQueue() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 15, 5)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .execute

        let focus = TaskItem(title: "Focus", order: 1, zone: .focus)
        let frozenA = TaskItem(title: "FrozenA", order: 2, zone: .frozen)
        let frozenB = TaskItem(title: "FrozenB", order: 3, zone: .frozen)
        todayDay.tasks.append(focus)
        todayDay.tasks.append(frozenA)
        todayDay.tasks.append(frozenB)

        let targetDate = today.addingDays(1)
        let targetDay = requireDay(in: todayWeek, date: targetDate)
        targetDay.status = .draft
        try context.save()

        let preview = try service.preview(taskID: frozenA.id, targetDate: targetDate, today: today)
        _ = try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)

        XCTAssertEqual(todayDay.status, .execute)
        XCTAssertTrue(todayDay.focusTask === focus)
        XCTAssertEqual(todayDay.focusTask?.order, 1)
        XCTAssertEqual(todayDay.frozenTasks.count, 1)
        XCTAssertTrue(todayDay.frozenTasks.first === frozenB)
        XCTAssertEqual(todayDay.frozenTasks.first?.order, 2)
        XCTAssertTrue(targetDay.sortedDraftTasks.contains(where: { $0.title == "FrozenA" }))
    }

    func test_execute_fromFocusWithoutFrozenMarksSourceCompleted() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 16, 30)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .execute

        let focus = TaskItem(title: "SoloFocus", order: 1, zone: .focus)
        todayDay.tasks.append(focus)

        let targetDate = today.addingDays(1)
        let targetDay = requireDay(in: todayWeek, date: targetDate)
        targetDay.status = .draft
        try context.save()

        let preview = try service.preview(taskID: focus.id, targetDate: targetDate, today: today)
        _ = try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)

        XCTAssertEqual(todayDay.status, .completed)
        XCTAssertEqual(todayDay.closedAt, now)
        XCTAssertNil(todayDay.focusTask)
        XCTAssertTrue(todayDay.frozenTasks.isEmpty)
    }

    func test_execute_implicitlyCreatesTargetDayWhenWeekExistsWithoutDay() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 18, 0)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft
        let sourceTask = TaskItem(title: "MoveMe", order: 1, zone: .draft)
        todayDay.tasks.append(sourceTask)

        let targetDate = today.addingDays(10)
        let targetWeek = WeekCalculator().makeWeek(for: targetDate, status: .pending)
        targetWeek.days.removeAll { $0.dayId == targetDate.dayId }
        context.insert(targetWeek)
        try context.save()

        let preview = try service.preview(taskID: sourceTask.id, targetDate: targetDate, today: today)
        XCTAssertFalse(preview.requiresWeekCreation)

        let result = try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)
        XCTAssertFalse(result.createdWeek)
        let createdTargetDay = targetWeek.days.first(where: { $0.dayId == targetDate.dayId })
        XCTAssertNotNil(createdTargetDay)
        XCTAssertEqual(createdTargetDay?.status, .draft)
        XCTAssertEqual(createdTargetDay?.sortedDraftTasks.count, 1)
        XCTAssertEqual(createdTargetDay?.sortedDraftTasks.first?.title, "MoveMe")
    }

    func test_execute_requiresConfirmationToCreateMissingWeek() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 19, 0)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft
        let sourceTask = TaskItem(title: "MissingWeek", order: 1, zone: .draft)
        todayDay.tasks.append(sourceTask)
        try context.save()

        let targetDate = today.addingDays(14)
        let preview = try service.preview(taskID: sourceTask.id, targetDate: targetDate, today: today)
        XCTAssertTrue(preview.requiresWeekCreation)

        XCTAssertThrowsError(
            try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)
        ) { error in
            guard case WeekyiiError.postponeTargetDayUnavailable = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }

        let result = try service.execute(preview: preview, allowCreateWeek: true, today: today, now: now)
        XCTAssertTrue(result.createdWeek)

        let targetWeekId = preview.targetWeekId
        let createdWeek = try context.fetch(FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == targetWeekId })).first
        XCTAssertEqual(createdWeek?.status, .pending)
        let createdDay = createdWeek?.days.first(where: { $0.dayId == targetDate.dayId })
        XCTAssertEqual(createdDay?.status, .draft)
        XCTAssertEqual(createdDay?.sortedDraftTasks.first?.title, "MissingWeek")
    }

    func test_pendingViewModel_onlyIncludesWeeksAfterCurrentWeek() {
        let today = makeDate(2026, 6, 21, 13, 14)
        let stalePendingWeek = WeekCalculator().makeWeek(for: today.addingDays(-14), status: .pending)
        let currentPendingWeek = WeekCalculator().makeWeek(for: today, status: .pending)
        let futurePendingWeek = WeekCalculator().makeWeek(for: today.addingDays(7), status: .pending)

        XCTAssertFalse(PendingViewModel.isFutureWeek(stalePendingWeek, relativeTo: today))
        XCTAssertFalse(PendingViewModel.isFutureWeek(currentPendingWeek, relativeTo: today))
        XCTAssertTrue(PendingViewModel.isFutureWeek(futurePendingWeek, relativeTo: today))
    }

    @MainActor
    func test_pendingViewModel_addDraftTaskTurnsEmptyDayIntoDraft() throws {
        throw XCTSkip("Temporarily skipped: SwiftData crashes on iOS 26.2 simulator in this unit path; behavior is covered by pending-week UI tests.")
        let context = container.mainContext
        let viewModel = PendingViewModel(modelContext: context)
        let futureDate = makeDate(2026, 3, 20)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        XCTAssertEqual(day.status, .empty)

        try viewModel.addDraftTask(
            to: day,
            title: "Plan review",
            description: "Check milestones",
            type: .ddl,
            steps: [],
            attachments: []
        )
        let draftTasks = day.sortedDraftTasks
        XCTAssertEqual(day.status, .draft)
        XCTAssertEqual(draftTasks.count, 1)
        XCTAssertEqual(draftTasks.first?.title, "Plan review")
        XCTAssertEqual(draftTasks.first?.taskType, .ddl)
    }

    @MainActor
    func test_pendingViewModel_updateDraftTaskRewritesFields() throws {
        throw XCTSkip("Temporarily skipped: SwiftData crashes on iOS 26.2 simulator in this unit path; behavior is covered by pending-week UI tests.")
        let context = container.mainContext
        let viewModel = PendingViewModel(modelContext: context)
        let futureDate = makeDate(2026, 3, 21)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        day.status = .draft
        let task = TaskItem(title: "Old", taskDescription: "Before", taskType: .regular, order: 1, zone: .draft)
        day.tasks.append(task)
        try context.save()

        try viewModel.updateDraftTask(
            task,
            in: day,
            title: "New",
            description: "After",
            type: .leisure,
            steps: [],
            attachments: []
        )

        XCTAssertEqual(task.title, "New")
        XCTAssertEqual(task.taskDescription, "After")
        XCTAssertEqual(task.taskType, .leisure)
    }

    @MainActor
    func test_pendingViewModel_deleteDraftTasksRemovesAndRenumbers() throws {
        throw XCTSkip("Temporarily skipped: SwiftData crashes on iOS 26.2 simulator in this unit path; behavior is covered by pending-week UI tests.")
        let context = container.mainContext
        let viewModel = PendingViewModel(modelContext: context)
        let futureDate = makeDate(2026, 3, 22)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        day.status = .draft
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .draft))
        day.tasks.append(TaskItem(title: "B", order: 2, zone: .draft))
        day.tasks.append(TaskItem(title: "C", order: 3, zone: .draft))
        try context.save()

        try viewModel.deleteDraftTasks(in: day, at: IndexSet(integer: 1))

        let draftTasks = day.sortedDraftTasks
        XCTAssertEqual(draftTasks.map(\.title), ["A", "C"])
        XCTAssertEqual(draftTasks.map(\.order), [1, 2])
    }

    @MainActor
    func test_pendingViewModel_moveDraftTasksReordersDay() throws {
        throw XCTSkip("Temporarily skipped: SwiftData crashes on iOS 26.2 simulator in this unit path; behavior is covered by pending-week UI tests.")
        let context = container.mainContext
        let viewModel = PendingViewModel(modelContext: context)
        let futureDate = makeDate(2026, 3, 23)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        day.status = .draft
        day.tasks.append(TaskItem(title: "A", order: 1, zone: .draft))
        day.tasks.append(TaskItem(title: "B", order: 2, zone: .draft))
        day.tasks.append(TaskItem(title: "C", order: 3, zone: .draft))
        try context.save()

        try viewModel.moveDraftTasks(in: day, from: IndexSet(integer: 2), to: 0)

        let draftTasks = day.sortedDraftTasks
        XCTAssertEqual(draftTasks.map(\.title), ["C", "A", "B"])
        XCTAssertEqual(draftTasks.map(\.order), [1, 2, 3])
    }

    func test_preview_rejectsCompletedTask() throws {
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .completed
        let completedTask = TaskItem(title: "Done", order: 1, zone: .complete)
        todayDay.tasks.append(completedTask)
        try context.save()

        XCTAssertThrowsError(
            try service.preview(taskID: completedTask.id, targetDate: today.addingDays(1), today: today)
        ) { error in
            guard case WeekyiiError.cannotPostponeCompletedTask = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    @MainActor
    func test_dataArchiveRoundTripsAndUsesReplacementSemantics() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let suiteName = "ModelTests.Archive.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)
        let appState = AppState()

        let customType = TaskTypeDefinition(idRaw: "custom-writing", name: "写作", iconName: "pencil", colorHex: "#123456", baseKind: .ddl, sortOrder: 10)
        let project = ProjectModel(name: "归档测试", startDate: Date(), endDate: Date().addingTimeInterval(86_400))
        let week = WeekModel(weekId: "archive-week", startDate: Date(), endDate: Date().addingTimeInterval(604_800), status: .present)
        let day = DayModel(dayId: "archive-day", date: Date(), status: .draft)
        let task = TaskItem(title: "保留任务", taskType: .ddl, order: 1)
        task.taskTypeIdRaw = customType.idRaw
        task.attachments = [TaskAttachment(data: Data([0x01, 0x02, 0x03]), fileName: "proof.bin", fileType: "application/octet-stream")]
        task.day = day
        task.project = project
        day.week = week
        context.insert(customType)
        context.insert(project)
        context.insert(week)
        context.insert(day)
        context.insert(task)
        try context.save()

        let archive = try WeekyiiDataArchiveService.export(modelContext: context, settings: settings, appState: appState)
        let inspection = try WeekyiiDataArchiveService.inspect(archive)
        XCTAssertEqual(inspection.taskCount, 1)
        XCTAssertEqual(inspection.projectCount, 1)

        context.insert(TaskItem(title: "应被替换", order: 99))
        try context.save()
        _ = try WeekyiiDataArchiveService.importReplacing(
            archive,
            modelContext: context,
            settings: settings,
            appState: appState,
            storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("store")
        )

        let restoredTasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(restoredTasks.map(\.title), ["保留任务"])
        XCTAssertEqual(restoredTasks.first?.taskTypeIdRaw, "custom-writing")
        XCTAssertEqual(restoredTasks.first?.attachments.first?.data, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(restoredTasks.first?.project?.name, "归档测试")
    }

    @MainActor
    func test_dataArchiveRejectsModifiedFile() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let suiteName = "ModelTests.ArchiveCorruption.\(UUID().uuidString)"
        let settings = UserSettings(defaults: UserDefaults(suiteName: suiteName)!)
        Self.retainedUserSettings.append(settings)
        var data = try WeekyiiDataArchiveService.export(modelContext: container.mainContext, settings: settings, appState: AppState())
        data[data.count / 2] ^= 0x01
        XCTAssertThrowsError(try WeekyiiDataArchiveService.inspect(data))
    }

    private func requireDay(in week: WeekModel, date: Date) -> DayModel {
        guard let day = week.days.first(where: { $0.dayId == date.dayId }) else {
            XCTFail("Missing day \(date.dayId)")
            fatalError("Missing day")
        }
        return day
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        guard let date = components.date else {
            fatalError("Invalid date components")
        }
        return date
    }
}

@MainActor
final class SuspendedTaskLifecycleServiceTests: XCTestCase {
    private var container: ModelContainer!

    private final class TestNotificationService: NotificationScheduling {
        var scheduledTaskIDs: [UUID] = []
        var cancelledTaskIDs: [UUID] = []

        func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int, fixedReminder: DateComponents?) {}
        func cancelKillTimeNotification(for day: DayModel) {}
        func removeDeliveredKillTimeNotifications(for day: DayModel) {}

        func scheduleSuspendedTaskNotifications(for task: SuspendedTaskItem) {
            scheduledTaskIDs.append(task.id)
        }

        func cancelSuspendedTaskNotifications(for task: SuspendedTaskItem) {
            cancelledTaskIDs.append(task.id)
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WeekModel.self,
            DayModel.self,
            TaskItem.self,
            TaskStep.self,
            TaskAttachment.self,
            ProjectModel.self,
            MindStampItem.self,
            SuspendedTaskItem.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: config)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try Self.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    func test_createSuspendedTaskRequiresCountdownAndSchedulesNotifications() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let now = makeDate(2026, 3, 12, 10, 0)
        let steps = [
            TaskStep(title: "S1", sortOrder: 1),
            TaskStep(title: "S0", sortOrder: 0),
        ]
        let attachments = [
            TaskAttachment(data: Data([0x01, 0x02]), fileName: "note.png", fileType: "image/png")
        ]

        let task = try service.createTask(
            title: "Wait for venue",
            description: "Need a concrete day later.",
            type: .regular,
            taskTypeIdRaw: "custom-waiting",
            countdownDays: 10,
            steps: steps,
            attachments: attachments,
            now: now
        )

        XCTAssertEqual(task.title, "Wait for venue")
        XCTAssertEqual(task.preferredCountdownDays, 10)
        XCTAssertEqual(task.taskTypeIdRaw, "custom-waiting")
        XCTAssertEqual(
            task.steps.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.title),
            ["S0", "S1"]
        )
        XCTAssertEqual(task.attachments.count, 1)
        XCTAssertEqual(task.attachments.first?.fileName, "note.png")
        assertLocalDeadline(task.decisionDeadline, year: 2026, month: 3, day: 22)
        XCTAssertEqual(notifications.scheduledTaskIDs, [task.id])
    }

    func test_extendSuspendedTaskPushesDeadlineAndReschedulesNotifications() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let now = makeDate(2026, 3, 12, 10, 0)

        let task = try service.createTask(
            title: "Explore vendor",
            description: "",
            type: .ddl,
            countdownDays: 10,
            now: now
        )

        notifications.scheduledTaskIDs.removeAll()
        try service.extendTask(task, by: 30, now: now)

        assertLocalDeadline(task.decisionDeadline, year: 2026, month: 4, day: 21)
        XCTAssertEqual(task.snoozeCount, 1)
        XCTAssertEqual(notifications.scheduledTaskIDs, [task.id])
    }

    func test_assignSuspendedTaskAppendsToExistingDraftDayAndDeletesSource() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let today = makeDate(2026, 3, 12)
        let targetDate = makeDate(2026, 3, 14)

        let presentWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(presentWeek)
        let targetDay = requireDay(in: presentWeek, date: targetDate)
        targetDay.status = .draft
        targetDay.tasks.append(TaskItem(title: "Existing", order: 1, zone: .draft))
        let steps = [TaskStep(title: "Step A", sortOrder: 0)]
        let attachments = [TaskAttachment(data: Data([0x0A]), fileName: "proof.jpg", fileType: "image/jpeg")]

        let task = try service.createTask(
            title: "Hold for later",
            description: "Put it on a real day when ready.",
            type: .leisure,
            taskTypeIdRaw: "custom-someday",
            countdownDays: 10,
            steps: steps,
            attachments: attachments,
            now: today
        )

        try service.assignTask(task, to: targetDate, today: today)

        XCTAssertEqual(targetDay.sortedDraftTasks.map(\.title), ["Existing", "Hold for later"])
        let assigned = targetDay.sortedDraftTasks.last
        XCTAssertEqual(assigned?.steps.map(\.title), ["Step A"])
        XCTAssertEqual(assigned?.attachments.first?.fileName, "proof.jpg")
        XCTAssertEqual(assigned?.attachments.first?.fileType, "image/jpeg")
        XCTAssertEqual(assigned?.taskTypeIdRaw, "custom-someday")
        let suspended = try context.fetch(FetchDescriptor<SuspendedTaskItem>())
        XCTAssertTrue(suspended.isEmpty)
        XCTAssertEqual(notifications.cancelledTaskIDs, [task.id])
    }

    func test_assignSuspendedTaskCreatesMissingFutureWeekAndDay() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let today = makeDate(2026, 3, 12)
        let targetDate = makeDate(2026, 3, 26)

        let presentWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(presentWeek)

        let task = try service.createTask(
            title: "Decide later",
            description: "",
            type: .regular,
            countdownDays: 30,
            now: today
        )

        try service.assignTask(task, to: targetDate, today: today)

        let weekId = targetDate.weekId
        let targetWeek = try context.fetch(FetchDescriptor<WeekModel>(predicate: #Predicate { $0.weekId == weekId })).first
        XCTAssertEqual(targetWeek?.status, .pending)
        let targetDay = targetWeek?.days.first(where: { $0.dayId == targetDate.dayId })
        XCTAssertEqual(targetDay?.status, .draft)
        XCTAssertEqual(targetDay?.sortedDraftTasks.first?.title, "Decide later")
    }

    func test_sweepExpiredSuspendedTasksDeletesExpiredRecordsAndCancelsNotifications() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let now = makeDate(2026, 3, 20, 12, 0)

        let expired = SuspendedTaskItem(
            title: "Expired",
            decisionDeadline: makeDate(2026, 3, 19, 23, 59, 59),
            preferredCountdownDays: 10
        )
        let active = SuspendedTaskItem(
            title: "Active",
            decisionDeadline: makeDate(2026, 3, 25, 23, 59, 59),
            preferredCountdownDays: 10
        )
        context.insert(expired)
        context.insert(active)
        try context.save()

        let deletedCount = try service.sweepExpiredTasks(now: now)
        let remaining = try context.fetch(FetchDescriptor<SuspendedTaskItem>())

        XCTAssertEqual(deletedCount, 1)
        XCTAssertEqual(remaining.map(\.title), ["Active"])
        XCTAssertEqual(notifications.cancelledTaskIDs, [expired.id])
    }

    func test_sweepExpiredSuspendedTasksKeepsOverdueRecordsUnderKeepOverduePolicy() throws {
        let context = container.mainContext
        let notifications = TestNotificationService()
        let service = SuspendedTaskLifecycleService(modelContext: context, notificationService: notifications)
        let now = makeDate(2026, 3, 20, 12, 0)

        let expired = SuspendedTaskItem(
            title: "Expired",
            decisionDeadline: makeDate(2026, 3, 19, 23, 59, 59),
            preferredCountdownDays: 10
        )
        let active = SuspendedTaskItem(
            title: "Active",
            decisionDeadline: makeDate(2026, 3, 25, 23, 59, 59),
            preferredCountdownDays: 10
        )
        context.insert(expired)
        context.insert(active)
        try context.save()

        let deletedCount = try service.sweepExpiredTasks(now: now, policy: .keepOverdue)
        let remaining = try context.fetch(FetchDescriptor<SuspendedTaskItem>())

        // Nothing is deleted and nothing is cancelled, so the overdue record
        // stays visible in the suspended box for the user to decide on.
        XCTAssertEqual(deletedCount, 0)
        XCTAssertEqual(Set(remaining.map(\.title)), ["Expired", "Active"])
        XCTAssertTrue(notifications.cancelledTaskIDs.isEmpty)
        XCTAssertEqual(expired.status, .active)

        // Re-running is idempotent: the record is still there, still untouched.
        XCTAssertEqual(try service.sweepExpiredTasks(now: now, policy: .keepOverdue), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SuspendedTaskItem>()).count, 2)
    }

    private func requireDay(in week: WeekModel, date: Date) -> DayModel {
        guard let day = week.days.first(where: { $0.dayId == date.dayId }) else {
            XCTFail("Missing day \(date.dayId)")
            fatalError("Missing day")
        }
        return day
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        guard let date = components.date else {
            fatalError("Invalid date components")
        }
        return date
    }

    private func assertLocalDeadline(_ date: Date, year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(components.year, year)
        XCTAssertEqual(components.month, month)
        XCTAssertEqual(components.day, day)
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 59)
        XCTAssertEqual(components.second, 59)
    }
}
