## Context

WalkCalc currently has two partially overlapping theme concepts. `SoftLedgerTheme` defines static shared SwiftUI colors for canvas, surfaces, text, rules, semantic balances, and accent styling. Separately, `WalkcalcStore` already persists a `themeColorId` in UserDefaults and exposes `primaryColor` / `primaryUIColor`, backed by `themeColorOptions`, but those values are not the source of truth for production accent rendering.

The previous `theme-surface-colors` work intentionally made neutral infrastructure grayscale: shallow gray canvas in light mode, pure black canvas in dark mode, and grayscale supporting surfaces/text/separators. The new theme system should build on that split. Theme choice should affect accent-owned UI, not turn the app canvas or general text hierarchy into colored variants.

## Goals / Non-Goals

**Goals:**
- Define a small, explicit set of supported app themes in picker order: system blue, black, yellow, and green.
- Make system blue the default so the app starts from the platform accent direction unless users choose another theme.
- Replace the loose `themeColorOptions` concept with a stronger theme/palette model that includes SwiftUI and UIKit colors needed by production UI.
- Persist and restore the selected theme locally.
- Make accent-owned UI read from the selected theme consistently, including app tint, primary actions, selected controls, accent icons, badges, and soft accent fills.
- Add a clear in-app theme picker with compact color previews and accessibility labels.
- Keep neutral surface, text, separator, background, loading, semantic balance, destructive, validation, and category color rules intact unless a requirement explicitly says otherwise.

**Non-Goals:**
- Add remote theme sync, account-level theme settings, or backend API changes.
- Add arbitrary custom colors or user-authored palettes.
- Redesign screen layouts, typography, card hierarchy, Liquid Glass behavior, or category color taxonomy.
- Change light/dark appearance selection; the theme system is orthogonal to the system color scheme.
- Replace existing semantic balance colors with theme-derived colors.

## Decisions

1. Model themes as semantic palettes, not raw colors.

   Introduce an `AppTheme` or equivalent domain type with stable identifiers for `blue`, `black`, `yellow`, and `green` in that picker order. Each case should provide at least `accent`, `accentUIColor`, `accentSoft`, display label, and preview swatches for light/dark where needed. The existing `ThemeColorOption` / `themeColorOptions` can be replaced or adapted during migration, but production code should stop treating a theme as only one raw color.

   Rationale: the black shadcn-style theme needs more nuance than a single accent color because selected states and soft fills must remain legible without making neutral surfaces theme-owned.

   Alternative considered: keep `themeColorOptions` as-is and add yellow/black entries. That is smaller, but it preserves the current mismatch where persisted color preference does not drive `SoftLedgerTheme.accent`.

2. Make selected theme available through explicit shared UI infrastructure.

   Accent-owned SwiftUI code should read from a shared selected palette via environment-backed accent helpers or a narrow observable theme service injected from `WalkcalcStore`. The app root should provide the selected palette, but it should not apply a blanket SwiftUI `.tint` that recolors controls which previously used `.primary`, `.secondary`, `.tertiary`, or inherited system defaults. The existing global UIKit tint should remain the previous yellow treatment unless a specific UIKit-backed accent-owned control is explicitly themed.

   Rationale: the current static `SoftLedgerTheme.accent` API is easy to use but cannot react to user selection. A shared access point keeps call sites consistent while preserving uncolored and secondary UI behavior.

   Alternative considered: use an app-root `.tint(selectedTheme.accent)`. That is broad, but it changes controls that were not explicitly accent-owned.

3. Keep neutral infrastructure separate from theme palettes.

   `SoftLedgerTheme.canvas`, `paper`, `formPaper`, `ink`, `secondaryInk`, `mutedInk`, `rule`, loading tint, semantic balance colors, and category colors should not be redefined per theme. Theme palettes own accent and accent-soft treatments only, plus any explicitly theme-owned selected-control styling.

   Rationale: this preserves the existing grayscale foundation and prevents blue/green/yellow themes from becoming full-page color washes.

   Alternative considered: define a full palette for every token per theme. That gives more control but reintroduces theme-specific neutral hierarchy and increases visual QA cost.

4. Migrate persisted values conservatively.

   Store the new selected theme under a stable key such as `walkcalc.selectedTheme`. On first launch after migration, map the legacy `themeColor` value where possible: `blue` becomes `blue`, `green` becomes `green`, `gold` becomes `yellow`, and missing or unsupported legacy values such as `rose` should fall back to the default blue theme.

   Rationale: the app already has a user preference key, but the new supported set is different. A one-way tolerant mapping avoids crashes or blank selections.

   Alternative considered: reuse `themeColor`. Reusing the old key makes migration simpler but leaves ambiguous legacy IDs and makes it harder to distinguish old color choices from the new theme contract.

5. Put the picker in an existing settings/profile surface.

   The picker should be a compact native settings row or list section with four choices in one row, visible swatches, accessibility labels, and a clear selected state. It should use familiar controls and stay visually quiet; the selection itself can demonstrate the theme through accent tint.

   Rationale: theme selection is app preference behavior, not a primary workflow. It belongs where users already manage account/app preferences.

   Alternative considered: add a prominent home-screen theme switcher. That makes discovery easier, but it overemphasizes a preference and adds noise to the ledger workflow.

## Risks / Trade-offs

- Static `SoftLedgerTheme.accent` call sites may not update if only the store changes -> Introduce a shared dynamic access path and audit `SoftLedgerTheme.accent`, `.tint(SoftLedgerTheme.accent)`, and `UIView.appearance().tintColor` usages.
- Broad inherited tint can recolor controls that were previously secondary or uncolored -> Do not apply root theme tint; use explicit accent helpers only on accent-owned UI and leave global UIKit tint at the previous yellow default.
- Black theme can blur the line between accent and neutral in dark mode -> Define black theme accent/soft values separately for light and dark and test selected states in both appearances.
- Legacy `rose` preference has no requested replacement -> Map unsupported legacy IDs to the default blue theme and keep the picker constrained to the four supported themes.
- A broad theme refactor can touch many views -> Start with shared tokens and only adjust call sites that explicitly hard-code accent colors or bypass shared controls.

## Migration Plan

1. Add the new theme model and migration helper while keeping current neutral tokens unchanged.
2. Initialize selected theme from the new key, legacy `themeColor`, or default blue.
3. Wire the selected palette into the app root environment and explicit shared accent token access.
4. Replace production accent call sites that still read static yellow values.
5. Add the picker UI and ensure selection writes the new key.
6. Remove or deprecate unused legacy `themeColorOptions` entries once no production code depends on them.

Rollback is local: keep the neutral token changes untouched, restore the previous selected-theme behavior, and leave migrated preference values ignored if the dynamic theme access path needs to be disabled.

## Open Questions

- Exact display labels can be finalized during implementation; proposed labels are Blue, Black, Yellow, and Green.
- The black theme's light-mode accent should be validated visually; a near-black accent with gray soft fill is likely, but it must preserve selected-control contrast.
