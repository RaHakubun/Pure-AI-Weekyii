import XCTest
import SwiftData
import Photos
import SwiftUI
import CryptoKit
@testable import Weekyii

final class ModelTests: XCTestCase {
    private struct FixedCloudSyncEntitlementProvider: CloudSyncEntitlementProviding {
        let state: CloudSyncEntitlementState

        func currentState() async -> CloudSyncEntitlementState {
            state
        }
    }

    private static var retainedUserSettings: [UserSettings] = []
    // Deallocating an AppState inside a @MainActor test crashes the process on
    // the iOS 26.2 simulator (isolated-deinit back-deploy shim double-free);
    // archive tests therefore keep the instance alive for the whole run.
    private static var retainedAppStates: [AppState] = []

    override func tearDown() {
        // `UserSettings.save()` pushes its reminder rhythm into the shared
        // `NotificationService` singleton. Without this reset, a settings test
        // that changes the morning time or disables suspended reminders would
        // leak that rhythm into `NotificationServiceTests`, which relies on the
        // historical defaults when it does not pass an explicit configuration.
        NotificationService.shared.configuration = .default
        super.tearDown()
    }

    func test_persistentConfigurationIsCanonicalLocalAndWritable() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekyii-persistent-configuration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appendingPathComponent("Weekyii.store")

        let configuration = WeekyiiPersistence.persistentModelConfiguration(storeURL: storeURL)
        let expectedConfiguration = ModelConfiguration(
            "Weekyii",
            schema: WeekyiiPersistence.currentSchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        XCTAssertEqual(configuration, expectedConfiguration)
        XCTAssertEqual(configuration.url, storeURL)
        XCTAssertNil(configuration.cloudKitContainerIdentifier)
        XCTAssertTrue(configuration.allowsSave)
        XCTAssertFalse(configuration.isStoredInMemoryOnly)
    }

    func test_persistentURLUsesCanonicalStoreFilename() {
        let canonicalURL = WeekyiiPersistence.persistentStoreURL()
        XCTAssertEqual(canonicalURL.lastPathComponent, "Weekyii.store")
    }

    @MainActor
    func test_cloudSyncPreferenceDefaultsOffAndMigratesLegacyValuesToOff() throws {
        let freshDefaults = makeSuiteDefaults()
        let freshSettings = UserSettings(defaults: freshDefaults)
        Self.retainedUserSettings.append(freshSettings)

        XCTAssertFalse(freshSettings.cloudSyncRequested)
        XCTAssertEqual(freshDefaults.object(forKey: "cloudSyncRequested") as? Bool, false)
        XCTAssertEqual(freshDefaults.object(forKey: "weekyii.cloudSyncPreferenceMigratedV2") as? Bool, true)

        for legacyValue in [false, true] {
            let defaults = makeSuiteDefaults()
            defaults.set(legacyValue, forKey: "cloudSyncEnabled")

            let settings = UserSettings(defaults: defaults)
            Self.retainedUserSettings.append(settings)

            XCTAssertFalse(settings.cloudSyncRequested, "legacy value \(legacyValue) must not opt into explicit sync")
            XCTAssertEqual(defaults.object(forKey: "cloudSyncRequested") as? Bool, false)
            XCTAssertEqual(defaults.object(forKey: "weekyii.cloudSyncPreferenceMigratedV2") as? Bool, true)
            XCTAssertEqual(
                defaults.object(forKey: "cloudSyncEnabled") as? Bool,
                legacyValue,
                "migration must preserve the old preference as historical information"
            )
        }
    }

    @MainActor
    func test_cloudSyncPreferenceMigrationIsIdempotentAcrossUserSettingsInstances() throws {
        for legacyValue in [false, true] {
            let suite = "WeekyiiCloudSyncMigration.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(legacyValue, forKey: "cloudSyncEnabled")

            let firstSettings = UserSettings(defaults: defaults)
            // Keep MainActor-isolated settings alive for the simulator test run;
            // constructing another instance over the same suite still exercises reload.
            Self.retainedUserSettings.append(firstSettings)

            XCTAssertFalse(firstSettings.cloudSyncRequested)
            XCTAssertEqual(defaults.object(forKey: "weekyii.cloudSyncPreferenceMigratedV2") as? Bool, true)
            XCTAssertEqual(defaults.object(forKey: "cloudSyncEnabled") as? Bool, legacyValue)

            firstSettings.cloudSyncRequested = true
            XCTAssertEqual(defaults.object(forKey: "cloudSyncRequested") as? Bool, true)
            XCTAssertEqual(defaults.object(forKey: "cloudSyncEnabled") as? Bool, legacyValue)

            let secondSettings = UserSettings(defaults: defaults)
            Self.retainedUserSettings.append(secondSettings)

            XCTAssertTrue(secondSettings.cloudSyncRequested)
            XCTAssertEqual(defaults.object(forKey: "cloudSyncRequested") as? Bool, true)
            XCTAssertEqual(defaults.object(forKey: "weekyii.cloudSyncPreferenceMigratedV2") as? Bool, true)
            XCTAssertEqual(defaults.object(forKey: "cloudSyncEnabled") as? Bool, legacyValue)
        }
    }

    @MainActor
    func test_cloudSyncPreferenceSaveDoesNotRewriteLegacyValue() {
        for legacyValue in [false, true] {
            let defaults = makeSuiteDefaults()
            defaults.set(legacyValue, forKey: "cloudSyncEnabled")

            let settings = UserSettings(defaults: defaults)
            Self.retainedUserSettings.append(settings)
            settings.defaultKillTimeHour = 8
            settings.cloudSyncRequested = true

            XCTAssertEqual(defaults.object(forKey: "cloudSyncEnabled") as? Bool, legacyValue)
        }
    }

    @MainActor
    func test_cloudSyncPreferencePreservesValidV2ValueDuringMigration() {
        for requestedValue in [false, true] {
            let defaults = makeSuiteDefaults()
            defaults.set(requestedValue, forKey: "cloudSyncRequested")
            defaults.set(!requestedValue, forKey: "cloudSyncEnabled")

            let settings = UserSettings(defaults: defaults)
            Self.retainedUserSettings.append(settings)

            XCTAssertEqual(settings.cloudSyncRequested, requestedValue)
            XCTAssertEqual(defaults.object(forKey: "cloudSyncRequested") as? Bool, requestedValue)
            XCTAssertEqual(defaults.object(forKey: "weekyii.cloudSyncPreferenceMigratedV2") as? Bool, true)
        }
    }

    @MainActor
    func test_cloudSyncPreferenceChangeDoesNotTouchStoreFiles() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekyii-cloud-preference-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let canonicalURL = folder.appendingPathComponent("Weekyii.store")
        let secondaryStoreURL = folder.appendingPathComponent("secondary-store.fixture")
        let legacyBytes = Data("legacy store stays untouched".utf8)
        try legacyBytes.write(to: secondaryStoreURL)

        let suite = "WeekyiiCloudPreference.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)

        settings.setCloudSyncRequested(false)

