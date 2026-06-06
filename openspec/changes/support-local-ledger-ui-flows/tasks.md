## 1. Store Source Context

- [ ] 1.1 Add a stable local owner identity for local ledger contexts.
- [ ] 1.2 Track `LedgerSourceMetadata` for groups returned by home, group detail, and mutation refreshes.
- [ ] 1.3 Add helpers for `localLedgerContext()`, `context(for groupId:)`, and `sourceMetadata(for groupId:)`.
- [ ] 1.4 Keep remote context behavior unchanged for authenticated remote groups.

## 2. Local Home And Create Flow

- [ ] 2.1 Add a store path to refresh local home data from `SwiftDataLedgerDataSource`.
- [ ] 2.2 Wire the existing create-group sheet to create local groups when the active/preferred source is local.
- [ ] 2.3 Ensure created local groups appear in the existing Groups home empty/populated states.
- [ ] 2.4 Preserve existing remote create-group behavior for remote/authenticated contexts.

## 3. Local Group Detail And Mutations

- [ ] 3.1 Route `refreshGroup`, `refreshGroupBalances`, record pagination, record search, member records, and settlement suggestions through `context(for: groupId)`.
- [ ] 3.2 Route group rename, archive, unarchive, delete, and add-temporary-member mutations through `context(for: groupId)`.
- [ ] 3.3 Route add/edit/delete record and settlement mutations through `context(for: groupId)`.
- [ ] 3.4 Ensure mutation follow-up refreshes use the same source as the mutated group.
- [ ] 3.5 Keep cache invalidation behavior consistent for local and remote record/search/member-record caches.

## 4. Capability Gating

- [ ] 4.1 Keep join-by-code remote-only and authentication-required when no account token is available.
- [ ] 4.2 Keep registered-user search remote-only and authentication-required when no account token is available.
- [ ] 4.3 Prevent registered-user invite from silently creating local registered participants.
- [ ] 4.4 Keep temporary-member creation available for local groups.
- [ ] 4.5 Add minimal source-aware UI labels or disabled states only where capability differences would otherwise be unclear.

## 5. Verification

- [ ] 5.1 Add debug verification for store-level local create group, home load, group detail load, add temporary member, record add/edit/delete, search, archive/delete, and settlement.
- [ ] 5.2 Verify local data created through store-facing methods persists through SwiftData recreation where practical.
- [ ] 5.3 Verify remote-only operations return auth-required feedback without mutating local state when unauthenticated.
- [ ] 5.4 Run existing SwiftData ledger verification.
- [ ] 5.5 Run existing repository verification.
- [ ] 5.6 Build the native app with `xcodebuild`.
