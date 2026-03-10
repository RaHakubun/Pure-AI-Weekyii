# WP Project Tiles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the Projects full page into a Windows Phone style live-tile board with long-press edit mode, tile resizing, drag-to-reorder, and safe deletion (including cascade option), while keeping iOS performance smooth.

**Architecture:** Keep business operations in `ExtensionsViewModel` (SwiftData persistence), introduce a lightweight board state object for interaction (`editMode`, drag state, timer tick), and replace the current project list layout with a custom span-based tile layout. Live-tile display data is precomputed from project/task model once per refresh and rendered with low-frequency shared ticks.

**Tech Stack:** SwiftUI, SwiftData, Observation (`@Observable`), custom `Layout`, `DragGesture`, `DropDelegate`-style hit mapping, `confirmationDialog`, XCTest (model and layout logic), optional snapshot tests if available.

---

### Task 1: Data Model and Persistence Contracts

**Files:**
- Create: `Models/Enums/ProjectTileSize.swift`
- Modify: `Models/ProjectModel.swift`
- Modify: `App/WeekyiiApp.swift`
- Create: `Persistence/WeekyiiMigrationPlan.swift`
- Test: `Tests/ModelTests.swift`

**Step 1: Write failing tests**

```swift
func test_projectTileSize_defaultIsSmall() {
    let p = ProjectModel(name: "A", startDate: .now, endDate: .now)
    XCTAssertEqual(p.tileSize, .small)
}

func test_projectTileOrder_defaultIsZero() {
    let p = ProjectModel(name: "A", startDate: .now, endDate: .now)
    XCTAssertEqual(p.tileOrder, 0)
}
```

**Step 2: Run tests and verify fail**
Run: `xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:WeekyiiTests/ModelTests`

**Step 3: Minimal implementation**
- Add enum:
  - `small(1x1)`
  - `wide(2x1)`
  - `large(2x2)`
- Add to `ProjectModel`:
  - `var tileSizeRaw: String = ProjectTileSize.small.rawValue`
  - `var tileOrder: Int = 0`
  - computed `tileSize` getter/setter.
- Define a versioned SwiftData schema for the pre-tile store and the current store.
- Add a migration plan that upgrades existing `ProjectModel` rows and assigns safe defaults for tile fields instead of relying on runtime fallback.

**Step 4: Re-run tests and verify pass**

**Step 5: Commit**
`git commit -m "feat(project): add tile size and tile order persistence"`

### Task 2: Board State and Live Data Snapshot Layer

**Files:**
- Create: `Features/Extensions/ProjectTileBoardState.swift`
- Create: `Features/Extensions/ProjectTileSnapshot.swift`
- Modify: `Features/Extensions/ExtensionsViewModel.swift`
- Test: `Tests/ModelTests.swift`

**Step 1: Write failing tests for snapshot derivation**
- Given project tasks, summary should output:
  - completed count
  - remaining count
  - expired count
  - nearest pending task title/date

**Step 2: Run tests and verify fail**

**Step 3: Minimal implementation**
- `ProjectTileBoardState` (UI-only state):
  - `isEditing`
  - `draggingProjectID`
  - `liveTick`
  - `activeDeleteProject`
- `ProjectTileSnapshot` (render payload, Equatable):
  - stable values only, no heavy filtering in tile body.
- In `ExtensionsViewModel`, add `projectTileSnapshots()` that precomputes snapshot map once after `refresh()`.

**Step 4: Run tests and verify pass**

**Step 5: Commit**
`git commit -m "feat(project-board): add board state and snapshot layer"`

### Task 3: Replace Grid with Span-Based Tile Layout Engine

**Files:**
- Create: `Features/Extensions/ProjectTileGridLayout.swift`
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Test: `Tests/ProjectTileGridLayoutTests.swift`

**Step 1: Write failing layout tests**
- Places `small/wide/large` tiles without overlap.
- Preserves visual order by `tileOrder`.
- Reflow is stable across repeated calculations.

**Step 2: Run tests and verify fail**

**Step 3: Minimal implementation**
- Remove `LazyVGrid` in `ProjectsFullView`.
- Add custom placement engine:
  - fixed column count (recommended 4 on iPhone, adaptive on iPad)
  - tile spans from `ProjectTileSize`
  - first-fit algorithm with occupancy matrix.
- Add computed frames map for hit-testing and drag preview.

**Step 4: Run tests and verify pass**

**Step 5: Commit**
`git commit -m "feat(project-board): add span-based tile grid layout"`

### Task 4: Build Metro Tile View Variants

**Files:**
- Create: `Features/Extensions/ProjectMetroTileView.swift`
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Modify: `Resources/Localizable.xcstrings`

**Step 1: Build per-size tile templates**
- `small`: icon + progress ring + single status metric.
- `wide`: name + progress + next task/expired info.
- `large`: dual panel live content + mini list.

**Step 2: Add live content rotation**
- Shared page timer tick every 4-6s.
- Tile content index = `(liveTick + hash(projectID)) % panelCount`.

**Step 3: Add breathing animation**
- Use transform/opacity only.
- Disable when `accessibilityReduceMotion == true`.

**Step 4: Validate no heavy work in body**
- body reads only precomputed snapshot and primitive values.

