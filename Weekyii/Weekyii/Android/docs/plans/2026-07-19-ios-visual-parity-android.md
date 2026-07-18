# Android iOS Visual Parity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the Android presentation layer so Weekyii is immediately recognizable as the same product as the current `online-chatgpt-develop` iOS build while retaining Android-native interaction behavior and all existing business logic.

**Architecture:** Keep repositories, state machines, view models, alarms, widgets, and persistence unchanged. Add a reusable Compose design-system layer, then migrate screens from ad-hoc Material components to Weekyii components. Use simulator screenshots from the current iOS build as the visual source of truth and Pixel 9 Pro screenshots as acceptance evidence.

**Tech Stack:** Kotlin, Jetpack Compose Material 3, Room, DataStore, Compose UI tests, Android Emulator, Xcode iOS Simulator.

---

### Task 1: Lock the visual baseline

**Files:**
- Create: `docs/visual-baseline/README.md`
- Create: `docs/visual-baseline/ios/`
- Create: `docs/visual-baseline/android-before/`

**Steps:**
1. Build and launch the current `online-chatgpt-develop` iOS app without modifying its worktree.
2. Capture Today, Week, Pending, Past, Extensions, and Settings in light and dark appearance.
3. Capture empty, draft, execute, completed, and expired Today states when the app's test hooks permit it.
4. Record the observable palette, hierarchy, spacing, typography, cards, buttons, tab bar, and artwork behavior in `README.md`.
5. Capture the current Android screens for before/after comparison.

### Task 2: Add Weekyii design tokens

**Files:**
- Modify: `app/src/main/java/com/weekyii/android/ui/theme/Color.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/theme/Theme.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/theme/Type.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/theme/Dimensions.kt`
- Create: `app/src/test/java/com/weekyii/android/ui/theme/WeekyiiThemeTokensTest.kt`

**Steps:**
1. Write token tests covering the supported theme IDs and semantic color roles.
2. Run `./gradlew testDebugUnitTest --tests '*WeekyiiThemeTokensTest'` and confirm the new tests fail.
3. Implement semantic palettes for background, elevated surface, outline, primary text, secondary text, accent, success, warning, and task types.
4. Add shared spacing, radius, elevation, icon-size, and content-width values derived from the iOS baseline.
5. Run the token tests and existing unit suite.

### Task 3: Add reusable Weekyii components

**Files:**
- Create: `app/src/main/java/com/weekyii/android/ui/components/WeekyiiCard.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/components/WeekyiiButton.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/components/WeekyiiHeader.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/components/WeekyiiSegmentedControl.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/components/WeekyiiEmptyState.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/components/WeekyiiTaskRow.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/components/WeekyiiStatusArtwork.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/components/StatusBadge.kt`
- Create: `app/src/androidTest/java/com/weekyii/android/ui/components/WeekyiiComponentsTest.kt`

**Steps:**
1. Add Compose UI tests for labels, button enabled state, segmented selection, and accessible task actions.
2. Implement the components with the iOS-derived palette, thin outlines, restrained shadows, rounded geometry, and Android semantics.
3. Move secondary task actions into an overflow/menu or contextual sheet instead of a crowded horizontal row.
4. Compile Android tests with `./gradlew compileDebugAndroidTestKotlin`.
5. Preview and capture the component gallery on Pixel 9 Pro.

### Task 4: Rebuild Today

**Files:**
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/today/TodayScreen.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/screens/today/TodayHeader.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/screens/today/TodayStatusCard.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/screens/today/TodayTaskFlow.kt`
- Create: `app/src/main/java/com/weekyii/android/ui/screens/today/TodayKillTimeCard.kt`
- Create: `app/src/androidTest/java/com/weekyii/android/ui/screens/today/TodayScreenTest.kt`

**Steps:**
1. Add UI tests for empty, draft, execute, completed, and expired state landmarks.
2. Match the iOS hierarchy: centered Weekyii wordmark, Today/Week segmented control, status card, task-flow card, primary action, kill-time card, and bottom navigation.
3. Reproduce the warm ivory background, amber accent, fine card outline, low shadow, and theme-specific status artwork.
4. Preserve every existing ViewModel call and state transition.
5. Capture Pixel 9 Pro screenshots for all five states and compare with the iOS baseline.

### Task 5: Migrate the remaining screens

**Files:**
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/week/WeekScreen.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/pending/PendingScreen.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/past/PastScreen.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/extensions/ExtensionsScreen.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/extensions/ProjectDetailScreen.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/screens/settings/SettingsScreen.kt`
- Modify: `app/src/main/java/com/weekyii/android/ui/navigation/NavGraph.kt`

**Steps:**
1. Replace ad-hoc cards, buttons, headers, spacing, and empty states with Weekyii components.
2. Match iOS screen hierarchy and palette without copying iOS-only navigation behavior.
3. Keep Android-native back navigation, date/time pickers, overflow actions, and touch targets.
4. Capture each migrated screen in light and dark appearance.

### Task 6: Visual and functional acceptance

**Files:**
- Modify: `docs/visual-baseline/README.md`
- Create: `docs/visual-baseline/android-after/`

**Steps:**
1. Run `./gradlew testDebugUnitTest`.
2. Run `./gradlew compileDebugAndroidTestKotlin`.
3. Run `./gradlew lintDebug`.
4. Run `./gradlew assembleDebug`.
5. Run connected UI tests on Pixel 9 Pro when the emulator is available.
6. Inspect light/dark screenshots for clipping, action crowding, safe areas, scrolling, text scaling, and all named task states.
7. Confirm the iOS worktree remains unmodified by this work.
8. Commit and push only `codex/android-port`.
