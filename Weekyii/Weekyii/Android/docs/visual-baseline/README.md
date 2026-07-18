# Weekyii visual baseline

This baseline is taken from the current `online-chatgpt-develop` iOS build on the iPhone 17 Pro iOS 26.2 simulator. The Android implementation may use Android-native controls and navigation conventions, but it must preserve this product language.

## Today baseline observed

- Canvas: warm near-white background with generous vertical breathing room.
- Brand: centered orange-gold Weekyii wordmark in the top header; the wordmark is the visual anchor, not a plain text heading.
- Section switcher: wide capsule segmented control for 当下 / 本周, with a filled amber selection and soft outline/shadow around the full control.
- Status card: large rounded card with a fine warm outline, a restrained shadow, status and started-day count at the top, theme status artwork in the middle, and date at the bottom.
- Empty state: separate large rounded card with a centered line icon, centered title/subtitle, and a compact amber primary action below.
- Kill time: its own semantic card lower in the scroll, with an orange accent and a clear edit/confirm flow.
- Bottom tabs: white floating capsule-like bar with five evenly weighted destinations; selected Today is a pale neutral pill with amber icon/text, not a full saturated block.
- Typography: dark brown primary text, muted taupe secondary text, large hierarchy, and no dense control rows.

## Android before snapshot

The pre-refactor Android screenshot was captured at `/tmp/weekyii-android-current.png`. It demonstrates the main mismatches to remove: plain text branding, a compact two-button row, a flat rectangular status gradient, dense/incorrect hierarchy, green selected navigation treatment, and default Material spacing.

## Extensions baseline observed

- The hub uses the centered Weekyii wordmark followed by two equal square shortcut cards in one row: 呆胶布 and 悬置箱.
- The projects module is one wide rounded card below the shortcuts. Its header contains the folder icon, title, and a right-aligned 查看全部入口; the empty state is centered inside the same card with a folder-plus icon and 新建项目 action.
- The hub does not repeat empty section headings below the module cards. Detail lists belong to the module destination opened from a shortcut or 查看全部.
- iOS reference: `/tmp/weekyii-ios-extensions-baseline.png`.
- Android acceptance capture: `/tmp/weekyii-android-extensions-ios-aligned-final5.png`.

## Expired Today acceptance

The Pixel 9 Pro expired-state capture is `/tmp/weekyii-android-expired-audit.png`. It verifies the red expired status artwork, the forgotten-task count, and the disabled past kill-time control without retaining expired task details.

## Acceptance rule

Every Android screen must be checked against the corresponding iOS screen in the simulator. A screen is not accepted because it compiles or because its ViewModel behavior passes; it must also match the baseline's hierarchy, palette, geometry, density, and state communication at the same user-visible state.
