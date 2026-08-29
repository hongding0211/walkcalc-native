## 1. Store And Ordering Support

- [x] 1.1 Expose source-aware current-participant identity and personal settlement transfers from `WalkcalcStore`.
- [x] 1.2 Add deterministic descending-absolute-balance ordering that preserves original order for ties.

## 2. Group Detail Preview

- [x] 2.1 Render every current-user suggested payment as an informational row with no direct action or disclosure affordance.
- [x] 2.2 Preserve the capped member fallback, apply absolute-balance ordering, and keep the agreed footer labels and navigation.
- [x] 2.3 Refresh balance projections and settlement suggestions for the group-detail preview.
- [x] 2.4 Align personal transfer cards with the workspace presentation while keeping them informational.
- [x] 2.5 Present personal transfer amounts with payer-negative/receiver-positive color and sign semantics.
- [x] 2.6 Preserve the original grouped-list container while aligning settlement row content with the workspace.

## 3. Balances Workspace

- [x] 3.1 Move error feedback to the top, Suggested settlement above All balances, and keep existing settlement actions unchanged.
- [x] 3.2 Apply deterministic absolute-balance ordering to the complete All balances list.

## 4. Verification

- [x] 4.1 Add focused debug verification for personal-transfer filtering and absolute-balance ordering in remote and local identity contexts.
- [x] 4.2 Build the iOS Simulator target and verify the Icon Composer package compiles with the updated asset.
- [x] 4.3 Verify the refined settlement preview compiles and the OpenSpec change remains valid.