        XCTAssertFalse(settings.cloudSyncRequested)
        XCTAssertEqual(try Data(contentsOf: secondaryStoreURL), legacyBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalURL.path))
    }

    @MainActor
    func test_openAccessEntitlementAndPreferenceControllerAreIndependentOfThemeUnlock() async {
        let lockedThemeSettings = UserSettings(defaults: makeSuiteDefaults())
        lockedThemeSettings.premiumThemeUnlocked = false
        let unlockedThemeSettings = UserSettings(defaults: makeSuiteDefaults())
        unlockedThemeSettings.premiumThemeUnlocked = true
        Self.retainedUserSettings.append(contentsOf: [lockedThemeSettings, unlockedThemeSettings])

        let openAccessProvider = OpenAccessCloudSyncEntitlementProvider()
        let lockedThemeState = await openAccessProvider.currentState()
        let unlockedThemeState = await openAccessProvider.currentState()
        XCTAssertEqual(lockedThemeState, .entitled)
        XCTAssertEqual(unlockedThemeState, .entitled)

        let defaults = makeSuiteDefaults()
        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)
        let controller = CloudSyncPreferenceController(entitlementProvider: openAccessProvider)

        let didEnable = await controller.setRequested(true, for: settings)
        XCTAssertTrue(didEnable)
        XCTAssertTrue(settings.cloudSyncRequested)
        XCTAssertEqual(defaults.object(forKey: "cloudSyncRequested") as? Bool, true)

        let didDisable = await controller.setRequested(false, for: settings)
        XCTAssertTrue(didDisable)
        XCTAssertFalse(settings.cloudSyncRequested)
        XCTAssertEqual(defaults.object(forKey: "cloudSyncRequested") as? Bool, false)
    }

    @MainActor
    func test_cloudSyncEntitlementProviderCanBeInjectedWithoutPaywallBehavior() async {
        let defaults = makeSuiteDefaults()
        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)
        let controller = CloudSyncPreferenceController(
            entitlementProvider: FixedCloudSyncEntitlementProvider(state: .notPurchased)
        )

        let saved = await controller.setRequested(true, for: settings)

        XCTAssertFalse(saved)
        XCTAssertFalse(settings.cloudSyncRequested)
        XCTAssertEqual(defaults.object(forKey: "cloudSyncRequested") as? Bool, false)
    }

    @MainActor
    func test_persistentStoreRemainsWritableAcrossReopen() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekyii-persistent-reopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let storeURL = folder.appendingPathComponent("Weekyii.store")
        do {
            let writable = try WeekyiiPersistence.makeModelContainer(
                storeURL: storeURL,
                storeMode: .persistent
            )
            let week = WeekModel(
                weekId: "2026-W38",
                startDate: Date(timeIntervalSince1970: 1_000),
                endDate: Date(timeIntervalSince1970: 2_000),
                status: .present
            )
            writable.mainContext.insert(week)
            try writable.mainContext.save()
        }

        do {
            let canonical = try WeekyiiPersistence.makeModelContainer(
                storeURL: storeURL,
                storeMode: .persistent
            )
            canonical.mainContext.insert(WeekModel(
                weekId: "canonical-write",
                startDate: Date(timeIntervalSince1970: 3_000),
                endDate: Date(timeIntervalSince1970: 4_000)
            ))
            XCTAssertNoThrow(try canonical.mainContext.save())
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        let reopened = try WeekyiiPersistence.makeModelContainer(storeURL: storeURL)
        let reopenedWeekIds = Set(try reopened.mainContext.fetch(FetchDescriptor<WeekModel>()).map(\.weekId))
        XCTAssertEqual(reopenedWeekIds, ["2026-W38", "canonical-write"])
    }

    @MainActor
    func test_bootstrapIgnoresLegacyCloudPreference() throws {
        for cloudSyncEnabled in [false, true] {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("weekyii-local-bootstrap-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let storeURL = folder.appendingPathComponent("Weekyii.store")
            let suite = "WeekyiiPersistenceBootstrap.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(cloudSyncEnabled, forKey: "cloudSyncEnabled")

            let state = WeekyiiPersistence.bootstrapPersistentContainer(
                storeURL: storeURL,
                defaults: defaults
            )

            guard case .ready = state else {
                XCTFail("The legacy cloud preference must not block local launch")
                continue
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        }
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

    private func makeSuiteDefaults(name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor
    func test_terminalDay_hidesOpenZonesWithoutDeletingRawTasks() {
        let day = DayModel(dayId: "2026-09-19", date: makeDate(2026, 9, 19), status: .completed)
        let draft = TaskItem(title: "迟到的草稿", order: 1, zone: .draft)
        let focus = TaskItem(title: "迟到的专注", order: 2, zone: .focus)
        let frozen = TaskItem(title: "迟到的冻结", order: 3, zone: .frozen)
        let complete = TaskItem(title: "已完成", order: 4, zone: .complete)
        complete.completedOrder = 1
        day.tasks = [draft, focus, frozen, complete]

        XCTAssertTrue(day.isTerminal)
        XCTAssertEqual(day.tasks.count, 4)
        XCTAssertTrue(day.sortedDraftTasks.isEmpty)
        XCTAssertNil(day.focusTask)
        XCTAssertTrue(day.frozenTasks.isEmpty)
        XCTAssertEqual(day.completedTasks.map(\.title), ["已完成"])
    }

    @MainActor
    func test_taskGarbageCollectorDeletesOnlyOldOpenZoneTasks() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let oldDate = makeDate(2026, 1, 1)
        let oldDay = DayModel(dayId: oldDate.dayId, date: oldDate, status: .expired)
        let draft = TaskItem(title: "旧草稿", order: 1, zone: .draft)
        let focus = TaskItem(title: "旧专注", order: 2, zone: .focus)
        let frozen = TaskItem(title: "旧冻结", order: 3, zone: .frozen)
        let complete = TaskItem(title: "完成历史", order: 4, zone: .complete)
        oldDay.tasks = [draft, focus, frozen, complete]
        context.insert(oldDay)
        context.insert(draft)
        context.insert(focus)
        context.insert(frozen)
        context.insert(complete)
        try context.save()

        let deleted = TaskGarbageCollector(modelContext: context, retentionWeeks: 8)
            .collect(referenceDate: makeDate(2026, 9, 19))
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(deleted, 3)
        XCTAssertEqual(remaining.map(\.title), ["完成历史"])
        XCTAssertNotNil(try context.fetch(FetchDescriptor<DayModel>()).first)
    }

    @MainActor
    func test_dataInvariantRepair_doesNotInventClosedAtForSoftCompletion() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let day = DayModel(dayId: "2026-09-19", date: makeDate(2026, 9, 19), status: .completed)
        day.tasks.append(TaskItem(title: "已完成区任务", order: 1, zone: .complete))
        context.insert(day)
        try context.save()

        _ = DataInvariantRepairService(modelContainer: container)
            .repair(referenceDate: makeDate(2026, 9, 19, 12))

        XCTAssertEqual(day.status, .completed)
        XCTAssertNil(day.closedAt)
    }

    @MainActor
    func test_dataInvariantRepair_preservesExpiredDayAndLateTaskZone() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let day = DayModel(dayId: "2026-09-19", date: makeDate(2026, 9, 19), status: .expired)
        let lateFrozenTask = TaskItem(title: "迟到的冻结任务", order: 1, zone: .frozen)
        day.tasks.append(lateFrozenTask)
        context.insert(day)
        try context.save()

        _ = DataInvariantRepairService(modelContainer: container)
            .repair(referenceDate: makeDate(2026, 9, 19, 12))

        XCTAssertEqual(day.status, .expired)
        XCTAssertEqual(day.tasks.first?.zone, .frozen)
        XCTAssertTrue(day.frozenTasks.isEmpty)
    }

    @MainActor
    func test_dataInvariantRepair_promotesClosedExpiredDayToCompleted() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let day = DayModel(dayId: "2026-09-19", date: makeDate(2026, 9, 19), status: .expired)
        day.closedAt = makeDate(2026, 9, 19, 10)
        context.insert(day)
        try context.save()

        _ = DataInvariantRepairService(modelContainer: container)
            .repair(referenceDate: makeDate(2026, 9, 19, 12))

        XCTAssertEqual(day.status, .completed)
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
            .filter { $0.folderName.contains("preflight-v8") }
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
            "snapshot-2026-09-13T11-00-00Z-preflight-v8-BBBBBBBB",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: matching, withIntermediateDirectories: true)

        var verifiedFolders: [String] = []
        let found = BackupRecoveryService.hasValidSnapshot(
            storeURL: storeURL,
            reason: "preflight-v8"
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
    func test_bootstrapRepairsDuplicateWeeksAndReportsConsistency() throws {
        let storeURL = try makeTemporaryStoreURL()
        let today = makeDate(2026, 9, 13)

        do {
            let container = try WeekyiiPersistence.makeModelContainer(
                storeURL: storeURL,
                storeMode: .persistent
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
            storeURL: storeURL,
            storeMode: .persistent,
            referenceDate: today
        )

        guard case .ready(let container, let diagnostics) = launchState else {
            XCTFail("A recoverable local merge must not block app launch")
            return
        }
        let weeks = try container.mainContext.fetch(FetchDescriptor<WeekModel>())
            .filter { $0.weekId == today.weekId }
        let days = try container.mainContext.fetch(FetchDescriptor<DayModel>())
            .filter { $0.dayId == today.dayId }
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(Set(days[0].tasks.map(\.title)), ["来自 iPhone", "来自 iPad"])
        XCTAssertGreaterThan(diagnostics.invariantRepair.repairedDuplicateCount, 0)
        XCTAssertTrue(diagnostics.consistency.isConsistent)
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
                storeMode: .persistent
            )
            let context = container.mainContext
            context.insert(WeekCalculator().makeWeek(for: previousWeekDate, status: .present))
            context.insert(WeekCalculator().makeWeek(for: today, status: .present))
            try context.save()
        }

        let launchState = WeekyiiPersistence.bootstrapPersistentContainer(
            storeURL: storeURL,
            storeMode: .persistent,
            referenceDate: today
        )

        guard case .ready(let container, let diagnostics) = launchState else {
            XCTFail("Competing present-week updates must be repaired during launch")
            return
        }
        let weeks = try container.mainContext.fetch(FetchDescriptor<WeekModel>())
        let presentWeeks = weeks.filter { $0.status == .present }
        XCTAssertEqual(presentWeeks.map(\.weekId), [today.weekId])
        XCTAssertEqual(weeks.first { $0.weekId == previousWeekDate.weekId }?.status, .past)
        XCTAssertTrue(diagnostics.consistency.isConsistent)
    }

    @MainActor
    func test_remainingBusinessConsistencyDiagnosticIsNonfatalAndStoreRemainsWritable() throws {
        let storeURL = try makeTemporaryStoreURL()
        let today = makeDate(2026, 9, 13)
        let previousWeekDate = Calendar(identifier: .iso8601).date(byAdding: .day, value: -7, to: today)!

        do {
            let container = try WeekyiiPersistence.makeModelContainer(storeURL: storeURL)
            container.mainContext.insert(WeekCalculator().makeWeek(for: previousWeekDate, status: .present))
            container.mainContext.insert(WeekCalculator().makeWeek(for: today, status: .present))
            try container.mainContext.save()
        }

        let launchState = WeekyiiPersistence.bootstrapPersistentContainer(
            storeURL: storeURL,
            referenceDate: today,
            invariantRepair: { _, _ in DataInvariantRepairReport() }
        )

        guard case .ready(let container, let diagnostics) = launchState else {
            XCTFail("A remaining business diagnostic must not fail local launch")
            return
        }
        XCTAssertEqual(
            diagnostics.consistency.diagnostics,
            [.multiplePresentWeeks(count: 2)]
        )
        XCTAssertEqual(
            try container.mainContext.fetch(FetchDescriptor<WeekModel>()).filter { $0.status == .present }.count,
            2,
            "diagnostics must not discard business records"
        )

        let localTask = TaskItem(title: "Local CRUD remains available", order: 1)
        container.mainContext.insert(localTask)
        try container.mainContext.save()
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<TaskItem>()).contains { $0.title == localTask.title }
        )
    }

    @MainActor
    func test_unreadablePersistentStoreStillFailsBootstrap() throws {
        let storeURL = try makeTemporaryStoreURL()
        try Data("not a readable SwiftData store".utf8).write(to: storeURL)

        let launchState = WeekyiiPersistence.bootstrapPersistentContainer(
            storeURL: storeURL,
            legacyStoreURL: storeURL.deletingLastPathComponent().appendingPathComponent("MissingLegacy.store")
        )

        guard case .failed = launchState else {
            XCTFail("A genuine persistent-store open failure must remain fatal")
            return
        }
    }

    @MainActor
    func test_bootstrapFailsWhenRequiredInvariantRepairFails() throws {
        let storeURL = try makeTemporaryStoreURL()
        let launchState = WeekyiiPersistence.bootstrapPersistentContainer(
            storeURL: storeURL,
            legacyStoreURL: storeURL.deletingLastPathComponent()
                .appendingPathComponent("MissingLegacy.store"),
            invariantRepair: { _, _ in
                throw WeekyiiPersistenceError.inconsistentState("injected repair transaction failure")
            }
        )

        guard case .failed = launchState else {
            XCTFail("A required repair transaction failure must remain fatal")
            return
        }
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
    func test_publishedV7FixtureMigratesToV8() throws {
        let storeURL = try makeTemporaryStoreURL()
        do {
            let legacySchema = Schema(versionedSchema: WeekyiiSchemaV7.self)
            let legacyConfiguration = ModelConfiguration(
                "Weekyii",
                schema: legacySchema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)
            let context = legacyContainer.mainContext
            let week = WeekyiiSchemaV7.WeekModel(
                weekId: "2026-W40",
                startDate: Date(timeIntervalSince1970: 1_790_000_000),
                endDate: Date(timeIntervalSince1970: 1_790_518_400),
                status: .present
            )
            let day = WeekyiiSchemaV7.DayModel(
                dayId: "2026-09-28",
                date: Date(timeIntervalSince1970: 1_790_000_000),
                status: .draft
            )
            let project = WeekyiiSchemaV7.ProjectModel(
                name: "V7 project",
                startDate: Date(timeIntervalSince1970: 1_790_000_000),
                endDate: Date(timeIntervalSince1970: 1_790_518_400)
            )
            let task = WeekyiiSchemaV7.TaskItem(
                title: "V7 task",
                taskDescription: "carried over",
                taskType: .ddl,
                order: 1,
                zone: .draft
            )
            task.steps.append(WeekyiiSchemaV7.TaskStep(title: "V7 step", isCompleted: true, sortOrder: 1))
            task.attachments.append(WeekyiiSchemaV7.TaskAttachment(data: Data([7, 7, 7]), fileName: "v7.bin", fileType: "application/octet-stream"))
            task.project = project
            day.tasks.append(task)
            week.days.append(day)
            context.insert(week)
            context.insert(project)
            context.insert(WeekyiiSchemaV7.MindStampItem(text: "V7 stamp", imageBlob: Data([9, 9])))
            context.insert(WeekyiiSchemaV7.SuspendedTaskItem(title: "V7 suspended", decisionDeadline: Date(timeIntervalSince1970: 1_790_600_000), preferredCountdownDays: 3))
            context.insert(WeekyiiSchemaV7.TaskTypeDefinition(idRaw: "custom-v7", name: "V7 Type", iconName: "cloud", colorHex: "#445566", baseKindRaw: TaskType.regular.rawValue, sortOrder: 10))
            try context.save()
        }

        let container = try WeekyiiPersistence.makeModelContainer(storeURL: storeURL)
        let context = container.mainContext
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let projects = try context.fetch(FetchDescriptor<ProjectModel>())
        let stamps = try context.fetch(FetchDescriptor<MindStampItem>())
        let suspended = try context.fetch(FetchDescriptor<SuspendedTaskItem>())
        let taskTypes = try context.fetch(FetchDescriptor<TaskTypeDefinition>())

        XCTAssertEqual(tasks.map(\.title), ["V7 task"])
        XCTAssertEqual(tasks.first?.steps.map(\.title), ["V7 step"])
        XCTAssertEqual(tasks.first?.attachments.first?.data, Data([7, 7, 7]))
        XCTAssertEqual(tasks.first?.project?.name, "V7 project")
        XCTAssertEqual(projects.map(\.name), ["V7 project"])
        XCTAssertEqual(stamps.map(\.text), ["V7 stamp"])
        XCTAssertEqual(suspended.map(\.title), ["V7 suspended"])
        XCTAssertTrue(taskTypes.contains { $0.idRaw == "custom-v7" })
    }

    @MainActor
    func test_publishedV7CurrentDayDraftSurvivesFullBootstrap() throws {
        let storeURL = try makeTemporaryStoreURL()
        let today = makeDate(2026, 9, 26)
        let endOfWeek = Calendar(identifier: .iso8601).date(byAdding: .day, value: 1, to: today)!

        do {
            let schema = Schema(versionedSchema: WeekyiiSchemaV7.self)
            let configuration = ModelConfiguration(
                "Weekyii",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = container.mainContext
            let week = WeekyiiSchemaV7.WeekModel(
                weekId: today.weekId,
                startDate: today,
                endDate: endOfWeek,
                status: .present
            )
            let day = WeekyiiSchemaV7.DayModel(dayId: today.dayId, date: today, status: .draft)
            let project = WeekyiiSchemaV7.ProjectModel(
                name: "Upgrade project",
                startDate: today,
                endDate: endOfWeek
            )
            let task = WeekyiiSchemaV7.TaskItem(title: "Keep this draft", order: 1, zone: .draft)
            task.steps.append(WeekyiiSchemaV7.TaskStep(title: "Keep this step"))
            task.attachments.append(WeekyiiSchemaV7.TaskAttachment(
                data: Data([1, 2, 3, 4]),
                fileName: "upgrade.bin",
                fileType: "application/octet-stream"
            ))
            task.project = project
            day.tasks.append(task)
            week.days.append(day)
            context.insert(week)
            context.insert(project)
            try context.save()
        }

        let launchState = WeekyiiPersistence.bootstrapPersistentContainer(
            storeURL: storeURL,
            referenceDate: today,
            legacyStoreURL: storeURL.deletingLastPathComponent().appendingPathComponent("MissingLegacy.store")
        )
        guard case .ready(let container, _) = launchState else {
            XCTFail("An existing V7 user store must open after an in-place upgrade")
            return
        }

        let context = container.mainContext
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.map(\.title), ["Keep this draft"])
        XCTAssertEqual(tasks.first?.steps.map(\.title), ["Keep this step"])
        XCTAssertEqual(tasks.first?.attachments.first?.data, Data([1, 2, 3, 4]))
        XCTAssertEqual(tasks.first?.project?.name, "Upgrade project")
        XCTAssertEqual(tasks.first?.day?.dayId, today.dayId)
    }

    @MainActor
    func test_habitRelationshipRoundTripsThroughContext() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Date().startOfDay
        let day = DayModel(dayId: today.dayId, date: today, status: .draft)
        let habit = HabitModel(name: "冥想", category: .mindfulness, scheduleWeekdays: [1, 3, 5], startDayId: today.dayId)
        let task = TaskItem(title: "冥想", order: 1)
        task.day = day
        task.habit = habit
        day.tasks.append(task)
        context.insert(day)
        context.insert(habit)

        let record = HabitDayRecord(dayId: today.dayId)
        record.habit = habit
        habit.records.append(record)
        context.insert(record)
        try context.save()

        let habits = try context.fetch(FetchDescriptor<HabitModel>())
        XCTAssertEqual(habits.count, 1)
        XCTAssertEqual(habits.first?.tasks.map(\.title), ["冥想"])
        XCTAssertEqual(habits.first?.records.map(\.dayId), [today.dayId])
        XCTAssertEqual(habits.first?.scheduleWeekdays, [1, 3, 5])
        XCTAssertEqual(habits.first?.category, .mindfulness)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.first?.habit?.name, "冥想")

        let records = try context.fetch(FetchDescriptor<HabitDayRecord>())
        XCTAssertEqual(records.first?.habit?.name, "冥想")
        XCTAssertEqual(records.first?.status, .pending)
    }

    func test_habitWeekdayBitmaskEncodesISOWeekdays() throws {
        let habit = HabitModel(name: "Test", scheduleWeekdays: [7], startDayId: "2026-01-01")
        XCTAssertEqual(habit.scheduleWeekdays, [7])          // 只选周日
        habit.scheduleWeekdaysRaw = 0b0011111
        XCTAssertEqual(habit.scheduleWeekdays, [1, 2, 3, 4, 5])  // 工作日
        habit.scheduleWeekdaysRaw = 0
        XCTAssertEqual(habit.scheduleWeekdays, [])
        XCTAssertEqual(habit.scheduleSummary, "")

        habit.scheduleKind = .monthly
        habit.scheduleMonthDays = [1, 15, 31]
        XCTAssertEqual(habit.scheduleMonthDays, [1, 15, 31])
        XCTAssertEqual(habit.scheduleMonthDaysRaw, (1 << 0) | (1 << 14) | (1 << 30))
        XCTAssertTrue(habit.hasSchedule)
        habit.scheduleMonthDaysRaw = 0
        XCTAssertEqual(habit.scheduleMonthDays, [])
        XCTAssertFalse(habit.hasSchedule)
    }

    // MARK: - Habit materializer

    @MainActor
    func test_habitSyncCreatesOnlyTodayAndIsIdempotent() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let todayKey = today.dayId
        let day = DayModel(dayId: todayKey, date: today, status: .empty)
        let habit = HabitModel(name: "晨跑", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: "2026-09-01")
        context.insert(day)
        context.insert(habit)

        let materializer = HabitTaskMaterializer(modelContext: context)
        let first = materializer.sync(today: today, now: makeDate(2026, 9, 16, 9))

        XCTAssertEqual(first.createdCount, 1)
        XCTAssertTrue(first.didChange)
        XCTAssertTrue(habit.records.contains { $0.dayId == todayKey })

        let second = materializer.sync(today: today, now: makeDate(2026, 9, 16, 10))
        XCTAssertEqual(second.createdCount, 0)
        XCTAssertFalse(second.didChange)

        XCTAssertEqual(day.tasks.count, 1)
        XCTAssertEqual(day.tasks.first?.title, "晨跑")
        XCTAssertEqual(day.tasks.first?.habit?.id, habit.id)
        XCTAssertEqual(day.tasks.first?.day?.dayId, todayKey)
        XCTAssertEqual(habit.records.count, 1)
        XCTAssertEqual(habit.records.first?.status, .pending)
        XCTAssertEqual(habit.records.first?.dayId, todayKey)

        let days = try context.fetch(FetchDescriptor<DayModel>())
        XCTAssertFalse(days.contains { $0.dayId > todayKey })
    }

    @MainActor
    func test_habitSyncUsesTodayRecordEvenWhenLegacyWatermarkIsEmpty() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let day = DayModel(dayId: today.dayId, date: today, status: .empty)
        let habit = HabitModel(name: "晨跑", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: "2026-09-01")
        let record = HabitDayRecord(dayId: today.dayId)
        record.habit = habit
        habit.records.append(record)
        habit.generatedThroughDayId = ""
        context.insert(day)
        context.insert(habit)
        context.insert(record)

        let outcome = HabitTaskMaterializer(modelContext: context)
            .sync(today: today, now: makeDate(2026, 9, 16, 9))

        XCTAssertEqual(outcome.createdCount, 0)
        XCTAssertTrue(day.tasks.isEmpty)
        XCTAssertTrue(habit.records.contains { $0.dayId == today.dayId })
    }

    @MainActor
    func test_habitSyncIgnoresFutureLegacyWatermarkWhenTodayHasNoRecord() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let day = DayModel(dayId: today.dayId, date: today, status: .empty)
        let habit = HabitModel(name: "晨跑", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: "2026-09-01")
        habit.generatedThroughDayId = "2099-12-31"
        context.insert(day)
        context.insert(habit)

        let outcome = HabitTaskMaterializer(modelContext: context)
            .sync(today: today, now: makeDate(2026, 9, 16, 9))

        XCTAssertEqual(outcome.createdCount, 1)
        XCTAssertEqual(day.tasks.filter { $0.habit?.id == habit.id }.count, 1)
        XCTAssertTrue(habit.records.contains { $0.dayId == today.dayId })
    }

    @MainActor
    func test_habitSyncDoesNotResurrectDeletedTaskWhileDayRecordRemains() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let tomorrow = makeDate(2026, 9, 17)
        let todayModel = DayModel(dayId: today.dayId, date: today, status: .empty)
        let tomorrowModel = DayModel(dayId: tomorrow.dayId, date: tomorrow, status: .empty)
        let habit = HabitModel(name: "晨跑", scheduleWeekdays: Set(1...7), startDayId: today.dayId)
        context.insert(todayModel)
        context.insert(tomorrowModel)
        context.insert(habit)
        let materializer = HabitTaskMaterializer(modelContext: context)

        let first = materializer.sync(today: today, now: makeDate(2026, 9, 16, 9))
        XCTAssertEqual(first.createdCount, 1)
        XCTAssertEqual(todayModel.tasks.filter { $0.habit?.id == habit.id }.count, 1)
        XCTAssertEqual(habit.records.filter { $0.dayId == today.dayId }.count, 1)

        let generatedTask = try XCTUnwrap(todayModel.tasks.first { $0.habit?.id == habit.id })
        todayModel.tasks.removeAll { $0.id == generatedTask.id }
        context.delete(generatedTask)
        habit.generatedThroughDayId = ""

        let sameDay = materializer.sync(today: today, now: makeDate(2026, 9, 16, 10))
        XCTAssertEqual(sameDay.createdCount, 0)
        XCTAssertTrue(todayModel.tasks.allSatisfy { $0.habit?.id != habit.id })
        XCTAssertTrue(habit.records.contains { $0.dayId == today.dayId })

        let nextDay = materializer.sync(today: tomorrow, now: makeDate(2026, 9, 17, 9))
        XCTAssertEqual(nextDay.createdCount, 1)
        XCTAssertEqual(tomorrowModel.tasks.filter { $0.habit?.id == habit.id }.count, 1)
        XCTAssertEqual(habit.records.filter { $0.dayId == tomorrow.dayId }.count, 1)
        XCTAssertEqual(habit.records.first { $0.dayId == today.dayId }?.status, .missed)
    }

    @MainActor
    func test_habitSyncReevaluatesLockedDayWithoutCreatingProcessedEvidence() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let todayKey = today.dayId
        let day = DayModel(dayId: todayKey, date: today, status: .execute)
        let habit = HabitModel(name: "晨跑", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: "2026-09-01")
        context.insert(day)
        context.insert(habit)

        let materializer = HabitTaskMaterializer(modelContext: context)
        let first = materializer.sync(today: today, now: makeDate(2026, 9, 16, 9))

        XCTAssertEqual(first.createdCount, 0)
        XCTAssertEqual(first.blockedCount, 1)
        XCTAssertTrue(day.tasks.isEmpty)
        XCTAssertTrue(habit.records.isEmpty)

        let second = materializer.sync(today: today, now: makeDate(2026, 9, 16, 10))
        XCTAssertEqual(second.blockedCount, 1)
        XCTAssertEqual(second.createdCount, 0)
        XCTAssertTrue(day.tasks.isEmpty)
        XCTAssertTrue(habit.records.isEmpty)
    }

    @MainActor
    func test_habitSyncSkipsWhenPastKillTime() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let todayKey = today.dayId
        let day = DayModel(dayId: todayKey, date: today, status: .draft)
        day.killTimeHour = 8
        day.killTimeMinute = 0
        let habit = HabitModel(name: "晨跑", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: "2026-09-01")
        context.insert(day)
        context.insert(habit)

        let materializer = HabitTaskMaterializer(modelContext: context)
        let outcome = materializer.sync(today: today, now: makeDate(2026, 9, 16, 9))

        XCTAssertEqual(outcome.createdCount, 0)
        XCTAssertEqual(outcome.blockedCount, 1)
        XCTAssertTrue(day.tasks.isEmpty)
        XCTAssertTrue(habit.records.isEmpty)

        let repeated = materializer.sync(today: today, now: makeDate(2026, 9, 16, 10))
        XCTAssertEqual(repeated.blockedCount, 1)
        XCTAssertTrue(day.tasks.isEmpty)
        XCTAssertTrue(habit.records.isEmpty)
    }

    @MainActor
    func test_habitSyncSkipsNotScheduledAndFutureStart() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let todayKey = today.dayId
        let day = DayModel(dayId: todayKey, date: today, status: .empty)
        let weekendOnly = HabitModel(name: "周日冥想", scheduleWeekdays: [7], startDayId: "2026-09-01")
        let futureStart = HabitModel(name: "明天开始", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: "2026-09-17")
        context.insert(day)
        context.insert(weekendOnly)
        context.insert(futureStart)

        let materializer = HabitTaskMaterializer(modelContext: context)
        let outcome = materializer.sync(today: today, now: makeDate(2026, 9, 16, 9))

        XCTAssertEqual(outcome.createdCount, 0)
        XCTAssertTrue(day.tasks.isEmpty)
        XCTAssertTrue(weekendOnly.records.isEmpty)
        XCTAssertTrue(futureStart.records.isEmpty)
    }

    @MainActor
    func test_habitMonthlyScheduleOccurrenceAndSkipsMissingDates() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let hitDay = makeDate(2026, 9, 15)
        let monthEnd = makeDate(2026, 9, 30)
        let hitDayModel = DayModel(dayId: hitDay.dayId, date: hitDay, status: .empty)
        let monthEndModel = DayModel(dayId: monthEnd.dayId, date: monthEnd, status: .empty)
        // 9/15 命中计划；9 月没有 31 日 → 31 号习惯整个 9 月不生成。
        let onSchedule = HabitModel(name: "15 号记账", scheduleKind: .monthly, scheduleMonthDays: [15], startDayId: "2026-08-15")
        let missingDate = HabitModel(name: "31 号复盘", scheduleKind: .monthly, scheduleMonthDays: [31], startDayId: "2026-08-31")
        context.insert(hitDayModel)
        context.insert(monthEndModel)
        context.insert(onSchedule)
        context.insert(missingDate)

        let materializer = HabitTaskMaterializer(modelContext: context)
        let hitOutcome = materializer.sync(today: hitDay, now: makeDate(2026, 9, 15, 9))

        XCTAssertEqual(hitOutcome.createdCount, 1)
        XCTAssertEqual(hitDayModel.tasks.count, 1)
        XCTAssertEqual(hitDayModel.tasks.first?.habit?.id, onSchedule.id)
        XCTAssertEqual(onSchedule.records.count, 1)
        XCTAssertEqual(onSchedule.records.first?.dayId, hitDay.dayId)
        XCTAssertEqual(onSchedule.records.first?.status, .pending)
        XCTAssertTrue(missingDate.records.isEmpty)

        let endOutcome = materializer.sync(today: monthEnd, now: makeDate(2026, 9, 30, 9))

        XCTAssertEqual(endOutcome.createdCount, 0)
        XCTAssertTrue(monthEndModel.tasks.isEmpty)
        XCTAssertTrue(missingDate.records.isEmpty)

        // 缺日月份不产生时间线节点；含 31 日的 8 月节点存在。
        let nodes = HabitStatisticsCalculator.timeline(for: missingDate, today: monthEnd)
        XCTAssertEqual(nodes.map(\.dayId), ["2026-08-31"])
        XCTAssertFalse(nodes.contains { $0.dayId.hasPrefix("2026-09") })

        let days = try context.fetch(FetchDescriptor<DayModel>())
        XCTAssertFalse(days.contains { $0.dayId > monthEnd.dayId })
    }

    @MainActor
    func test_habitOneOffScheduleMaterializesOnce() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let start = makeDate(2026, 9, 16)
        let nextDay = makeDate(2026, 9, 17)
        let startModel = DayModel(dayId: start.dayId, date: start, status: .empty)
        let nextModel = DayModel(dayId: nextDay.dayId, date: nextDay, status: .empty)
        let habit = HabitModel(name: "体检", scheduleKind: .once, startDayId: start.dayId)
        context.insert(startModel)
        context.insert(nextModel)
        context.insert(habit)

        let materializer = HabitTaskMaterializer(modelContext: context)
        let first = materializer.sync(today: start, now: makeDate(2026, 9, 16, 9))

        XCTAssertEqual(first.createdCount, 1)
        XCTAssertEqual(startModel.tasks.count, 1)
        XCTAssertEqual(startModel.tasks.first?.habit?.id, habit.id)
        XCTAssertEqual(habit.records.count, 1)

        let repeated = materializer.sync(today: start, now: makeDate(2026, 9, 16, 10))
        XCTAssertEqual(repeated.createdCount, 0)
        XCTAssertEqual(startModel.tasks.count, 1)
        XCTAssertEqual(habit.records.count, 1)

        let next = materializer.sync(today: nextDay, now: makeDate(2026, 9, 17, 9))

        XCTAssertEqual(next.createdCount, 0)
        XCTAssertTrue(nextModel.tasks.isEmpty)
        XCTAssertEqual(habit.records.count, 1)
        XCTAssertEqual(habit.records.first?.status, .missed)
    }

    @MainActor
    func test_habitSyncSweepsPendingRecordsToMissed() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let todayKey = today.dayId
        let habit = HabitModel(name: "周日冥想", scheduleWeekdays: [7], startDayId: "2026-09-01")
        let stale = HabitDayRecord(dayId: "2026-09-15")
        stale.habit = habit
        habit.records.append(stale)
        let current = HabitDayRecord(dayId: todayKey)
        current.habit = habit
        habit.records.append(current)
        context.insert(habit)
        context.insert(stale)
        context.insert(current)

        let materializer = HabitTaskMaterializer(modelContext: context)
        let outcome = materializer.sync(today: today, now: makeDate(2026, 9, 16, 9))

        XCTAssertEqual(outcome.missedRecordCount, 1)
        XCTAssertTrue(outcome.didChange)
        XCTAssertEqual(stale.status, .missed)
        XCTAssertEqual(current.status, .pending)
    }

    @MainActor
    func test_habitStageCompletionUpsertsCompletedRecord() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let todayKey = today.dayId
        let completedAt = makeDate(2026, 9, 16, 21, 30)
        let day = DayModel(dayId: todayKey, date: today, status: .execute)

        let withRecord = HabitModel(name: "喝水", startDayId: "2026-09-01")
        let pending = HabitDayRecord(dayId: todayKey)
        pending.habit = withRecord
        withRecord.records.append(pending)
        let taskA = TaskItem(title: "喝水", order: 1, zone: .focus)
        taskA.day = day
        taskA.habit = withRecord
        day.tasks.append(taskA)

        let withoutRecord = HabitModel(name: "记账", startDayId: "2026-09-01")
        let taskB = TaskItem(title: "记账", order: 2)
        taskB.day = day
        taskB.habit = withoutRecord
        day.tasks.append(taskB)

        context.insert(day)
        context.insert(withRecord)
        context.insert(withoutRecord)
        context.insert(pending)
        try context.save()

        HabitRecordService.stageCompletion(for: taskA, at: completedAt)
        XCTAssertEqual(withRecord.records.count, 1)
        XCTAssertEqual(withRecord.records.first?.status, .completed)
        XCTAssertEqual(withRecord.records.first?.completedAt, completedAt)

        HabitRecordService.stageCompletion(for: taskB, at: completedAt)
        XCTAssertEqual(withoutRecord.records.count, 1)
        XCTAssertEqual(withoutRecord.records.first?.status, .completed)
        XCTAssertEqual(withoutRecord.records.first?.dayId, todayKey)
        XCTAssertEqual(withoutRecord.records.first?.completedAt, completedAt)

        let records = try context.fetch(FetchDescriptor<HabitDayRecord>())
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.filter { $0.status == .completed }.count, 2)
    }

    @MainActor
    func test_habitAssignTodayCanRecreateTaskDespiteExistingDayRecordAndRejectsLocked() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let todayKey = today.dayId
        let day = DayModel(dayId: todayKey, date: today, status: .empty)
        let habit = HabitModel(name: "晨跑", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: "2026-09-01")
        context.insert(day)
        context.insert(habit)

        let materializer = HabitTaskMaterializer(modelContext: context)
        materializer.sync(today: today, now: makeDate(2026, 9, 16, 9))

        var stats = HabitStatisticsCalculator.statistics(for: habit, today: today)
        XCTAssertTrue(stats.hasTodayTask)
        XCTAssertEqual(stats.todayStatus, .pending)

        let generated = try XCTUnwrap(day.tasks.first { $0.habit?.id == habit.id })
        let generatedId = generated.id
        day.tasks = day.tasks.filter { $0.id != generatedId }
        context.delete(generated)
        habit.generatedThroughDayId = ""

        // 任务删除后记录仍为 pending，故「加入今日」可见性必须基于 hasTodayTask 而非 todayStatus。
        stats = HabitStatisticsCalculator.statistics(for: habit, today: today)
        XCTAssertFalse(stats.hasTodayTask)
        XCTAssertEqual(stats.todayStatus, .pending)

        let recreated = materializer.assignToday(habit: habit, today: today, now: makeDate(2026, 9, 16, 10))
        XCTAssertEqual(recreated, .created)
        XCTAssertEqual(day.tasks.filter { $0.habit?.id == habit.id }.count, 1)
        XCTAssertTrue(habit.records.contains { $0.dayId == todayKey })
        XCTAssertTrue(HabitStatisticsCalculator.statistics(for: habit, today: today).hasTodayTask)

        let duplicate = materializer.assignToday(habit: habit, today: today, now: makeDate(2026, 9, 16, 11))
        XCTAssertEqual(duplicate, .alreadyExists)

        let recreatedTask = try XCTUnwrap(day.tasks.first { $0.habit?.id == habit.id })
        let recreatedId = recreatedTask.id
        day.tasks = day.tasks.filter { $0.id != recreatedId }
        context.delete(recreatedTask)
        day.status = .execute

        let locked = materializer.assignToday(habit: habit, today: today, now: makeDate(2026, 9, 16, 12))
        XCTAssertEqual(locked, .dayLocked)

        let weekendOnly = HabitModel(name: "周日冥想", scheduleWeekdays: [7], startDayId: "2026-09-01")
        context.insert(weekendOnly)
        let notScheduled = materializer.assignToday(habit: weekendOnly, today: today, now: makeDate(2026, 9, 16, 13))
        XCTAssertEqual(notScheduled, .notScheduledToday)

        let weekendStats = HabitStatisticsCalculator.statistics(for: weekendOnly, today: today)
        XCTAssertEqual(weekendStats.todayStatus, .notScheduled)
        XCTAssertFalse(weekendStats.hasTodayTask)
    }

    @MainActor
    func test_habitStatisticsStreakRateAndDedupe() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let habit = HabitModel(name: "晨跑", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: "2026-09-09")
        context.insert(habit)

        func addRecord(_ dayId: String, _ status: HabitDayRecordStatus) {
            let record = HabitDayRecord(dayId: dayId)
            record.status = status
            if status == .completed {
                record.completedAt = WeekyiiDayId.date(from: dayId)
            }
            record.habit = habit
            habit.records.append(record)
            context.insert(record)
        }

        addRecord("2026-09-09", .completed)
        addRecord("2026-09-10", .missed)
        addRecord("2026-09-14", .completed)
        addRecord("2026-09-15", .completed)
        addRecord("2026-09-16", .completed)

        let first = HabitStatisticsCalculator.statistics(for: habit, today: today)
        XCTAssertEqual(first.currentStreak, 3)
        XCTAssertEqual(first.longestStreak, 3)
        XCTAssertEqual(first.completedCount, 4)
        XCTAssertEqual(first.missedCount, 1)
        XCTAssertEqual(first.totalRecordedCount, 5)
        XCTAssertEqual(try XCTUnwrap(first.completionRate), 0.8, accuracy: 0.0001)
        XCTAssertEqual(first.completionRatePercent, 80)
        XCTAssertEqual(first.todayStatus, .completed)

        addRecord("2026-09-10", .completed)

        let deduped = HabitStatisticsCalculator.statistics(for: habit, today: today)
        XCTAssertEqual(deduped.completedCount, 5)
        XCTAssertEqual(deduped.missedCount, 0)
        XCTAssertEqual(deduped.totalRecordedCount, 5)
        XCTAssertEqual(deduped.currentStreak, 5)
        XCTAssertEqual(deduped.longestStreak, 5)
        XCTAssertEqual(deduped.completionRatePercent, 100)
    }

    @MainActor
    func test_habitTimelineAssemblesScheduledDaysWithStates() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let habit = HabitModel(name: "晨跑", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: "2026-09-07")
        context.insert(habit)

        func addRecord(_ dayId: String, _ status: HabitDayRecordStatus, completedAt: Date? = nil) {
            let record = HabitDayRecord(dayId: dayId)
            record.status = status
            record.completedAt = completedAt
            record.habit = habit
            habit.records.append(record)
            context.insert(record)
        }

        let completedAt = makeDate(2026, 9, 14, 8, 12)
        addRecord("2026-09-14", .completed, completedAt: completedAt)
        addRecord("2026-09-15", .missed)
        addRecord("2026-09-16", .pending)

        let nodes = HabitStatisticsCalculator.timeline(for: habit, today: today)

        XCTAssertEqual(nodes.map(\.dayId), [
            "2026-09-16", "2026-09-15", "2026-09-14",
            "2026-09-11", "2026-09-10", "2026-09-09",
            "2026-09-08", "2026-09-07",
        ])

        let byDay = Dictionary(uniqueKeysWithValues: nodes.map { ($0.dayId, $0) })
        XCTAssertEqual(byDay["2026-09-16"]?.state, .pending)
        XCTAssertEqual(byDay["2026-09-15"]?.state, .missed)
        XCTAssertEqual(byDay["2026-09-14"]?.state, .completed)
        XCTAssertEqual(byDay["2026-09-14"]?.completedAt, completedAt)
        XCTAssertEqual(byDay["2026-09-09"]?.state, .unrecorded)
        XCTAssertNil(byDay["2026-09-09"]?.completedAt)
        XCTAssertNotEqual(byDay["2026-09-15"]?.state, byDay["2026-09-09"]?.state)
    }

    // MARK: - Habit view model

    private final class HabitTestAppState: AppStateStore {
        var systemStartDate: Date?
        var lastProcessedDate: Date?
        var lastRolloverAt: Date?
        var runtimeErrorMessage: String?
        var stateTransitionRevision: Int = 0

        func save() {}
        func markProcessed(at date: Date) {}
        func markRollover(at date: Date) { lastRolloverAt = date }
        func incrementDaysStarted() {}
        func bumpStateTransitionRevision() { stateTransitionRevision += 1 }
    }

    private final class HabitTestTimeProvider: TimeProviding {
        var mockDate: Date

        init(mockDate: Date) {
            self.mockDate = mockDate
        }

        var now: Date { mockDate }

        var today: Date { Calendar(identifier: .iso8601).startOfDay(for: mockDate) }

        var currentWeekId: String {
            let calendar = Calendar(identifier: .iso8601)
            let week = calendar.component(.weekOfYear, from: mockDate)
            let year = calendar.component(.yearForWeekOfYear, from: mockDate)
            return String(format: "%04d-W%02d", year, week)
        }
    }

    @MainActor
    func test_habitCreateMaterializesTodayWhenScheduled() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let day = DayModel(dayId: today.dayId, date: today, status: .empty)
        context.insert(day)
        let appState = HabitTestAppState()
        let viewModel = HabitViewModel(
            modelContext: context,
            appState: appState,
            timeProvider: HabitTestTimeProvider(mockDate: makeDate(2026, 9, 16, 9))
        )

        let habit = try viewModel.createHabit(name: "晨跑", startDate: today)

        XCTAssertEqual(day.tasks.map(\.title), ["晨跑"])
        XCTAssertEqual(day.tasks.first?.habit?.id, habit.id)
        XCTAssertEqual(habit.records.count, 1)
        XCTAssertEqual(habit.records.first?.dayId, today.dayId)
        XCTAssertEqual(viewModel.activeHabits.map(\.id), [habit.id])
        XCTAssertTrue(viewModel.archivedHabits.isEmpty)
        XCTAssertEqual(appState.stateTransitionRevision, 1)
    }

    @MainActor
    func test_habitUpdateMaterializesNewlyScheduledTodayWithoutARecord() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let day = DayModel(dayId: today.dayId, date: today, status: .empty)
        context.insert(day)
        let appState = HabitTestAppState()
        let viewModel = HabitViewModel(
            modelContext: context,
            appState: appState,
            timeProvider: HabitTestTimeProvider(mockDate: makeDate(2026, 9, 16, 9))
        )

        let habit = try viewModel.createHabit(
            name: "周二跑",
            scheduleWeekdays: [1, 2],
            startDate: today
        )
        XCTAssertTrue(day.tasks.isEmpty)
        XCTAssertTrue(habit.records.isEmpty)
        habit.generatedThroughDayId = "2099-12-31"

        try viewModel.updateHabit(
            habit,
            name: "晨跑",
            iconName: habit.iconName,
            colorHex: habit.colorHex,
            category: habit.category,
            scheduleKind: .weekly,
            scheduleWeekdays: [1, 2, 3],
            scheduleMonthDays: [],
            startDate: today
        )

        XCTAssertEqual(habit.name, "晨跑")
        XCTAssertEqual(habit.scheduleWeekdays, [1, 2, 3])
        XCTAssertEqual(day.tasks.map(\.title), ["晨跑"])
        XCTAssertEqual(day.tasks.first?.habit?.id, habit.id)
        XCTAssertEqual(habit.generatedThroughDayId, "2099-12-31", "schedule edits must not rewrite the V8 compatibility watermark")
        XCTAssertTrue(habit.records.contains { $0.dayId == today.dayId })
        XCTAssertEqual(appState.stateTransitionRevision, 2)
    }

    @MainActor
    func test_habitArchiveStopsGenerationAndRestoreResumesToday() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let provider = HabitTestTimeProvider(mockDate: makeDate(2026, 9, 16, 9))
        let today = provider.today
        let tomorrow = makeDate(2026, 9, 17)
        let day16 = DayModel(dayId: today.dayId, date: today, status: .empty)
        let day17 = DayModel(dayId: tomorrow.dayId, date: tomorrow, status: .empty)
        context.insert(day16)
        context.insert(day17)
        let appState = HabitTestAppState()
        let viewModel = HabitViewModel(modelContext: context, appState: appState, timeProvider: provider)

        let morning = try viewModel.createHabit(name: "晨跑", startDate: today)
        XCTAssertEqual(day16.tasks.map(\.title), ["晨跑"])

        try viewModel.setActive(morning, false)
        XCTAssertTrue(viewModel.activeHabits.isEmpty)
        XCTAssertEqual(viewModel.archivedHabits.map(\.id), [morning.id])

        provider.mockDate = makeDate(2026, 9, 17, 9)
        let stretch = try viewModel.createHabit(name: "拉伸", startDate: provider.today)
        XCTAssertEqual(day17.tasks.map(\.title), ["拉伸"])
        XCTAssertFalse(day17.tasks.contains { $0.habit?.id == morning.id })

        try viewModel.setActive(morning, true)
        XCTAssertEqual(viewModel.activeHabits.map(\.id), [morning.id, stretch.id])
        XCTAssertEqual(Set(day17.tasks.map(\.title)), ["拉伸", "晨跑"])
        XCTAssertTrue(morning.records.contains { $0.dayId == tomorrow.dayId })
        XCTAssertTrue(stretch.records.contains { $0.dayId == tomorrow.dayId })
    }

    @MainActor
    func test_habitDeleteRemovesDraftTasksAndKeepsStartedDayTasks() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = makeDate(2026, 9, 16)
        let tomorrow = makeDate(2026, 9, 17)
        let day16 = DayModel(dayId: today.dayId, date: today, status: .empty)
        let day17 = DayModel(dayId: tomorrow.dayId, date: tomorrow, status: .execute)
        context.insert(day16)
        context.insert(day17)
        let appState = HabitTestAppState()
        let viewModel = HabitViewModel(
            modelContext: context,
            appState: appState,
            timeProvider: HabitTestTimeProvider(mockDate: makeDate(2026, 9, 16, 9))
        )

        let habit = try viewModel.createHabit(name: "晨跑", startDate: today)

        let draftExtra = TaskItem(title: "倒垃圾", order: 2, zone: .draft)
        draftExtra.day = day16
        day16.tasks.append(draftExtra)
        let keptTask = TaskItem(title: "晨跑", order: 1, zone: .complete)
        keptTask.day = day17
        keptTask.habit = habit
        day17.tasks.append(keptTask)
        try context.save()

        try viewModel.deleteHabit(habit)

        XCTAssertEqual(day16.tasks.map(\.title), ["倒垃圾"])
        XCTAssertEqual(day16.tasks.first?.order, 1)
        XCTAssertEqual(day17.tasks.map(\.title), ["晨跑"])
        XCTAssertNil(day17.tasks.first?.habit)
        XCTAssertTrue(viewModel.activeHabits.isEmpty)
        XCTAssertTrue(viewModel.archivedHabits.isEmpty)
        let habits = try context.fetch(FetchDescriptor<HabitModel>())
        XCTAssertTrue(habits.isEmpty)
        let records = try context.fetch(FetchDescriptor<HabitDayRecord>())
        XCTAssertTrue(records.isEmpty)
    }

    @MainActor
    func test_dataArchiveRoundTripsHabitsRecordsAndTaskLinks() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let suiteName = "ModelTests.ArchiveHabits.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)
        let appState = AppState()
        Self.retainedAppStates.append(appState)

        let targetDate = makeDate(2026, 9, 16)
        let dayId = targetDate.dayId
        let week = WeekModel(weekId: "habit-archive-week", startDate: makeDate(2026, 9, 14), endDate: makeDate(2026, 9, 20), status: .present)
        let day = DayModel(dayId: dayId, date: targetDate, status: .draft)
        day.week = week
        let habit = HabitModel(name: "晨跑", iconName: "figure.run", colorHex: "#FF8800", category: .health, scheduleKind: .weekly, scheduleWeekdays: [1, 2, 3], startDayId: dayId)
        habit.generatedThroughDayId = dayId
        let completedLog = HabitDayRecord(dayId: dayId, createdAt: makeDate(2026, 9, 16, 8))
        completedLog.status = .completed
        completedLog.completedAt = makeDate(2026, 9, 16, 8, 30)
        completedLog.habit = habit
        let missedLog = HabitDayRecord(dayId: makeDate(2026, 9, 15).dayId, createdAt: makeDate(2026, 9, 15, 8))
        missedLog.status = .missed
        missedLog.habit = habit
        habit.records = [completedLog, missedLog]
        let task = TaskItem(title: "晨跑任务", taskType: .regular, order: 1)
        task.day = day
        task.habit = habit
        context.insert(week)
        context.insert(day)
        context.insert(habit)
        context.insert(task)
        try context.save()

        let archive = try WeekyiiDataArchiveService.export(modelContext: context, settings: settings, appState: appState)
        let inspection = try WeekyiiDataArchiveService.inspect(archive)
        XCTAssertEqual(inspection.habitCount, 1)
        XCTAssertTrue(inspection.conciseSummary.contains("1 个习惯"))

        let restoredContainer = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let restoredContext = restoredContainer.mainContext
        _ = try WeekyiiDataArchiveService.importReplacing(
            archive,
            modelContext: restoredContext,
            settings: settings,
            appState: appState,
            storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("store")
        )

        let restoredHabits = try restoredContext.fetch(FetchDescriptor<HabitModel>())
        XCTAssertEqual(restoredHabits.count, 1)
        let restoredHabit = try XCTUnwrap(restoredHabits.first)
        XCTAssertEqual(restoredHabit.name, "晨跑")
        XCTAssertEqual(restoredHabit.scheduleKind, .weekly)
        XCTAssertEqual(restoredHabit.scheduleWeekdays, [1, 2, 3])
        XCTAssertEqual(restoredHabit.scheduleWeekdaysRaw, habit.scheduleWeekdaysRaw)
        XCTAssertEqual(restoredHabit.generatedThroughDayId, dayId)

        XCTAssertEqual(restoredHabit.records.count, 2)
        let restoredCompleted = try XCTUnwrap(restoredHabit.records.first { $0.dayId == dayId })
        XCTAssertEqual(restoredCompleted.status, .completed)
        XCTAssertEqual(restoredCompleted.completedAt, makeDate(2026, 9, 16, 8, 30))
        let restoredMissed = try XCTUnwrap(restoredHabit.records.first { $0.dayId == makeDate(2026, 9, 15).dayId })
        XCTAssertEqual(restoredMissed.status, .missed)
        XCTAssertNil(restoredMissed.completedAt)

        let restoredTasks = try restoredContext.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(restoredTasks.map(\.title), ["晨跑任务"])
        XCTAssertEqual(restoredTasks.first?.habit?.id, restoredHabit.id)
        XCTAssertEqual(restoredHabit.tasks.map(\.title), ["晨跑任务"])
    }

    @MainActor
    func test_dataArchiveImportsLegacySchema7PayloadWithoutHabits() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let suiteName = "ModelTests.ArchiveLegacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)
        let appState = AppState()
        Self.retainedAppStates.append(appState)

        let targetDate = makeDate(2026, 9, 16)
        let week = WeekModel(weekId: "legacy-week", startDate: makeDate(2026, 9, 14), endDate: makeDate(2026, 9, 20), status: .present)
        let day = DayModel(dayId: targetDate.dayId, date: targetDate, status: .draft)
        day.week = week
        let habit = HabitModel(name: "阅读", startDayId: targetDate.dayId)
        let task = TaskItem(title: "阅读任务", order: 1)
        task.day = day
        task.habit = habit
        context.insert(week)
        context.insert(day)
        context.insert(habit)
        context.insert(task)
        try context.save()

        let archive = try WeekyiiDataArchiveService.export(modelContext: context, settings: settings, appState: appState)
        let legacy = try downgradeArchiveToSchema7(archive)

        let inspection = try WeekyiiDataArchiveService.inspect(legacy)
        XCTAssertEqual(inspection.habitCount, 0)
        XCTAssertEqual(inspection.taskCount, 1)

        let restoredContainer = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let restoredContext = restoredContainer.mainContext
        _ = try WeekyiiDataArchiveService.importReplacing(
            legacy,
            modelContext: restoredContext,
            settings: settings,
            appState: appState,
            storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("store")
        )

        XCTAssertEqual(try restoredContext.fetch(FetchDescriptor<HabitModel>()).count, 0)
        XCTAssertEqual(try restoredContext.fetch(FetchDescriptor<HabitDayRecord>()).count, 0)
        let restoredTasks = try restoredContext.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(restoredTasks.map(\.title), ["阅读任务"])
        XCTAssertNil(restoredTasks.first?.habit)
    }

    private func downgradeArchiveToSchema7(_ data: Data) throws -> Data {
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payloadString = try XCTUnwrap(envelope["payload"] as? String)
        let payloadData = try XCTUnwrap(Data(base64Encoded: payloadString))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        payload.removeValue(forKey: "habits")
        if var tasks = payload["tasks"] as? [[String: Any]] {
            for index in tasks.indices {
                tasks[index].removeValue(forKey: "habitId")
            }
            payload["tasks"] = tasks
        }
        let downgradedPayload = try JSONSerialization.data(withJSONObject: payload)
        envelope["schemaVersion"] = 7
        envelope["payload"] = downgradedPayload.base64EncodedString()
        envelope["payloadSHA256"] = SHA256.hash(data: downgradedPayload).map { String(format: "%02x", $0) }.joined()
        return try JSONSerialization.data(withJSONObject: envelope)
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
    func test_userSettings_defaultKillTimeReadsInjectedLocalDefaults() {
        let suiteName = "ModelTests.KillTimeLocalRead.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(18, forKey: "defaultKillTimeHour")
        defaults.set(25, forKey: "defaultKillTimeMinute")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)

        XCTAssertEqual(settings.defaultKillTimeHour, 18)
        XCTAssertEqual(settings.defaultKillTimeMinute, 25)
    }

    @MainActor
    func test_userSettings_defaultKillTimeChangesPersistAndRestoreFromSameSuite() {
        let suiteName = "ModelTests.KillTimeRestore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(settings)
        settings.defaultKillTimeHour = 20
        settings.defaultKillTimeMinute = 10

        XCTAssertEqual(defaults.object(forKey: "defaultKillTimeHour") as? Int, 20)
        XCTAssertEqual(defaults.object(forKey: "defaultKillTimeMinute") as? Int, 10)

        let restored = UserSettings(defaults: defaults)
        Self.retainedUserSettings.append(restored)
        XCTAssertEqual(restored.defaultKillTimeHour, 20)
        XCTAssertEqual(restored.defaultKillTimeMinute, 10)
    }

    @MainActor
    func test_userSettings_defaultKillTimeIsIndependentAcrossDefaultsSuites() {
        let firstSuite = "ModelTests.KillTimeFirstSuite.\(UUID().uuidString)"
        let secondSuite = "ModelTests.KillTimeSecondSuite.\(UUID().uuidString)"
        let firstDefaults = UserDefaults(suiteName: firstSuite)!
        let secondDefaults = UserDefaults(suiteName: secondSuite)!
        firstDefaults.removePersistentDomain(forName: firstSuite)
        secondDefaults.removePersistentDomain(forName: secondSuite)
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        firstDefaults.set(16, forKey: "defaultKillTimeHour")
        firstDefaults.set(5, forKey: "defaultKillTimeMinute")
        secondDefaults.set(21, forKey: "defaultKillTimeHour")
        secondDefaults.set(40, forKey: "defaultKillTimeMinute")

        let firstSettings = UserSettings(defaults: firstDefaults)
        Self.retainedUserSettings.append(firstSettings)
        firstSettings.defaultKillTimeHour = 17

        let secondSettings = UserSettings(defaults: secondDefaults)
        Self.retainedUserSettings.append(secondSettings)

        XCTAssertEqual(secondSettings.defaultKillTimeHour, 21)
        XCTAssertEqual(secondSettings.defaultKillTimeMinute, 40)
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

        XCTAssertEqual(settings.defaultProjectColorHex, "#E39A3F")
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

    func test_projectTilePresentation_mediumBrowseUsesCompactPills() {
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
        XCTAssertEqual(presentation.secondaryContent, .compactPills)
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

    func test_projectTilePresentation_smallAddsProgressBarAndKeepsStrip() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            nextTaskTitle: "下一步"
        )

        let small = ProjectTilePresentation(snapshot: snapshot, size: .small, isEditing: false, liveTick: 0)
        let mini = ProjectTilePresentation(snapshot: snapshot, size: .mini, isEditing: false, liveTick: 0)

        XCTAssertTrue(small.showsProgressBar)
        XCTAssertEqual(small.secondaryContent, .microStatsStrip)
        XCTAssertEqual(small.taskRowCount, 0)
        XCTAssertFalse(mini.showsProgressBar)
    }

    func test_projectTilePresentation_mediumAddsProgressBarUnderBigNumber() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            nextTaskTitle: "整理材料"
        )

        let presentation = ProjectTilePresentation(snapshot: snapshot, size: .medium, isEditing: false, liveTick: 0)

        XCTAssertTrue(presentation.showsProgressBar)
        XCTAssertFalse(presentation.showsTrendChart)
        XCTAssertEqual(presentation.primaryNumberFontSize, 48)
        XCTAssertEqual(presentation.secondaryContent, .compactPills)
    }

    func test_projectTilePresentation_wideCarriesTrendChartAndTaskRows() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
            nextTaskTitle: "明天交付",
            trend: makeTileTrendSeries()
        )

        let browse = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: false, liveTick: 0)
        let edit = ProjectTilePresentation(snapshot: snapshot, size: .wide, isEditing: true, liveTick: 0)

        XCTAssertTrue(browse.showsTrendChart)
        XCTAssertFalse(browse.showsProgressBar)
        XCTAssertEqual(browse.taskRowCount, 3)
        XCTAssertEqual(edit.taskRowCount, 0)
        XCTAssertEqual(edit.secondaryContent, .compactPills)

        let emptyTrend = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000034")!,
            nextTaskTitle: "明天交付"
        )
        XCTAssertFalse(
            ProjectTilePresentation(snapshot: emptyTrend, size: .wide, isEditing: false, liveTick: 0).showsTrendChart
        )
    }

    func test_projectTilePresentation_compactBoardTrimsSecondaryRows() {
        let snapshot = makeTileSnapshot(
            projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!,
            nextTaskTitle: "明天交付"
        )

        let medium = ProjectTilePresentation(
            snapshot: snapshot,
            size: .medium,
            isEditing: false,
            liveTick: 0,
            isCompactBoard: true
        )
        let small = ProjectTilePresentation(
            snapshot: snapshot,
            size: .small,
            isEditing: false,
            liveTick: 0,
            isCompactBoard: true
        )
        let wide = ProjectTilePresentation(
            snapshot: snapshot,
            size: .wide,
            isEditing: false,
            liveTick: 0,
            isCompactBoard: true
        )

        XCTAssertEqual(medium.primaryNumberFontSize, 32)
        XCTAssertEqual(medium.secondaryContent, .none)
        XCTAssertTrue(medium.showsProgressBar)
        XCTAssertEqual(small.secondaryContent, .none)
        XCTAssertTrue(small.showsProgressBar)
        XCTAssertEqual(wide.taskRowCount, 0)
        XCTAssertEqual(wide.secondaryContent, .none)
        XCTAssertEqual(wide.trendChartMaxHeight, 30)
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

    private func makeTileSnapshot(
        projectID: UUID,
        nextTaskTitle: String?,
        trend: [ProjectTileTrendPoint] = []
    ) -> ProjectTileSnapshot {
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
            nextTaskDate: nextTaskTitle == nil ? nil : Date(timeIntervalSince1970: 1_762_444_800),
            trend: trend
        )
    }

    /// 14 天窗口，索引 0...10 落在今天及以前（历史段），11...13 是未来段。
    private func makeTileTrendSeries() -> [ProjectTileTrendPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<14).map { offset in
            ProjectTileTrendPoint(
                day: calendar.date(byAdding: .day, value: offset - 10, to: today) ?? today,
                completed: offset == 4 ? 2 : 0,
                planned: offset >= 11 ? 1 : 0
            )
        }
    }
}

