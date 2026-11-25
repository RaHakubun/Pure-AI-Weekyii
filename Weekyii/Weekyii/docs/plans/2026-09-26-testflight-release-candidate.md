# Weekyii TestFlight Release Candidate Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn the current Weekyii workspace into a traceable TestFlight candidate, upload a unique build, and validate in-place upgrade and optional iCloud sync without risking existing user data.

**Architecture:** Keep the current `online-chatgpt-develop` checkout as requested. Treat the existing dirty app changes as candidate input, exclude machine-local artifacts, and gate upload on fresh tests, a signed archive, and a migration audit. The CloudKit production `WYEntityV1` schema is already deployed; live sync still requires an installed TestFlight build and device evidence.

**Tech Stack:** Xcode, SwiftUI, SwiftData, CloudKit, XCTest, App Store Connect/TestFlight.

---

### Task 1: Freeze and audit the candidate

**Files:** `App/WeekyiiPersistence.swift`, `Models/*.swift`, `Services/LegacyStoreConsolidator.swift`, `Services/CloudSync*.swift`, `Weekyii.xcodeproj/project.pbxproj`, and all currently changed app/test resources.

1. Record `git status --short --branch`, `git diff --check`, and the tracked/untracked source inventory. Exclude `.DS_Store`, `xcuserdata`, `.workbuddy-ai`, unrelated review documents and image scratch files from the release commit.
2. Compare the current SwiftData schema and bootstrap path against the previously shipped 1.1 (1) store; verify a real V7 store opens, and inspect a current-date fixture so expiration rules do not hide migration loss.
3. Run fresh unit and UI tests for the exact candidate state; inspect failures before changing code. A test result is accepted only with an `xcresult` and zero failures.
4. Archive Release with distribution signing and inspect the app/widget entitlements, bundle IDs, version/build, and code signature.

### Task 2: Make and upload a unique build

**Files:** `Weekyii.xcodeproj/project.pbxproj` plus only any test or app fix proven necessary by Task 1.

1. Advance the main app version/build from 1.1 (1) to an unused App Store Connect value, retaining consistent extension versioning.
2. Repeat affected tests and a fresh Release archive after that change.
3. Stage only reviewed release files, commit on `online-chatgpt-develop`, push that branch, and confirm the remote commit matches the archived source.
4. Upload that archive to TestFlight. Verify the build appears in App Store Connect and record processing/export-compliance/review state; do not infer success from the upload command alone.

### Task 3: In-place TestFlight acceptance

**Files:** No source changes unless a test reveals a defect.

1. On an iPhone with the previous TestFlight build and real local data, record an anonymized pre-upgrade inventory; update in place without uninstalling, then compare tasks, attachments, habits, and settings.
2. Enable iCloud sync on that device and verify its local data survives first sync. On a second device signed into the same iCloud account, install the new TestFlight build and verify convergence in both directions.
3. Test an account without usable iCloud storage and offline mode; local create/edit/read must continue. Record diagnostics and any CloudKit errors.
4. Report each case as passed, failed, or unverified. Do not claim end-to-end success without device evidence.
