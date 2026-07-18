# Android Custom Task Types Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Match the online task-type workflow with built-in and user-defined types, persisted defaults, and task-editor selection.

**Architecture:** Keep the existing Room `TaskTypeDefinitionEntity` as the catalog source. Add a repository that seeds built-ins and owns create/update/archive/restore operations, extend DataStore settings with the default type ID, and pass the catalog into Today task creation/editing. Custom types retain a built-in base kind for deadline/analytics behavior.

**Tech Stack:** Kotlin, Room, DataStore Preferences, Jetpack Compose Material 3, JUnit 4.

---

### Task 1: Add failing behavior tests

**Files:**
- Create: `app/src/test/java/com/weekyii/android/data/repository/TaskTypeDefinitionRepositoryTest.kt`
- Modify: `app/src/test/java/com/weekyii/android/domain/StateMachineTest.kt`

Cover built-in seeding, duplicate-name rejection, custom type lifecycle, archived-type exclusion, default type persistence, and task creation retaining the selected custom type ID with its base kind.

### Task 2: Implement catalog and settings persistence

**Files:**
- Create: `app/src/main/java/com/weekyii/android/data/repository/TaskTypeDefinitionRepository.kt`
- Modify: `app/src/main/java/com/weekyii/android/domain/UserSettingsStore.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/viewmodel/SettingsViewModel.kt`
- Modify: `app/src/main/java/com/weekyii/android/MainActivity.kt`

### Task 3: Add Compose settings management and Today type selection

**Files:**
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/settings/SettingsScreen.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/today/TodayScreen.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/viewmodel/TodayViewModel.kt`

### Task 4: Verify and checkpoint

Run the complete unit-test suite and Debug APK build, then commit only after fresh verification.
