# Verification

Validated on an isolated iPhone 17 Pro simulator running iOS 26.4, using Xcode 26.4.1.

- Debug and Release simulator builds succeed.
- `--verify-expense-scroll-title --verify-temporal-display` passes all 21 scroll-title checks and the existing temporal display checks.
- The fixture uses 180 records, including 60 records in today's section. It checks native title text, a heading scrolled offscreen inside that long section, forward/reverse section transitions, overview restoration, sheet return, appending records, removing the active date, empty filters, restoring filters, and empty records.
- During same-section and cross-section scrolling, GroupView body evaluations stayed at 5, record reads at 15, and section rebuilds at 1 in the final run. Data mutations intentionally cause new reads/rebuilds. These counters verify dependency isolation, not rendering frame rate.
- Strict OpenSpec validation and `git diff --check` pass.

## Repeating the integration check

Build Debug and launch the app in a dedicated simulator with `--verify-expense-scroll-title --verify-temporal-display`. The opt-in host supplies fixture data and moves via SwiftUI's ScrollViewProxy. It prints individual `SCROLL_TITLE_CHECK` outcomes followed by `EXPENSE_SCROLL_TITLE_VERIFICATION: PASSED` or `FAILED`. It never sends fixture mutations to the backend.

The fixture aligns distant targets twice because nested lazy stacks refine their estimated heights after first realizing a section. The production title feature does not issue scroll commands. Debug counters are inactive during normal launches and absent from Release.

## Limits

Simulator screenshot capture failed in this environment, and manual scroll input could not be confirmed. Automated checks read the actual native navigation title and exercise real SwiftUI layout, but do not replace visual review or physical-device drag/deceleration and frame-rate profiling. No claim of measured FPS improvement is made.
