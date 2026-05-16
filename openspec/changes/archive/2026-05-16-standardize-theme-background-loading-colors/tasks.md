## 1. Theme Surface Tokens

- [x] 1.1 Update `SoftLedgerTheme.canvas` light-mode value to shallow grayscale and dark-mode value to pure black.
- [x] 1.2 Audit production `SoftLedgerBackground()` and `SoftLedgerTheme.canvas` usages to confirm app backgrounds flow through shared tokens/helpers rather than feature-local tinted colors.
- [x] 1.3 Convert supporting neutral tokens to grayscale values, including `paper`, `formPaper`, `ink`, `secondaryInk`, `mutedInk`, `rule`, avatar fallback fills, and low-emphasis neutral fills.
- [x] 1.4 Keep accent, positive, negative, category, destructive, and validation colors semantic rather than converting them to grayscale.
- [x] 1.5 Update `docs/visual-style.md` so the accepted light canvas token documents shallow grayscale, card/form surfaces document white, the dark canvas token documents pure black, supporting neutral colors document grayscale values, and accent/semantic colors remain separate.

## 2. Loading Indicator Color

- [x] 2.1 Add a shared progress styling helper or update `AsyncConfirmationIcon` so confirmation spinners render with `.tint(.secondary)`.
- [x] 2.2 Audit production `ProgressView` usages in auth, home, groups, sheets, search, pagination, settlement, and shared UI code.
- [x] 2.3 Apply `.tint(.secondary)` to all visible indeterminate loading indicators, including those nested inside views that set `.tint(SoftLedgerTheme.accent)`.
- [x] 2.4 Ensure accompanying loading copy uses grayscale secondary or muted text styles unless it communicates a semantic state.

## 3. Production Visual Review

- [x] 3.1 Verify home, group detail, group settings, create/join group, add member, record editor, record search, balances, and archived-management surfaces still have clear grayscale hierarchy on a shallow gray light canvas and black dark canvas.
- [x] 3.2 Check representative empty, initial-loading, pagination-loading, search-loading, and submission-loading states to confirm progress indicators use `.secondary`.
- [x] 3.3 Verify dark mode uses pure black app background and readable `.secondary` progress indicators.
- [x] 3.4 Remove or replace leftover hard-coded warm neutral values from production code unless they are intentionally scoped to design playground examples.

## 4. Verification

- [x] 4.1 Run the native build/test command used for this project and fix any Swift compile or test failures caused by the style updates.
- [x] 4.2 Re-scan production code for `ProgressView`, `SoftLedgerTheme.canvas`, warm neutral hex values, and the previous dark canvas hex value to confirm no required production call site was missed.
- [x] 4.3 Record any intentionally unchanged design-playground-only warm neutral references in the implementation notes or final summary.
