## 1. Theme Model And Persistence

- [x] 1.1 Add a first-class app theme model with stable `blue`, `black`, `yellow`, and `green` identifiers, display labels, SwiftUI accent colors, UIKit accent colors, soft accent colors, and preview swatches.
- [x] 1.2 Add selected-theme loading that reads the new persisted key, maps legacy `themeColor` values (`blue`, `green`, `gold`, unsupported values), and defaults to blue.
- [x] 1.3 Replace or adapt `WalkcalcStore.themeColorId`, `primaryColor`, `primaryUIColor`, and `setThemeColor` so production code uses the selected app theme rather than loose color options.
- [x] 1.4 Ensure selecting a theme persists locally and updates published state without requiring sign out or app restart.

## 2. Shared Theme Application

- [x] 2.1 Add a shared dynamic access path for the selected theme palette, such as an environment value or narrowly injected theme service available from the app root.
- [x] 2.2 Wire the selected theme through explicit accent helpers while preserving app-wide SwiftUI default tint behavior and the previous global UIKit tint.
- [x] 2.3 Update shared accent-owned UI helpers so primary actions, selected controls, accent icons, accent badges, and accent-soft fills read from the selected theme palette.
- [x] 2.4 Audit production `SoftLedgerTheme.accent`, `SoftLedgerTheme.accentUIColor`, `SoftLedgerTheme.accentSoft`, and `.tint(SoftLedgerTheme.accent)` usages and migrate only explicit accent-owned call sites to the dynamic selected theme.
- [x] 2.5 Keep `SoftLedgerTheme.canvas`, neutral surface/text/separator tokens, semantic balance colors, category colors, destructive colors, validation colors, and secondary progress tint independent from the selected theme.

## 3. Theme Picker UI

- [x] 3.1 Add a compact theme selection control to an existing settings or profile preference surface.
- [x] 3.2 Show all four supported themes with compact color previews, accessibility labels, and a clear selected state.
- [x] 3.3 Ensure changing the picker selection immediately updates visible accent-owned UI and persists the selected theme.
- [x] 3.4 Remove or hide unsupported legacy choices such as rose from production theme selection.

## 4. Verification

- [x] 4.1 Build the native app to catch compile errors from the theme model and accent call-site migration.
- [x] 4.2 Verify blue is the default for fresh installs and for unsupported legacy stored theme values.
- [x] 4.3 Verify blue, black, yellow, and green themes update accent-owned UI in representative home, group, sheet/form, and settings/profile screens.
- [x] 4.4 Verify light-mode neutral canvas/surfaces/text/separators remain grayscale under every theme.
- [x] 4.5 Verify dark-mode pure black canvas, neutral surfaces/text/separators, semantic balance colors, category colors, destructive/validation colors, and secondary loading tint remain correct under every theme.
