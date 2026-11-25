import CryptoKit
import Foundation
import SwiftData

/// Consolidates the legacy `Weekyii.local.store` into the canonical
/// `Weekyii.store`, once.
///
/// ## Why this exists
///
/// Earlier builds could keep business data in either `Weekyii.store` or
/// `Weekyii.local.store`, depending on the selected persistence mode. A device
/// that used both modes may therefore hold two live business graphs, neither a
/// subset of the other. Current runtime uses one canonical store, so the historical
/// file cannot simply be deleted — it may still hold some of the user's data.
///
/// This type is the "migrate, don't discard" step: it unions the legacy graph into
/// the canonical one, then retires the legacy file so normal runtime can never
/// open it again.
///
/// ## Startup integration
///
/// B1b invokes consolidation before opening the canonical runtime container. A
/// failure is allowed to stop launch so legacy user data cannot be skipped.
///
/// ## Which side wins
///
/// There is no trustworthy common ancestor between the two stores — that is the
/// defect being retired — so a true three-way merge is unavailable, and pretending
/// otherwise would be fiction. The rule is the plan's:
///
/// * different business ids → both kept;
/// * same business id, different content → **canonical wins**;
/// * anything ambiguous → refuse, loudly.
///
/// That is `WeekyiiSnapshotMergeService.mergePreferringLocal(local: canonical,
/// remote: legacy)`: canonical is the "local" side, so a record already present
/// there is never replaced. Consolidation therefore only has to *add* what
/// canonical lacks, which is all `write` does. Add-only is also what makes a half-
/// finished run repeatable: a second pass contributes nothing, and the retry after a
/// failed retirement lands on rows that are already there and verifies them again.
///
/// ## Crash safety, in one paragraph
///
/// Both stores are snapshotted *before* they are first opened — opening a persistent
/// store can migrate or checkpoint it, so a later snapshot is not a snapshot of what
/// was there. The commit is add-only, then re-read and compared by content hash rather
/// than by identity. The legacy bundle is copied out and verified by SHA-256 before any
/// original is touched. The primary `Weekyii.local.store` is then the *first* thing
/// removed: that file is the state boundary, and once it is gone no runtime can open the
/// legacy database again. Everything after it — finalizing the archive, deleting the WAL,
/// SHM and support directories — is best-effort cleanup of bytes the verified archive
/// already holds, so a leftover sidecar can never send a later launch back to an
/// incomplete source. The completion marker is written last, so it is never true while
/// `Weekyii.local.store` is still a file the old runtime would open, and it is never
/// the reason a retirement is skipped. A legacy store with no migratable user data is
/// retired the same way, for the same reason.
///
/// ## Relationships
///
/// Parent links are applied through the child's own pointer (`task.day`,
/// `attachment.task`, …), never by rewriting a parent's collection. The
/// attachment's `owner` is the authority on ownership, matching
/// `rebuildRelationships`, so an attachment arriving from the legacy store joins
/// the task that owns it rather than one that merely listed it.
///
/// ## What it deliberately never touches
///
/// `UserSettings`, `AppState`, entitlements, sync preferences, account state.
/// This is business-data consolidation; its only preference write is its own
/// completion marker. Both stores use the local SwiftData configuration while
/// they are inspected and consolidated.
enum LegacyStoreConsolidator {

    // MARK: - Contract

    /// Device-local, one-way latch. Written last: only after the canonical store has
    /// been re-read and compared by content hash where there was an import to verify,
    /// and in every case only after the legacy store has been retired out of the store
    /// directory. A crash before this point is recoverable by running again, and this
    /// marker is never read as permission to skip retirement.
    static let completionMarkerKey = "weekyii.legacyStoreConsolidationCompletedV1"

    /// Directory the retired legacy store is moved into, beside the canonical store.
    static let archiveDirectoryName = "LegacyStores"

    /// Store file names remain explicit because one is the current runtime store
    /// and the other is a historical migration source.
    static let canonicalStoreFileName = "Weekyii.store"
    static let legacyStoreFileName = "Weekyii.local.store"

    enum Outcome: Equatable {
        /// The marker is set: nothing was read, written, or moved.
        case alreadyConsolidated
        /// No legacy file at that path — the common case, for a device that never
        /// used the local-only store.
        case noLegacyStore
        /// The legacy store opened cleanly and held no migratable user data — see
        /// `hasMigratableUserData`, where a store holding only built-in task types
        /// counts as none. There was nothing to import, but the file still had to stop
        /// being a store the old runtime could open: left in place it would be
        /// re-inspected on every launch, and each inspection takes another pre-open
        /// recovery point, so the retention window would eventually evict the user's
        /// real restore points. So it is retired through the same verified mechanism as
        /// a real migration and the marker is written. Canonical is not opened: there is
        /// no import for a content comparison to verify.
        case retiredWithoutImport
        /// Legacy entities were unioned into the canonical store and the legacy
        /// store was retired.
        case consolidated
    }

    enum LegacyArchive: Equatable {
        case notAttempted
        case movedToArchive(URL)
        /// Nothing was left at the legacy path to move.
        case alreadyAbsent
    }

    /// No `Equatable`: the payload types it would compare carry main-actor-isolated
    /// conformances, so synthesizing it here only produces concurrency warnings that
    /// nothing needs — callers assert on `outcome` and the key arrays.
    struct Report {
        let outcome: Outcome
        /// Legacy entities the canonical store did not already hold, canonical order.
        let entitiesAdded: [SyncEntityKey]
        /// Keys both stores held with different content; canonical's value won.
        let conflictsResolvedInFavourOfCanonical: [SyncEntityKey]
        /// Verified recovery-point folder names, each taken before the store it
        /// describes was first opened by this migration.
        let recoverySnapshots: [String]
        let legacyArchive: LegacyArchive
        /// Non-fatal trouble after the primary store was already out of its active
        /// path — a staging bundle that could not be renamed, sidecars that could not
        /// be deleted. The archive is complete in every one of these cases, so they are
        /// recorded rather than thrown: a later launch must never come back to "finish"
        /// a retirement whose state boundary has already been crossed.
        let retirementWarnings: [String]
        /// Canonical store entity counts. Both are 0 on `.retiredWithoutImport`, which
        /// never opens canonical.
        let entityCountBefore: Int
        let entityCountAfter: Int

