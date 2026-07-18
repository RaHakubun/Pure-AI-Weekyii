# Today Flexible Queue Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Match the online Today flow by allowing unlocked flexible execution users to edit, delete, and reorder Frozen tasks while preserving the Focus commitment.

**Architecture:** Add repository mutations constrained to `EXECUTE + FLEXIBLE + unlocked` and `FROZEN` tasks only. The ViewModel will expose these mutations, and the existing Material edit dialog will be reused for Frozen task details; compact rows will gain reorder, edit, and delete affordances.

**Tech Stack:** Kotlin, Room-backed repository, Jetpack Compose Material 3, JUnit 4.

---

### Task 1: Add failing repository behavior tests

**Files:**
- Modify: `app/src/test/java/com/weekyii/android/domain/StateMachineTest.kt`

Cover Frozen title/resource updates, deletion with contiguous queue order, and moving a Frozen task up/down. Tests must reject mutations while locked or in strict mode.

### Task 2: Implement repository and ViewModel mutations

**Files:**
- Modify: `app/src/main/java/com/weekyii/android/data/repository/WeekyiiRepository.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/viewmodel/TodayViewModel.kt`

Add the guarded mutation methods and refresh state after each operation.

### Task 3: Extend the Today Material UI

**Files:**
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/today/TodayScreen.kt`

Reuse the existing edit dialog for Frozen tasks and add visible edit/delete/up/down controls to each Frozen row when the queue is unlocked.

### Task 4: Verify and checkpoint

Run the targeted tests, complete unit-test suite, and Debug APK build. Commit after fresh verification.
