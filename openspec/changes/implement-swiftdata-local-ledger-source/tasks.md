## 1. SwiftData Model Schema

- [x] 1.1 Add SwiftData model types for local groups, participants, records, and local source metadata.
- [x] 1.2 Define stable local ID generation for groups, members, and records.
- [x] 1.3 Add model fields for created/modified/occurred timestamps, archive state, owner identity, participant temporary status, settlement flag, and optional future remote mapping IDs.
- [x] 1.4 Configure cascade behavior or explicit deletion so deleting a local group removes its participants and records.

## 2. SwiftData Local Source

- [x] 2.1 Add `SwiftDataLedgerDataSource` conforming to `LedgerDataSource`.
- [x] 2.2 Implement local home/groups loading with pagination, group search, source metadata, and owner total balance.
- [x] 2.3 Implement group detail, balances, record pagination, structured record search, member records, and settlement suggestions.
- [x] 2.4 Implement group mutations: create, rename, archive, unarchive, and delete.
- [x] 2.5 Implement local member mutation for temporary members.
- [x] 2.6 Implement record mutations: add expense, add settlement, update, delete, and resolve all debts.
- [x] 2.7 Return explicit auth/capability failures for join shared group, invite registered users, and search registered users from the local source.

## 3. Projection And Calculation

- [x] 3.1 Add mapping from SwiftData models to `WalkGroup`, `Member`, and `WalkRecord`.
- [x] 3.2 Recompute member debt, cost, record count, participant count, participant preview, unresolved-balance flags, and modified timestamps after writes.
- [x] 3.3 Keep local record ordering newest-first and preserve pagination totals.
- [x] 3.4 Match backend/local fallback structured record search semantics for note and localized category-name OR conditions.
- [x] 3.5 Generate deterministic settlement transfers and settlement records using existing `Money` helpers.

## 4. Repository Integration

- [x] 4.1 Add a production local `ModelContainer` construction path that can be injected into `LedgerRepository`.
- [x] 4.2 Wire `LedgerRepository` construction so a local source can exist without changing current launch UI behavior.
- [x] 4.3 Preserve existing remote source behavior and current store method names.
- [x] 4.4 Keep SwiftData model types out of views, panels, and published `WalkcalcStore` state.

## 5. Verification

- [x] 5.1 Add debug verification for `SwiftDataLedgerDataSource` with an in-memory SwiftData container.
- [x] 5.2 Verify create group, add temporary member, add/edit/delete expense records, add settlement records, resolve debts, and delete group.
- [x] 5.3 Verify home/group/record pagination totals, group search, structured record search, and member-record filtering.
- [x] 5.4 Verify balance recomputation for splits, edits, deletes, settlements, and zero-balance resolution.
- [x] 5.5 Verify local join group, invite, and search registered users return account-required/capability failures and do not mutate persisted data.
- [x] 5.6 Add a temporary on-disk persistence smoke verification that survives data-source/container recreation.
- [x] 5.7 Run existing repository verification and build the native app.
