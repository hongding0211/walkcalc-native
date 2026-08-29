## Why

The group-detail balance preview currently surfaces the first participants in storage order, which can hide the settlement transfers that are directly relevant to the current user. The balances workspace also places the actionable settlement plan below the complete participant list, making the next useful action harder to scan.

## What Changes

- Prioritize suggested settlement transfers involving the current user in the group-detail Balances preview.
- Show every current-user transfer without a preview cap, keep those rows informational, and retain `View details` as the only entry into the balances workspace.
- Label the prioritized preview `Suggested settlement`, visually align its transfer cards with the balances workspace, and color/sign amounts from the current user's perspective.
- Preserve the existing capped member-balance preview when no current-user transfer exists, but order it by descending absolute balance.
- Put balance-workspace errors first, Suggested settlement second, and All balances afterward.
- Order All balances by descending absolute balance while preserving deterministic tie behavior.
- Apply the same behavior to local SwiftData and authenticated remote groups without changing backend APIs.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `complete-balance-member-visibility`: Change balance-preview prioritization and ordering while preserving access to the complete participant set in the balances workspace.

## Impact

- Native group-detail balance preview and balances workspace in `GroupViews.swift` and `GroupPanels.swift`.
- Native store access to current-participant identity and cached/fallback settlement suggestions.
- Existing local and remote ledger APIs remain unchanged; no backend work or new dependency is required.
