# WP Project Tiles Polish Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the current Windows Phone style project board so it reads clearly on iPhone 17 Pro, preserves drag/delete/resize interactions, and keeps live-tile motion smooth on iOS.

**Architecture:** Keep the existing board data flow in `ExtensionsViewModel`, keep the persisted tile size and tile order fields already added to `ProjectModel`, and focus the next pass on view structure. The board should stay a span-based layout, but each tile size must have a dedicated content template, dedicated edit chrome, and a predictable live-content policy.

**Tech Stack:** SwiftUI, SwiftData, Observation, custom `Layout`, `DropDelegate`, `confirmationDialog`, XCTest, simulator verification on `iPhone 17 Pro`.

---

## Root Cause Summary

1. The board uses a 4-unit grid in `Features/Extensions/ExtensionsHubView.swift`, but the tile body is not size-aware. Small tiles render the same information density as wide and large tiles, which causes text collisions.
2. Edit controls are painted directly on top of the tile body without reserving space, so delete/resize affordances overlap text and metric chips.
3. The live-tile content model is too generic. Every tile can show progress, metrics, next task, and the bottom task count at once, which breaks hierarchy.
4. Typography and spacing are not adapted to the actual rendered cell size on `iPhone 17 Pro`, so the current 4-unit layout looks compressed rather than intentional.
5. There are still two extensions page implementations in the repo. The app currently uses `ExtensionsHubView`, but the legacy `ExtensionsView` can mislead future changes if not treated as deprecated.
6. The first board rollout also revealed a persistence risk: adding tile fields to `ProjectModel` without a formal migration path could break store initialization and trigger the app's in-memory startup mode. The polish pass must not introduce any new persisted board fields unless the migration plan is updated in the same change.

---

## Approach Options

### Option A: Keep the 4-unit WP board and make tiles size-aware

This keeps the Windows Phone metaphor intact. Small tiles become compact visual glyphs, wide tiles become summary tiles, and large tiles become actual live tiles. This is the recommended approach because it preserves the interaction model already built and fixes the current problems at the right layer.

### Option B: Fall back to a 2-column adaptive board

This would be easier to read immediately, but it weakens the WP identity. Wide and large tiles would look acceptable, but small tiles would no longer feel like real Metro tiles. I do not recommend this unless we decide the product should prioritize conventional iOS readability over WP character.

### Option C: Rebuild the board on top of `UICollectionView`

This gives maximum drag-and-drop control, but it is not justified yet. The current issues are content-template problems, not proof that SwiftUI `Layout` is insufficient.

**Recommendation:** Option A.

---

## Target Visual Model

The board should keep a 4-unit logical grid, but content must map to tile size:

- `small (1x1)`: icon, abbreviated title or initials, one primary metric, no status chip, no multi-line text.
- `wide (2x1)`: icon, full title, status chip, one live panel at a time, one secondary metric.
- `large (2x2)`: icon, title, status, dual live regions, next task preview, progress and counts.

The visual language should move closer to Metro:

- flatter color planes with a subtle vertical luminance shift, not a muddy blended gradient
- stronger corner radius consistency
- larger icon-to-title contrast
- less chrome inside the tile
- motion limited to breathing opacity/scale and content fades

Edit mode should remain WP-like:

- long press enters board edit mode
- delete control top-right
- resize control bottom-right
- drag reorder only in edit mode
- content shrinks or reflows to reserve control space

---

## Implementation Plan

### Task 1: Separate the tile system from `ExtensionsHubView`

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Create: `Features/Extensions/ProjectTiles/ProjectMetroTileView.swift`
- Create: `Features/Extensions/ProjectTiles/ProjectTileGridLayout.swift`
- Create: `Features/Extensions/ProjectTiles/ProjectTileEditChrome.swift`

**Work:**
- Move `ProjectMetroTileView`, `ProjectTileGridLayout`, and drop delegate code out of the monolithic file.
- Keep `ProjectsFullView` as the coordinator only.
- Introduce a tiny style model, for example `ProjectTileStyle`, derived from `ProjectTileSize` and `isEditing`.

**Why:**
- The current file is carrying board, tile, layout, drag, and previews together, which makes it hard to reason about size-specific behavior.

### Task 2: Replace the single tile template with three templates

**Files:**
- Modify: `Features/Extensions/ProjectTiles/ProjectMetroTileView.swift`
- Modify: `Models/Enums/ProjectTileSize.swift`