**Step 5: Commit**
`git commit -m "feat(project-board): add metro live tile views"`

### Task 5: Long-Press Edit Mode and Safe Delete Flow

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Modify: `Resources/Localizable.xcstrings`
- Reuse: `Features/Extensions/ExtensionsViewModel.swift`

**Step 1: Long-press to enter edit mode**
- `onLongPressGesture(minimumDuration: 0.35)` on tile.
- In edit mode:
  - disable navigation to detail
  - show delete button (top-right)
  - show resize button (bottom-right)
  - subtle jiggle animation.

**Step 2: Delete confirmation**
- First confirmation: "Delete this project?"
- Second choice sheet: "Project only" vs "Project + Tasks".
- Call existing `viewModel.deleteProject(project, includeTasks:)`.

**Step 3: Resize behavior**
- Tap resize button cycles size: `small -> wide -> large -> small`.
- Persist to SwiftData immediately.

**Step 4: Commit**
`git commit -m "feat(project-board): add edit mode delete and resize controls"`

### Task 6: Drag-and-Drop Reorder in Edit Mode

**Files:**
- Modify: `Features/Extensions/ProjectTileGridLayout.swift`
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Modify: `Features/Extensions/ExtensionsViewModel.swift`
- Test: `Tests/ProjectTileGridLayoutTests.swift`

**Step 1: Implement drag state**
- Track dragging tile id and drag translation.
- Render lifted tile with scale/shadow and placeholder gap.

**Step 2: Compute target slot**
- Convert drag center to nearest valid occupancy slot.
- Preview insertion position before drop.

**Step 3: Persist order**
- On drop, renumber all visible projects (`tileOrder = 0...n-1`).
- Save once per drop (no per-frame writes).

**Step 4: Add auto-scroll at edges**
- When drag near top/bottom edge in scroll view, slowly auto-scroll.

**Step 5: Commit**
`git commit -m "feat(project-board): support drag reorder with persisted order"`

### Task 7: Performance Guardrails (Required)

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Modify: `Features/Extensions/ProjectMetroTileView.swift`
- Optional: `Shared/Animation+Weekyii.swift`

**Step 1: Shared tick only**
- Single timer at page level (`liveTick`), not one timer per tile.

**Step 2: Throttle updates**
- Tick every 5s default.
- Pause tick in edit mode and while dragging.
- Pause when scene not active.

**Step 3: Reduce recomputation**
- Keep tile view `Equatable` payload.
- Avoid sorting/filtering tasks in tile body.

**Step 4: Animation budget**
- Breathing amplitude <= 2.5%.
- Avoid frame/layout animations in idle state.
- Prefer opacity/scale transform over relayout.

**Step 5: Instrumentation**
- Use `_printChanges()` for noisy views in debug.
- Validate 60fps on >= 20 projects and no input lag > 100ms.

**Step 6: Commit**
`git commit -m "perf(project-board): add throttled live updates and animation budget"`

### Task 8: Accessibility, Localization, and UX Polish

**Files:**
- Modify: `Resources/Localizable.xcstrings`
- Modify: `Features/Extensions/ProjectMetroTileView.swift`
- Modify: `Features/Extensions/ExtensionsHubView.swift`

**Step 1: Accessibility labels/actions**
- VoiceOver for tile summary.
- Custom actions: resize, delete, open project.

**Step 2: Reduce motion fallback**
- Disable breathing/jiggle under reduce motion.

**Step 3: Localization keys**
- Add strings for edit mode, resize labels, delete impact text.

**Step 4: Haptics**
- light impact on entering edit mode.
- success impact on drop.
- warning impact before destructive action.

**Step 5: Commit**
`git commit -m "feat(project-board): add accessibility localization and haptics"`

### Task 9: Integration Verification

**Files:**
- Test: `Tests/ModelTests.swift`
- Test: `Tests/ProjectTileGridLayoutTests.swift`
- Manual QA checklist: `测试流程.md`

**Step 1: Automated checks**
Run:
- `xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' test`

**Step 2: Manual validation**
- Create 10+ projects with mixed sizes.
- Enter edit mode, resize, drag, delete with both options.

### Post-implementation incident update

- March 6, 2026: this redesign exposed a persistence migration gap. Existing installs could fail store initialization after `ProjectModel` gained tile persistence fields, which then triggered the app's in-memory startup fallback.
- Follow-up requirement: no future board-related persisted fields may be added without updating the versioned SwiftData migration path and a regression test that opens a store written by the previous schema.
- Reopen app and verify tile order/size persistence.
- Check live tiles update cadence and battery impact.

**Step 3: Regression checks**
- Project detail page still works.
- Add task sheet unaffected.
- MindStamps page unaffected.

**Step 4: Final commit**
`git commit -m "feat(extensions): windows-phone style project board"`

## Non-Goals (YAGNI)
- Cross-device cloud sync of tile layout preferences.
- Per-user custom animation themes.
- Arbitrary tile freeform placement outside grid.

## Risk Controls
- SwiftData schema changes: keep defaults and computed wrappers to reduce migration issues.
- Gesture conflict (`NavigationLink` vs long-press/drag): block navigation during edit mode.
- Performance regression from over-animated tiles: one shared ticker + reduced motion fallback.
