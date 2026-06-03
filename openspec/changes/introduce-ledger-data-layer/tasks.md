## 1. Data-Layer Contract

- [x] 1.1 Define ledger source mode/session context types that represent local availability, authenticated remote availability, and current local owner identity.
- [x] 1.2 Define repository request/response types for home group pages, group detail, records, member records, balances, settlement suggestions, and mutations.
- [x] 1.3 Define structured operation outcomes for success, validation failure, authentication required, source unavailable, recoverable network failure, and unrecoverable auth failure.
- [x] 1.4 Document which operations are source-agnostic and which require remote authentication, such as joining shared groups and searching registered users.

## 2. Source Protocols

- [x] 2.1 Add a `LedgerDataSource` protocol or equivalent split protocols for read, mutation, member, record, and settlement operations.
- [x] 2.2 Add a `RemoteLedgerDataSource` that wraps current `APIClient` routes without changing backend request/response contracts.
- [x] 2.3 Add a fake or in-memory ledger data source for tests and for proving local-mode semantics before persistence is implemented.
- [x] 2.4 Ensure source implementations do not own SwiftUI view state, alerts, sheets, or navigation decisions.

## 3. Repository Coordinator

- [x] 3.1 Add `LedgerRepository` to select and call the appropriate source based on session/source context.
- [x] 3.2 Keep pagination, cache keys, and source metadata explicit enough for `WalkcalcStore` to maintain its existing published state.
- [x] 3.3 Route remote auth-required and unrecoverable-auth outcomes through the existing auth/session failure path rather than as generic network failures.
- [x] 3.4 Preserve existing localized UI feedback behavior while moving source-specific error classification out of view-facing methods.

## 4. Store Migration

- [x] 4.1 Move home refresh and group pagination from direct `APIClient` calls to the repository.
- [x] 4.2 Move group detail, balance refresh, record pagination, record search, and member-record loading to the repository.
- [x] 4.3 Move group mutations, member mutations, record mutations, and settlement mutations to the repository.
- [x] 4.4 Keep existing public `WalkcalcStore` method names where practical so views and panels do not need broad rewrites in this change.
- [x] 4.5 Remove duplicated token/source guards from migrated store methods after repository outcomes cover those cases.

## 5. Verification

- [x] 5.1 Add repository tests or debug verification using the fake/in-memory source for local-style create group, add temporary member, add record, edit record, delete record, search, and settlement calculation entry points.
- [x] 5.2 Verify fake-source outcomes for auth-required remote-only operations, source-unavailable operations, validation failures, and successful source-agnostic operations.
- [x] 5.3 Verify authenticated remote home loading still requests home summary and the first group page through the existing backend contracts and publishes the same `groups`, `groupTotal`, and `totalBalanceMinor` values.
- [x] 5.4 Verify remote group pagination and group search preserve page, page size, append/replace behavior, filtered totals, and loading flags.
- [x] 5.5 Verify remote group detail loading preserves group refresh, first records page, record totals, balances refresh, member-record loading, and member-record pagination.
- [x] 5.6 Verify remote structured record search still sends note/category OR conditions and preserves local interim search-match behavior.
- [x] 5.7 Verify remote mutations preserve current follow-up refresh behavior for create group, invite/add temporary member, rename group, archive/unarchive group, delete group, add/edit/delete record, and settlement records.
- [x] 5.8 Verify missing-token remote-only operations return an auth-required outcome instead of generic failure.
- [x] 5.9 Verify expired-token refresh, unrecoverable auth failure, recoverable transport failure, and server-envelope failure keep their existing store-level routing/feedback behavior after repository migration.
- [x] 5.10 Build the native app after implementation.
