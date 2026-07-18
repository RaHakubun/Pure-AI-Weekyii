# Android State Invariants Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep the Android state machine structurally valid after every reconcile and ensure the current week always has all seven day records.

**Architecture:** `WeekyiiRepository.ensureWeek` will be idempotent for both new and existing weeks, creating only missing day rows. `StateMachine.reconcile` will normalize each executing day through a repository operation that repairs Focus/Frozen zones and contiguous order before expiry checks.

**Tech Stack:** Kotlin, Room DAOs, kotlinx.coroutines, JUnit 4.

---

### Task 1: Add failing invariant tests

**Files:**
- Modify: `app/src/test/java/com/weekyii/android/domain/StateMachineTest.kt`
- Modify: `app/src/test/java/com/weekyii/android/data/repository/WeekyiiRepositoryBehaviorTest.kt`

Add tests proving that an executing day with two Focus tasks is normalized to one Focus plus ordered Frozen tasks, that a day with only Frozen tasks promotes the first one, and that an existing week missing day rows is completed to seven days.

### Task 2: Implement the minimal repository/state-machine repair

**Files:**
- Modify: `app/src/main/java/com/weekyii/android/data/repository/WeekyiiRepository.kt`
- Modify: `app/src/main/java/com/weekyii/android/domain/StateMachine.kt`

Make `ensureWeek` fill missing days and add `normalizeExecutionState(dayId, now)` with deterministic order repair. Invoke normalization before kill-time processing.

### Task 3: Verify and checkpoint

Run the targeted tests, then the complete unit-test and debug-APK command from the Android worktree. Commit only after fresh verification.