@MainActor
final class TaskPostponeServiceTests: XCTestCase {
    private static var retainedUserSettings: [UserSettings] = []
    // Swift 6 在 iOS 26.2 上通过 back-deploy 路径析构 @MainActor 类时会
    // double-free task-local 存储：swift_task_deinitOnExecutorMainActorBackDeploy
    // -> TaskLocal::StopLookupScope::~StopLookupScope
    // -> ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED。
    // 保留实例即可绕过（与 retainedUserSettings 同因）。
    private static var retainedViewModels: [PendingViewModel] = []
    private static var retainedAppStates: [AppState] = []
    private static var retainedContainers: [ModelContainer] = []

    /// PendingViewModel 默认使用真实系统时间；这些用例固定在 2026-03 中旬，
    /// 日期漂移后（真实时间越过测试日期）canEdit 会抛 cannotEditStartedDay。
    /// 注入固定时间让测试与时钟解耦。
    private final class FixedMarchTimeProvider: TimeProviding {
        private let iso8601 = Calendar(identifier: .iso8601)
        var now: Date { makeDate(2026, 3, 19, 12) }
        var today: Date { iso8601.startOfDay(for: now) }
        var currentWeekId: String {
            let week = iso8601.component(.weekOfYear, from: now)
            let year = iso8601.component(.yearForWeekOfYear, from: now)
            return String(format: "%04d-W%02d", year, week)
        }
        private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
            var components = DateComponents()
            components.calendar = iso8601
            components.timeZone = TimeZone(secondsFromGMT: 0)
            components.year = year; components.month = month; components.day = day; components.hour = hour
            return components.date!
        }
    }
    private var container: ModelContainer!

    private static func makeContainer() throws -> ModelContainer {
        // 必须用当前 schema：这些用例插入的是当前类型的模型
        // （WeekCalculator().makeWeek(...) 等）。早先这里用 V4 schema，
        // 触发 SwiftData "Failed to cast model ... to ..." 致命错误
        // （ModelContext.swift:712），表现为测试进程反复崩溃被误判为
        // 模拟器宿主 malloc 问题。
        // 用与项目其它测试一致的构造路径（含 migrationPlan 与统一配置）。
        // 裸 ModelContainer(for:configurations:) 在 iOS 26.2 上会触发
        // SwiftData 的 double-free（malloc: pointer being freed was not allocated）。
        return try WeekyiiPersistence.makeModelContainer(inMemory: true)
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
        XCTAssertFalse(todayDay.tasks.contains { $0.zone == .focus })
        XCTAssertFalse(todayDay.tasks.contains { $0.zone == .frozen })
    }

    func test_execute_fromFocusWithoutFrozenCompletesSourceDay() throws {
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
        XCTAssertFalse(todayDay.tasks.contains { $0.zone == .focus || $0.zone == .frozen })
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
        let context = container.mainContext
        let viewModel = PendingViewModel(
            modelContext: context,
            timeProvider: FixedMarchTimeProvider()
        )
        Self.retainedViewModels.append(viewModel)
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
        let context = container.mainContext
        let viewModel = PendingViewModel(
            modelContext: context,
            timeProvider: FixedMarchTimeProvider()
        )
        Self.retainedViewModels.append(viewModel)
        let futureDate = makeDate(2026, 3, 21)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        day.status = .draft
        let task = TaskItem(title: "Old", taskDescription: "Before", taskType: .regular, order: 1, zone: .draft)
        day.tasks.append(task)
        context.insert(task)
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
        let context = container.mainContext
        let viewModel = PendingViewModel(
            modelContext: context,
            timeProvider: FixedMarchTimeProvider()
        )
        Self.retainedViewModels.append(viewModel)
        let futureDate = makeDate(2026, 3, 22)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        day.status = .draft
        let a = TaskItem(title: "A", order: 1, zone: .draft)
        let b = TaskItem(title: "B", order: 2, zone: .draft)
        let c = TaskItem(title: "C", order: 3, zone: .draft)
        day.tasks.append(a)
        day.tasks.append(b)
        day.tasks.append(c)
        context.insert(a)
        context.insert(b)
        context.insert(c)
        try context.save()

        try viewModel.deleteDraftTasks(in: day, at: IndexSet(integer: 1))

        let draftTasks = day.sortedDraftTasks
        XCTAssertEqual(draftTasks.map(\.title), ["A", "C"])
        XCTAssertEqual(draftTasks.map(\.order), [1, 2])
    }

    @MainActor
    func test_pendingViewModel_moveDraftTasksReordersDay() throws {
        let context = container.mainContext
        let viewModel = PendingViewModel(
            modelContext: context,
            timeProvider: FixedMarchTimeProvider()
        )
        Self.retainedViewModels.append(viewModel)
        let futureDate = makeDate(2026, 3, 23)
        let week = WeekCalculator().makeWeek(for: futureDate, status: .pending)
        context.insert(week)
        let day = requireDay(in: week, date: futureDate)
        day.status = .draft
        let a = TaskItem(title: "A", order: 1, zone: .draft)
        let b = TaskItem(title: "B", order: 2, zone: .draft)
        let c = TaskItem(title: "C", order: 3, zone: .draft)
        day.tasks.append(a)
        day.tasks.append(b)
        day.tasks.append(c)
        context.insert(a)
        context.insert(b)
        context.insert(c)
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

    func test_preview_habitTaskCannotBePostponed() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft
        let habit = HabitModel(name: "晨跑", startDayId: today.dayId)
        context.insert(habit)
        let habitTask = TaskItem(title: "晨跑", order: 1, zone: .draft)
        habitTask.habit = habit
        todayDay.tasks.append(habitTask)
        try context.save()

        XCTAssertThrowsError(
            try service.preview(taskID: habitTask.id, targetDate: today.addingDays(1), today: today)
        ) { error in
            guard case WeekyiiError.cannotPostponeHabitTask = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func test_execute_habitTaskCannotBePostponed() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)
        let now = makeDate(2026, 3, 5, 10, 0)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft
        let habit = HabitModel(name: "晨跑", startDayId: today.dayId)
        context.insert(habit)
        let habitTask = TaskItem(title: "晨跑", order: 1, zone: .draft)
        habitTask.habit = habit
        todayDay.tasks.append(habitTask)
        let targetDate = today.addingDays(1)
        let preview = TaskPostponeService.Preview(
            taskID: habitTask.id,
            targetDate: targetDate,
            targetDayId: targetDate.dayId,
            targetWeekId: targetDate.weekId,
            requiresWeekCreation: false
        )
        try context.save()

        XCTAssertThrowsError(
            try service.execute(preview: preview, allowCreateWeek: false, today: today, now: now)
        ) { error in
            guard case WeekyiiError.cannotPostponeHabitTask = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
        XCTAssertEqual(todayDay.tasks.count, 1)
        XCTAssertEqual(habitTask.zone, .draft)
    }

    func test_preview_normalTaskUnaffectedByHabitGuard() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let service = TaskPostponeService(modelContext: context)
        let today = makeDate(2026, 3, 5)

        let todayWeek = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(todayWeek)
        let todayDay = requireDay(in: todayWeek, date: today)
        todayDay.status = .draft
        let normalTask = TaskItem(title: "Read", order: 1, zone: .draft)
        todayDay.tasks.append(normalTask)
        try context.save()

        let preview = try service.preview(taskID: normalTask.id, targetDate: today.addingDays(1), today: today)
        XCTAssertEqual(preview.targetDayId, today.addingDays(1).dayId)
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
        Self.retainedAppStates.append(appState)
        Self.retainedContainers.append(container)

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
        let appState = AppState()
        Self.retainedAppStates.append(appState)
        Self.retainedContainers.append(container)
        var data = try WeekyiiDataArchiveService.export(modelContext: container.mainContext, settings: settings, appState: appState)
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
            HabitModel.self,
            HabitDayRecord.self,
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

// MARK: - Phase A0: resource identity stabilization

/// Regression coverage for Phase A0 — "资源身份稳定化".
///
/// The invariants come from the execution plan's §W / §AH:
///
/// * `TaskAttachment.id` is the attachment's **business identity** — the key the
///   sync layer will address it by. It must survive edits and owner changes, and
///   may only be minted for a genuine duplication.
/// * `TaskStep.createdAt` must survive a copy, so a no-op save does not look like
///   a content change.
/// * Editing one resource kind must not rebuild the other.
///
/// **Every case here fails against the pre-A0 implementation**, which rebuilt both
/// kinds from scratch on every save — `delete all`, then
/// `TaskAttachment(data:fileName:fileType:)` with no `id`, and
/// `TaskStep(title:isCompleted:sortOrder:)` with no `createdAt`.
@MainActor
final class TaskResourceIdentityTests: XCTestCase {
    private var container: ModelContainer!

    private final class NoopNotificationService: NotificationScheduling {
        func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int, fixedReminder: DateComponents?) {}
        func cancelKillTimeNotification(for day: DayModel) {}
        func removeDeliveredKillTimeNotifications(for day: DayModel) {}
        func scheduleSuspendedTaskNotifications(for task: SuspendedTaskItem) {}
        func cancelSuspendedTaskNotifications(for task: SuspendedTaskItem) {}
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([
            WeekModel.self,
            DayModel.self,
            TaskItem.self,
            TaskStep.self,
            TaskAttachment.self,
            ProjectModel.self,
            MindStampItem.self,
            SuspendedTaskItem.self,
            HabitModel.self,
            HabitDayRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: config)
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Attachment identity (§AH, 8+ cases)

    /// 1. A save that does not touch attachments must not change their identity.
    func test_reconcileAttachments_preservesIdentityOnUnrelatedEdit() throws {
        let context = container.mainContext
        let service = TaskMutationService(modelContext: context)
        let originalID = UUID()
        let original = TaskAttachment(
            id: originalID,
            data: Data([0x01, 0x02, 0x03]),
            fileName: "proof.png",
            fileType: "image/png",
            createdAt: makeDate(2026, 3, 1)
        )
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)
        task.attachments = [original]
        try context.save()

        // Only the title changes; the caller hands the existing attachments back in.
        try service.updateTask(
            task,
            payload: TaskDraftPayload(
                title: "T2",
                description: "",
                type: .regular,
                taskTypeIdRaw: "custom",
                steps: [],
                attachments: task.attachments
            )
        )
        try context.save()

        XCTAssertEqual(task.attachments.count, 1)
        XCTAssertEqual(task.attachments.first?.id, originalID)
        XCTAssertEqual(task.attachments.first?.createdAt, makeDate(2026, 3, 1))
    }

    /// 2. The *persisted row* is reused, not deleted and re-inserted.
    func test_reconcileAttachments_reusesThePersistedRowAndKeepsCreatedAt() throws {
        let context = container.mainContext
        let original = TaskAttachment(
            id: UUID(),
            data: Data([0x01]),
            fileName: "proof.png",
            fileType: "image/png",
            createdAt: makeDate(2026, 3, 1)
        )
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)
        task.attachments = [original]
        try context.save()

        let before = task.attachments.first
        // A detached copy carrying the same business identity but edited bytes
        // and a bogus createdAt.
        let edited = TaskAttachment(
            id: original.id,
            data: Data([0x09, 0x09]),
            fileName: "proof.png",
            fileType: "image/png",
            createdAt: makeDate(2030, 1, 1)
        )
        TaskResourceIdentity.reconcileAttachments(on: task, with: [edited], in: context)

        XCTAssertTrue(task.attachments.first === before, "the persisted row must be updated in place")
        XCTAssertEqual(task.attachments.first?.data, Data([0x09, 0x09]))
        XCTAssertEqual(task.attachments.first?.id, original.id)
        XCTAssertEqual(
            task.attachments.first?.createdAt,
            makeDate(2026, 3, 1),
            "createdAt belongs to the resource, not to the edit"
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskAttachment>()).count, 1)
    }

    /// 3. Attachments dropped from the incoming list are deleted, not orphaned.
    func test_reconcileAttachments_deletesRemovedAttachments() throws {
        let context = container.mainContext
        let kept = TaskAttachment(data: Data([0x01]), fileName: "kept.bin", fileType: "application/octet-stream")
        let dropped = TaskAttachment(data: Data([0x02]), fileName: "dropped.bin", fileType: "application/octet-stream")
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)
        task.attachments = [kept, dropped]
        try context.save()

        TaskResourceIdentity.reconcileAttachments(on: task, with: [kept], in: context)
        try context.save()

        XCTAssertEqual(task.attachments.map(\.id), [kept.id])
        let persisted = try context.fetch(FetchDescriptor<TaskAttachment>())
        XCTAssertEqual(persisted.map(\.id), [kept.id])
    }

    /// 4. A genuinely new attachment is inserted carrying the caller's identity.
    func test_reconcileAttachments_insertsNewAttachmentsWithCallerIdentity() throws {
        let context = container.mainContext
        let newID = UUID()
        let incoming = TaskAttachment(
            id: newID,
            data: Data([0x07]),
            fileName: "new.bin",
            fileType: "application/octet-stream",
            createdAt: makeDate(2026, 2, 2)
        )
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)

        TaskResourceIdentity.reconcileAttachments(on: task, with: [incoming], in: context)

        XCTAssertEqual(task.attachments.count, 1)
        XCTAssertEqual(task.attachments.first?.id, newID)
        XCTAssertEqual(task.attachments.first?.createdAt, makeDate(2026, 2, 2))
    }

    /// 5. One business identity must not end up on two rows.
    func test_reconcileAttachments_deduplicatesRepeatedBusinessIdentity() throws {
        let context = container.mainContext
        let sharedID = UUID()
        let first = TaskAttachment(id: sharedID, data: Data([0x01]), fileName: "a.bin", fileType: "application/octet-stream")
        let second = TaskAttachment(id: sharedID, data: Data([0x02]), fileName: "b.bin", fileType: "application/octet-stream")
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)

        TaskResourceIdentity.reconcileAttachments(on: task, with: [first, second], in: context)

        XCTAssertEqual(task.attachments.count, 1)
        XCTAssertEqual(task.attachments.first?.data, Data([0x01]))
    }

    /// 6. Duplication is the only operation that mints a new attachment identity.
    ///
    /// There is deliberately **no** "copy preserving the same UUID" helper: that
    /// would let a caller leave the original row alive and end up with two
    /// SwiftData rows sharing one business id. A real move re-parents the existing
    /// row instead — see `test_assignSuspendedTask_movesResourcesPreservingAttachmentIdentity`.
    func test_duplicatedAttachmentCopies_mintFreshIdentity() throws {
        let original = TaskAttachment(
            id: UUID(),
            data: Data([0x01]),
            fileName: "a.bin",
            fileType: "application/octet-stream",
            createdAt: makeDate(2026, 3, 1)
        )

        let duplicated = TaskResourceIdentity.duplicatedAttachmentCopies(from: [original])
        XCTAssertNotEqual(duplicated.first?.id, original.id)
        XCTAssertNotEqual(duplicated.first?.createdAt, original.createdAt)
        XCTAssertEqual(duplicated.first?.data, original.data)
    }

    /// 7. Editing attachments must not rebuild steps.
    func test_replaceTaskAttachments_leavesStepsUntouched() throws {
        let context = container.mainContext
        let service = TaskMutationService(modelContext: context)
        let stepDate = makeDate(2026, 3, 1)
        let step = TaskStep(title: "S", sortOrder: 0, createdAt: stepDate)
        let attachment = TaskAttachment(data: Data([0x01]), fileName: "a.bin", fileType: "application/octet-stream")
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)
        task.steps = [step]
        task.attachments = [attachment]
        try context.save()

        let stepRow = task.steps.first
        service.replaceTaskAttachments(for: task, attachments: [])

        XCTAssertTrue(task.attachments.isEmpty)
        XCTAssertEqual(task.steps.count, 1)
        XCTAssertTrue(task.steps.first === stepRow, "steps must not be rebuilt when only attachments change")
        XCTAssertEqual(task.steps.first?.createdAt, stepDate)
    }

    /// 8. Editing steps must not rebuild attachments.
    func test_replaceTaskSteps_leavesAttachmentsUntouched() throws {
        let context = container.mainContext
        let service = TaskMutationService(modelContext: context)
        let attachmentID = UUID()
        let attachment = TaskAttachment(
            id: attachmentID,
            data: Data([0x01]),
            fileName: "a.bin",
            fileType: "application/octet-stream",
            createdAt: makeDate(2026, 3, 1)
        )
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)
        task.steps = [TaskStep(title: "S", sortOrder: 0)]
        task.attachments = [attachment]
        try context.save()

        let attachmentRow = task.attachments.first
        service.replaceTaskSteps(for: task, steps: [TaskStep(title: "S2", sortOrder: 0)])

        XCTAssertEqual(task.steps.map(\.title), ["S2"])
        XCTAssertEqual(task.attachments.count, 1)
        XCTAssertTrue(
            task.attachments.first === attachmentRow,
            "attachments must not be rebuilt when only steps change"
        )
        XCTAssertEqual(task.attachments.first?.id, attachmentID)
    }

    /// 9. Assigning a suspended task to a day **moves** its resources.
    func test_assignSuspendedTask_movesResourcesPreservingAttachmentIdentity() throws {
        let context = container.mainContext
        let service = SuspendedTaskLifecycleService(
            modelContext: context,
            notificationService: NoopNotificationService()
        )
        let today = makeDate(2026, 3, 12)
        let targetDate = makeDate(2026, 3, 14)
        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)
        guard let targetDay = week.days.first(where: { $0.dayId == targetDate.dayId }) else {
            return XCTFail("Missing target day \(targetDate.dayId)")
        }
        targetDay.status = .draft

        let attachmentID = UUID()
        let created = makeDate(2026, 3, 1)
        let task = try service.createTask(
            title: "Hold for later",
            description: "",
            type: .regular,
            countdownDays: 10,
            steps: [TaskStep(title: "Step A", sortOrder: 0, createdAt: created)],
            attachments: [
                TaskAttachment(
                    id: attachmentID,
                    data: Data([0x0A]),
                    fileName: "proof.jpg",
                    fileType: "image/jpeg",
                    createdAt: created
                )
            ],
            now: today
        )

        try service.assignTask(task, to: targetDate, today: today)

        let assigned = targetDay.sortedDraftTasks.last
        XCTAssertEqual(assigned?.attachments.map(\.id), [attachmentID])
        XCTAssertEqual(assigned?.attachments.first?.createdAt, created)
        XCTAssertEqual(assigned?.steps.map(\.createdAt), [created])
        XCTAssertTrue(try context.fetch(FetchDescriptor<SuspendedTaskItem>()).isEmpty)
    }

    /// 10. Editing a suspended task preserves step identity end to end — the
    /// editor sheet carries `createdAt` through its drafts, so a save must not
    /// drift it.
    func test_updateSuspendedTask_preservesStepCreatedAtAcrossTheEditor() throws {
        let context = container.mainContext
        let service = SuspendedTaskLifecycleService(
            modelContext: context,
            notificationService: NoopNotificationService()
        )
        let now = makeDate(2026, 3, 12)
        let created = makeDate(2026, 3, 1)
        let task = try service.createTask(
            title: "Waiting",
            description: "",
            type: .regular,
            countdownDays: 10,
            steps: [TaskStep(title: "S", sortOrder: 0, createdAt: created)],
            now: now
        )

        // What `SuspendedTaskEditorSheet` now produces: same createdAt, new title.
        let edited = task.steps.map {
            TaskStep(title: $0.title + "!", isCompleted: $0.isCompleted, sortOrder: $0.sortOrder, createdAt: $0.createdAt)
        }
        try service.updateTask(
            task,
            title: "Waiting",
            description: "",
            type: .regular,
            countdownDays: 10,
            steps: edited,
            attachments: [],
            now: now
        )

        XCTAssertEqual(task.steps.map(\.title), ["S!"])
        XCTAssertEqual(task.steps.map(\.createdAt), [created])
    }

    // MARK: - Step stability (§AH, 4 cases)

    /// 1. A copy carries `createdAt` across.
    func test_stepCopies_preserveCreatedAt() throws {
        let created = makeDate(2026, 3, 1)
        let copies = TaskResourceIdentity.stepCopies(from: [TaskStep(title: "S", sortOrder: 0, createdAt: created)])
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(copies.first?.createdAt, created)
    }

    /// 2. Ordering is deterministic and `sortOrder` is renumbered densely.
    func test_stepCopies_renumberSortOrderDeterministically() throws {
        let earlier = makeDate(2026, 3, 1)
        let later = makeDate(2026, 3, 2)
        let input = [
            TaskStep(title: "C", sortOrder: 5, createdAt: later),
            TaskStep(title: "A", sortOrder: 5, createdAt: earlier),
            TaskStep(title: "B", sortOrder: 9, createdAt: later),
        ]

        let copies = TaskResourceIdentity.stepCopies(from: input)

        XCTAssertEqual(copies.map(\.title), ["A", "C", "B"])
        XCTAssertEqual(copies.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(copies.map(\.createdAt), [earlier, later, later])
    }

    /// 3. Re-saving the same steps must not drift their `createdAt`.
    func test_reconcileSteps_doesNotDriftCreatedAtAcrossRepeatedSaves() throws {
        let context = container.mainContext
        let service = TaskMutationService(modelContext: context)
        let created = makeDate(2026, 3, 1)
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)

        let payload = { (steps: [TaskStep]) in
            TaskDraftPayload(
                title: "T",
                description: "",
                type: .regular,
                taskTypeIdRaw: "custom",
                steps: steps,
                attachments: []
            )
        }

        try service.updateTask(task, payload: payload([TaskStep(title: "S", sortOrder: 0, createdAt: created)]))
        XCTAssertEqual(task.steps.map(\.createdAt), [created])

        // Second save hands back a *copy* carrying the original createdAt.
        try service.updateTask(task, payload: payload(TaskResourceIdentity.stepCopies(from: task.steps)))
        XCTAssertEqual(task.steps.map(\.title), ["S"])
        XCTAssertEqual(task.steps.map(\.createdAt), [created])

        // Third save hands the owner's own rows straight back.
        try service.updateTask(task, payload: payload(task.steps))
        XCTAssertEqual(task.steps.map(\.title), ["S"])
        XCTAssertEqual(task.steps.map(\.createdAt), [created])
    }

    /// 4. Handing the owner its own rows back reorders in place instead of
    /// minting replacements.
    func test_reconcileSteps_reordersOwnRowsInPlace() throws {
        let context = container.mainContext
        let first = TaskStep(title: "A", sortOrder: 1, createdAt: makeDate(2026, 3, 1))
        let second = TaskStep(title: "B", sortOrder: 0, createdAt: makeDate(2026, 3, 2))
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)
        task.steps = [first, second]
        try context.save()

        TaskResourceIdentity.reconcileSteps(on: task, with: [first, second], in: context)

        XCTAssertEqual(task.steps.count, 2)
        XCTAssertTrue(task.steps.contains { $0 === first })
        XCTAssertTrue(task.steps.contains { $0 === second })
        XCTAssertEqual(TaskResourceIdentity.sortedSteps(task.steps).map(\.title), ["B", "A"])
        XCTAssertEqual(TaskResourceIdentity.sortedSteps(task.steps).map(\.sortOrder), [0, 1])
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskStep>()).count, 2)
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
}

