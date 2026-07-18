# Android Online Parity Roadmap

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring the Android app on `codex/android-port` to behavioral parity with the current `online-chatgpt-develop` baseline while keeping Android-native Material UI and preserving the existing local-first data model.

**Architecture:** Continue using Room repositories and ViewModels as the single source of truth. Android-only presentation and platform services (AlarmManager, WorkManager, AppWidget) adapt the shared behavior without introducing a second database or business-logic script. Each phase is independently testable and committed before the next phase.

**Tech Stack:** Kotlin, Jetpack Compose Material 3, Room, DataStore, WorkManager, AlarmManager, Android AppWidget, JUnit.

---

### Phase 1: Stabilize and checkpoint current parity work

**Files:** `app/src/test/java/com/weekyii/android/domain/StateMachineTest.kt`, current Today/MindStamp/Project/Settings/notification changes.

1. Keep the `UserSettingsStore` in-memory fake aligned with the production interface.
2. Run unit tests, AndroidTest Kotlin compilation, and `assembleDebug`.
3. Inspect the diff for accidental UI or data changes.
4. Commit as one coherent checkpoint: `feat(android): add today rituals notifications and settings themes`.

### Phase 2: Complete suspended-task parity

**Files:** `data/db/dao/SuspendedTaskDao.kt`, `data/repository/SuspendedTaskRepository.kt`, `ui/model/Models.kt`, `ui/viewmodel/ExtensionsViewModel.kt`, `ui/screens/extensions/ExtensionsScreen.kt`, suspended repository tests.

1. Add a failing repository test proving steps and attachments survive create/update and assignment.
2. Add resource replacement operations and expose the resources in `SuspendedTaskUi`.
3. Add Android-native editor controls for multiline steps and document attachments, preserving bytes and MIME metadata.
4. Add notification scheduling/cancellation for suspended-task checkpoints and wire create/update/extend/assign/delete/sweep lifecycle events.
5. Run focused tests, then the complete verification matrix, and commit.

### Phase 3: Finish Settings and presentation parity

**Files:** `ui/screens/settings/SettingsScreen.kt`, `ui/viewmodel/SettingsViewModel.kt`, `domain/UserSettingsStore.kt`, theme and notification tests.

1. Add failing tests for persisted theme, appearance mode, default execution mode, default task type, and kill-time behavior.
2. Implement only settings already represented by the iOS contract; keep unsupported Android platform choices explicit.
3. Ensure narrow screens scroll horizontally or wrap theme choices without clipping.
4. Verify DataStore defaults and migration behavior, then commit.

### Phase 4: Validate archive and state lifecycle round trips

**Files:** archive services/repository, reconcile worker, Room schema tests, new round-trip tests.

1. Add tests covering tasks, suspended resources, projects, custom types, MindStamps, and settings through export/import.
2. Fix any missing fields or ordering/invariant drift.
3. Exercise background reconciliation and notification cancellation after rollover.
4. Run all JVM tests and commit.

### Phase 5: Add Android home-screen support

**Files:** `ui/widget/*`, `AndroidManifest.xml`, resources, widget tests where feasible.

1. Define the widget contract (today status, focus task, frozen count, kill time) from existing repository state.
2. Implement a small Android-native widget using the same read-only state and a refresh receiver/worker.
3. Keep widget rendering resilient when no current day exists.
4. Build and verify installation metadata, then commit.

### Phase 6: Instrumentation and final online-branch audit

1. Run `connectedDebugAndroidTest` with an emulator or device; if none is connected, report the exact manual action needed.
2. Review `git diff online-chatgpt-develop...HEAD` and the parity design docs for remaining behavior gaps.
3. Run the full verification matrix and produce the final APK path and commit list.

