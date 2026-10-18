# Today And Week Layout Controls Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the Today draft add/edit text buttons with icon buttons, and add a three-state display control for the in-app Week view so the seven day cards can switch between cards, full-width strips, and collapsed.

**Architecture:** Keep the feature local to the existing SwiftUI layer. Add a small presentational model for week row summaries so the new strip layout and its tests stay deterministic. Preserve existing navigation to day detail and existing accessibility identifiers where possible.

**Tech Stack:** SwiftUI, SwiftData, XCTest, Xcode/iOS Simulator.

---

### Task 1: Add week overview presentation tests

**Files:**
- Modify: `Tests/ModelTests.swift`

**Step 1:** Add failing tests for the new week display mode cycling order.

**Step 2:** Add failing tests for the new week strip summary prioritization:
- focus task first
- draft task fallback
- completed summary fallback when no active task exists

**Step 3:** Run:
```bash
xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WeekyiiTests/ModelTests test
```

**Step 4:** Confirm the tests fail for the missing production types.

### Task 2: Implement week overview mode switching

**Files:**
- Modify: `Features/Week/WeekOverviewView.swift`

**Step 1:** Add a local enum for the three modes: cards, strips, collapsed.

**Step 2:** Add a small summary/presentation helper for day strips.

**Step 3:** Replace the fixed `LazyVGrid` block inside `WeekOverviewContentView` with:
- a compact mode switch control
- existing card grid for `.cards`
- a vertical strip list for `.strips`
- a collapsed placeholder for `.collapsed`

**Step 4:** Keep `NavigationLink` behavior for both cards and strips.

### Task 3: Replace draft text actions with icon buttons

**Files:**
- Modify: `Features/Today/DraftEditorView.swift`

**Step 1:** Keep existing behavior and identifiers:
- `draftAddButton`
- `draftEditButton`

**Step 2:** Replace text labels with icon-only controls.

**Step 3:** Make edit mode visually clear by switching the icon between edit and done.

### Task 4: Verify

**Files:**
- Modify if needed: `WeekyiiUITests/DraftReorderUITests.swift`

**Step 1:** Run focused model tests.

**Step 2:** Run a simulator build.

**Step 3:** If UI identifiers changed in a meaningful way, update/add UI coverage and rerun that target.