// MARK: - Phase A1: normalized business snapshot

/// Regression coverage for Phase A1 — the normalized `WeekyiiBusinessSnapshot`,
/// the frozen `SyncEntityKey`, and the repository's refusal to silently collapse
/// two records onto one identity.
@MainActor
final class WeekyiiSnapshotRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private static var retainedContainers: [ModelContainer] = []

    private final class NoopNotificationService: NotificationScheduling {
        func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int, fixedReminder: DateComponents?) {}
        func cancelKillTimeNotification(for day: DayModel) {}
        func removeDeliveredKillTimeNotifications(for day: DayModel) {}
        func scheduleSuspendedTaskNotifications(for task: SuspendedTaskItem) {}
        func cancelSuspendedTaskNotifications(for task: SuspendedTaskItem) {}
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try Self.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
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
            HabitModel.self,
            HabitDayRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        // SwiftData containers can be deallocated out from under an in-flight test
        // on the iOS 26 simulator; keep them alive for the whole run.
        retainedContainers.append(container)
        return container
    }

    private func load() throws -> WeekyiiSnapshotLoadResult {
        try WeekyiiSnapshotRepository.load(from: container.mainContext)
    }

    // MARK: - SyncEntityKey

    /// The wire form is the sync contract. Renaming a kind, or changing how a
    /// business id is rendered, silently re-keys every record a remote device has
    /// already stored — so it is pinned here.
    func test_syncEntityKey_wireFormIsPinned() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"))

        XCTAssertEqual(SyncEntityKey(kind: .week, businessId: "2026-W38").description, "week:2026-W38")
        XCTAssertEqual(SyncEntityKey(kind: .day, businessId: "2026-09-21").description, "day:2026-09-21")
        XCTAssertEqual(SyncEntityKey(kind: .taskType, businessId: "custom-writing").description, "taskType:custom-writing")
        XCTAssertEqual(
            SyncEntityKey(kind: .task, id: uuid).description,
            "task:0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"
        )
        XCTAssertEqual(SyncEntityKey(kind: .suspendedTask, id: uuid).description.hasPrefix("suspendedTask:"), true)
        XCTAssertEqual(SyncEntityKey(kind: .attachment, id: uuid).description.hasPrefix("attachment:"), true)
        XCTAssertEqual(SyncEntityKey(kind: .project, id: uuid).description.hasPrefix("project:"), true)
        XCTAssertEqual(SyncEntityKey(kind: .mindStamp, id: uuid).description.hasPrefix("mindStamp:"), true)
        XCTAssertEqual(SyncEntityKey(kind: .habit, id: uuid).description.hasPrefix("habit:"), true)
        XCTAssertEqual(SyncEntityKey(kind: .habitDayRecord, id: uuid).description.hasPrefix("habitDayRecord:"), true)

        // UUIDs are rendered uppercase. Lowercasing would give one record two keys.
        XCTAssertTrue(SyncEntityKey(kind: .task, id: uuid).businessId.contains("A"))

        // Adding a kind is fine; renaming one is not. This fails on purpose if a
        // kind is renamed or removed.
        XCTAssertEqual(
            SyncEntityKind.allCases.map(\.rawValue),
            ["week", "day", "task", "suspendedTask", "attachment", "project", "mindStamp", "taskType", "habit", "habitDayRecord"]
        )
    }

    func test_syncEntityKey_roundTripsAndToleratesColonInBusinessId() throws {
        let keys = [
            SyncEntityKey(kind: .task, id: UUID()),
            SyncEntityKey(kind: .day, businessId: "2026-09-21"),
            // A user-authored task-type slug may itself contain a colon; the split
            // is on the first one, so it still round-trips.
            SyncEntityKey(kind: .taskType, businessId: "custom:writing"),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for key in keys {
            let data = try encoder.encode(key)
            XCTAssertEqual(try decoder.decode(SyncEntityKey.self, from: data), key)
        }
        XCTAssertEqual(SyncEntityKey(kind: .taskType, businessId: "custom:writing").businessId, "custom:writing")
        XCTAssertThrowsError(try decoder.decode(SyncEntityKey.self, from: Data("\"nonsense\"".utf8)))
        XCTAssertThrowsError(try decoder.decode(SyncEntityKey.self, from: Data("\"notAKind:x\"".utf8)))
    }

    // MARK: - Normalization

    /// The point of hoisting attachments out of the task (§D of the plan): editing
    /// an attachment must not change the task's own content, or the task aggregate
    /// would be re-uploaded every time an unrelated attachment changes.
    func test_snapshot_taskEncodingIsIndependentOfAttachmentBytes() throws {
        let taskID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001"))
        let attachmentID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001"))
        let createdAt = makeDate(2026, 3, 1)

        func build(bytes: Data) throws -> WeekyiiBusinessSnapshot {
            let container = try Self.makeContainer()
            let context = container.mainContext
            let task = TaskItem(title: "T", order: 1)
            task.id = taskID
            context.insert(task)
            task.attachments = [
                TaskAttachment(id: attachmentID, data: bytes, fileName: "proof.bin", fileType: "application/octet-stream", createdAt: createdAt)
            ]
            try context.save()
            return try WeekyiiSnapshotRepository.requireCleanSnapshot(from: context)
        }

        let before = try build(bytes: Data([0x01, 0x02]))
        let after = try build(bytes: Data([0xFF, 0xFE, 0xFD]))

        XCTAssertEqual(before.tasks, after.tasks, "the task's own content must not depend on attachment bytes")
        XCTAssertNotEqual(before.attachments, after.attachments)
    }

    func test_snapshotAndHabitHashIgnoreLegacyWatermarkDifferences() throws {
        let habitID = try XCTUnwrap(UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001"))

        func build(legacyWatermark: String) throws -> WeekyiiBusinessSnapshot {
            let isolatedContainer = try Self.makeContainer()
            let context = isolatedContainer.mainContext
            let habit = HabitModel(
                name: "晨跑",
                scheduleWeekdays: [1, 2, 3, 4, 5],
                startDayId: "2026-03-01"
            )
            habit.id = habitID
            habit.createdAt = makeDate(2026, 3, 1)
            habit.generatedThroughDayId = legacyWatermark
            context.insert(habit)
            try context.save()
            return try WeekyiiSnapshotRepository.requireCleanSnapshot(from: context)
        }

        let emptyWatermark = try build(legacyWatermark: "")
        let corruptWatermark = try build(legacyWatermark: "2099-12-31")
        let habitKey = SyncEntityKey(kind: .habit, id: habitID)

        XCTAssertEqual(emptyWatermark.habits, corruptWatermark.habits)
        XCTAssertEqual(
            try WeekyiiSnapshotCodec.entityHashes(emptyWatermark)[habitKey],
            try WeekyiiSnapshotCodec.entityHashes(corruptWatermark)[habitKey]
        )
        XCTAssertEqual(
            try WeekyiiSnapshotCodec.snapshotHash(emptyWatermark),
            try WeekyiiSnapshotCodec.snapshotHash(corruptWatermark)
        )
    }

    func test_snapshot_hoistsAttachmentsAndKeepsOnlyIdsOnTheTask() throws {
        let context = container.mainContext
        let attachmentID = UUID()
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)
        task.attachments = [
            TaskAttachment(
                id: attachmentID,
                data: bytes,
                fileName: "proof.bin",
                fileType: "application/octet-stream",
                createdAt: makeDate(2026, 3, 1)
            )
        ]
        try context.save()

        let result = try load()
        XCTAssertTrue(result.isClean, "\(result.diagnostics)")

        let taskSnapshot = try XCTUnwrap(result.snapshot.tasks.first)
        XCTAssertEqual(taskSnapshot.attachmentIds, [attachmentID])

        let attachment = try XCTUnwrap(result.snapshot.attachments.first)
        XCTAssertEqual(result.snapshot.attachments.count, 1)
        XCTAssertEqual(attachment.id, attachmentID)
        XCTAssertEqual(attachment.data, bytes)
        XCTAssertEqual(attachment.owner, .task(task.id))
        XCTAssertEqual(attachment.entityKey, SyncEntityKey(kind: .attachment, id: attachmentID))
    }

    /// Identity is the UUID, never the content: two attachments holding identical
    /// bytes are two entities. (§AH also asks for equal `blobSHA256` here — that
    /// hash is Phase A2's content-identity layer; this test pins the entity layer.)
    func test_snapshot_equalContentAttachmentsKeepDistinctKeysAndBothSurvive() throws {
        let context = container.mainContext
        let bytes = Data([0x01, 0x02, 0x03])
        let firstID = UUID()
        let secondID = UUID()
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)
        task.attachments = [
            TaskAttachment(id: firstID, data: bytes, fileName: "a.bin", fileType: "application/octet-stream"),
            TaskAttachment(id: secondID, data: bytes, fileName: "b.bin", fileType: "application/octet-stream"),
        ]
        try context.save()

        let result = try load()
        XCTAssertTrue(result.isClean, "\(result.diagnostics)")
        XCTAssertEqual(result.snapshot.attachments.count, 2)
        XCTAssertEqual(Set(result.snapshot.attachments.map(\.entityKey)).count, 2)
        XCTAssertEqual(
            Set(result.snapshot.tasks.first?.attachmentIds ?? []),
            Set([firstID, secondID])
        )
    }

    func test_snapshot_embedsStepsWithATotalOrder() throws {
        let context = container.mainContext
        let createdAt = makeDate(2026, 3, 1)
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)
        // Two steps tie on (sortOrder, createdAt) — the snapshot still needs a
        // total order, or two runs could encode different bytes.
        task.steps = [
            TaskStep(title: "Zebra", sortOrder: 0, createdAt: createdAt),
            TaskStep(title: "Alpha", sortOrder: 0, createdAt: createdAt),
            TaskStep(title: "First", sortOrder: 0, createdAt: makeDate(2026, 2, 1)),
        ]
        try context.save()

        let result = try load()
        XCTAssertEqual(result.snapshot.tasks.first?.steps.map(\.title), ["First", "Alpha", "Zebra"])
        // Steps are embedded: there is no step entity kind to address them by.
        XCTAssertFalse(SyncEntityKind.allCases.contains { $0.rawValue == "step" })
    }

    /// The A2 canonical encoding (and therefore its hashes) depends on this: the
    /// same graph must encode identically regardless of fetch order.
    func test_snapshot_orderIsCanonicalRegardlessOfInsertionOrder() throws {
        let ids = try [
            XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
        ]

        func build(order: [UUID]) throws -> WeekyiiBusinessSnapshot {
            let container = try Self.makeContainer()
            let context = container.mainContext
            // Only the *insert order* may differ between the two runs, so every
            // property is derived from the id — otherwise the two graphs differ
            // by construction and the comparison proves nothing.
            for id in order {
                let index = try XCTUnwrap(ids.firstIndex(of: id))
                let task = TaskItem(title: "T\(index)", order: index + 1)
                task.id = id
                context.insert(task)
            }
            try context.save()
            return try WeekyiiSnapshotRepository.requireCleanSnapshot(from: context)
        }

        let forward = try build(order: ids)
        let shuffled = try build(order: [ids[2], ids[0], ids[1]])

        XCTAssertEqual(forward.tasks.map(\.id), ids)
        XCTAssertEqual(shuffled.tasks.map(\.id), ids)
        XCTAssertEqual(forward, shuffled)
        XCTAssertEqual(forward.entityKeys(), forward.entityKeys().sorted())
    }

    // MARK: - Duplicate identity

    func test_load_reportsDuplicateBusinessIdInsteadOfDroppingIt() throws {
        let context = container.mainContext
        let sharedID = UUID()
        let first = TaskItem(title: "First", order: 1)
        first.id = sharedID
        let second = TaskItem(title: "Second", order: 2)
        second.id = sharedID
        context.insert(first)
        context.insert(second)
        try context.save()

        let firstLoad = try load()
        let secondLoad = try load()

        XCTAssertEqual(firstLoad.snapshot.tasks.count, 1, "one business identity must yield one entity")
        let duplicates = firstLoad.diagnostics(of: .duplicateBusinessId)
        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates.first?.entityKey, SyncEntityKey(kind: .task, id: sharedID))
        XCTAssertTrue(
            duplicates.first?.detail.contains("2 rows") ?? false,
            "the diagnostic must say how many rows collided: \(duplicates.first?.detail ?? "nil")"
        )
        // The survivor is chosen by a documented rule, so two runs agree.
        XCTAssertEqual(firstLoad.snapshot, secondLoad.snapshot)
    }

    /// The whole point of `requireCleanSnapshot`: an ambiguous store must not be
    /// able to produce a clean-looking snapshot that sync would then treat as
    /// authoritative. `load` still hands back the best-effort snapshot — that is
    /// what a repair tool needs — but the syncable route has to refuse.
    func test_requireCleanSnapshot_refusesAnAmbiguousStore() throws {
        let context = container.mainContext
        let sharedID = UUID()
        let first = TaskItem(title: "First", order: 1)
        first.id = sharedID
        let second = TaskItem(title: "Second", order: 2)
        second.id = sharedID
        context.insert(first)
        context.insert(second)
        try context.save()

        // `load` is the diagnostic view: it reports the collision and still returns
        // a snapshot, so a repair tool can show the user what happened.
        let result = try load()
        XCTAssertEqual(result.diagnostics(of: .duplicateBusinessId).count, 1)
        XCTAssertFalse(result.isClean)

        // The syncable view must not.
        XCTAssertThrowsError(try WeekyiiSnapshotRepository.requireCleanSnapshot(from: context)) { error in
            guard case .ambiguousStore(let diagnostics)? = error as? WeekyiiSnapshotRepositoryError else {
                return XCTFail("expected ambiguousStore, got \(error)")
            }
            XCTAssertEqual(diagnostics.map(\.kind), [.duplicateBusinessId])
        }
    }

    /// And the clean case must still pass through, or the guard would be useless.
    func test_requireCleanSnapshot_returnsACleanStore() throws {
        let context = container.mainContext
        let task = TaskItem(title: "T", order: 1)
        context.insert(task)
        try context.save()

        let snapshot = try WeekyiiSnapshotRepository.requireCleanSnapshot(from: context)

        XCTAssertEqual(snapshot.tasks.map(\.id), [task.id])
    }

    func test_validate_reportsDuplicateBusinessIdInsideASnapshot() throws {
        let sharedID = UUID()
        let snapshot = makeSnapshot(tasks: [
            makeTaskSnapshot(id: sharedID),
            makeTaskSnapshot(id: sharedID),
        ])

        let diagnostics = WeekyiiSnapshotRepository.validate(snapshot)

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.kind, .duplicateBusinessId)
        XCTAssertEqual(diagnostics.first?.entityKey, SyncEntityKey(kind: .task, id: sharedID))
    }

    // MARK: - Referential diagnostics

    func test_validate_reportsOrphanAttachment() throws {
        let attachmentID = UUID()
        let snapshot = makeSnapshot(attachments: [
            makeAttachmentSnapshot(id: attachmentID, owner: .task(UUID()))
        ])

        let diagnostics = WeekyiiSnapshotRepository.validate(snapshot)

        XCTAssertEqual(diagnostics.map(\.kind), [.orphanAttachment])
        XCTAssertEqual(diagnostics.first?.entityKey, SyncEntityKey(kind: .attachment, id: attachmentID))
    }

    func test_validate_reportsOwnerThatDoesNotListTheAttachment() throws {
        let taskID = UUID()
        let attachmentID = UUID()
        let snapshot = makeSnapshot(
            tasks: [makeTaskSnapshot(id: taskID)],
            attachments: [makeAttachmentSnapshot(id: attachmentID, owner: .task(taskID))]
        )

        let diagnostics = WeekyiiSnapshotRepository.validate(snapshot)

        XCTAssertEqual(diagnostics.map(\.kind), [.attachmentOwnerMismatch])
        XCTAssertEqual(diagnostics.first?.entityKey, SyncEntityKey(kind: .attachment, id: attachmentID))
    }

    func test_validate_reportsDanglingAttachmentReference() throws {
        let taskID = UUID()
        let missingID = UUID()
        let snapshot = makeSnapshot(tasks: [makeTaskSnapshot(id: taskID, attachmentIds: [missingID])])

        let diagnostics = WeekyiiSnapshotRepository.validate(snapshot)

        XCTAssertEqual(diagnostics.map(\.kind), [.danglingAttachmentReference])
        XCTAssertEqual(diagnostics.first?.entityKey, SyncEntityKey(kind: .task, id: taskID))
        XCTAssertTrue(diagnostics.first?.detail.contains(missingID.uuidString) ?? false)
    }

    func test_validate_reportsMissingParents() throws {
        let taskID = UUID()
        let habitRecordID = UUID()
        let snapshot = makeSnapshot(
            days: [makeDaySnapshot(dayId: "2026-03-12", weekId: "2026-W11")],
            tasks: [makeTaskSnapshot(id: taskID, dayId: "2026-03-99", projectId: UUID(), habitId: UUID())],
            habitDayRecords: [makeHabitDayRecordSnapshot(id: habitRecordID, habitId: UUID(), dayId: "2026-03-12")]
        )

        let diagnostics = WeekyiiSnapshotRepository.validate(snapshot)

        // Diagnostics sort by `kind.rawValue`, so `missingDay` precedes `missingHabit`.
        XCTAssertEqual(
            diagnostics.map(\.kind),
            [.missingDay, .missingHabit, .missingHabit, .missingProject, .missingWeek]
        )
    }

    func test_validate_cleanSnapshotHasNoDiagnostics() throws {
        let weekId = "2026-W11"
        let dayId = "2026-03-12"
        let taskID = UUID()
        let projectID = UUID()
        let habitID = UUID()
        let attachmentID = UUID()

        let snapshot = makeSnapshot(
            weeks: [makeWeekSnapshot(weekId: weekId)],
            days: [makeDaySnapshot(dayId: dayId, weekId: weekId)],
            tasks: [makeTaskSnapshot(id: taskID, dayId: dayId, projectId: projectID, habitId: habitID, attachmentIds: [attachmentID])],
            attachments: [makeAttachmentSnapshot(id: attachmentID, owner: .task(taskID))],
            projects: [makeProjectSnapshot(id: projectID)],
            habits: [makeHabitSnapshot(id: habitID)],
            habitDayRecords: [makeHabitDayRecordSnapshot(id: UUID(), habitId: habitID, dayId: dayId)]
        )

        XCTAssertTrue(WeekyiiSnapshotRepository.validate(snapshot).isEmpty)
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertEqual(snapshot.entityCount, 7)
    }

    /// `TaskAttachment.task` and `.suspendedTask` are independent relationships, so
    /// one row can hang off two owners. The snapshot must say so rather than pick
    /// one silently.
    func test_load_reportsOneAttachmentListedByTwoOwners() throws {
        let context = container.mainContext
        let task = TaskItem(title: "T", order: 1)
        let suspended = SuspendedTaskItem(
            title: "S",
            decisionDeadline: makeDate(2026, 3, 22),
            preferredCountdownDays: 10
        )
        let attachment = TaskAttachment(data: Data([0x01]), fileName: "shared.bin", fileType: "application/octet-stream")
        context.insert(task)
        context.insert(suspended)
        context.insert(attachment)
        task.attachments = [attachment]
        suspended.attachments = [attachment]
        try context.save()

        let result = try load()

        XCTAssertEqual(result.snapshot.attachments.count, 1)
        let collisions = result.diagnostics(of: .attachmentMultipleOwners)
        XCTAssertEqual(collisions.count, 1, "\(result.diagnostics)")
        XCTAssertEqual(collisions.first?.entityKey, SyncEntityKey(kind: .attachment, id: attachment.id))
    }

    func test_load_orphanAttachmentIsReported() throws {
        let context = container.mainContext
        let attachment = TaskAttachment(data: Data([0x01]), fileName: "orphan.bin", fileType: "application/octet-stream")
        context.insert(attachment)
        try context.save()

        let result = try load()

        XCTAssertEqual(result.snapshot.attachments.count, 1)
        let orphans = result.diagnostics(of: .orphanAttachment)
        XCTAssertEqual(orphans.count, 1)
        XCTAssertEqual(orphans.first?.entityKey, SyncEntityKey(kind: .attachment, id: attachment.id))
    }

    func test_diagnostics_areDeterministicallyOrdered() throws {
        let taskID = UUID()
        let snapshot = makeSnapshot(
            days: [makeDaySnapshot(dayId: "2026-03-12", weekId: "2026-W11")],
            tasks: [makeTaskSnapshot(id: taskID, dayId: "2026-03-99", attachmentIds: [UUID()])]
        )

        let first = WeekyiiSnapshotRepository.validate(snapshot)
        let second = WeekyiiSnapshotRepository.validate(snapshot)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, first.sorted { $0.kind.rawValue < $1.kind.rawValue })
        XCTAssertFalse(first.isEmpty)
    }

    // MARK: - A0 ↔ A1

    /// The payoff of Phase A0: assigning a suspended task to a day **moves** its
    /// resources, so the attachment's `SyncEntityKey` is the same before and after.
    /// Pre-A0 the resource was re-created and the key changed, which an incremental
    /// sync would read as "delete + insert".
    func test_assignSuspendedTask_keepsAttachmentEntityKeyStable() throws {
        let context = container.mainContext
        let service = SuspendedTaskLifecycleService(
            modelContext: context,
            notificationService: NoopNotificationService()
        )
        let today = makeDate(2026, 3, 12)
        let targetDate = makeDate(2026, 3, 14)
        let week = WeekCalculator().makeWeek(for: today, status: .present)
        context.insert(week)
        guard let targetDay = week.days.first(where: { $0.dayId == targetDate.dayId }) else {
            return XCTFail("Missing target day \(targetDate.dayId)")
        }
        targetDay.status = .draft

        let attachmentID = UUID()
        let task = try service.createTask(
            title: "Hold for later",
            description: "",
            type: .regular,
            countdownDays: 10,
            attachments: [
                TaskAttachment(
                    id: attachmentID,
                    data: Data([0x0A]),
                    fileName: "proof.jpg",
                    fileType: "image/jpeg",
                    createdAt: makeDate(2026, 3, 1)
                )
            ],
            now: today
        )

        let key = SyncEntityKey(kind: .attachment, id: attachmentID)
        let before = try load()
        XCTAssertEqual(before.snapshot.attachments.map(\.entityKey), [key])
        XCTAssertEqual(before.snapshot.attachments.first?.owner, .suspendedTask(task.id))

        try service.assignTask(task, to: targetDate, today: today)

        let after = try load()
        XCTAssertTrue(after.isClean, "\(after.diagnostics)")
        XCTAssertEqual(after.snapshot.attachments.map(\.entityKey), [key], "the attachment must keep its identity")
        guard case .task = after.snapshot.attachments.first?.owner else {
            return XCTFail("expected the attachment to be owned by the new task")
        }
    }

    // MARK: - Helpers

    private func makeSnapshot(
        weeks: [WeekSnapshot] = [],
        days: [DaySnapshot] = [],
        tasks: [TaskSnapshot] = [],
        suspendedTasks: [SuspendedTaskSnapshot] = [],
        attachments: [AttachmentSnapshot] = [],
        projects: [ProjectSnapshot] = [],
        habits: [HabitSnapshot] = [],
        habitDayRecords: [HabitDayRecordSnapshot] = []
    ) -> WeekyiiBusinessSnapshot {
        WeekyiiBusinessSnapshot(
            weeks: weeks,
            days: days,
            tasks: tasks,
            suspendedTasks: suspendedTasks,
            attachments: attachments,
            projects: projects,
            mindStamps: [],
            taskTypes: [],
            habits: habits,
            habitDayRecords: habitDayRecords
        )
    }

    private func makeWeekSnapshot(weekId: String) -> WeekSnapshot {
        WeekSnapshot(
            weekId: weekId,
            startDate: makeDate(2026, 3, 9),
            endDate: makeDate(2026, 3, 15),
            status: .present,
            completedTasksCount: 0,
            expiredTasksCount: 0,
            totalStartedDays: 0
        )
    }

    private func makeDaySnapshot(dayId: String, weekId: String? = nil) -> DaySnapshot {
        DaySnapshot(
            dayId: dayId,
            weekId: weekId,
            date: makeDate(2026, 3, 12),
            dayOfWeek: "Thu",
            status: .draft,
            killTimeHour: 23,
            killTimeMinute: 45,
            followsDefaultKillTime: true,
            initiatedAt: nil,
            closedAt: nil,
            executionModeRaw: ExecutionMode.strict.rawValue,
            isDraftZoneUnlocked: false,
            expiredCount: 0
        )
    }

    private func makeTaskSnapshot(
        id: UUID,
        dayId: String? = nil,
        projectId: UUID? = nil,
        habitId: UUID? = nil,
        attachmentIds: [UUID] = []
    ) -> TaskSnapshot {
        TaskSnapshot(
            id: id,
            dayId: dayId,
            projectId: projectId,
            habitId: habitId,
            title: "T",
            taskDescription: "",
            taskType: .regular,
            taskTypeIdRaw: TaskType.regular.rawValue,
            order: 1,
            zone: .draft,
            startedAt: nil,
            endedAt: nil,
            completedOrder: 0,
            steps: [],
            attachmentIds: attachmentIds
        )
    }

    private func makeAttachmentSnapshot(id: UUID, owner: AttachmentOwner, data: Data? = Data([0x01])) -> AttachmentSnapshot {
        AttachmentSnapshot(
            id: id,
            owner: owner,
            data: data,
            fileName: "a.bin",
            fileType: "application/octet-stream",
            createdAt: makeDate(2026, 3, 1)
        )
    }

    private func makeProjectSnapshot(id: UUID) -> ProjectSnapshot {
        ProjectSnapshot(
            id: id,
            name: "P",
            projectDescription: "",
            color: "#C46A1A",
            icon: "folder.fill",
            status: .active,
            startDate: makeDate(2026, 3, 1),
            endDate: makeDate(2026, 3, 31),
            createdAt: makeDate(2026, 3, 1),
            tileSizeRaw: ProjectTileSize.medium.rawValue,
            tileOrder: 0
        )
    }

    private func makeHabitSnapshot(id: UUID) -> HabitSnapshot {
        HabitSnapshot(
            id: id,
            name: "H",
            iconName: "repeat.circle.fill",
            colorHex: "#34C759",
            categoryRaw: HabitCategory.health.rawValue,
            scheduleKindRaw: HabitScheduleKind.weekly.rawValue,
            scheduleWeekdaysRaw: 0b0011111,
            scheduleMonthDaysRaw: 0,
            startDayId: "2026-03-01",
            isActive: true,
            createdAt: makeDate(2026, 3, 1),
            sortOrder: 0
        )
    }

    private func makeHabitDayRecordSnapshot(id: UUID, habitId: UUID?, dayId: String) -> HabitDayRecordSnapshot {
        HabitDayRecordSnapshot(
            id: id,
            habitId: habitId,
            dayId: dayId,
            statusRaw: HabitDayRecordStatus.pending.rawValue,
            createdAt: makeDate(2026, 3, 12),
            completedAt: nil
        )
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
}

