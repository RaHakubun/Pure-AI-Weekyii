# Weekyii Technical Report

## 1. Executive Summary
Weekyii is an iOS SwiftUI + SwiftData application for weekly-granularity task execution with strict daily flow control (`draft -> execute -> completed/expired`). The system is composed of five product surfaces:
- `Today` (execution engine)
- `Pending` (future week planning)
- `Past` (analytics/review)
- `Extensions` (Projects + MindStamps)
- `Settings` (defaults, developer seed tools)

At runtime, a centralized `StateMachine` performs cross-day/week transitions, expiration, and summary reconciliation, while feature ViewModels own user-driven operations.

## 2. Runtime Architecture
### 2.1 Entry and dependency wiring
Application startup is in `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/App/WeekyiiApp.swift`.

Key points:
- SwiftData schema registration (`WeekModel`, `DayModel`, `TaskItem`, `TaskStep`, `TaskAttachment`, `ProjectModel`, `MindStampItem`)
- Persistent store located at `Application Support/Weekyii/Weekyii.store`
- Persistent store located at `Application Support/Weekyii/Weekyii.store`
- Store initialization previously fell back to an in-memory container if persistent initialization failed. This path was triggered after `ProjectModel` added persisted tile fields without a formal migration path, causing an existing on-device store to be treated as unavailable.
- Runtime fallback is not considered a safe steady-state because it hides migration defects and risks user confusion about whether data is still durable.
- Global services: `AppState`, `UserSettings`, `StateMachine`, minute-level timer

```swift
let schema = Schema([
    WeekModel.self,
    DayModel.self,
    TaskItem.self,
    TaskStep.self,
    TaskAttachment.self,
    ProjectModel.self,
    MindStampItem.self
])

let config = ModelConfiguration("Weekyii", schema: schema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)
modelContainer = try ModelContainer(for: schema, migrationPlan: WeekyiiMigrationPlan.self, configurations: config)
```

### 2.1.1 Persistence incident note
- Date: March 6, 2026
- Trigger: `ProjectModel` gained persisted board fields (`tileSizeRaw`, `tileOrder`) for the Windows Phone project board redesign.
- Observed behavior: existing installs could fail persistent `ModelContainer` initialization and show the alert `本地数据暂时不可用，已进入只保启动模式。请尽快备份并重启。`
- Root cause: schema evolution relied on ad-hoc lightweight migration assumptions instead of a declared SwiftData versioned schema and migration plan.
- Required correction: formalize schema versioning, add an explicit migration path for the previous `ProjectModel`, and remove the user-facing in-memory runtime mode as the normal recovery path.

### 2.2 Top-level navigation
`/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/App/ContentView.swift` defines a 5-tab architecture:
- Past
- Today
- Pending
- Extensions
- Settings

`appState.dataRevision` is bound to `.id(...)` on `TabView` to force refresh after data reseed/reset.

## 3. Domain Model (SwiftData)
### 3.1 Core entities
- `WeekModel`: unique `weekId`, date range, status (`pending/present/past`), summary metrics
- `DayModel`: unique `dayId`, status (`empty/draft/execute/completed/expired`), kill time, lifecycle timestamps
- `TaskItem`: zone (`draft/focus/frozen/complete`), ordering, timing, description, steps, attachments
- `ProjectModel`: cross-day container with optional relation to tasks (`nullify` rule)
- `MindStampItem`: text/image memory stamp for ritual display

### 3.2 Relationship graph
- `WeekModel` --cascade--> `[DayModel]`
- `DayModel` --cascade--> `[TaskItem]`
- `TaskItem` --cascade--> `[TaskStep]`, `[TaskAttachment]`
- `ProjectModel` --nullify--> `[TaskItem]` (`TaskItem.project` optional)

### 3.3 Identity and temporal encoding
In `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Shared/Extensions/Date+Weekyii.swift`:
- `dayId`: `yyyy-MM-dd`
- `weekId`: `YYYY-Www` based on ISO week/yearForWeekOfYear

```swift
var weekId: String {
    let calendar = Calendar(identifier: .iso8601)
    let week = calendar.component(.weekOfYear, from: self)
    let year = calendar.component(.yearForWeekOfYear, from: self)
    return String(format: "%04d-W%02d", year, week)
}
```

## 4. State Transition Engine
`/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Services/StateMachine.swift`

`processStateTransitions()` pipeline:
1. `ensureSystemStartDate()`
2. `processStaleOpenDaysBeforeToday()`
3. `processCrossDay()`
4. `processCrossWeek()`
5. `processKillTime()`
6. `refreshWeekSummaryMetrics()`
7. persistence + app-state mark

### 4.1 Cross-day behavior
- `execute` day crossing boundary -> `expired` with `focus + frozen` count
- `draft` day crossing boundary -> `expired` with `expiredCount = 0`
- non-completed unfinished task details are deleted on expiration

```swift
private func expire(day: DayModel, expiredCount: Int) {
    day.status = .expired
    day.expiredCount = expiredCount
    removeTasks(in: [.draft, .focus, .frozen], from: day)
    notificationService.cancelKillTimeNotification(for: day)
}
```

### 4.2 Cross-week behavior
- Ensures only one `present` week is active
- Migrates previous `present` weeks to `past`
- Promotes existing current week or creates new one

### 4.3 Kill-time enforcement
For `draft`/`execute` today, if `now >= killDate`, transitions to `expired` immediately.

