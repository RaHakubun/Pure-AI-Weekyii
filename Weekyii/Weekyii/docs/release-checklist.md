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

## Task Consistency Gates

- Today/Pending/Project/Suspended task create/edit all keep title/description/type/steps/attachments.
- Project detail add-task flow never downgrades to a simplified task model.
- Draft reorder/delete behavior remains stable after task mutation service integration.

## UI/Theme/Notification Smoke

- Light/Dark appearance both readable in Today and Extensions.
- Theme switch propagates to app and widget snapshot.
- Notification permission ON/OFF behavior is handled without crash.
- Suspended task reminders are scheduled/canceled consistently.