// MARK: - Phase A2: merge, canonical encoding, archive adapter

/// Regression coverage for Phase A2 — the deterministic local-wins merge, the
/// entity-hash / blob-hash layering, and the archive ↔ snapshot adapter.
@MainActor
final class WeekyiiSnapshotMergeServiceTests: XCTestCase {

    // MARK: - Codec

    func test_codec_canonicalEncodingIsStableAndRoundTrips() throws {
        let graph = makeGraph()

        let first = try WeekyiiSnapshotCodec.encode(graph)
        let second = try WeekyiiSnapshotCodec.encode(graph)

        XCTAssertEqual(first, second, "the same graph must encode to the same bytes")
        XCTAssertEqual(try WeekyiiSnapshotCodec.decode(first), graph)
    }

    func test_codec_encodingIgnoresArrayInsertionOrder() throws {
        let graph = makeGraph()
        let shuffled = WeekyiiBusinessSnapshot(
            weeks: Array(graph.weeks.reversed()),
            days: Array(graph.days.reversed()),
            tasks: Array(graph.tasks.reversed()),
            suspendedTasks: Array(graph.suspendedTasks.reversed()),
            attachments: Array(graph.attachments.reversed()),
            projects: Array(graph.projects.reversed()),
            mindStamps: Array(graph.mindStamps.reversed()),
            taskTypes: Array(graph.taskTypes.reversed()),
            habits: Array(graph.habits.reversed()),
            habitDayRecords: Array(graph.habitDayRecords.reversed())
        )

        XCTAssertEqual(graph, shuffled)
        XCTAssertEqual(try WeekyiiSnapshotCodec.encode(graph), try WeekyiiSnapshotCodec.encode(shuffled))
        XCTAssertEqual(try WeekyiiSnapshotCodec.snapshotHash(graph), try WeekyiiSnapshotCodec.snapshotHash(shuffled))
    }

