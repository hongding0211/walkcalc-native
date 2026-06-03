## Why

WalkCalc's native ledger flow is currently coupled to authenticated server access. `WalkcalcStore` owns app state, startup routing, pagination caches, mutation feedback, API token guards, and server calls in the same layer. This makes it difficult to support App Review's required account-independent ledger usage without either duplicating UI logic or adding ad hoc "guest" branches throughout the app.

Before changing the launch UI or implementing local persistence, the app needs a unified ledger data layer that can expose the same group, member, record, balance, search, and mutation operations over both local and remote sources.

## What Changes

- Introduce a ledger data-access abstraction between `WalkcalcStore` and concrete storage/network implementations.
- Define one repository-facing contract for home groups, group detail, records, member records, balances, settlement suggestions, and mutations.
- Separate account/session state from ledger data-source choice so upper UI state can work with local-only, remote-authenticated, and future sync-capable modes.
- Move server-specific token and API concerns behind a remote ledger source instead of keeping them in UI-facing store methods.
- Prepare a local ledger source contract without requiring this change to implement local persistence or alter the startup/login UI.
- Preserve existing server-backed behavior while creating a path to add local ledger storage and later local-to-remote upload/merge.

## Capabilities

### New Capabilities
- `unified-ledger-data-access`: Defines the native ledger repository contract and source-mode behavior required to support local and remote ledger data through one upper-layer interface.

### Modified Capabilities
- None in this proposal. Existing UI routing and server-backed collection behavior remain unchanged until the abstraction is implemented and adopted.

## Impact

- Affected native code: `walkcalc-native/App/WalkcalcStore.swift`, `walkcalc-native/Core/Networking/APIClient.swift`, `walkcalc-native/Core/Models/Models.swift`, and new data-layer files under an appropriate native core/services folder.
- No backend API contract change is expected for this step.
- No intended UI change in this step; the login-first launch behavior can be changed in a later OpenSpec change after the data layer exists.
- Testing impact: add repository-level verification using a fake/in-memory source, regression coverage that existing remote-backed flows still call the same server APIs through the new layer, and focused checks for auth, pagination, cache invalidation, mutation refresh, and error classification.