        var didChangeCanonicalStore: Bool { !entitiesAdded.isEmpty }
    }

    enum ConsolidationError: LocalizedError {
        /// Two rows claim one business identity, or a link dangles, in the legacy
        /// store. Picking a survivor would decide for the user which record is real.
        case legacyStoreAmbiguous([WeekyiiSnapshotDiagnostic])
        case canonicalStoreAmbiguous([WeekyiiSnapshotDiagnostic])
        /// Both sides were individually clean, so this is the *union* being
        /// inconsistent — a parent neither store had. Committing it would write a
        /// graph that only a repair pass could explain afterwards.
        case mergedSnapshotAmbiguous([WeekyiiSnapshotDiagnostic])
        /// The merged snapshot says a record has a parent, but no object for it
        /// could be resolved — neither pre-existing nor added by this pass. Skipping
        /// it silently would drop data, so it is fatal.
        case parentEntityMissingForMerge(SyncEntityKey, parent: SyncEntityKey)
        /// A merged entity was not present in the canonical store after the commit
        /// and re-read. The marker is not written, so a retry runs again.
        case entitiesAbsentAfterCommit([SyncEntityKey])
        /// The canonical store holds every planned entity but not the planned *content*
        /// (or holds entities nobody planned). Identity alone is not proof that the
        /// writer copied a field, so this is the integrity test that gates the marker;
        /// the two snapshot hashes ride along because they are what a field-by-field
        /// comparison of the two archived snapshots starts from.
        case canonicalContentMismatch(
            differing: [SyncEntityKey],
            unplanned: [SyncEntityKey],
            expectedSnapshotHash: String,
            committedSnapshotHash: String
        )
        /// The union is committed and verified, but the legacy bundle could not be moved
        /// out of the store directory. Fatal rather than reported, because the
        /// completion marker must never exist while `Weekyii.local.store` is still the
        /// file the old runtime would open. Nothing above this point is durable except
        /// the add-only canonical rows, so the next run re-verifies and retires again.
        case legacyRetirementFailed(String)
        case legacyStoreUnreadable(String)
        case canonicalStoreUnreadable(String)

        var errorDescription: String? {
            switch self {
            case .legacyStoreAmbiguous(let diagnostics):
                return "旧本地数据库有 \(diagnostics.count) 处身份歧义，已拒绝合并：\(diagnostics.map(\.description).joined(separator: "; "))"
            case .canonicalStoreAmbiguous(let diagnostics):
                return "当前数据库有 \(diagnostics.count) 处身份歧义，已拒绝合并：\(diagnostics.map(\.description).joined(separator: "; "))"
            case .mergedSnapshotAmbiguous(let diagnostics):
                return "两份数据合并后仍有 \(diagnostics.count) 处不一致，已拒绝写入：\(diagnostics.map(\.description).joined(separator: "; "))"
            case .parentEntityMissingForMerge:
                // The keys ride on the error value; they are deliberately not
                // interpolated here, because `SyncEntityKey`'s
                // `CustomStringConvertible` conformance is main-actor isolated and
                // this is a nonisolated `LocalizedError` requirement.
                return "合并结果里有一条记录找不到它的父记录，已拒绝写入。"
            case .entitiesAbsentAfterCommit(let keys):
                return "合并写入后仍有 \(keys.count) 条记录不在当前数据库中，已放弃完成标记。"
            case .canonicalContentMismatch(let differing, let unplanned, let expectedHash, let committedHash):
                return "合并写入后当前数据库的内容与预期不一致：\(differing.count) 条记录内容不符，\(unplanned.count) 条记录不在计划内（预期快照 \(expectedHash.prefix(12))，实际 \(committedHash.prefix(12))），已放弃完成标记。"
            case .legacyRetirementFailed(let reason):
                return "数据已并入当前数据库，但旧本地数据库未能安全退役：\(reason)。完成标记未写入，下次启动会重试。"
            case .legacyStoreUnreadable(let reason):
                return "旧本地数据库无法读取：\(reason)"
            case .canonicalStoreUnreadable(let reason):
                return "当前数据库无法读取：\(reason)"
            }
        }
    }

    // MARK: - Entry point

    /// Runs the consolidation unless it has already run.
    ///
    /// Both store URLs are explicit parameters — including in production, where
    /// they are the defaults — so the paths the tests exercised are the paths the
    /// shipping code uses. `retirementFileSystem` is the one test seam: the removal of
    /// the legacy files, injectable so the mid-retirement state machine can be pinned
    /// deterministically instead of provoked with permission accidents.
    static func consolidateIfNeeded(
        canonicalStoreURL: URL = LegacyStoreConsolidator.canonicalStoreURL(),
        legacyStoreURL: URL = LegacyStoreConsolidator.legacyStoreURL(),
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        retirementFileSystem: RetirementFileSystem = .live
    ) throws -> Report {
        guard defaults.object(forKey: completionMarkerKey) == nil else {
            return Report(
                outcome: .alreadyConsolidated,
                entitiesAdded: [],
                conflictsResolvedInFavourOfCanonical: [],
                recoverySnapshots: [],
                legacyArchive: .notAttempted,
                retirementWarnings: [],
                entityCountBefore: 0,
                entityCountAfter: 0
            )
        }

        guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
            return Report(
                outcome: .noLegacyStore,
                entitiesAdded: [],
                conflictsResolvedInFavourOfCanonical: [],
                recoverySnapshots: [],
                legacyArchive: .notAttempted,
                retirementWarnings: [],
                entityCountBefore: 0,
                entityCountAfter: 0
            )
        }