    /// The whole point of hoisting attachments out of the task (§D): changing an
    /// attachment's bytes must move the attachment's own hash and leave the task's
    /// alone, or every unrelated attachment edit would re-upload the task.
    func test_codec_entityHashLayersPayloadBytesUnderTheAttachment() throws {
        let taskID = UUID()
        let attachmentID = UUID()

        func graph(bytes: Data) -> WeekyiiBusinessSnapshot {
            makeSnapshot(
                tasks: [makeTask(id: taskID, attachmentIds: [attachmentID])],
                attachments: [makeAttachment(id: attachmentID, owner: .task(taskID), bytes: bytes)]
            )
        }

        let taskKey = SyncEntityKey(kind: .task, id: taskID)
        let attachmentKey = SyncEntityKey(kind: .attachment, id: attachmentID)

        // Same length on purpose. With different lengths the byte count alone would
        // tell the two apart and a regression that dropped `blobSHA256` would slip
        // through — which is exactly what a first version of this test did.
        let before = try WeekyiiSnapshotCodec.entityHashes(graph(bytes: Data([0x01, 0x02])))
        let after = try WeekyiiSnapshotCodec.entityHashes(graph(bytes: Data([0xFF, 0xFE])))

        XCTAssertEqual(before[taskKey], after[taskKey], "the task's hash must not move with the attachment's bytes")
        XCTAssertNotEqual(before[attachmentKey], after[attachmentKey], "the attachment's own hash must track its bytes")
        XCTAssertNotEqual(
            try WeekyiiSnapshotCodec.snapshotHash(graph(bytes: Data([0x01, 0x02]))),
            try WeekyiiSnapshotCodec.snapshotHash(graph(bytes: Data([0xFF, 0xFE])))
        )
    }

