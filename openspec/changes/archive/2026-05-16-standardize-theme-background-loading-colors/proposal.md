## Why

The app is preparing for multiple selectable accent themes, but the current warm neutral palette is coupled to the visual theme and makes future theme variation harder to reason about. Backgrounds and supporting neutral UI colors should move toward grayscale, while loading states should use a consistent secondary treatment that stays quiet across themes.

## What Changes

- Keep existing accent, semantic balance, and category color semantics intact.
- Standardize app-level background/canvas surfaces to a shallow grayscale canvas in light mode and pure black in dark mode so future theme colors do not compete with tinted backgrounds.
- Express supporting neutral UI colors, such as text, secondary text, muted text, card/form surfaces, separators, and low-emphasis fills, with grayscale values rather than warm tinted neutrals.
- Preserve semantic positive/negative colors and branded accent colors unless contrast requires a small accessibility adjustment.
- Standardize all indeterminate loading and progress indicators to use SwiftUI `.secondary` coloring.
- Apply the loading color rule consistently across initial content loads, pagination, search-scoped progress, toolbar submission progress, sheet submission progress, and any shared loading helpers.

## Capabilities

### New Capabilities
- `theme-surface-colors`: Defines how app background/canvas and supporting neutral colors use grayscale while accent, category, and semantic colors remain available for theme expression.

### Modified Capabilities
- `right-sized-operation-progress`: Progress feedback keeps its existing placement and lifecycle rules, but all visible loading indicators use `.secondary` as their color treatment.

## Impact

- Affected code: shared style/color tokens under `walkcalc-native/Shared/UI`, app background usage in production SwiftUI screens, and loading/progress indicators in `walkcalc-native/Features/Home`, `walkcalc-native/Features/Groups`, authentication, and shared UI helpers.
- APIs: no backend or public API changes.
- Dependencies: no new external dependencies expected.
- Verification: native build plus targeted visual checks for app backgrounds, neutral surfaces, grayscale text/separators, and loading states in both light and dark mode, including shallow gray light canvas with white cards and pure black dark canvas.
