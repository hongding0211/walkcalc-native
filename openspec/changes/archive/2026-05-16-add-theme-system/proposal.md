## Why

WalkCalc already has centralized visual tokens, but users cannot choose between the different color directions the product wants to support. A selectable theme system lets the app keep its neutral hierarchy stable while offering distinct accent palettes: the current yellow, system blue, green, and a black shadcn-style theme.

## What Changes

- Introduce a first-class set of selectable app themes: system blue, black, yellow, and green.
- Make system blue the default/current visual direction unless a saved user preference selects another theme.
- Apply the selected theme through shared SwiftUI theme tokens so primary actions, selected controls, navigation tint, accent affordances, and theme-owned fills update consistently.
- Persist the selected theme locally so the app restores the user's choice across launches.
- Provide an in-app theme selection surface using clear names and color previews.
- Preserve semantic balance, destructive, validation, and category color meanings unless a theme explicitly owns the related accent treatment.
- Keep neutral canvas, text, separator, and surface hierarchy governed by the existing grayscale theme surface rules.

## Capabilities

### New Capabilities
- `selectable-color-themes`: Defines supported theme choices, selection persistence, user-facing theme controls, and how selected themes apply to app accent styling.

### Modified Capabilities
- `theme-surface-colors`: Clarifies that selectable themes may change accent-owned colors while neutral canvas, text, separators, and supporting surfaces remain grayscale infrastructure.

## Impact

- Affected code: shared theme/color tokens under `walkcalc-native/Shared/UI`, app bootstrap/environment wiring, settings/profile UI where theme selection belongs, and screens using accent tint or custom theme colors.
- Persistence: local app preference storage for the selected theme; no backend API change required.
- Dependencies: no new external dependencies expected.
- Verification: native build plus visual checks that blue, black, yellow, and green themes update accent-owned UI consistently in light and dark mode while neutral hierarchy and semantic colors remain correct.