    /// The same metadata/blob separation, for the other blob-carrying entity.
    /// Equal-length payloads on purpose, so only the blob hash can discriminate —
    /// see the attachment test above for why that matters.
    func test_codec_entityHashLayersImageBytesUnderTheMindStamp() throws {
        let stampID = UUID()
        let key = SyncEntityKey(kind: .mindStamp, id: stampID)

        func hashes(text: String, image: Data?) throws -> [SyncEntityKey: String] {
            try WeekyiiSnapshotCodec.entityHashes(
                makeSnapshot(
                    mindStamps: [
                        MindStampSnapshot(id: stampID, text: text, imageBlob: image, createdAt: makeDate(2026, 3, 1))
                    ]
                )
            )
        }

        let base = try hashes(text: "hello", image: Data([0x01, 0x02]))
        let newText = try hashes(text: "hello!", image: Data([0x01, 0x02]))
        let newBytes = try hashes(text: "hello", image: Data([0xFF, 0xFE]))

        XCTAssertEqual(base[key]?.count, 64, "a SHA-256 hex digest")
        XCTAssertNotEqual(base[key], newText[key], "changing the text must change the entity hash")
        XCTAssertNotEqual(base[key], newBytes[key], "changing the image bytes must change the entity hash")
    }

    func test_codec_equalImageBytesShareABlobHashButStayDistinctEntities() throws {
        let bytes = Data([0x0A, 0x0B])
        let first = MindStampSnapshot(id: UUID(), text: "a", imageBlob: bytes, createdAt: makeDate(2026, 3, 1))
        let second = MindStampSnapshot(id: UUID(), text: "b", imageBlob: bytes, createdAt: makeDate(2026, 3, 1))

        XCTAssertEqual(
            WeekyiiSnapshotCodec.blobHash(first.imageBlob),
            WeekyiiSnapshotCodec.blobHash(second.imageBlob)
        )
        XCTAssertNotEqual(first.entityKey, second.entityKey)
        XCTAssertNotEqual(
            try WeekyiiSnapshotCodec.entityHash(first),
            try WeekyiiSnapshotCodec.entityHash(second),
            "equal bytes are not equal entities — these two differ in text"
        )
    }

    /// The image is a blob, not an entity: it has no `SyncEntityKey` of its own, and
    /// the mind stamp's key comes from its `id`.
    func test_mindStampImageIsABlobNotAnEntity() throws {
        let stampID = UUID()
        let stamp = MindStampSnapshot(id: stampID, text: "t", imageBlob: Data([0x01]), createdAt: makeDate(2026, 3, 1))

        XCTAssertEqual(stamp.entityKey, SyncEntityKey(kind: .mindStamp, id: stampID))
        XCTAssertEqual(SyncEntityKind.allCases.filter { $0.rawValue.contains("mindStamp") }, [.mindStamp])
        for kind in SyncEntityKind.allCases {
            let name = kind.rawValue.lowercased()
            XCTAssertFalse(name.contains("blob"), "a blob must not be addressable: \(kind.rawValue)")
            XCTAssertFalse(name.contains("image"), "an image must not be addressable: \(kind.rawValue)")
        }
    }

    /// "No image" and "a zero-byte image" are different states and must not hash alike.
    func test_codec_mindStampDistinguishesNoImageFromAnEmptyImage() throws {
        let stampID = UUID()

        func hash(image: Data?) throws -> String {
            let snapshot = makeSnapshot(
                mindStamps: [
                    MindStampSnapshot(id: stampID, text: "t", imageBlob: image, createdAt: makeDate(2026, 3, 1))
                ]
            )
            return try XCTUnwrap(WeekyiiSnapshotCodec.entityHashes(snapshot)[SyncEntityKey(kind: .mindStamp, id: stampID)])
        }

        XCTAssertNotEqual(try hash(image: nil), try hash(image: Data()))
    }

    func test_codec_blobHashDistinguishesNoBytesFromZeroBytes() throws {
        XCTAssertNil(WeekyiiSnapshotCodec.blobHash(nil))
        XCTAssertNotNil(WeekyiiSnapshotCodec.blobHash(Data()))
        XCTAssertNotEqual(WeekyiiSnapshotCodec.blobHash(Data()), WeekyiiSnapshotCodec.blobHash(Data([0x00])))
        XCTAssertEqual(
            WeekyiiSnapshotCodec.blobHash(Data([0x01, 0x02])),
            WeekyiiSnapshotCodec.blobHash(Data([0x01, 0x02]))
        )
    }

    func test_codec_entityHashesRejectsTwoRecordsClaimingOneIdentity() throws {
        let sharedID = UUID()
        let snapshot = makeSnapshot(tasks: [makeTask(id: sharedID), makeTask(id: sharedID)])

        XCTAssertThrowsError(try WeekyiiSnapshotCodec.entityHashes(snapshot)) { error in
            XCTAssertEqual(
                error as? WeekyiiSnapshotCodecError,
                .duplicateEntityKey(SyncEntityKey(kind: .task, id: sharedID))
            )
        }
    }

    func test_codec_snapshotHashDependsOnContentNotOnOrder() throws {
        let graph = makeGraph()
        let other = makeSnapshot(tasks: [makeTask(id: UUID())])

        XCTAssertEqual(try WeekyiiSnapshotCodec.snapshotHash(graph), try WeekyiiSnapshotCodec.snapshotHash(graph))
        XCTAssertNotEqual(try WeekyiiSnapshotCodec.snapshotHash(graph), try WeekyiiSnapshotCodec.snapshotHash(other))
        XCTAssertNotEqual(
            try WeekyiiSnapshotCodec.snapshotHash(graph),
            try WeekyiiSnapshotCodec.snapshotHash(.empty)
        )
    }

    /// §AH, stated as a test: two attachments holding identical bytes are still two
    /// entities. They share a blob hash, keep distinct `SyncEntityKey`s, and both
    /// survive a merge.
    func test_codec_equalContentAttachmentsShareABlobHashButKeepDistinctEntityKeys() throws {
        let bytes = Data([0x0A, 0x0B])
        let firstID = UUID()
        let secondID = UUID()
        let taskID = UUID()

        let local = makeSnapshot(tasks: [makeTask(id: taskID)])
        let remote = makeSnapshot(
            tasks: [makeTask(id: taskID, attachmentIds: [firstID, secondID])],
            attachments: [
                makeAttachment(id: firstID, owner: .task(taskID), bytes: bytes),
                makeAttachment(id: secondID, owner: .task(taskID), bytes: bytes),
            ]
        )

        let merged = try WeekyiiSnapshotMergeService.mergePreferringLocal(local: local, remote: remote).snapshot

        XCTAssertEqual(merged.attachments.count, 2, "both attachments must survive the merge")
        XCTAssertEqual(
            Set(merged.attachments.compactMap { WeekyiiSnapshotCodec.blobHash($0.data) }).count,
            1,
            "identical bytes must share one blob hash"
        )
        XCTAssertEqual(Set(merged.attachments.map(\.entityKey)).count, 2, "and still be two entities")
        XCTAssertEqual(Set(merged.tasks.first?.attachmentIds ?? []), Set([firstID, secondID]))
        XCTAssertTrue(WeekyiiSnapshotRepository.validate(merged).isEmpty)
    }

    // MARK: - Merge

    func test_merge_addsEntitiesThatExistOnlyRemotely() throws {
        let taskID = UUID()
        let result = try WeekyiiSnapshotMergeService.mergePreferringLocal(
            local: makeSnapshot(),
            remote: makeSnapshot(tasks: [makeTask(id: taskID)])
        )

        XCTAssertEqual(result.snapshot.tasks.map(\.id), [taskID])
        XCTAssertEqual(result.report.addedFromRemote, [SyncEntityKey(kind: .task, id: taskID)])
        XCTAssertTrue(result.report.keptLocal.isEmpty)
        XCTAssertTrue(result.report.conflicting.isEmpty)
        XCTAssertTrue(result.report.isClean, "\(result.report.diagnostics)")
    }

    func test_merge_keepsLocalWhenBothSidesHoldTheSameKey() throws {
        let taskID = UUID()
        let result = try WeekyiiSnapshotMergeService.mergePreferringLocal(
            local: makeSnapshot(tasks: [makeTask(id: taskID, title: "local")]),
            remote: makeSnapshot(tasks: [makeTask(id: taskID, title: "remote")])
        )

        XCTAssertEqual(result.snapshot.tasks.map(\.title), ["local"])
        XCTAssertEqual(result.report.keptLocal, [SyncEntityKey(kind: .task, id: taskID)])
        XCTAssertEqual(result.report.conflicting, [SyncEntityKey(kind: .task, id: taskID)])
        XCTAssertFalse(result.report.localSnapshotChanged)
    }

    /// There is no clock in the merge, so a device with a wrong clock cannot
    /// overwrite this one just by looking "newer".
    func test_merge_doesNotUseATimestampToBreakTies() throws {
        let taskID = UUID()
        let result = try WeekyiiSnapshotMergeService.mergePreferringLocal(
            local: makeSnapshot(tasks: [makeTask(id: taskID, title: "local", startedAt: makeDate(2026, 3, 1))]),
            remote: makeSnapshot(tasks: [makeTask(id: taskID, title: "remote", startedAt: makeDate(2027, 1, 1))])
        )

        XCTAssertEqual(result.snapshot.tasks.first?.title, "local")
        XCTAssertEqual(result.snapshot.tasks.first?.startedAt, makeDate(2026, 3, 1))
    }

    /// This verifies the explicit **local-preference merge helper**. It is *not* a
    /// proof that the future sync protocol does not converge — convergence is
    /// Phase E's baseline comparison, not this function.
    ///
    /// The roles are part of the contract, not an implementation detail: swapping
    /// them must swap the winner. This fails if someone "improves" the helper into
    /// something order-independent without saying so, or reintroduces a content-hash
    /// authority rule.
    func test_mergePreferringLocal_isDeliberatelyNotCommutative() throws {
        let taskID = UUID()
        let a = makeSnapshot(tasks: [makeTask(id: taskID, title: "a")])
        let b = makeSnapshot(tasks: [makeTask(id: taskID, title: "b")])

        XCTAssertEqual(try WeekyiiSnapshotMergeService.mergePreferringLocal(local: a, remote: b).snapshot.tasks.map(\.title), ["a"])
        XCTAssertEqual(try WeekyiiSnapshotMergeService.mergePreferringLocal(local: b, remote: a).snapshot.tasks.map(\.title), ["b"])
    }

    func test_merge_rejectsASnapshotWithDuplicateKeys() throws {
        let sharedID = UUID()
        let malformed = makeSnapshot(tasks: [makeTask(id: sharedID), makeTask(id: sharedID)])

        XCTAssertThrowsError(try WeekyiiSnapshotMergeService.mergePreferringLocal(local: malformed, remote: makeSnapshot())) { error in
            XCTAssertEqual(
                error as? WeekyiiSnapshotCodecError,
                .duplicateEntityKey(SyncEntityKey(kind: .task, id: sharedID))
            )
        }
    }

