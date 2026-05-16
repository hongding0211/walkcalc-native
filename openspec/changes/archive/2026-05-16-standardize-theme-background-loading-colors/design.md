## Context

WalkCalc currently centralizes the accepted "Soft Utility Ledger" palette in `SoftLedgerTheme`, with production screens generally using `SoftLedgerBackground()` or `SoftLedgerTheme.canvas` for the app canvas. Light mode canvas is currently warm paper (`#F6F2EA`) and dark mode canvas is neutral graphite (`#131416`). Text, secondary text, muted text, cards, forms, separators, accent, and semantic balance colors are separate tokens, but many supporting neutral tokens still carry warm hue.

The next theme direction keeps color expression in accent, category, and semantic balance states, while moving background and supporting neutral UI infrastructure to grayscale. A shallow gray light-mode canvas with white cards preserves the original canvas-to-card hierarchy without warm hue, and a pure black dark-mode canvas gives dark appearance a neutral base. Grayscale surfaces/text/separators avoid baking a warm theme into every screen. Loading feedback should also stop borrowing accent or custom theme colors; progress should be quiet and secondary regardless of the active theme.

## Goals / Non-Goals

**Goals:**
- Make the light-mode app canvas/background a shallow grayscale base through shared theme tokens, with cards and rows using white surfaces.
- Make the dark-mode app canvas/background pure black through shared theme tokens.
- Convert supporting neutral tokens to grayscale, including primary text, secondary text, muted text, card/paper surfaces, form surfaces, separators/rules, avatar fallback fills, and low-emphasis neutral fills.
- Preserve existing accent, positive/negative balance, category, and destructive colors as semantic/theme colors unless contrast requires a local adjustment.
- Standardize visible `ProgressView` loading indicators to use SwiftUI `.secondary` coloring.
- Prefer shared helpers or modifiers for progress styling where repeated code exists.
- Update design documentation/specs so future theme work treats canvas/background and neutral hierarchy colors as grayscale infrastructure, not theme colors.

**Non-Goals:**
- Add a full user-selectable theme system in this change.
- Redesign layout, typography, surface radii, Liquid Glass usage, or card hierarchy.
- Change semantic balance colors, category colors, destructive colors, or the global UIKit accent tint.
- Replace native loading placement rules from `right-sized-operation-progress`.
- Add backend, persistence, or settings changes.

## Decisions

1. Change the shared canvas token first.

   Update `SoftLedgerTheme.canvas` light mode to shallow gray (`#F7F7F7`) and dark mode to pure black (`#000000`), then let screens that already use `SoftLedgerBackground()` inherit the change. Direct `.background(SoftLedgerTheme.canvas)` call sites should continue to use the token rather than hard-coded `Color.white` or `Color.black`.

   Rationale: the app already has a central canvas token, so changing it preserves existing architecture and reduces per-screen churn.

   Alternative considered: replace every canvas usage with `Color.white`. That flattened the original hierarchy because cards and rows then needed gray fills to separate from the background.

2. Convert neutral hierarchy tokens to grayscale.

   Update neutral tokens such as `paper`, `formPaper`, `ink`, `secondaryInk`, `mutedInk`, and `rule` to grayscale values that preserve the current hierarchy without warm hue. Light cards and rows should use white surfaces over a shallow gray canvas, while dark surfaces should remain distinguishable from the black canvas through near-black gray fills and rules.

   Rationale: future theme colors should sit on a neutral gray system. If warm neutrals remain in cards, labels, and separators, the app still visually carries one theme even after the canvas becomes white/black.

   Alternative considered: change only `canvas` and leave all other warm neutrals. That is lower risk, but it does not fully support theme variation because the UI would still read as warm-toned.

   Alternative considered: make both light canvas and light surfaces pure white. That flattened hierarchy and made cards, forms, list rows, and avatar fallbacks depend too much on borders and shadows.

3. Use SwiftUI `.secondary` for loading tint.

   All visible indeterminate `ProgressView` instances should apply `.tint(.secondary)` directly or through a small shared helper/modifier. Existing local progress placement remains unchanged.

   Rationale: `.secondary` tracks system contrast and appearance, fits the requested loading color, and avoids coupling loading states to accent/theme colors.

   Alternative considered: use `SoftLedgerTheme.secondaryInk`. It is close visually today, but it remains theme-specific and does not exactly express the requested system `.secondary` style.

4. Keep global accent behavior unchanged.

   `UIView.appearance().tintColor` and explicit `.tint(SoftLedgerTheme.accent)` on navigation/buttons should remain in place for interactive controls. Only progress indicators should move away from accent coloring.

   Rationale: future theme work likely changes accent selection, but this change is limited to neutral backgrounds and loading state color.

## Risks / Trade-offs

- Gray or black canvas can reduce visible separation if surface values are too close -> Verify representative home, group detail, sheets, and empty states in both appearances; adjust only gray canvas/surface/rule contrast if hierarchy becomes unclear.
- Removing warm neutral hues may make the app feel colder -> Preserve warmth through existing accent, category, and semantic colors, not through background infrastructure.
- Direct hard-coded backgrounds may be missed -> Audit production `SoftLedgerTheme.canvas`, `SoftLedgerBackground`, `Color.white`, and `ProgressView` call sites before implementation is complete.
- `.tint(.secondary)` on `ProgressView` may inherit differently inside tinted containers -> Prefer applying it directly to the progress view or shared helper so it does not pick up accent from parent `.tint(SoftLedgerTheme.accent)`.
- Pure black dark canvas can make graphite surfaces feel higher contrast than before -> Tune dark grayscale surface/rule values only enough to preserve readable hierarchy.