**Work:**
- Route rendering by `snapshot.size` or explicit `tileSize`.
- Build `SmallProjectTileContent`, `WideProjectTileContent`, and `LargeProjectTileContent`.
- Remove the unconditional bottom `tasks` overlay.
- Hide the status pill and long strings from small tiles.
- Clamp line limits and font sizes per size class.

**Expected result:**
- No duplicate `0 tasks` lines.
- No "No upcoming task" overlap.
- Small tiles feel deliberate instead of broken.

### Task 3: Reserve edit chrome space instead of painting over content

**Files:**
- Modify: `Features/Extensions/ProjectTiles/ProjectMetroTileView.swift`
- Modify: `Features/Extensions/ProjectTiles/ProjectTileEditChrome.swift`

**Work:**
- Add edge insets that depend on `isEditing` and `tileSize`.
- For `small`, reduce action button diameter and simplify content.
- For `wide` and `large`, top-right and bottom-right zones must be excluded from text flow.
- Use a single visual treatment for edit buttons so the board reads as one system.

**Expected result:**
- Delete and resize controls no longer cover labels or chips.

### Task 4: Rework live-tile information hierarchy

**Files:**
- Modify: `Features/Extensions/ExtensionsViewModel.swift`
- Modify: `Features/Extensions/ProjectTiles/ProjectMetroTileView.swift`
- Modify: `Resources/Localizable.xcstrings`

**Work:**
- Expand `ProjectTileSnapshot` only with UI-ready values; do not add new persisted fields.
- Define one primary live panel per tile size:
  - `small`: progress or remaining count
  - `wide`: progress or next task
  - `large`: progress, next task, and overdue signal
- Replace hardcoded English fallback copy with localized strings.
- Keep one shared board timer and switch panels deterministically.

**Expected result:**
- Every tile shows one clear message at a time instead of several competing messages.

### Task 5: Tune board geometry for iPhone 17 Pro

**Files:**
- Modify: `Features/Extensions/ProjectTiles/ProjectTileGridLayout.swift`
- Modify: `Features/Extensions/ExtensionsHubView.swift`

**Work:**
- Keep the 4-unit logical grid, but retune paddings and gaps for phone:
  - horizontal board padding from `24` down to `16`
  - tile gap from `8` to `10` only if visual rhythm improves in simulator, otherwise stay at `8`
  - corner radius from `10` to `12` or `14`
- Add a style rule that small tiles must not rely on more than two text lines total.

**Expected result:**
- The board keeps the Metro mosaic feel but stops looking squeezed.

### Task 6: Tighten drag-and-drop behavior

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Modify: `Features/Extensions/ProjectTiles/ProjectTileGridLayout.swift`

**Work:**
- Keep reordering only in edit mode.
- Prevent unnecessary `tileProjects` resets while dragging.
- Add a clearer lifted state for the dragged tile.
- Persist order once on drop, not during hover.

**Expected result:**
- Reordering remains stable and visually understandable.

### Task 7: Performance guardrails

**Files:**
- Modify: `Features/Extensions/ProjectTiles/ProjectMetroTileView.swift`
- Modify: `Features/Extensions/ExtensionsHubView.swift`

**Work:**
- Keep a single `.task(id:)` timer at the board level.
- Disable breathing and panel changes while editing or dragging.
- Ensure tiles read only `ProjectTileSnapshot` plus primitive flags.
- Keep animations transform-based, not layout-based.
- Add debug-only `_printChanges()` temporarily if diff churn needs inspection.

**Expected result:**
- Stable interaction on iPhone 17 Pro without timer storms or layout thrash.

---

## Non-Goals

- No new SwiftData schema changes in this pass.
- No new migration surface beyond the explicit fix required to keep the project board store-compatible.
- No rewrite of delete business logic.
- No UIKit collection view bridge unless SwiftUI layout proves insufficient after the polish pass.

---

## Verification

Run after implementation:

1. `xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
2. Manual board checks on iPhone 17 Pro:
   - 10 to 20 projects
   - mixed `small/wide/large`
   - edit mode enter/exit
   - delete dialog with and without cascade
   - drag reorder
   - live panel cycling when idle
3. Confirm there is no fallback alert about local data availability.

---

## Recommended Order of Work

1. Extract tile code into dedicated files.
2. Implement the three size-specific tile templates.
3. Reserve edit chrome space and simplify small-tile content.
4. Retune board spacing and corner radii.
5. Polish live panel switching and localization.
6. Re-verify drag behavior and performance.
