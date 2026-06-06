## Why

WalkCalc now has a unified ledger repository and a production SwiftData local ledger source, but the UI-facing store still selects remote contexts for normal home, group, member, record, and settlement workflows. As a result, the app cannot yet expose account-independent ledger functionality through the same polished native flows that already exist for authenticated server-backed data.

This change wires the existing UI and store layer to support local-backed groups and records through the same create, edit, delete, archive, balance, search, and settlement paths used by remote-backed groups. The goal is to make local ledger use feel like first-class WalkCalc behavior while preserving authenticated remote behavior for users who already have an account token.

## What Changes

- Add UI-facing local ledger mode selection in `WalkcalcStore` so source-agnostic operations can use the SwiftData local source.
- Load and display local groups in the existing Groups home screen without creating a separate local-only UI.
- Reuse current create-group, group-detail, group-settings, record-editor, search, balances, and settlement panels for local-backed data.
- Gate account-dependent actions such as joining a shared group, searching registered users, and inviting registered users behind the existing login-required/auth-required behavior.
- Show minimal source awareness only where capabilities differ, such as an unobtrusive local indicator or disabled remote-only entry points.
- Route unauthenticated launches into the existing Groups home backed by local SwiftData, so a signed-out user sees the same empty-state shape and can create local groups immediately.
- Preserve existing authenticated remote behavior and existing public store method names wherever practical.

## Capabilities

### New Capabilities

- `local-ledger-ui-flows`: Defines how native UI workflows create, display, mutate, and gate local-backed ledger data through the existing repository and view surfaces.

### Modified Capabilities

- None. Existing remote-backed collection behavior remains in force; this change adds local-backed UI support without changing backend contracts.

## Impact

- Affected native code: `walkcalc-native/App/WalkcalcStore.swift`, `walkcalc-native/Features/Home/HomeViews.swift`, `walkcalc-native/Features/Groups/GroupViews.swift`, `walkcalc-native/Features/Groups/GroupPanels.swift`, and localized strings in `walkcalc-native/Shared/Localization/L10n.swift` if new labels are needed.
- No backend API changes.
- App launch routing changes for unauthenticated users: no-token startup enters local Groups home instead of the login screen.
- No local-to-remote upload, merge, sync queue, or conflict resolution in this proposal.
- Testing impact: add debug verification or focused UI/store verification for local home loading, local CRUD, capability gating, source-aware refresh behavior, and remote regression build coverage.
