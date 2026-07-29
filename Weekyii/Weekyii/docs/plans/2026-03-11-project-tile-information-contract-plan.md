# Project Tile Information Contract Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the project board tile system so each tile size has an explicit information contract, and resizing a tile in edit mode immediately reveals a different, size-appropriate content layout.

**Architecture:** Keep the existing 4-column Metro grid and persisted `tileSizeRaw` model field, but replace the current loosely-coupled `livePanel` selection with a stricter per-size presentation contract. The board remains static in browse mode; resizing in edit mode should re-render the same project snapshot through a different layout contract rather than animate hidden content.

**Tech Stack:** SwiftUI, SwiftData, custom `Layout`, `@Observable`, XCTest

---

## Current State Exploration

### Size System In Code

Current tile sizes are defined in `Models/Enums/ProjectTileSize.swift`:

- `mini`: `1 x 1`
- `small`: `2 x 1`
- `medium`: `2 x 2`
- `wide`: `4 x 2`

This is already a complete 4-tier Metro grid. The issue is not the number of sizes. The issue is that the information contract is still too generic.

### Current Rendering Chain

- Entry: `App/ContentView.swift`
- Board page: `Features/Extensions/ExtensionsHubView.swift`
- Tile presentation rules: `Features/Extensions/ProjectTilePresentation.swift`
- Snapshot source and tile state mutations: `Features/Extensions/ExtensionsViewModel.swift`
- Persistence + migration normalization: `App/WeekyiiPersistence.swift`

### Current Data Available To Tiles

`ProjectTileSnapshot` currently provides enough information to build a good first-pass contract without schema changes:

- `name`
- `icon`
- `colorHex`
- `progress`
- `completedCount`
- `totalCount`
- `remainingCount`
- `expiredCount`
- `nextTaskTitle`
- `nextTaskDate`

### Current Weaknesses

1. `mini` and `small` are still metric-first, but their identity is not clearly differentiated.
2. `medium` and `wide` both reuse the same `progress / metrics / nextTask` panel idea, so they feel like resized siblings instead of distinct tile classes.
3. Edit mode overlays are correct functionally, but resizing only changes `tileSize`; it does not intentionally communicate a new information hierarchy.
4. `ProjectTilePresentation` decides only insets, line limits, and one `livePanel`, which is too weak to describe layout density.

## Recommended Information Contract

### Decision

Keep **4 sizes**. Do not collapse to 3.

Rationale:

- `mini` and `small` solve different shape problems: one is a badge-like square, the other is a narrow summary rail.
- `medium` is the canonical square Metro tile and should remain the default project tile.
- `wide` is the only tile that can communicate schedule-oriented information without looking cramped.

### Contract By Size

#### 1. `mini` (`1 x 1`)

Purpose: instant recognition

Show:

- project icon
- short project name or single-line truncation
- one primary KPI only

Primary KPI priority:

1. if `remainingCount > 0`: remaining tasks
2. else if `totalCount > 0`: completion percentage
3. else: completed count

Do not show:

- status chip
- date
- secondary metrics
- next task title

Edit mode behavior:

- keep title if it still fits one line
- reserve stronger top-right / bottom-right safe zones for delete and resize controls
- resizing from `mini` to `small` should visibly introduce a second information lane

#### 2. `small` (`2 x 1`)

Purpose: compact horizontal summary

Show:

- icon
- project title, 1 line
- one primary metric block
- one secondary micro-stat if room allows

Primary content priority:

1. progress percentage
2. remaining tasks
3. completed / total micro pair

Do not show:

- status chip
- next task date
- full next task title

Edit mode behavior:

- preserve title + one metric so users can still identify the tile while resizing
- resizing from `small` to `medium` should add the status chip and a second metric area

#### 3. `medium` (`2 x 2`)

Purpose: standard project dashboard tile

Show:

- icon
- project title, up to 2 lines
- status chip
- one dominant hero block
- one secondary metrics row

Dominant hero block priority:

1. progress percentage if project has tasks
2. next upcoming task title if there is no meaningful progress story
3. empty-state summary if no tasks exist

