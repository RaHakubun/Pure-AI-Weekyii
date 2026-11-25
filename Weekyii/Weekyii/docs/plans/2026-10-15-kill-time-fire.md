# Kill-time fire redesign

**Goal:** Turn the cutoff card into a convincing, stylised fire whose urgency follows the previewed cutoff time immediately and monotonically.

**Scope:** `Shared/Components/KillTimeEditor.swift`, the cutoff-card integration in `Features/Today/TodayView.swift`, and focused model/UI tests. Keep existing persistence and cutoff confirmation rules.

## Findings

- Gaussian bumps form a soft landscape rather than rising, tapered flames.
- A 2.5-second intensity animation trails the slider and repeatedly retargets during dragging.
- The old three-hour window makes earlier/later selections outside that window look identical.
- The drawing uses generic red/orange/yellow rather than the active theme palette.
- Pausing currently replaces time with zero, changing the shape abruptly; reduced-motion settings are not read inside the fire view.
- The slider's selected value must use a stable range throughout an editing session. Previews must never persist until confirmation.

## Visual design

Keep the established flame direction: a fire growing from the bottom edge, low under the slider and higher in the open area beside the large time. Render a low continuous ember bed, asymmetric tapered flame tongues with independently staggered rise/curl/decay, smaller warm cores, and sparse upward embers. Avoid a full-width wave silhouette, photographic smoke, heavy blur, flashing, or moving the card's content.

Use existing theme colors: urgency/DDL for the outer silhouette, accent orange for the body, accent-orange light for the core. Paper and brutal themes remain flat; neon/terminal use their existing accent language. Dark mode needs lower alpha to preserve controls.

## Time and interaction

- Compute pressure from the remaining minutes to the displayed cutoff (including unsaved preview), continuously over the full same-day range. Earlier means strictly more pressure; overdue saturates at full pressure.
- Direct manipulation updates pressure immediately, with no delayed spring or 2.5-second interpolation. Discrete cancellation/confirmation can use the existing short transition token.
- Pressure controls flame height, width, core brightness and ember visibility. The flame phase is independent of pressure so reversing direction cannot reseed or jump the fire.
- Anchor the slider range to the persisted cutoff while previewing; the existing gesture also freezes its lower bound until release. A committed cutoff becomes the new anchor.
- Keep the animation clock continuous over pause/resume. Reduce motion renders a stable fire, still reflecting time edits. Stop continuous drawing when inactive or backgrounded.
- Constrain geometry to nonzero, finite measured bounds; protect the time text, slider and confirmation header with a soft vertical mask.

## Verification

1. Test the full-day monotonic pressure mapping, near/overdue boundaries, and finite, bounded geometry on narrow/normal/wide cards.
2. Verify shape changes over time but does not reseed when pressure changes; higher pressure increases height at a fixed phase.
3. Check pause/resume and reduced-motion behavior.
4. Build Debug for iOS Simulator; run focused unit tests.
5. Capture rendered combinations of pressure, phase, theme and appearance; inspect flame shapes, readability and clipping, then exercise the actual slider and cancel path in the simulator.

No commits, branch changes or changes to unrelated unfinished work.

## Validation record

- The initial regression run failed because the previous curve was zero for all values at/after 180 remaining minutes.
- The replacement passes the full-day strict monotonicity and overdue/near-cutoff tests.
- Geometry is tested over 6 widths × 4 heights × 6 pressures × 5 phases, including zero-sized surfaces. Pressure reversal preserves tongue identity and phase and increases every tongue's height at a fixed phase.
- Pause/resume tests verify no phase reset and no accumulation of hidden elapsed time.
- Rendered and visually inspected 14 themes × 2 appearances × 3 pressure levels, plus four successive burn phases.
- Simulator UI test drags earlier, drags later, checks the displayed cutoff values, and cancels back to the saved value. Screenshots show the cutoff/confirmation text remains clear.
- `xcodebuild test` passed 6 focused unit tests and 1 UI test on iPhone 17 Pro / iOS 26.2; result bundle `/tmp/weekyii-fire-integration.xcresult`.
- No physical-device performance claim is made by these simulator checks.

## Material layering revision

User feedback: the first redraw still lacked depth and moved too quickly.

- Replace translucent scaled copies with three opaque tonal planes. Each plane has independent spacing, phase and height, so the front materials visibly occlude the back ones.
- Use restrained contact shadows and fine lit edges at plane boundaries. Continue deriving colors from the current theme, with tonal contrast maintained in dark mode; terminal keeps tonal separation without shadows.
- Run all autonomous motion at 0.28 of the previous rate: flame lifecycles are approximately 6–8 seconds, including slower curl and embers. Direct slider pressure feedback stays immediate.
- Added a regression test that failed on the previous half-second tip displacement; it passes with the slower motion. Independent-plane pressure tests also pass.
- Latest simulator run: 9 focused unit/render tests plus the drag/reverse/cancel UI test passed; result `/tmp/weekyii-material-review.xcresult`. The run includes the 84 theme combinations and an eight-second animated GIF attachment.