        // The legacy store's raw bytes are protected *before* the first open. Opening
        // a persistent store can itself write — a WAL checkpoint, or the case that
        // matters here: a schema migration of a store that has been dormant since an
        // older app build. A snapshot taken afterwards is not a snapshot of what was
        // there, so this call cannot move below `readSnapshot`.
        var recoverySnapshots: [String] = []
        if let legacyPoint = try BackupRecoveryService.createSnapshot(
            storeURL: legacyStoreURL,
            reason: "pre-consolidation-legacy"
        ) {
            recoverySnapshots.append(legacyPoint.folderName)
        }

        let legacy = try readSnapshot(at: legacyStoreURL, role: .legacy)
        guard hasMigratableUserData(legacy) else {
            // Nothing to import, but the file still has to stop being a store the old
            // runtime could open. If it stayed, every launch would take another
            // pre-open recovery point for a store that is never going to be migrated,
            // and `BackupRecoveryService`'s retention window is shared with the user's
            // real restore points. Canonical is not opened on this path: there is no
            // import, so there is nothing for a content comparison to verify.
            let retirement = try retireLegacyStore(
                at: legacyStoreURL,
                beside: canonicalStoreURL,
                now: now,
                fileManager: fileManager,
                fileSystem: retirementFileSystem
            )
            defaults.set(true, forKey: completionMarkerKey)
            return Report(
                outcome: .retiredWithoutImport,
                entitiesAdded: [],
                conflictsResolvedInFavourOfCanonical: [],
                recoverySnapshots: recoverySnapshots,
                legacyArchive: retirement.archive,
                retirementWarnings: retirement.warnings,
                entityCountBefore: 0,
                entityCountAfter: 0
            )
        }

        // Canonical's pre-open point, taken only now that consolidation is actually
        // required: opening it can migrate or checkpoint it too.
        if let canonicalPoint = try BackupRecoveryService.createSnapshot(
            storeURL: canonicalStoreURL,
            reason: "pre-consolidation-canonical"
        ) {
            recoverySnapshots.append(canonicalPoint.folderName)
        }

        let canonical = try readSnapshot(at: canonicalStoreURL, role: .canonical)

        let merged = try WeekyiiSnapshotMergeService.mergePreferringLocal(
            local: canonical,
            remote: legacy
        )
        guard merged.report.diagnostics.isEmpty else {
            throw ConsolidationError.mergedSnapshotAmbiguous(merged.report.diagnostics)
        }

        let added = merged.report.addedFromRemote
        if !added.isEmpty {
            try write(added: added, from: merged.snapshot, intoCanonicalStoreAt: canonicalStoreURL)
        }

        let verified = try readSnapshot(at: canonicalStoreURL, role: .canonical)
        let absent = Set(merged.snapshot.entityKeys()).subtracting(verified.entityKeys())
        guard absent.isEmpty else {
            throw ConsolidationError.entitiesAbsentAfterCommit(absent.sorted())
        }
        try verifyContent(expected: merged.snapshot, committed: verified)

        // Retirement comes first and the latch last: a marker must never exist while
        // `Weekyii.local.store` is still sitting in the directory the old runtime
        // resolves stores from. A throw anywhere above `defaults.set` — including a
        // failed retirement — leaves the marker unset, so the next run re-verifies the
        // add-only canonical writes and retires again.
        let retirement = try retireLegacyStore(
            at: legacyStoreURL,
            beside: canonicalStoreURL,
            now: now,
            fileManager: fileManager,
            fileSystem: retirementFileSystem
        )
        defaults.set(true, forKey: completionMarkerKey)

