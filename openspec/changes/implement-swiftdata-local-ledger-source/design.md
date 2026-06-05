## Context

`introduce-ledger-data-layer` added the repository boundary and moved ledger operations behind `LedgerDataSource`. The existing concrete sources are:

- `RemoteLedgerDataSource`, which wraps current backend APIs.
- `InMemoryLedgerDataSource`, which proves local semantics for repository verification but is not persistent.

The new local source should reuse the same repository contract and the same domain projection models: `WalkGroup`, `Member`, `WalkRecord`, `SettlementTransfer`, `LedgerHomeSnapshot`, `LedgerGroupSnapshot`, `LedgerPage`, and `LedgerMutationResponse`.

## Goals / Non-Goals

**Goals:**

- Implement a production local ledger backend using SwiftData.
- Match remote-source behavior for local-capable operations as closely as practical.
- Keep SwiftData model types private to the ledger layer and project them into existing domain structs.
- Use stable local identifiers suitable for future remote mapping.
- Recompute local balances and settlement suggestions deterministically after every relevant mutation.
- Provide verification that local data persists beyond one data-source instance.

**Non-Goals:**

- Change launch routing to show the app without login.
- Add or change UI for local/remote state.
- Implement local-to-remote upload, merge, conflict resolution, or sync status.
- Let local storage create, search, or invite registered remote users.
- Replace the remote backend or change backend routes.

## Decisions

1. **Use SwiftData as a private persistence detail.**
   Add `@Model` types for local persistence and keep them behind `SwiftDataLedgerDataSource`.

   Rationale: views and `WalkcalcStore` should continue working with repository/domain structs. Exposing SwiftData models upward would couple UI identity and persistence identity too early.

2. **Use local IDs as domain IDs.**
   Persist IDs such as `local-group-<uuid>`, `local-member-<uuid>`, and `local-record-<uuid>`. Domain projections use those IDs directly until future upload creates remote mappings.

   Rationale: the existing UI and repository contract already identify groups and records by strings. Stable local IDs avoid special cases and support future `localId -> remoteId` mapping.

3. **Persist source metadata for future upload, but do not sync.**
   Local model objects should include optional remote identifiers and dirty/sync metadata only where useful, but this change does not interpret them as upload state.

   Rationale: adding fields now avoids a near-term migration when upload is proposed. Sync behavior still needs its own product and conflict design.

4. **Recompute local projections after writes.**
   After group/member/record/settlement mutations, recompute member `debtMinor`, `costMinor`, record counts, group participant preview, unresolved-balance flags, modified timestamps, and home total balance.

   Rationale: the remote backend returns derived balances. The local backend must own equivalent derived values for the UI to remain source-agnostic.

5. **Keep unsupported remote-only operations explicit.**
   `joinGroup`, `searchUsers`, and `invite` return `.authenticationRequired` or a capability-oriented failure when the active source is local.

   Rationale: these operations require remote account identity or registered users. Pretending they are locally successful would corrupt future sync semantics and confuse UI gating.

6. **Reuse in-memory behavior as an oracle, not as storage.**
   The SwiftData implementation can follow the calculation and filtering semantics of `InMemoryLedgerDataSource`, but verification should exercise the SwiftData source directly.

   Rationale: in-memory coverage is useful, but App Review needs persistent local data.

## Proposed Shape

Add model/source files under `walkcalc-native/Core/Ledger/`:

- `SwiftDataLedgerModels.swift`
  - `LocalLedgerGroupModel`
  - `LocalLedgerParticipantModel`
  - `LocalLedgerRecordModel`
  - optional metadata value fields for remote mapping/future sync
- `SwiftDataLedgerDataSource.swift`
  - conforms to `LedgerDataSource`
  - owns or receives a `ModelContainer`
  - uses a serialized `ModelContext` access pattern appropriate for SwiftData concurrency
- `LocalLedgerProjection.swift`
  - maps SwiftData models into `WalkGroup`, `Member`, `WalkRecord`
  - centralizes balance and settlement calculations if it keeps source file size manageable

Expected local data flow:

```text
WalkcalcStore / LedgerRepository
          |
          v
SwiftDataLedgerDataSource
          |
          v
SwiftData ModelContainer
          |
          v
Local group / participant / record models
```

## Local Behavior Contract

The local source should implement:

- `home`: page local groups, apply group search, return total local balance for the local owner.
- `groups`: same pagination/search semantics as home without summary.
- `groupDetail`: return group plus first record page.
- `groupBalances`: return all local participants with recomputed debt/cost/record counts.
- `records`: paginate records sorted newest-first; structured search matches only requested supported fields.
- `memberRecords`: return records where the member paid or appears in `forWhom`.
- `settlementSuggestion`: generate deterministic transfers from negative balances to positive balances.
- `createGroup`: create group with local owner as first member.
- `archiveGroup` / `unarchiveGroup`: archive per local owner.
- `deleteGroup`: delete group and cascading participants/records.
- `changeGroupName`: update name and modified timestamp.
- `addTempUser`: create local temporary participant.
- `addRecord` / `updateRecord` / `deleteRecord`: mutate records and recompute balances.
- `addSettlementRecord` / `resolveDebts`: create settlement records and recompute balances.

The local source should reject or require account auth for:

- `joinGroup`
- `invite`
- `searchUsers`

## Risks / Trade-offs

- [Risk] SwiftData relationship behavior can create hidden fetch/order issues. -> Mitigation: verify projections with multiple groups, participants, records, and relaunch.
- [Risk] Local balance math may diverge from backend math. -> Mitigation: reuse existing money helpers and verify expense splits, settlements, deletes, and edits.
- [Risk] Record search may broaden beyond backend semantics. -> Mitigation: only match fields present in `RecordSearchRequest` and reject/ignore unsupported fields consistently with existing local fallback expectations.
- [Risk] Repository source selection may remain remote-only after this change. -> Mitigation: this change can inject the local source into repository construction without changing startup routing; UI wiring remains a later change.
- [Risk] SwiftData models may leak into UI state. -> Mitigation: keep all projections at the data-source boundary.
- [Risk] Adding sync metadata too early could imply sync support. -> Mitigation: store metadata fields only; do not expose upload/merge behavior.

## Verification Strategy

1. **In-memory SwiftData verification.**
   Create a `ModelContainer` with in-memory storage and run local data-source operations for create group, add temp members, add records, edit records, delete records, archive/unarchive, rename, member records, search, settlement suggestion, and resolve debts.

2. **Persistence smoke verification.**
   Use a temporary on-disk SwiftData container, write a group with members and records, create a fresh data-source/container pointing at the same store, and verify the projected home/group/detail data survives.

3. **Parity checks against local semantics.**
   Compare key outcomes against expected domain projections: pagination totals, newest-first record ordering, owner total balance, member debt/cost values, and zeroed balances after resolve debts.

4. **Capability checks.**
   Verify local `joinGroup`, `invite`, and `searchUsers` return an account-required/capability failure and do not mutate local data.

5. **Build verification.**
   Build the native app and keep existing repository verification available.
