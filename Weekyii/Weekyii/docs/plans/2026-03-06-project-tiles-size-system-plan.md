# Project Tiles Size System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current ad hoc three-size project tile system with a stable Windows Phone style modular size system that never overlaps, keeps layout deterministic, and separates breathing visuals from tile frame geometry.

**Architecture:** Keep the custom `ProjectTileGridLayout`, but make it a true module grid driven by one base unit and explicit size specs. Move size decisions into a single source of truth, update tile templates to match those specs, and remove all whole-tile visual transforms that can visually escape their assigned frames. Layout correctness must come from grid math, not from view padding adjustments.

**Tech Stack:** SwiftUI, SwiftData, custom `Layout`, XCTest, existing `ExtensionsHubView` / `ExtensionsViewModel` / `ProjectModel`.

---

### Task 1: Freeze the target size system

**Files:**
- Modify: `Models/Enums/ProjectTileSize.swift`
- Reference: `Features/Extensions/ExtensionsHubView.swift`
- Test: `Tests/ModelTests.swift`

**Step 1: Replace the current 3-size enum with a 4-size module system**

Define:
- `mini`: `1 col x 1 row`
- `medium`: `2 col x 2 row`
- `wide`: `4 col x 2 row`
- `large`: `4 col x 4 row`

Also add helpers:
- `colSpan`
- `rowSpan`
- `next`
- `isSquare`
- `displayOrder`

**Step 2: Decide and document the cycle order**

Use:
- `mini -> medium -> wide -> large -> mini`

This should be the only size cycle path used by edit mode.

**Step 3: Add or update tests for size spans and cycle order**

Run: `xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WeekyiiTests/ModelTests test`

Expected:
- enum spans match the chosen system
- cycle order is deterministic

**Step 4: Commit**

```bash
git add Models/Enums/ProjectTileSize.swift Tests/ModelTests.swift
git commit -m "refactor: define modular project tile sizes"
```

### Task 2: Make grid geometry truly modular

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Test: `Tests/ModelTests.swift`

**Step 1: Introduce explicit grid constants near the project board**

Define one place for:
- `boardColumns = 4`
- `boardHorizontalPadding = 16`
- `boardColumnSpacing = 12`
- `boardRowSpacing = 28`
- `boardBottomSpacing = 32`

These values must not vary by edit/non-edit mode unless there is a strong reason.

**Step 2: Update `ProjectTileGridLayout` call site to use those constants**

Remove the current conditional row spacing logic:
- no more `isEditingTiles ? ... : ...`

The user’s complaint is valid: tile spacing must not depend on transient state if we want stable geometry.

**Step 3: Keep `ProjectTileGridLayout` width/height math purely frame-based**

The layout formula should remain:
- `cellWidth = (availableWidth - totalColumnSpacing) / columns`
- `frameWidth = colSpan * cellWidth + (colSpan - 1) * columnSpacing`
- `frameHeight = rowSpan * cellWidth + (rowSpan - 1) * rowSpacing`

Do not let tile content or overlay controls affect frame height.

**Step 4: Ensure grid-to-footer separation is explicit**

Add fixed spacing between the grid and the footer create button using a dedicated constant, not inherited `VStack` spacing.

**Step 5: Add a small geometry test if practical, otherwise a pure helper test**

If direct `Layout` testing is awkward, extract a tiny helper that computes frame sizes from spans and test that instead.

**Step 6: Commit**

```bash
git add Features/Extensions/ExtensionsHubView.swift Tests/ModelTests.swift
git commit -m "refactor: stabilize project board grid geometry"
```

### Task 3: Separate tile frame from tile visuals

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Modify: `Features/Extensions/ProjectTilePresentation.swift`
- Test: `Tests/ModelTests.swift`

**Step 1: Remove whole-tile breathing scale from non-editing mode**

Current issue:
- tile frame stays fixed
- `scaleEffect` makes the visual grow beyond its assigned frame

Replace whole-tile breathing with one of:
- animated background highlight
- animated gloss opacity
- animated inner content transition

Do not animate `scaleEffect`, `rotationEffect`, or any transform that changes perceived outer bounds.

**Step 2: Keep edit mode fully static**

Edit mode should not:
- rotate
- scale
- change spacing
- change frame

Edit mode should only add:
- delete affordance
- resize affordance
- drag affordance
- subtle border/shadow emphasis

**Step 3: Reserve action zones inside the tile frame**

Update `ProjectTilePresentation.contentInsets` so each size leaves guaranteed safe space for:
- top-right delete button
- bottom-right resize button

No overlay should ever sit outside the tile’s own frame.

**Step 4: Add tests for presentation insets**

