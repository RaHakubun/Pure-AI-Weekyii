# Android Project Parity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring Android Projects to parity with the online branch for task placement, project detail metrics, editable draft tasks, lifecycle transitions, and safe deletion.

**Architecture:** Extend the existing Room-backed `ProjectRepository` with project-task mutations and a composed detail snapshot built from project, day, and task records. Keep lifecycle and editability rules in the repository, expose state through `ExtensionsViewModel`, and add a Compose detail route/screen that follows Material patterns while preserving the online behavior.

**Tech Stack:** Kotlin, Room, Kotlin coroutines/Flow, Jetpack Compose Material 3, JUnit.

---

### Task 1: Lock project mutation rules with repository tests

**Files:**
- Modify: `app/src/test/java/com/weekyii/android/data/repository/ExtensionsRepositoryTest.kt`
- Modify: `app/src/test/java/com/weekyii/android/data/repository/ProjectRepositoryTestSupport.kt` (create only if test fakes need extraction)

**Step 1:** Add failing tests for creating project tasks on an allowed future date, rejecting past/out-of-range/locked days, auto-activating planning projects, updating and deleting only draft tasks, and rejecting completion with open tasks.

**Step 2:** Run the focused test class and verify the new tests fail for missing repository behavior.

**Step 3:** Keep the test fixtures deterministic with `TimeProvider` fixed to 2026-07-20 and in-memory DAO fakes.

### Task 2: Implement Room-backed project task mutations and detail composition

**Files:**
- Modify: `app/src/main/java/com/weekyii/android/data/db/dao/TaskDao.kt`
- Modify: `app/src/main/java/com/weekyii/android/data/repository/ProjectRepository.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/model/Models.kt`

**Step 1:** Add task queries needed to observe/project-filter tasks and resolve task day dates.

**Step 2:** Implement placement validation, target-week/day creation, append/update/delete draft task operations, date-range validation, lifecycle transition validation, and include/exclude-task deletion.

**Step 3:** Add a deterministic project detail snapshot: sections grouped by day, progress/completed/remaining/expired counts, and next pending task.

**Step 4:** Run the focused repository tests, then the full unit suite.

### Task 3: Expose project detail state and actions to Compose

**Files:**
- Modify: `app/src/main/java/com/weekyii/android/ui/viewmodel/ExtensionsViewModel.kt`
- Modify: `app/src/main/java/com/weekyii/android/MainActivity.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/navigation/NavGraph.kt`

**Step 1:** Add selected-project navigation state and methods for add/edit/delete/lifecycle operations.

**Step 2:** Wire the repository with DayDao/TaskDao/WeekCalculator in the application composition root.

**Step 3:** Add a typed detail route and preserve bottom navigation state.

### Task 4: Build the Android project detail UI

**Files:**
- Create: `app/src/main/java/com/weekyii/android/ui/screens/extensions/ProjectDetailScreen.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/extensions/ExtensionsScreen.kt`

**Step 1:** Add identity/status, lifecycle actions, progress metrics, next-task summary, and date-grouped task ledger.

**Step 2:** Add Material dialogs/sheets for adding tasks across selected dates, editing draft tasks, and choosing project-only vs project-and-task deletion.

**Step 3:** Run `assembleDebug` and unit tests; report any emulator/Android Studio click-through still required before claiming UI parity.

### Task 5: Verify and document

**Files:**
- Modify: `README-android.md` if user-facing setup or current coverage needs updating.

**Step 1:** Run the complete verification command with the configured Android Studio JDK.

**Step 2:** Record exact test count, APK path, and any manual Android Studio/emulator checks still pending.

**Step 3:** Commit the completed parity slice with a focused message.
