## 1. Store Source Context

- [x] 1.1 Add a stable local owner identity for local ledger contexts.
- [x] 1.2 Track `LedgerSourceMetadata` for groups returned by home, group detail, and mutation refreshes.
- [x] 1.3 Add helpers for `localLedgerContext()`, `context(for groupId:)`, and `sourceMetadata(for groupId:)`.
- [x] 1.4 Keep remote context behavior unchanged for authenticated remote groups.

## 2. Local Home And Create Flow

- [x] 2.1 Add a store path to refresh local home data from `SwiftDataLedgerDataSource`.
- [x] 2.2 Wire the existing create-group sheet to create local groups when the active/preferred source is local.
- [x] 2.3 Ensure created local groups appear in the existing Groups home empty/populated states.
- [x] 2.4 Preserve existing remote create-group behavior for remote/authenticated contexts.

## 3. Local Group Detail And Mutations

- [x] 3.1 Route `refreshGroup`, `refreshGroupBalances`, record pagination, record search, member records, and settlement suggestions through `context(for: groupId)`.
- [x] 3.2 Route group rename, archive, unarchive, delete, and add-temporary-member mutations through `context(for: groupId)`.
- [x] 3.3 Route add/edit/delete record and settlement mutations through `context(for: groupId)`.
- [x] 3.4 Ensure mutation follow-up refreshes use the same source as the mutated group.
- [x] 3.5 Keep cache invalidation behavior consistent for local and remote record/search/member-record caches.

## 4. Capability Gating

- [x] 4.1 Keep join-by-code remote-only and authentication-required when no account token is available.
- [x] 4.2 Keep registered-user search remote-only and authentication-required when no account token is available.
- [x] 4.3 Prevent registered-user invite from silently creating local registered participants.
- [x] 4.4 Keep temporary-member creation available for local groups.
- [x] 4.5 Add minimal source-aware UI labels or disabled states only where capability differences would otherwise be unclear.

## 5. Verification

- [x] 5.1 Add debug verification for store-level local create group, home load, group detail load, add temporary member, record add/edit/delete, search, archive/delete, and settlement.
- [x] 5.2 Verify local data created through store-facing methods persists through SwiftData recreation where practical.
- [x] 5.3 Verify remote-only operations return auth-required feedback without mutating local state when unauthenticated.
- [x] 5.4 Run existing SwiftData ledger verification.
- [x] 5.5 Run existing repository verification.
- [x] 5.6 Build the native app with `xcodebuild`.

## 6. Unauthenticated Launch

- [x] 6.1 Route no-token startup to the existing Groups home in local mode.
- [x] 6.2 Keep authenticated startup on the existing remote source path.
- [x] 6.3 Hide or disable remote-only join/account controls where a signed-out local user would otherwise see a misleading login entry.
- [x] 6.4 Verify no-token bootstrap uses the local home route.