Assert for each size:
- trailing inset is large enough in edit mode
- bottom inset is large enough in edit mode
- no edit-only insets leak into normal mode

**Step 5: Commit**

```bash
git add Features/Extensions/ExtensionsHubView.swift Features/Extensions/ProjectTilePresentation.swift Tests/ModelTests.swift
git commit -m "refactor: keep project tile visuals inside fixed bounds"
```

### Task 4: Make each size have its own content contract

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Modify: `Features/Extensions/ProjectTilePresentation.swift`
- Test: `Tests/ModelTests.swift`

**Step 1: Replace the current size contracts**

Use these display rules:
- `mini`: icon, short title, one primary metric
- `medium`: icon, title, primary panel, no dense metric rail
- `wide`: icon, title, one live panel, optional next task/date
- `large`: icon, title, full live panel, metric rail

**Step 2: Stop treating `wide` as the default size**

Right now many tiles read like compressed wide cards. The new default should be `medium`, because that is the standard WP square tile.

**Step 3: Update fallback snapshot rendering**

When there is no upcoming task:
- `mini`: show metric
- `medium`: show progress or count
- `wide`: show progress or summary
- `large`: show progress plus metric rail

Never render empty placeholder text that makes a tile feel broken.

**Step 4: Add tests for panel selection per size**

Assert:
- `mini` never chooses dense next-task text
- `medium` does not use large-tile rail
- `wide` prefers next task when present
- `large` can rotate among all major panels

**Step 5: Commit**

```bash
git add Features/Extensions/ExtensionsHubView.swift Features/Extensions/ProjectTilePresentation.swift Tests/ModelTests.swift
git commit -m "refactor: align project tile templates with size contracts"
```

### Task 5: Rebuild editing interactions around stable frames

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Modify: `Features/Extensions/ExtensionsViewModel.swift`
- Test: `Tests/ModelTests.swift`

**Step 1: Keep the current reorder mechanism only if it remains frame-stable**

Acceptance bar:
- no overlap while dragging
- no preview ghost covering another tile
- no spacing changes during drag

If `onDrag/onDrop` still violates any of these after Tasks 1-4, replace it.

**Step 2: Preferred replacement if needed: custom `DragGesture` reorder**

Model:
- one dragged tile id
- drag translation
- target insertion index derived from geometry

Behavior:
- dragged tile stays inside its own frame overlay
- siblings shift to reserved target positions
- no duplicate preview layer from the system

**Step 3: Keep persistence logic unchanged**

Continue using:
- `cycleTileSize(for:)`
- `updateTileOrder(with:)`

Do not introduce any new persistence fields for this task.

**Step 4: Add a regression test or at minimum a deterministic reorder helper**

If UI drag is not practical to unit test, extract pure reorder logic and test ordered IDs.

**Step 5: Commit**

```bash
git add Features/Extensions/ExtensionsHubView.swift Features/Extensions/ExtensionsViewModel.swift Tests/ModelTests.swift
git commit -m "refactor: stabilize project tile editing interactions"
```

### Task 6: Tune board composition for iPhone 17 Pro

**Files:**
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Optional: `docs/plans/2026-03-06-project-tiles-size-system-plan.md`

**Step 1: Verify board composition assumptions on iPhone 17 Pro width**

Check:
- two `medium` tiles fit cleanly across
- one `wide` tile spans full row
- one `large` tile spans full board width and two row heights
- footer create button never visually collides with final row

**Step 2: Lock the board composition constants**

Once they look right, stop changing spacing as a symptom fix. Future adjustments should come from size definitions or template density, not arbitrary margin inflation.

**Step 3: Update plan doc or technical notes if constants differ from the original draft**

Keep the selected module values documented for future work.

**Step 4: Commit**

```bash
git add Features/Extensions/ExtensionsHubView.swift docs/plans/2026-03-06-project-tiles-size-system-plan.md
git commit -m "docs: finalize project tile board composition constants"
```

### Task 7: Full verification

**Files:**
- No code changes required unless verification fails

**Step 1: Run focused unit tests**

Run:
```bash
xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WeekyiiTests/ModelTests test
```

Expected:
- all tile size and presentation tests pass

**Step 2: Run full suite**

Run:
```bash
xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Expected:
- all unit tests pass
- all UI tests pass

**Step 3: Manual spot-check**

Verify on simulator:
- non-edit mode: no tile visually grows outside frame
- edit mode: no tile overlaps vertically or horizontally
- reorder: no duplicate tile ghost
- footer button: no collision with final row
- size cycle: `mini -> medium -> wide -> large`

**Step 4: Commit**

```bash
git add .
git commit -m "feat: rebuild project tile size system"
```
