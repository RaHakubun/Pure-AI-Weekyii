# Suspended Tasks and State Transition Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix cross-day Today refresh, introduce a reusable global state-transition notification mechanism, and ship the Suspended Tasks feature in Extensions.

**Architecture:** Reuse the existing app-wide `StateMachine` as the single source of truth for lifecycle transitions and publish a lightweight transition revision through `AppState`. Add Suspended Tasks as an independent SwiftData model and Extensions module, then bridge it into future days using the existing future-day resolution logic from `TaskPostponeService`/`PendingViewModel`.

**Tech Stack:** SwiftUI, SwiftData, XCTest, XCUI, UserNotifications.

---

### Task 1: Fix cross-day Today refresh and publish state transitions

**Files:**
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/App/AppState.swift`
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Services/StateMachine.swift`
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Today/TodayView.swift`
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Tests/StateMachineTests.swift`

**Step 1: Write failing tests**
- Add a `stateTransitionRevision` contract to the test `AppStateStore` fake.
- Add a failing test asserting `StateMachine.processStateTransitions()` bumps that revision.
- Add a failing test asserting a pre-created `TodayViewModel` can see the new day after state-machine transitions when refreshed.

**Step 2: Run tests to verify RED**
Run:
```bash
xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WeekyiiTests/StateMachineTests test
```
Expected: FAIL because transition revision API does not exist yet / assertions fail.

**Step 3: Implement minimal code**
- Extend `AppStateStore` with `stateTransitionRevision` and `bumpStateTransitionRevision()`.
- Persist this field in `AppState`.
- Call `bumpStateTransitionRevision()` at the end of `StateMachine.processStateTransitions()` before save/persist completion.
- In `TodayView`, observe `appState.stateTransitionRevision` and call `viewModel?.refresh()` when it changes.
- Keep the current `scenePhase`-triggered state machine; do not add BGTask work here.

**Step 4: Run tests to verify GREEN**
Run the same StateMachine tests.
Expected: PASS.

### Task 2: Generalize the transition-notification mechanism for feature reuse

**Files:**
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Pending/PendingView.swift`
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Extensions/ExtensionsHubView.swift`
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Extensions/MindStampViewModel.swift` (only if needed for refresh consistency)
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/docs/plans/2026-03-12-suspended-tasks-design.md`

**Step 1: Write failing tests or assertions**
- Add one test around the new revision API if Task 1 does not already cover persistence.
- Prefer lightweight unit tests; avoid UI tests unless needed.

**Step 2: Run RED**
Run targeted tests.
Expected: FAIL if persistence/notification contract not fully wired.

**Step 3: Implement minimal code**
- Make `PendingView` refresh when `appState.stateTransitionRevision` changes.
- Make `ExtensionsHubView` refresh its module view models when the same revision changes.
- Update the Suspended Tasks design doc with the fact that it will subscribe to this global revision instead of relying on `onAppear` only.

**Step 4: Run GREEN**
Run targeted tests/build.
Expected: PASS.

### Task 3: Add Suspended Tasks data model and migration

**Files:**
- Create: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Models/Enums/SuspendedTaskStatus.swift`
- Create: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Models/Enums/SuspendedTaskCountdownPreset.swift`
- Create: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Models/SuspendedTaskItem.swift`
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/App/WeekyiiPersistence.swift`
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Tests/ModelTests.swift`

**Step 1: Write failing tests**
- Creation stores `decisionDeadline` from preset.
- Renewing extends deadline.
- Assigning to a date removes the suspended item and creates a draft `TaskItem` in target day.
- Cleanup sweep deletes overdue suspended items.

**Step 2: Run RED**
Run:
```bash
xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WeekyiiTests/ModelTests test
```
Expected: FAIL because model/service do not exist.

**Step 3: Implement minimal code**
- Add the new enums/model.
- Add schema V3 and migration from V2.
- Keep steps/attachments owned by suspended items with cascade semantics.

**Step 4: Run GREEN**
Run ModelTests again.
Expected: PASS for the new model tests.

### Task 4: Implement Suspended Task domain service

**Files:**
- Create: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Services/SuspendedTaskService.swift`
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Services/NotificationService.swift`
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Services/StateMachine.swift`
- Test: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Tests/ModelTests.swift`
- Test: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Tests/StateMachineTests.swift`

**Step 1: Write failing tests**
- Scheduling suspended reminders generates/cancels the expected identifiers.
- Renewing reschedules notifications.
- Assigning to an existing day works.
- Assigning to a missing day/week creates them.
- State-machine cleanup removes expired suspended items after max reminders/final grace.

**Step 2: Run RED**
Run targeted test bundles.
Expected: FAIL.

**Step 3: Implement minimal code**
- `SuspendedTaskService` methods: create, update, renew, delete, assign(to:), cleanupExpired()`.
- Reuse `TaskPostponeService` resolution logic; if extraction is needed, keep it minimal and local.
- Extend `NotificationService` with suspended-task schedule/cancel helpers.
- Add a suspended sweep into `StateMachine.processStateTransitions()`.

**Step 4: Run GREEN**
Run tests again.
Expected: PASS.

### Task 5: Build Suspended Tasks UI in Extensions

**Files:**
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Extensions/ExtensionsHubView.swift`
- Create: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Extensions/SuspendedTasksFullView.swift`
- Create: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Extensions/SuspendedTaskEditorSheet.swift`
- Create: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Extensions/SuspendedTaskAssignSheet.swift`
- Create: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Extensions/SuspendedTaskViewModel.swift`
- Modify: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Resources/Localizable.xcstrings`
- Test: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/WeekyiiUITests/DraftReorderUITests.swift` or dedicated suspended UI tests

**Step 1: Write failing UI tests / unit tests**
- Extensions page shows the new module.
- Module empty state includes education copy that explains it is not a normal inbox.
- Full view supports add/edit/renew/delete/assign flows.
- Delete requires confirmation.

**Step 2: Run RED**
Run targeted UI tests.
Expected: FAIL because UI does not exist.

**Step 3: Implement minimal code**
- Add a new preview module in Extensions between Projects and Mind Stamps.
- Add onboarding copy clarifying: “这里不是普通收件箱；每条任务都必须在倒计时内被续期、分派或删除。”
- Reuse `TaskEditorSheet` content shape where practical.
- Use confirmation dialogs for delete and assign-with-creation decisions.

**Step 4: Run GREEN**
Run targeted UI tests/build.
Expected: PASS.

### Task 6: Final verification

**Files:**
- Verify only

**Step 1: Run full unit + UI test suite**
Run:
```bash
xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```
Expected: PASS.

**Step 2: Build once more for sanity**
Run:
```bash
xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Expected: BUILD SUCCEEDED.
