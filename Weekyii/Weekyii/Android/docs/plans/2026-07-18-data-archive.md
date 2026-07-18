# Android Versioned Data Archive Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Provide a versioned, checksummed JSON archive that can be inspected, exported, and safely imported as a full local-data replacement.

**Architecture:** A serializable envelope mirrors the online archive contract (`formatIdentifier`, format/schema versions, export timestamp, payload SHA-256, base64 payload). Room entities and related steps/attachments are flattened into records. Import validates all IDs, references, enum values, and time ranges before creating a database snapshot and replacing all rows in one Room transaction.

**Tech Stack:** Kotlin serialization JSON, Room KTX transactions, Android Storage Access Framework, SHA-256.

---

### Task 1: Add failing archive codec and validation tests

**Files:**
- Create: `app/src/test/java/com/weekyii/android/data/archive/WeekyiiArchiveServiceTest.kt`

Cover round-trip payload inspection, checksum rejection, unsupported versions, duplicate/reference validation, and invalid kill-time rejection.

### Task 2: Implement archive records and codec

**Files:**
- Create: `app/src/main/java/com/weekyii/android/data/archive/WeekyiiArchiveService.kt`
- Modify: `build.gradle.kts`
- Modify: `app/build.gradle.kts`

### Task 3: Implement Room export/import replacement and snapshots

**Files:**
- Modify: DAO interfaces for bounded list/delete operations
- Modify: `app/src/main/java/com/weekyii/android/data/db/AppDatabase.kt`
- Create: `app/src/main/java/com/weekyii/android/data/archive/BackupRecoveryService.kt`

### Task 4: Add Settings export/import UI

**Files:**
- Modify: `app/src/main/java/com/weekyii/android/ui/viewmodel/SettingsViewModel.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/settings/SettingsScreen.kt`

### Task 5: Verify and checkpoint

Run the full unit-test suite and Debug APK build; only then commit the archive milestone.