        return Report(
            outcome: .consolidated,
            entitiesAdded: added,
            conflictsResolvedInFavourOfCanonical: merged.report.conflicting,
            recoverySnapshots: recoverySnapshots,
            legacyArchive: retirement.archive,
            retirementWarnings: retirement.warnings,
            entityCountBefore: canonical.entityCount,
            entityCountAfter: verified.entityCount
        )
    }

    // MARK: - Store paths

    static func canonicalStoreURL(fileManager: FileManager = .default) -> URL {
        storeDirectory(fileManager: fileManager).appendingPathComponent(canonicalStoreFileName)
    }

    static func legacyStoreURL(fileManager: FileManager = .default) -> URL {
        storeDirectory(fileManager: fileManager).appendingPathComponent(legacyStoreFileName)
    }

    /// Resolves the historical source beside a supplied canonical URL. The
    /// bootstrap uses this overload for isolated test directories; production
    /// resolves both names through the standard Application Support directory.
    static func legacyStoreURL(beside canonicalStoreURL: URL) -> URL {
        canonicalStoreURL.deletingLastPathComponent().appendingPathComponent(legacyStoreFileName)
    }

    private static func storeDirectory(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Weekyii", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Read

    private enum StoreRole {
        case legacy
        case canonical

        var configurationName: String {
            switch self {
            case .legacy: return "Weekyii.legacyConsolidation.legacy"
            case .canonical: return "Weekyii.legacyConsolidation.canonical"
            }
        }

        func ambiguous(_ diagnostics: [WeekyiiSnapshotDiagnostic]) -> ConsolidationError {
            switch self {
            case .legacy: return .legacyStoreAmbiguous(diagnostics)
            case .canonical: return .canonicalStoreAmbiguous(diagnostics)
            }
        }

        func unreadable(_ reason: String) -> ConsolidationError {
            switch self {
            case .legacy: return .legacyStoreUnreadable(reason)
            case .canonical: return .canonicalStoreUnreadable(reason)
            }
        }
    }

    /// Opens one store with the local SwiftData configuration and demands a clean
    /// snapshot of it.
    ///
    /// A `ModelConfiguration` is built here rather than going through
    /// `WeekyiiPersistence.makeModelContainer`, because the migration needs to open
    /// historical stores independently of the current runtime configuration.
    ///
    /// Both stores open saveable, the legacy one included. Opening it read-only would
    /// be the tidy-looking choice, and it is the wrong one: a `Weekyii.local.store`
    /// left behind by an older build can sit on a dormant schema, and the migration
    /// to V8 has to be allowed to run. What makes that safe is not `allowsSave: false`
    /// but the pre-open recovery point taken before this call, and what makes it
    /// safe is the pre-open recovery point taken before this call. The migration
    /// itself never writes through this context.
    private static func readSnapshot(
        at storeURL: URL,
        role: StoreRole
    ) throws -> WeekyiiBusinessSnapshot {
        let container = try makeContainer(at: storeURL, name: role.configurationName)
        do {
            return try WeekyiiSnapshotRepository.requireCleanSnapshot(from: container.mainContext)
        } catch let error as WeekyiiSnapshotRepositoryError {
            guard case .ambiguousStore(let diagnostics) = error else {
                throw role.unreadable(error.localizedDescription)
            }
            throw role.ambiguous(diagnostics)
        } catch {
            throw role.unreadable(error.localizedDescription)
        }
    }

    private static func makeContainer(
        at storeURL: URL,
        name: String
    ) throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let configuration = ModelConfiguration(
            name,
            schema: WeekyiiPersistence.currentSchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: WeekyiiPersistence.currentSchema,
            migrationPlan: WeekyiiMigrationPlan.self,
            configurations: configuration
        )
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            retainedConsolidationContainers.append(container)
        }
        #endif
        return container
    }

    #if DEBUG
    /// Containers this migration creates are deliberately not released inside an
    /// `@MainActor` XCTest process: the Swift 6 back-destructor shim
    /// (`swift_task_deinitOnExecutorMainActorBackDeploy`) double-frees task-local
    /// storage when a `@MainActor` `ModelContainer` is deallocated on the iOS 26.2
    /// simulator, which crashes the test run. Same reason and same guard as
    /// the app bootstrap's open canonical container — a normal debug app run
    /// still releases them.
    @MainActor
    static var retainedConsolidationContainers: [ModelContainer] = []
    #endif

    // MARK: - Write

    /// Inserts exactly the entities the canonical store lacks.
    ///
    /// Add-only is the mechanical form of "canonical wins": a record that already
    /// exists here is never touched, so a same-key conflict cannot resolve any
    /// other way. The whole commit happens in one context and one `save()`, and any
    /// throw rolls it back — the canonical store is never left holding half a union.
    private static func write(
        added: [SyncEntityKey],
        from merged: WeekyiiBusinessSnapshot,
        intoCanonicalStoreAt storeURL: URL
    ) throws {
        let container = try makeContainer(
            at: storeURL,
            name: "Weekyii.legacyConsolidation.commit"
        )
        let context = container.mainContext
        do {
            var writer = try SnapshotWriter(context: context, adding: Set(added))
            // Insertion order follows the dependency direction: a row is only
            // written once the parents it points at are resolvable, whether they
            // were already in the store or were added moments ago.
            for snapshot in merged.taskTypes { writer.insert(snapshot) }
            for snapshot in merged.habits { writer.insert(snapshot) }
            for snapshot in merged.habitDayRecords { try writer.insert(snapshot) }
            for snapshot in merged.projects { writer.insert(snapshot) }
            for snapshot in merged.weeks { writer.insert(snapshot) }
            for snapshot in merged.days { try writer.insert(snapshot) }
            for snapshot in merged.tasks { try writer.insert(snapshot) }
            for snapshot in merged.suspendedTasks { writer.insert(snapshot) }
            for snapshot in merged.mindStamps { writer.insert(snapshot) }
            // Attachments last: their owner is a task or a suspended task, and both
            // passes above must have run before ownership can be resolved.
            for snapshot in merged.attachments { try writer.insert(snapshot) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - What counts as user data

    /// Rule 2, specialized for this migration.
    ///
    /// `WeekyiiBusinessSnapshot.isEmpty` is deliberately untouched: for the sync layer
    /// the meaningful question is "no records at all", and folding this migration's
    /// product judgement into it would silently redefine what a later phase calls an
    /// empty graph.
    ///
    /// A store holding nothing but built-in `TaskTypeDefinition` rows has no migratable
    /// user data. Built-ins are immutable in the current product UI, so they cannot
    /// record a user decision, and the canonical runtime re-seeds the same rows itself.
    /// A custom task type is the opposite — a row the user authored — so its presence
    /// alone makes the store worth consolidating, even if nothing else is in there.
    static func hasMigratableUserData(_ snapshot: WeekyiiBusinessSnapshot) -> Bool {
        if snapshot.taskTypes.contains(where: { !$0.isBuiltIn }) { return true }
        return snapshot.entityCount > snapshot.taskTypes.count
    }

    // MARK: - Post-commit verification

    /// Proves the canonical store reads back the graph the merge planned, field by
    /// field, rather than merely holding the right ids.
    ///
    /// A key-only check cannot tell a correct row from an empty one: the whole failure
    /// mode of a migration that writes models by hand is a forgotten property, and a
    /// task that exists with the default title and no steps is exactly as present as
    /// one that is right. `entityHash` is what closes that — steps are embedded in the
    /// task record, parent links are fields of it, and a binary counts through its
    /// `blobSHA256` rather than its length, so a mis-copied attachment differs too.
    ///
    /// Comparison is against `merged.snapshot`, which `rebuildRelationships` has
    /// already derived from each attachment's own `owner`. That is the same rule the
    /// store applies through SwiftData's inverse relationships, so a correct writer
    /// cannot trip this check, and a parent's attachment list gaining an added child is
    /// not mistaken for drift.
    static func verifyContent(
        expected: WeekyiiBusinessSnapshot,
        committed: WeekyiiBusinessSnapshot
    ) throws {
        let expectedHashes = try WeekyiiSnapshotCodec.entityHashes(expected)
        let committedHashes = try WeekyiiSnapshotCodec.entityHashes(committed)

        var differing: [SyncEntityKey] = []
        for key in expectedHashes.keys.sorted() {
            guard committedHashes[key] != expectedHashes[key] else { continue }
            differing.append(key)
        }
        let planned = Set(expectedHashes.keys)
        let unplanned = committedHashes.keys.filter { !planned.contains($0) }.sorted()

        guard differing.isEmpty, unplanned.isEmpty else {
            throw ConsolidationError.canonicalContentMismatch(
                differing: differing,
                unplanned: unplanned,
                expectedSnapshotHash: try WeekyiiSnapshotCodec.snapshotHash(expected),
                committedSnapshotHash: try WeekyiiSnapshotCodec.snapshotHash(committed)
            )
        }
    }

    // MARK: - Retiring the legacy store

    /// Copies the legacy bundle out, verifies it cryptographically, and only then
    /// removes the originals — the primary store first, because that file is the state
    /// boundary.
    ///
    /// The order *is* the design:
    ///
    /// 1. **Copy.** Every source goes into a staging bundle. Nothing in the source
    ///    directory is touched, so a failure here costs nothing but the staging copy.
    /// 2. **Verify.** Each copy is compared against its source by SHA-256, per regular
    ///    file, over the complete relative-path set. Equal byte counts are not evidence:
    ///    two files of the same length holding different bytes must not compare equal.
    /// 3. **Retire the primary.** `Weekyii.local.store` leaves its active path. This is
    ///    the one step whose failure is fatal, because until it happens the old runtime
    ///    can still open the legacy database. Throwing here keeps the completion marker
    ///    honest; the sources are otherwise untouched and the next run retries.
    /// 4. **Clean up, best effort.** Finalizing the staging bundle into its archive name
    ///    and deleting the WAL, SHM and support directories. The state boundary has
    ///    already been crossed and the verified archive already holds these bytes, so a
    ///    failure is recorded as a warning rather than thrown — a later launch must
    ///    never be sent back to "finish" a retirement by reopening an incomplete legacy
    ///    source.
    ///
    /// The destination stays inside the store directory so it travels with the app's
    /// support files, but as a *subdirectory*: store resolution only ever looks at
    /// `App Support/Weekyii/<name>.store`, so a retired file can no longer be opened by
    /// any code path.
    private static func retireLegacyStore(
        at legacyStoreURL: URL,
        beside canonicalStoreURL: URL,
        now: Date,
        fileManager: FileManager,
        fileSystem: RetirementFileSystem
    ) throws -> (archive: LegacyArchive, warnings: [String]) {
        // The primary file is the state boundary: without it nothing can open the legacy
        // database, so there is nothing left to retire and no marker left to earn.
        guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
            return (.alreadyAbsent, [])
        }
        let sources = legacyStoreFiles(for: legacyStoreURL, fileManager: fileManager)

        let root = canonicalStoreURL.deletingLastPathComponent()
            .appendingPathComponent(archiveDirectoryName, isDirectory: true)
        let timestamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let bundleName = "\(timestamp)-\(legacyStoreFileName)"
        let staging = root.appendingPathComponent("\(bundleName).staging", isDirectory: true)
        let destination = root.appendingPathComponent(bundleName, isDirectory: true)

        // Steps 1 and 2. The source is not touched, so any failure here just discards
        // the incomplete staging copy.
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            excludeFromBackup(at: root)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            for source in sources {
                try fileManager.copyItem(
                    at: source,
                    to: staging.appendingPathComponent(source.lastPathComponent)
                )
            }
            for source in sources {
                try verifyCopy(
                    of: source,
                    matches: staging.appendingPathComponent(source.lastPathComponent),
                    fileManager: fileManager
                )
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            if let error = error as? ConsolidationError { throw error }
            throw ConsolidationError.legacyRetirementFailed(error.localizedDescription)
        }

        // Step 3. Fatal on failure, and the staging copy goes with it: it was a copy of
        // a source that is still intact, so it is redundant rather than recovery data,
        // and keeping it would stack up bundles across retries. A primary that left on
        // its own has already crossed the boundary, which is what this step is for — so
        // that is success, not a failure.
        if fileManager.fileExists(atPath: legacyStoreURL.path) {
            do {
                try fileSystem.removeItem(legacyStoreURL, fileManager)
            } catch {
                try? fileManager.removeItem(at: staging)
                throw ConsolidationError.legacyRetirementFailed(error.localizedDescription)
            }
        }

        // Step 4. Renaming is cosmetic — a verified bundle that could not be renamed is
        // still retired, and is reported at the path it actually occupies.
        var archive = LegacyArchive.movedToArchive(destination)
        var warnings: [String] = []
        if (try? fileManager.moveItem(at: staging, to: destination)) == nil {
            archive = .movedToArchive(staging)
            warnings.append("退役副本未能重命名到最终路径，仍留在暂存目录：\(staging.lastPathComponent)")
        }

        var orphaned: [String] = []
        for source in sources where source.path != legacyStoreURL.path {
            // A sidecar that vanished on its own needs no cleanup, and reporting it as
            // an orphan would be noise: SQLite deletes its `-shm` whenever the last
            // connection closes.
            guard fileManager.fileExists(atPath: source.path) else { continue }
            do {
                try fileSystem.removeItem(source, fileManager)
            } catch {
                orphaned.append(source.lastPathComponent)
            }
        }
        if !orphaned.isEmpty {
            warnings.append(
                "旧本地库主体已退役，但 \(orphaned.count) 项附属文件未能清理（\(orphaned.sorted().joined(separator: "、"))）；完整副本已在归档中，下次启动不会重开旧库。"
            )
        }
        return (archive, warnings)
    }

    /// The removal of legacy files, split out as a seam so tests can fail the step
    /// after archive verification deterministically — the state machine's boundary
    /// between "nothing happened" and "the old runtime can no longer open this store"
    /// is otherwise only reachable by provoking real filesystem failures.
    struct RetirementFileSystem {
        var removeItem: (URL, FileManager) throws -> Void

        static let live = RetirementFileSystem(removeItem: { url, fileManager in
            try fileManager.removeItem(at: url)
        })
    }

    /// Proves a copied item holds the same bytes as its source: for a regular file its
    /// SHA-256, for a directory its complete relative-path set plus every regular
    /// file's SHA-256. Byte length rides along as supplemental metadata and in the
    /// failure, never as the criterion — a same-length corruption must not verify.
    ///
    /// This digest is backup-integrity evidence only. Nothing in the merge, in
    /// `rebuildRelationships` or in `SyncEntityKey` selection ever consults it.
    static func verifyCopy(of source: URL, matches copy: URL, fileManager: FileManager) throws {
        let sourceIsDirectory = try isDirectory(at: source, fileManager: fileManager)
        let copyIsDirectory = try isDirectory(at: copy, fileManager: fileManager)
        guard sourceIsDirectory == copyIsDirectory else {
            throw ConsolidationError.legacyRetirementFailed("退役副本与源文件的类型不一致：\(source.lastPathComponent)")
        }

        let sourceDigests = try fileDigests(of: source, isDirectory: sourceIsDirectory, fileManager: fileManager)
        let copyDigests = try fileDigests(of: copy, isDirectory: copyIsDirectory, fileManager: fileManager)
        guard sourceDigests == copyDigests else {
            let differing = Set(sourceDigests.keys).union(copyDigests.keys)
                .filter { sourceDigests[$0] != copyDigests[$0] }
                .sorted()
            throw ConsolidationError.legacyRetirementFailed(
                "退役副本与源文件不一致：\(source.lastPathComponent)（\(differing.prefix(3).joined(separator: "、")) 等 \(differing.count) 项）"
            )
        }
    }

    private struct FileDigest: Equatable {
        let byteCount: Int
        let sha256: String
    }

    private static func isDirectory(at url: URL, fileManager: FileManager) throws -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ConsolidationError.legacyRetirementFailed("退役时找不到文件：\(url.lastPathComponent)")
        }
        return isDirectory.boolValue
    }

    /// Relative path → digest for everything under `url`: the item itself when it is a
    /// regular file (keyed `""`), or every regular file under it when it is a
    /// directory, keyed by its path relative to that directory. A directory's complete
    /// key set is therefore part of the comparison, so a copy that dropped, added or
    /// renamed a file cannot compare equal.
    private static func fileDigests(
        of url: URL,
        isDirectory: Bool,
        fileManager: FileManager
    ) throws -> [String: FileDigest] {
        guard isDirectory else {
            return ["": try digest(of: url)]
        }

        let prefix = url.path + "/"
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: nil
        ) else {
            throw ConsolidationError.legacyRetirementFailed("无法枚举退役目录。")
        }
        var digests: [String: FileDigest] = [:]
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: Set(keys)).isRegularFile) == true else { continue }
            digests[String(fileURL.path.dropFirst(prefix.count))] = try digest(of: fileURL)
        }
        return digests
    }

    /// Streamed SHA-256, shaped like `WeekyiiPersistence.makeFileEntry`: the support
    /// directories hold `@Attribute(.externalStorage)` attachment bytes, so nothing
    /// here may load a file whole.
    private static func digest(of url: URL) throws -> FileDigest {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ConsolidationError.legacyRetirementFailed("无法读取退役文件：\(url.lastPathComponent)")
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        var byteCount = 0
        do {
            while true {
                let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
                guard !chunk.isEmpty else { break }
                byteCount += chunk.count
                hasher.update(data: chunk)
            }
        } catch {
            throw ConsolidationError.legacyRetirementFailed("读取退役文件失败：\(url.lastPathComponent)")
        }
        return FileDigest(
            byteCount: byteCount,
            sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    /// `LegacyStores/` is a local migration recovery duplicate and can carry attachment
    /// blobs, so it must not double the user's system-backup footprint. Best effort: a
    /// backup attribute is never a reason to fail a migration. Same treatment
    /// `WeekyiiPersistence` gives `Backups/`.
    private static func excludeFromBackup(at url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    /// The store file, its WAL sidecars, and every spelling Core Data has used for
    /// the external-storage support directory: hidden or visible, named after the
    /// store file or after its extension-stripped base name.
    /// `TaskAttachment.data` is `@Attribute(.externalStorage)`, so those directories
    /// hold real attachment bytes — moving the store without them would silently
    /// lose attachments. `WeekyiiPersistence.supportDirectoryCandidates` uses the
    /// same two base spellings; the other two are swept because a retired store can
    /// predate whichever spelling the current OS writes, and a leftover blob
    /// directory beside the canonical store is unreachable but undeletable.
    /// None of the four can name a canonical-store directory, since that store's
    /// base name (`Weekyii`) differs from the legacy one (`Weekyii.local`).
    private static func legacyStoreFiles(for url: URL, fileManager: FileManager) -> [URL] {
        let parent = url.deletingLastPathComponent()
        let fileName = url.lastPathComponent
        let baseName = url.deletingPathExtension().lastPathComponent
        return [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
            parent.appendingPathComponent(".\(baseName)_SUPPORT", isDirectory: true),
            parent.appendingPathComponent("\(fileName)_SUPPORT", isDirectory: true),
            parent.appendingPathComponent(".\(fileName)_SUPPORT", isDirectory: true),
            parent.appendingPathComponent("\(baseName)_SUPPORT", isDirectory: true),
        ].filter { fileManager.fileExists(atPath: $0.path) }
    }
}

// MARK: - Snapshot → SwiftData writer

/// Materializes the `WeekyiiBusinessSnapshot` records a canonical store lacks.
///
/// Deliberately narrower than `WeekyiiDataArchiveService`'s importer, which
/// replaces the whole graph — right for a restore the user asked for, wrong here,
/// where overwriting is the exact failure being prevented.
///
/// A value type on purpose: nothing needs identity past one `write` call, and an
/// `@MainActor` *class* released inside the migration deallocates through
/// `swift_task_deinitOnExecutorMainActorBackDeploy` — a double-free crash site on
/// the iOS 26.2 simulator, and therefore in every test of this path.
private struct SnapshotWriter {
    let context: ModelContext
    let adding: Set<SyncEntityKey>

    /// Existing rows are resolved by business key, so a legacy child can be
    /// attached to a canonical parent without loading the parent's whole subtree.
    var taskTypes: [String: TaskTypeDefinition]
    var habits: [UUID: HabitModel]
    var projects: [UUID: ProjectModel]
    var weeks: [String: WeekModel]
    var days: [String: DayModel]
    var tasks: [UUID: TaskItem]
    var suspendedTasks: [UUID: SuspendedTaskItem]

    /// The fetches below read the store as it stands, so two rows sharing one
    /// business identity would trap inside `Dictionary(uniqueKeysWithValues:)`
    /// before this type could decide anything. That state is unreachable: the
    /// caller has already rejected it via `requireCleanSnapshot`.
    init(context: ModelContext, adding: Set<SyncEntityKey>) throws {
        self.context = context
        self.adding = adding
        self.taskTypes = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskTypeDefinition>()).map { ($0.idRaw, $0) }
        )
        self.habits = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<HabitModel>()).map { ($0.id, $0) }
        )
        self.projects = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<ProjectModel>()).map { ($0.id, $0) }
        )
        self.weeks = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<WeekModel>()).map { ($0.weekId, $0) }
        )
        self.days = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<DayModel>()).map { ($0.dayId, $0) }
        )
        self.tasks = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskItem>()).map { ($0.id, $0) }
        )
        self.suspendedTasks = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<SuspendedTaskItem>()).map { ($0.id, $0) }
        )
    }

    // MARK: Parents

    mutating func insert(_ snapshot: TaskTypeSnapshot) {
        guard adding.contains(snapshot.entityKey) else { return }
        let item = TaskTypeDefinition(
            idRaw: snapshot.idRaw,
            name: snapshot.name,
            iconName: snapshot.iconName,
            colorHex: snapshot.colorHex,
            baseKind: TaskType(rawValue: snapshot.baseKindRaw) ?? .regular,
            sortOrder: snapshot.sortOrder,
            isBuiltIn: snapshot.isBuiltIn,
            isArchived: snapshot.isArchived
        )
        context.insert(item)
        taskTypes[snapshot.idRaw] = item
    }

    mutating func insert(_ snapshot: HabitSnapshot) {
        guard adding.contains(snapshot.entityKey) else { return }
        let item = HabitModel(
            name: snapshot.name,
            iconName: snapshot.iconName,
            colorHex: snapshot.colorHex,
            startDayId: snapshot.startDayId
        )
        item.id = snapshot.id
        item.categoryRaw = snapshot.categoryRaw
        item.scheduleKindRaw = snapshot.scheduleKindRaw
        item.scheduleWeekdaysRaw = snapshot.scheduleWeekdaysRaw
        item.scheduleMonthDaysRaw = snapshot.scheduleMonthDaysRaw
        item.isActive = snapshot.isActive
        item.createdAt = snapshot.createdAt
        item.sortOrder = snapshot.sortOrder
        context.insert(item)
        habits[snapshot.id] = item
    }

    mutating func insert(_ snapshot: ProjectSnapshot) {
        guard adding.contains(snapshot.entityKey) else { return }
        let item = ProjectModel(
            name: snapshot.name,
            projectDescription: snapshot.projectDescription,
            color: snapshot.color,
            icon: snapshot.icon,
            status: snapshot.status,
            startDate: snapshot.startDate,
            endDate: snapshot.endDate
        )
        item.id = snapshot.id
        item.createdAt = snapshot.createdAt
        item.tileSizeRaw = snapshot.tileSizeRaw
        item.tileOrder = snapshot.tileOrder
        context.insert(item)
        projects[snapshot.id] = item
    }

    mutating func insert(_ snapshot: WeekSnapshot) {
        guard adding.contains(snapshot.entityKey) else { return }
        let item = WeekModel(
            weekId: snapshot.weekId,
            startDate: snapshot.startDate,
            endDate: snapshot.endDate,
            status: snapshot.status
        )
        item.completedTasksCount = snapshot.completedTasksCount
        item.expiredTasksCount = snapshot.expiredTasksCount
        item.totalStartedDays = snapshot.totalStartedDays
        context.insert(item)
        weeks[snapshot.weekId] = item
    }

    mutating func insert(_ snapshot: MindStampSnapshot) {
        guard adding.contains(snapshot.entityKey) else { return }
        let item = MindStampItem(text: snapshot.text, imageBlob: snapshot.imageBlob)
        item.id = snapshot.id
        item.createdAt = snapshot.createdAt
        context.insert(item)
    }

    // MARK: Children with parents

    mutating func insert(_ snapshot: DaySnapshot) throws {
        guard adding.contains(snapshot.entityKey) else { return }
        let item = DayModel(dayId: snapshot.dayId, date: snapshot.date, status: snapshot.status)
        item.dayOfWeek = snapshot.dayOfWeek
        item.killTimeHour = snapshot.killTimeHour
        item.killTimeMinute = snapshot.killTimeMinute
        item.followsDefaultKillTime = snapshot.followsDefaultKillTime
        item.initiatedAt = snapshot.initiatedAt
        item.closedAt = snapshot.closedAt
        item.executionModeRaw = snapshot.executionModeRaw
        item.isDraftZoneUnlocked = snapshot.isDraftZoneUnlocked
        item.expiredCount = snapshot.expiredCount
        if let weekId = snapshot.weekId {
            item.week = try require(weeks[weekId], for: snapshot.entityKey, parent: SyncEntityKey(kind: .week, businessId: weekId))
        }
        context.insert(item)
        days[snapshot.dayId] = item
    }

    mutating func insert(_ snapshot: HabitDayRecordSnapshot) throws {
        guard adding.contains(snapshot.entityKey) else { return }
        let item = HabitDayRecord(dayId: snapshot.dayId, createdAt: snapshot.createdAt)
        item.id = snapshot.id
        item.statusRaw = snapshot.statusRaw
        item.completedAt = snapshot.completedAt
        if let habitId = snapshot.habitId {
            item.habit = try require(habits[habitId], for: snapshot.entityKey, parent: SyncEntityKey(kind: .habit, id: habitId))
        }
        context.insert(item)
    }

    mutating func insert(_ snapshot: TaskSnapshot) throws {
        guard adding.contains(snapshot.entityKey) else { return }
        let item = TaskItem(
            title: snapshot.title,
            taskDescription: snapshot.taskDescription,
            taskType: snapshot.taskType,
            order: snapshot.order,
            zone: snapshot.zone
        )
        item.id = snapshot.id
        item.taskTypeIdRaw = snapshot.taskTypeIdRaw
        item.startedAt = snapshot.startedAt
        item.endedAt = snapshot.endedAt
        item.completedOrder = snapshot.completedOrder
        item.steps = snapshot.steps.map { step in
            let model = TaskStep(title: step.title, isCompleted: step.isCompleted, sortOrder: step.sortOrder)
            model.createdAt = step.createdAt
            return model
        }
        if let dayId = snapshot.dayId {
            item.day = try require(days[dayId], for: snapshot.entityKey, parent: SyncEntityKey(kind: .day, businessId: dayId))
        }
        if let projectId = snapshot.projectId {
            item.project = try require(projects[projectId], for: snapshot.entityKey, parent: SyncEntityKey(kind: .project, id: projectId))
        }
        if let habitId = snapshot.habitId {
            item.habit = try require(habits[habitId], for: snapshot.entityKey, parent: SyncEntityKey(kind: .habit, id: habitId))
        }
        context.insert(item)
        tasks[snapshot.id] = item
    }

    mutating func insert(_ snapshot: SuspendedTaskSnapshot) {
        guard adding.contains(snapshot.entityKey) else { return }
        let item = SuspendedTaskItem(
            title: snapshot.title,
            taskDescription: snapshot.taskDescription,
            taskType: snapshot.taskType,
            createdAt: snapshot.createdAt,
            decisionDeadline: snapshot.decisionDeadline,
            preferredCountdownDays: snapshot.preferredCountdownDays,
            snoozeCount: snapshot.snoozeCount,
            status: SuspendedTaskStatus(rawValue: snapshot.statusRaw) ?? .active
        )
        item.id = snapshot.id
        item.taskTypeIdRaw = snapshot.taskTypeIdRaw
        item.steps = snapshot.steps.map { step in
            let model = TaskStep(title: step.title, isCompleted: step.isCompleted, sortOrder: step.sortOrder)
            model.createdAt = step.createdAt
            return model
        }
        context.insert(item)
        suspendedTasks[snapshot.id] = item
    }

    /// Ownership is set from the attachment's own `owner`, which is the authority
    /// `rebuildRelationships` uses. `TaskItem.attachments` and
    /// `SuspendedTaskItem.attachments` are separate inverse pairs, so this writes
    /// exactly one edge and lets SwiftData derive the parent's collection.
    mutating func insert(_ snapshot: AttachmentSnapshot) throws {
        guard adding.contains(snapshot.entityKey) else { return }
        let item = TaskAttachment(
            id: snapshot.id,
            data: snapshot.data,
            fileName: snapshot.fileName,
            fileType: snapshot.fileType,
            createdAt: snapshot.createdAt
        )
        switch snapshot.owner {
        case .task(let id):
            item.task = try require(tasks[id], for: snapshot.entityKey, parent: SyncEntityKey(kind: .task, id: id))
        case .suspendedTask(let id):
            item.suspendedTask = try require(suspendedTasks[id], for: snapshot.entityKey, parent: SyncEntityKey(kind: .suspendedTask, id: id))
        }
        context.insert(item)
    }

    private func require<Model>(_ model: Model?, for key: SyncEntityKey, parent: SyncEntityKey) throws -> Model {
        guard let model else {
            throw LegacyStoreConsolidator.ConsolidationError.parentEntityMissingForMerge(key, parent: parent)
        }
        return model
    }
}