    func test_merge_rejectsAVersionMismatch() throws {
        let future = WeekyiiBusinessSnapshot(
            version: WeekyiiBusinessSnapshot.currentVersion + 1,
            weeks: [], days: [], tasks: [], suspendedTasks: [], attachments: [],
            projects: [], mindStamps: [], taskTypes: [], habits: [], habitDayRecords: []
        )

        XCTAssertThrowsError(try WeekyiiSnapshotMergeService.mergePreferringLocal(local: makeSnapshot(), remote: future)) { error in
            XCTAssertEqual(
                error as? WeekyiiSnapshotCodecError,
                .versionMismatch(local: WeekyiiBusinessSnapshot.currentVersion, remote: future.version)
            )
        }
    }

    /// The additive half: an attachment that only the remote side knows about still
    /// lands on the local task, because the attachment's own `owner` says so.
    func test_merge_attachesARemoteAttachmentToALocalTask() throws {
        let taskID = UUID()
        let attachmentID = UUID()

        let result = try WeekyiiSnapshotMergeService.mergePreferringLocal(
            local: makeSnapshot(tasks: [makeTask(id: taskID)]),
            remote: makeSnapshot(
                tasks: [makeTask(id: taskID)],
                attachments: [makeAttachment(id: attachmentID, owner: .task(taskID), bytes: Data([0x01]))]
            )
        )

        XCTAssertEqual(result.snapshot.tasks.first?.attachmentIds, [attachmentID])
        XCTAssertEqual(result.report.relationshipConflictsResolved, [SyncEntityKey(kind: .task, id: taskID)])
        XCTAssertTrue(result.report.localSnapshotChanged)
        XCTAssertTrue(result.report.isClean, "\(result.report.diagnostics)")
    }

    /// `attachment.owner` wins over a stale `task.attachmentIds`. The other rule
    /// would silently drop an attachment that arrived from the remote side.
    func test_merge_letsTheAttachmentsOwnerWinOverAStaleTaskListing() throws {
        let staleOwnerID = UUID()
        let realOwnerID = UUID()
        let attachmentID = UUID()

        let result = try WeekyiiSnapshotMergeService.mergePreferringLocal(
            local: makeSnapshot(
                tasks: [
                    makeTask(id: staleOwnerID, attachmentIds: [attachmentID]),
                    makeTask(id: realOwnerID),
                ],
                attachments: [makeAttachment(id: attachmentID, owner: .task(realOwnerID), bytes: Data([0x01]))]
            ),
            remote: makeSnapshot()
        )

        let tasks = Dictionary(uniqueKeysWithValues: result.snapshot.tasks.map { ($0.id, $0) })
        XCTAssertEqual(tasks[staleOwnerID]?.attachmentIds, [])
        XCTAssertEqual(tasks[realOwnerID]?.attachmentIds, [attachmentID])
        XCTAssertEqual(
            Set(result.report.relationshipConflictsResolved),
            Set([SyncEntityKey(kind: .task, id: staleOwnerID), SyncEntityKey(kind: .task, id: realOwnerID)])
        )
        XCTAssertTrue(result.report.isClean, "\(result.report.diagnostics)")
    }

    func test_merge_keepsSuspendedTaskAttachmentsSeparateFromTaskAttachments() throws {
        let taskID = UUID()
        let suspendedID = UUID()
        let attachmentID = UUID()

        let result = try WeekyiiSnapshotMergeService.mergePreferringLocal(
            local: makeSnapshot(tasks: [makeTask(id: taskID)]),
            remote: makeSnapshot(
                suspendedTasks: [makeSuspendedTask(id: suspendedID)],
                attachments: [makeAttachment(id: attachmentID, owner: .suspendedTask(suspendedID), bytes: Data([0x01]))]
            )
        )

        XCTAssertEqual(result.snapshot.tasks.first?.attachmentIds, [])
        XCTAssertEqual(result.snapshot.suspendedTasks.first?.attachmentIds, [attachmentID])
        XCTAssertTrue(result.report.isClean, "\(result.report.diagnostics)")
    }

    func test_rebuildRelationships_isIdempotent() throws {
        let taskID = UUID()
        let attachmentID = UUID()
        let snapshot = makeSnapshot(
            tasks: [makeTask(id: taskID)],
            attachments: [makeAttachment(id: attachmentID, owner: .task(taskID), bytes: Data([0x01]))]
        )

        let once = WeekyiiSnapshotMergeService.rebuildRelationships(snapshot)
        let twice = WeekyiiSnapshotMergeService.rebuildRelationships(once.snapshot)

        XCTAssertEqual(once.snapshot, twice.snapshot)
        XCTAssertEqual(once.changedOwners, [SyncEntityKey(kind: .task, id: taskID)])
        XCTAssertTrue(twice.changedOwners.isEmpty)
    }

    func test_rebuildRelationships_leavesAnOrphanAttachmentInPlace() throws {
        let attachmentID = UUID()
        let snapshot = makeSnapshot(
            attachments: [makeAttachment(id: attachmentID, owner: .task(UUID()), bytes: Data([0x01]))]
        )

        let rebuilt = WeekyiiSnapshotMergeService.rebuildRelationships(snapshot)

        XCTAssertEqual(rebuilt.snapshot.attachments.count, 1, "an unattachable row must not be dropped")
        XCTAssertTrue(rebuilt.changedOwners.isEmpty)
        XCTAssertEqual(WeekyiiSnapshotRepository.validate(rebuilt.snapshot).map(\.kind), [.orphanAttachment])
    }

    // MARK: - Archive adapter

    func test_archiveAdapter_hoistsNestedAttachmentsAndHabitLogs() throws {
        let taskID = UUID()
        let attachmentID = UUID()
        let habitID = UUID()
        let logID = UUID()
        let bytes = Data([0xAB, 0xCD])

        let export = WeekyiiSnapshotArchiveAdapter.export(
            makeSnapshot(
                tasks: [makeTask(id: taskID, attachmentIds: [attachmentID])],
                attachments: [makeAttachment(id: attachmentID, owner: .task(taskID), bytes: bytes)],
                habits: [makeHabit(id: habitID)],
                habitDayRecords: [makeHabitDayRecord(id: logID, habitId: habitID, dayId: "2026-03-12")]
            ),
            settings: makeSettings(),
            appState: makeAppState()
        )

        XCTAssertTrue(export.isLossless)
        XCTAssertEqual(export.payload.tasks.count, 1)
        XCTAssertEqual(export.payload.tasks.first?.attachments.map(\.id), [attachmentID])
        XCTAssertEqual(export.payload.tasks.first?.attachments.first?.data, bytes)
        XCTAssertEqual(export.payload.habits?.first?.dayLogs?.map(\.id), [logID])

        let restored = WeekyiiSnapshotArchiveAdapter.snapshot(from: export.payload)

        XCTAssertEqual(restored.attachments.count, 1)
        XCTAssertEqual(restored.attachments.first?.owner, .task(taskID))
        XCTAssertEqual(restored.attachments.first?.data, bytes)
        XCTAssertEqual(restored.habitDayRecords.count, 1)
        XCTAssertEqual(restored.habitDayRecords.first?.habitId, habitID)
    }

    func test_archiveAdapter_roundTripsTheWholeGraph() throws {
        let graph = makeGraph()
        let export = WeekyiiSnapshotArchiveAdapter.export(
            graph,
            settings: makeSettings(),
            appState: makeAppState()
        )
        XCTAssertTrue(export.isLossless)

        let restored = WeekyiiSnapshotArchiveAdapter.snapshot(from: export.payload)

        XCTAssertEqual(restored.weeks, graph.weeks)
        XCTAssertEqual(restored.days, graph.days)
        XCTAssertEqual(restored.tasks, graph.tasks)
        XCTAssertEqual(restored.suspendedTasks, graph.suspendedTasks)
        XCTAssertEqual(restored.attachments, graph.attachments)
        XCTAssertEqual(restored.projects, graph.projects)
        XCTAssertEqual(restored.mindStamps, graph.mindStamps)
        XCTAssertEqual(restored.taskTypes, graph.taskTypes)
        XCTAssertEqual(restored.habits, graph.habits)
        XCTAssertEqual(restored.habitDayRecords, graph.habitDayRecords)
        XCTAssertEqual(
            try WeekyiiSnapshotCodec.snapshotHash(restored),
            try WeekyiiSnapshotCodec.snapshotHash(graph)
        )
    }

    func test_archiveAdapterIgnoresLegacyWatermarkAndExportsNeutralV1Value() throws {
        let graph = makeGraph()
        let initialExport = WeekyiiSnapshotArchiveAdapter.export(
            graph,
            settings: makeSettings(),
            appState: makeAppState()
        )
        XCTAssertEqual(initialExport.payload.habits?.first?.generatedThroughDayId, "")

        let encoded = try JSONEncoder().encode(initialExport.payload)
        var archiveObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var habitRecords = try XCTUnwrap(archiveObject["habits"] as? [[String: Any]])
        habitRecords[0]["generatedThroughDayId"] = "2099-12-31"
        archiveObject["habits"] = habitRecords
        let legacyPayloadData = try JSONSerialization.data(withJSONObject: archiveObject)
        let legacyPayload = try JSONDecoder().decode(WeekyiiDataArchiveService.Payload.self, from: legacyPayloadData)

        let normalized = WeekyiiSnapshotArchiveAdapter.snapshot(from: legacyPayload)
        XCTAssertEqual(normalized.habits, graph.habits)

        let reexport = WeekyiiSnapshotArchiveAdapter.export(
            normalized,
            settings: makeSettings(),
            appState: makeAppState()
        )
        XCTAssertEqual(reexport.payload.habits?.first?.generatedThroughDayId, "")
        XCTAssertEqual(WeekyiiDataArchiveService.currentFormatVersion, 1)
        XCTAssertEqual(WeekyiiDataArchiveService.currentSchemaVersion, 8)
    }

    func test_archiveAdapter_reportsWhatTheArchiveFormatCannotHold() throws {
        let orphanAttachmentID = UUID()
        let orphanLogID = UUID()

        let export = WeekyiiSnapshotArchiveAdapter.export(
            makeSnapshot(
                attachments: [makeAttachment(id: orphanAttachmentID, owner: .task(UUID()), bytes: Data([0x01]))],
                habitDayRecords: [makeHabitDayRecord(id: orphanLogID, habitId: nil, dayId: "2026-03-12")]
            ),
            settings: makeSettings(),
            appState: makeAppState()
        )

        XCTAssertFalse(export.isLossless)
        XCTAssertEqual(
            Set(export.droppedEntities),
            Set([
                SyncEntityKey(kind: .attachment, id: orphanAttachmentID),
                SyncEntityKey(kind: .habitDayRecord, id: orphanLogID),
            ])
        )
    }

    /// The adapter changes the in-memory shape only. If someone bumps the archive
    /// format version to carry the normalized shape, this fails.
    func test_archiveAdapter_leavesTheArchiveFormatVersionAlone() throws {
        XCTAssertEqual(WeekyiiDataArchiveService.currentFormatVersion, 1)
        XCTAssertEqual(WeekyiiDataArchiveService.currentSchemaVersion, 8)
        XCTAssertEqual(WeekyiiDataArchiveService.formatIdentifier, "com.fluentdesign.weekyii.archive")
    }

    // MARK: - Fixtures

    private func makeGraph() -> WeekyiiBusinessSnapshot {
        let weekId = "2026-W11"
        let dayId = "2026-03-12"
        let projectID = UUID()
        let habitID = UUID()
        let taskID = UUID()
        let suspendedID = UUID()
        let attachmentID = UUID()

        return makeSnapshot(
            weeks: [makeWeek(weekId: weekId)],
            days: [makeDay(dayId: dayId, weekId: weekId)],
            tasks: [
                makeTask(id: taskID, dayId: dayId, projectId: projectID, habitId: habitID, attachmentIds: [attachmentID])
            ],
            suspendedTasks: [makeSuspendedTask(id: suspendedID)],
            attachments: [makeAttachment(id: attachmentID, owner: .task(taskID), bytes: Data([0x01, 0x02]))],
            projects: [makeProject(id: projectID)],
            mindStamps: [MindStampSnapshot(id: UUID(), text: "stamp", imageBlob: nil, createdAt: makeDate(2026, 3, 1))],
            taskTypes: [makeTaskType(idRaw: "custom-writing")],
            habits: [makeHabit(id: habitID)],
            habitDayRecords: [makeHabitDayRecord(id: UUID(), habitId: habitID, dayId: dayId)]
        )
    }

    private func makeSnapshot(
        weeks: [WeekSnapshot] = [],
        days: [DaySnapshot] = [],
        tasks: [TaskSnapshot] = [],
        suspendedTasks: [SuspendedTaskSnapshot] = [],
        attachments: [AttachmentSnapshot] = [],
        projects: [ProjectSnapshot] = [],
        mindStamps: [MindStampSnapshot] = [],
        taskTypes: [TaskTypeSnapshot] = [],
        habits: [HabitSnapshot] = [],
        habitDayRecords: [HabitDayRecordSnapshot] = []
    ) -> WeekyiiBusinessSnapshot {
        WeekyiiBusinessSnapshot(
            weeks: weeks,
            days: days,
            tasks: tasks,
            suspendedTasks: suspendedTasks,
            attachments: attachments,
            projects: projects,
            mindStamps: mindStamps,
            taskTypes: taskTypes,
            habits: habits,
            habitDayRecords: habitDayRecords
        )
    }

    private func makeWeek(weekId: String) -> WeekSnapshot {
        WeekSnapshot(
            weekId: weekId,
            startDate: makeDate(2026, 3, 9),
            endDate: makeDate(2026, 3, 15),
            status: .present,
            completedTasksCount: 0,
            expiredTasksCount: 0,
            totalStartedDays: 0
        )
    }

    private func makeDay(dayId: String, weekId: String?) -> DaySnapshot {
        DaySnapshot(
            dayId: dayId,
            weekId: weekId,
            date: makeDate(2026, 3, 12),
            dayOfWeek: "Thu",
            status: .draft,
            killTimeHour: 23,
            killTimeMinute: 45,
            followsDefaultKillTime: true,
            initiatedAt: nil,
            closedAt: nil,
            executionModeRaw: ExecutionMode.strict.rawValue,
            isDraftZoneUnlocked: false,
            expiredCount: 0
        )
    }

    private func makeTask(
        id: UUID,
        title: String = "T",
        dayId: String? = nil,
        projectId: UUID? = nil,
        habitId: UUID? = nil,
        startedAt: Date? = nil,
        attachmentIds: [UUID] = []
    ) -> TaskSnapshot {
        TaskSnapshot(
            id: id,
            dayId: dayId,
            projectId: projectId,
            habitId: habitId,
            title: title,
            taskDescription: "",
            taskType: .regular,
            taskTypeIdRaw: TaskType.regular.rawValue,
            order: 1,
            zone: .draft,
            startedAt: startedAt,
            endedAt: nil,
            completedOrder: 0,
            steps: [],
            // Sorted here because the repository also sorts, so a fixture and a
            // rebuilt snapshot compare equal.
            attachmentIds: attachmentIds.sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func makeSuspendedTask(id: UUID, attachmentIds: [UUID] = []) -> SuspendedTaskSnapshot {
        SuspendedTaskSnapshot(
            id: id,
            title: "S",
            taskDescription: "",
            taskType: .regular,
            taskTypeIdRaw: TaskType.regular.rawValue,
            createdAt: makeDate(2026, 3, 1),
            decisionDeadline: makeDate(2026, 3, 22),
            preferredCountdownDays: 10,
            snoozeCount: 0,
            statusRaw: SuspendedTaskStatus.active.rawValue,
            steps: [],
            attachmentIds: attachmentIds.sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func makeAttachment(id: UUID, owner: AttachmentOwner, bytes: Data?) -> AttachmentSnapshot {
        AttachmentSnapshot(
            id: id,
            owner: owner,
            data: bytes,
            fileName: "a.bin",
            fileType: "application/octet-stream",
            createdAt: makeDate(2026, 3, 1)
        )
    }

    private func makeProject(id: UUID) -> ProjectSnapshot {
        ProjectSnapshot(
            id: id,
            name: "P",
            projectDescription: "",
            color: "#C46A1A",
            icon: "folder.fill",
            status: .active,
            startDate: makeDate(2026, 3, 1),
            endDate: makeDate(2026, 3, 31),
            createdAt: makeDate(2026, 3, 1),
            tileSizeRaw: ProjectTileSize.medium.rawValue,
            tileOrder: 0
        )
    }

    private func makeTaskType(idRaw: String) -> TaskTypeSnapshot {
        TaskTypeSnapshot(
            idRaw: idRaw,
            name: "写作",
            iconName: "pencil",
            colorHex: "#C46A1A",
            baseKindRaw: TaskType.regular.rawValue,
            sortOrder: 0,
            isBuiltIn: false,
            isArchived: false
        )
    }

    private func makeHabit(id: UUID) -> HabitSnapshot {
        HabitSnapshot(
            id: id,
            name: "H",
            iconName: "repeat.circle.fill",
            colorHex: "#34C759",
            categoryRaw: HabitCategory.health.rawValue,
            scheduleKindRaw: HabitScheduleKind.weekly.rawValue,
            scheduleWeekdaysRaw: 0b0011111,
            scheduleMonthDaysRaw: 0,
            startDayId: "2026-03-01",
            isActive: true,
            createdAt: makeDate(2026, 3, 1),
            sortOrder: 0
        )
    }

    private func makeHabitDayRecord(id: UUID, habitId: UUID?, dayId: String) -> HabitDayRecordSnapshot {
        HabitDayRecordSnapshot(
            id: id,
            habitId: habitId,
            dayId: dayId,
            statusRaw: HabitDayRecordStatus.pending.rawValue,
            createdAt: makeDate(2026, 3, 12),
            completedAt: nil
        )
    }

    private func makeSettings() -> WeekyiiDataArchiveService.SettingsRecord {
        WeekyiiDataArchiveService.SettingsRecord(
            defaultKillTimeHour: 23,
            defaultKillTimeMinute: 45,
            defaultTaskTypeRaw: TaskType.regular.rawValue,
            defaultTaskTypeIdRaw: TaskType.regular.rawValue,
            defaultExecutionModeRaw: ExecutionMode.strict.rawValue,
            killTimeReminderMinutes: 30,
            fixedReminderEnabled: false,
            fixedReminderHour: 9,
            fixedReminderMinute: 0,
            weekStartsOnMonday: true,
            defaultProjectDurationDays: 30,
            defaultProjectTileSizeRaw: ProjectTileSize.medium.rawValue,
            pendingMonthShowRegular: true,
            pendingMonthShowDDL: true,
            pendingMonthShowLeisure: false,
            selectedThemeRaw: WeekTheme.amber.rawValue,
            appearanceModeRaw: "system",
            premiumThemeUnlocked: false
        )
    }

    private func makeAppState() -> WeekyiiDataArchiveService.AppStateRecord {
        WeekyiiDataArchiveService.AppStateRecord(
            daysStartedCount: 3,
            dataRevision: 7,
            stateTransitionRevision: 2,
            systemStartDate: makeDate(2026, 1, 1),
            lastProcessedDate: makeDate(2026, 3, 12),
            lastRolloverAt: makeDate(2026, 3, 12)
        )
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
}