## 5. Feature Modules
## 5.1 Today module
- View: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Today/TodayView.swift`
- VM: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Today/TodayViewModel.swift`

Supports full daily pipeline:
- draft task editing (add/update/delete/reorder)
- `startDay()` -> first task to `focus`, rest to `frozen`, increments started-day metric
- `doneFocus()` -> move focus to `complete`, promote next frozen task; closes day when queue ends
- kill time change under state constraints
- random `MindStamp` full-screen ritual on start

```swift
func startDay() throws -> MindStampItem? {
    guard day.status == .draft else { throw WeekyiiError.cannotEditStartedDay }
    guard !sortedTasks.isEmpty else { throw WeekyiiError.cannotStartEmptyDay }
    day.status = .execute
    day.initiatedAt = now
    first.zone = .focus
    first.startedAt = now
    ...
}
```

## 5.2 Pending module
- View: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Pending/PendingView.swift`
- VM: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Pending/PendingViewModel.swift`

Capabilities:
- create future week by date or `weekId`
- strict week-id validation delegated to `WeekCalculator.weekStartDate(for:)`
- month-based week-option generation and existing/past tagging

```swift
guard let startDate = weekCalculator.weekStartDate(for: normalizedWeekId) else {
    errorMessage = String(localized: "error.date_format_invalid")
    return nil
}
```

## 5.3 Past module
- View: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Past/PastView.swift`
- VM: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Past/PastViewModel.swift`
- Service: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Past/PastAnalyticsService.swift`

Analytics includes:
- completion rate
- total/average focus duration
- productive time period
- week/month trend series
- heatmap status mapping

## 5.4 Extensions module
- Hub: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Extensions/ExtensionsHubView.swift`
- Projects VM: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Extensions/ExtensionsViewModel.swift`
- MindStamp VM: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Extensions/MindStampViewModel.swift`

Projects:
- CRUD + status lifecycle
- add tasks into concrete `DayModel` (auto-create pending week/day as needed)
- enforce date range + non-past + non-expired + non-completed day
- optional cascade delete behavior

```swift
guard taskDate >= today else {
    errorMessage = String(localized: "project.error.day_expired")
    return nil
}

guard day.status != .completed else {
    errorMessage = String(localized: "project.error.day_completed")
    return nil
}
```

MindStamps:
- text/image content persistence
- random draw for ritual scene

## 6. Notification and Time
`/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Services/NotificationService.swift`
- schedules kill-time notification
- schedules pre-reminder if unfinished tasks exist
- cancels by deterministic identifiers (`killtime-dayId`, `pre-killtime-dayId`)

## 7. UI/Design System Layer
Design primitives are centralized:
- spacing/radius/shadow: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Shared/DesignSystem/Spacing+Weekyii.swift`
- typography: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Shared/DesignSystem/Typography+Weekyii.swift`
- palette and gradients: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Shared/Extensions/Color+Weekyii.swift`
- reusable card shell: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Shared/Components/WeekCard.swift`

## 8. Persistence and Settings
- App state (`daysStartedCount`, revision markers, runtime error): `UserDefaults` via `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/App/AppState.swift`
- User preferences + seed options: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Resources/UserSettings.swift`
- Developer data seeding and reset tools: `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Resources/SettingsView.swift`

## 9. Test Coverage Snapshot
Current tests:
- `StateMachineTests`: cross-day/week/kill-time behaviors
- `WeekCalculatorTests`: week-id format and strict validity checks
- `ModelTests`: lightweight model invariants
- `DraftReorderUITests`: drag reorder smoke flow

Coverage strengths:
- core transition engine has baseline protection
- critical week-id validator has regression tests

Coverage gaps (high-value next):
- `TodayViewModel` scenario matrix (start/doneFocus/kill-time race)
- `ExtensionsViewModel` multi-date partial failure semantics
- `PastAnalyticsService` metric correctness edge cases
- locale-sensitive UI formatting/snapshot tests

## 10. Engineering Risks and Observations
1. `PastView` currently uses broad `@Query` and in-memory filtering for month slicing; large datasets may impact memory/perf.
2. `DateFormatter` objects are still created in some extension/util paths (`Date.dayId`, `Date.dayOfWeekShort`), which can be optimized via cached/static formatters.
3. Notification reminder body contains hardcoded Chinese text in `NotificationService` pre-reminder path; should move to localization key.
4. `UserSettings` writes all keys on each individual property mutation (`didSet { save() }`); can be batched/debounced if write amplification becomes visible.

## 11. Recommended Near-Term Refactoring Roadmap
1. Introduce a repository/query abstraction for month/week filtering to reduce broad fetches.
2. Add deterministic date/time dependency injection across all ViewModels (already present in core areas, should be standardized).
3. Build a targeted test suite for `Extensions` conflict rules (past/completed day rejection, batch add partial failures).
4. Move all remaining literals/comments to unified localization/style conventions for global collaboration readiness.
5. Add migration/versioning strategy doc for SwiftData schema evolution (currently implicit in source).

## 12. Conclusion
Weekyii already has a solid technical backbone:
- clear domain lifecycle
- deterministic ISO-week modeling
- centralized transition engine
- modular SwiftUI feature slices
- extensible data graph (`Project`, `MindStamp`)

The next maturity leap is not architectural replacement, but reliability hardening at boundaries: query performance, localization consistency, and deeper scenario tests.
