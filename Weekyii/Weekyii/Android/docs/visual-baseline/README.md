# Weekyii visual baseline

This baseline is taken from the current `online-chatgpt-develop` iOS build on the iPhone 17 Pro iOS 26.2 simulator (UDID `78AEA02E-5B71-4BDB-87F8-EA0F844EB8CC`). The App target was built from the iOS worktree into temporary DerivedData and installed without changing iOS source files. The Android implementation may use Android-native controls and navigation conventions, but it must preserve this product language.

Captured evidence in this directory:

- iOS Today, light: `ios/light/today-current.png`
- iOS Today, dark: `ios/dark/today-current.png`
- Android Today before migration, light: `android-before/light/today-current.png`
- Android Today before migration, dark: `android-before/dark/today-current.png`
- iOS Week, light: `ios/light/week-current.png`
- Android Week before migration: `android-before/light/week-current.png`
- Android light acceptance: `android-after/light/today-current.png`, `week-current.png`, `pending.png`, `past.png`, `extensions.png`, `settings.png`
- Android dark acceptance: `android-after/dark/today-current.png`, `pending.png`, `past.png`, `extensions.png`, `settings.png`
- Android alternate-theme acceptance: `android-after/light/today-ocean.png`
- Android large-type acceptance: `android-after/light/week-font-1.3.png`

## Today baseline observed

- Canvas: warm near-white background with generous vertical breathing room.
- Brand: centered orange-gold Weekyii wordmark in the top header; the wordmark is the visual anchor, not a plain text heading.
- Section switcher: wide capsule segmented control for 当下 / 本周, with a filled amber selection and soft outline/shadow around the full control.
- Status card: large rounded card with a fine warm outline, a restrained shadow, status and started-day count at the top, theme status artwork in the middle, and date at the bottom.
- Empty state: separate large rounded card with a centered line icon, centered title/subtitle, and a compact amber primary action below.
- Kill time: its own semantic card lower in the scroll, with an orange accent and a clear edit/confirm flow.
- Bottom tabs: white floating capsule-like bar with five evenly weighted destinations; selected Today is a pale neutral pill with amber icon/text, not a full saturated block.
- Typography: dark brown primary text, muted taupe secondary text, large hierarchy, and no dense control rows.

The reference light palette is the amber theme: primary `#C46A1A`, accent orange `#F08A3C`, background primary `#FFF7EE`, elevated surface `#FFFDF9`, tertiary surface `#F6EDE3`, primary text `#2A1D16`, secondary text `#6B5A4F`. In dark appearance the corresponding canvas/surface/text roles are `#18120E` / `#221A14` / `#F7EBDD`.

The iOS screenshot is 1206 × 2622 pixels; the Pixel 9 Pro screenshot is 1280 × 2856 pixels. Geometry is therefore compared by proportions and semantic spacing rather than raw pixels.

## Android before snapshot

The pre-refactor Android screenshot is stored in `android-before/light/today-current.png` and `android-before/dark/today-current.png`. It demonstrates the main mismatches to remove: a narrower wordmark, stronger/default Material shadows, a flat rectangular status gradient, dense/incorrect hierarchy, and bottom navigation treatment that does not yet reproduce the iOS floating capsule and selected neutral pill.

## Week parity decisions

- The Android topology now uses the iOS hierarchy: a continuous spine, thick hollow nodes, a dashed current-day ring, a 220dp topology canvas, and an in-card weekly inspector.
- Detail modes are named `当前状态 / 信息横条 / 折叠` and use the amber Weekyii segmented control.
- The fixed-width progress bar was replaced with a responsive 8dp track.
- Android keeps tap semantics and scroll behavior; iOS-only freeform zoom/drag is not copied when it conflicts with native Android navigation.

## Remaining-screen decisions

- Pending and Past use the shared semantic palette for calendar markers and heatmap intensity; task colors no longer bypass the selected theme.
- Extensions follows the iOS hub hierarchy: two square shortcuts and one project module. Duplicate suspended/project/MindStamp lists were removed from the hub because each remains available in its dedicated module.
- Settings preserves Android-native grouped navigation while using Weekyii palette roles for every icon tile in light, dark, and alternate themes.

## Extensions baseline observed

- The hub uses the centered Weekyii wordmark followed by two equal square shortcut cards in one row: 呆胶布 and 悬置箱.
- The projects module is one wide rounded card below the shortcuts. Its header contains the folder icon, title, and a right-aligned 查看全部入口; the empty state is centered inside the same card with a folder-plus icon and 新建项目 action.
- The hub does not repeat empty section headings below the module cards. Detail lists belong to the module destination opened from a shortcut or 查看全部.
- iOS reference capture will be added under `ios/` as each destination is navigated in the simulator.
- Android acceptance captures belong under `android-after/` and must include light/dark and each named Today state.

## Expired Today acceptance

The Pixel 9 Pro expired-state capture is retained as prior audit evidence outside this baseline directory. It verifies the red expired status artwork, the forgotten-task count, and the disabled past kill-time control without retaining expired task details.

## Acceptance rule

Every Android screen must be checked against the corresponding iOS screen in the simulator. A screen is not accepted because it compiles or because its ViewModel behavior passes; it must also match the baseline's hierarchy, palette, geometry, density, and state communication at the same user-visible state.