Secondary row:

- completed
- remaining or total

Do not show at the same time:

- full next task module and full metric cards together

Edit mode behavior:

- keep same general structure, but compress spacing and remove tertiary copy
- resizing from `medium` to `wide` should replace the square “dashboard” composition with a horizontal “timeline” composition

#### 4. `wide` (`4 x 2`)

Purpose: project timeline / schedule tile

Show:

- icon
- project title, 1 line
- status chip
- next task title and date as the default primary story
- compact metrics strip as secondary information

Fallback if no next task:

- progress percentage
- completed / remaining / expired compact stats

Do not show:

- large square metric cards
- duplicated headline + subtitle blocks fighting for horizontal space

Edit mode behavior:

- retain title and one clear primary story while reserving corners for controls
- resizing from `wide` to `mini` should immediately collapse from “timeline summary” to “single KPI badge”, making the information loss obvious and intentional

## Edit Mode Resizing Rules

The key UX rule is:

**Size change must mean layout contract change, not just frame change.**

Implementation implications:

1. `cycleTileSize(for:)` already mutates persisted size immediately. Keep that.
2. `ProjectMetroTileView` must re-render through a distinct size-specific body, not a shared generic panel.
3. Edit mode should not hide too much content; otherwise resizing feels fake. It should reserve action corners but still show the target size’s content hierarchy.
4. Every size transition should cause a visible change in:
   - title treatment
   - status visibility
   - metric count
   - next-task visibility

## Code Changes Plan

### Task 1: Expand the presentation contract

**Files:**
- Modify: `Features/Extensions/ProjectTilePresentation.swift`
- Test: `Tests/ModelTests.swift`

Change `ProjectTilePresentation` from a thin helper into a true layout contract:

- add fields like:
  - `titleStyle`
  - `primaryContent`
  - `secondaryContent`
  - `showsStatusChip`
  - `showsNextTaskDate`
  - `metricDensity`
  - `editChromeInsets`

Remove the remaining “generic live panel” mindset for most sizes. Keep content decisions deterministic and stable.

### Task 2: Split tile bodies into explicit per-size templates

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`

Replace the current shared `mini/small/medium/wide` helpers with templates that each map to one contract:

- `miniTileBody`
- `smallTileBody`
- `mediumTileBody`
- `wideTileBody`

Each body should consume the new contract rather than independently choosing content.

### Task 3: Define edit-mode content behavior explicitly

**Files:**
- Modify: `Features/Extensions/ProjectTilePresentation.swift`
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Test: `Tests/ModelTests.swift`

Add tests and code for edit-mode differences:

- `mini` editing remains identifiable
- `small` editing preserves title + one metric
- `medium` editing still shows status but trims secondary detail
- `wide` editing defaults to one primary story plus compact strip

### Task 4: Stabilize content priority ordering

**Files:**
- Modify: `Features/Extensions/ExtensionsViewModel.swift`
- Modify: `Features/Extensions/ProjectTilePresentation.swift`
- Test: `Tests/ModelTests.swift`

If needed, refine snapshot selection so the tile’s “next task” and “progress story” are deterministic and business-relevant.

No schema changes are required in the first pass unless we discover that the current snapshot lacks a critical field.

### Task 5: Verify geometry and overflow

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Test: `Tests/ModelTests.swift`

After the new contracts are in place, verify:

- `mini` never overflows its `1 x 1` unit
- `small` never behaves like a compressed `medium`
- `wide` never uses square dashboard composition
- edit overlays do not cover content-critical regions

## Test Strategy

Focus tests on contract behavior, not screenshots:

- size cycle order remains unchanged
- each size returns the correct visibility rules
- edit mode returns different insets and visibility than browse mode
- wide tiles with / without upcoming tasks choose the correct primary story
- mini tiles never request unsupported secondary content

## Recommended Execution Order

1. Lock the contract in tests
2. Expand `ProjectTilePresentation`
3. Rewrite `ProjectMetroTileView` around that contract
4. Polish edit-mode spacing and overlays
5. Run targeted tests, then full project validation
