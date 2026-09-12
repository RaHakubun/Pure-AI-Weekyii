# Weekyii Release Checklist

## Pre-merge Commands

```bash
xcodebuild build -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'
xcodebuild build-for-testing -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'
xcodebuild test -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:WeekyiiTests/StateMachineTests
xcodebuild test -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:WeekyiiTests/ModelTests
xcodebuild test -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:WeekyiiTests/NotificationServiceTests
```

## Reliability Gates

- Cross-day rollover updates Today automatically.
- `kill_time` expiration updates status and clears open zones correctly.
- Repeated reconcile calls are idempotent within the same minute.
- Only one present week remains after transitions.

## Data Safety Gates

- Startup creates backup snapshot folder with `manifest.json`.
- Backup manifest verifies all copied files (size + sha256).
- Launch fails closed on inconsistent persistence state.
- Failure screen can export diagnostics.
- Published V6 fixture migrates to V7 without losing tasks, projects, steps, attachments, MindStamp, suspended tasks, or custom task types.
- CloudKit-compatible schema test confirms no uniqueness constraints and validates optional relationships with inverses.
- Concurrent duplicate week/day records merge without dropping either device's tasks.

## iCloud Sync Gates

- Developer Portal App ID `com.fluentdesign.Weekyii` has iCloud/CloudKit and Push Notifications enabled.
- iCloud container is exactly `iCloud.com.fluentdesign.Weekyii` and is assigned to the App ID.
- The active Development and App Store provisioning profiles include the iCloud container, CloudKit service, and APS entitlement.
- A signed Development build creates/updates the development schema successfully.
- Same-account iPhone/iPad smoke covers create, edit, delete, attachment, offline edit/reconnect, and simultaneous edits.
- Settings shows account unavailable, syncing, synced, and error states correctly.
- CloudKit development schema is deployed to production before uploading the TestFlight build.
- TestFlight install upgrades in place and preserves the V6 local store before the first upload.

## Task Consistency Gates

- Today/Pending/Project/Suspended task create/edit all keep title/description/type/steps/attachments.
- Project detail add-task flow never downgrades to a simplified task model.
- Draft reorder/delete behavior remains stable after task mutation service integration.

## UI/Theme/Notification Smoke

- Light/Dark appearance both readable in Today and Extensions.
- Theme switch propagates to app and widget snapshot.
- Notification permission ON/OFF behavior is handled without crash.
- Suspended task reminders are scheduled/canceled consistently.
