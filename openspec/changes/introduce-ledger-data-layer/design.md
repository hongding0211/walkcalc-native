## Context

The current native implementation already has most domain models needed for both local and remote ledger modes: `WalkGroup`, `WalkRecord`, `Member`, `ResolvedDebt`, and `SettlementTransfer`. It also has temporary-member semantics through `Member.isTemporary` and `WalkGroup.tempUsers`.

The coupling problem is in orchestration. `WalkcalcStore` directly checks `token`, calls `APIClient`, applies refreshed tokens, updates pagination dictionaries, mutates in-memory arrays, handles fixture mode, and returns UI feedback messages. That works for a server-only app but makes local ledger support expensive because every operation would need a separate unauthenticated branch.

This change creates a stable data layer first. It does not change launch routing, remove login, or persist local data yet.

## Goals / Non-Goals

**Goals:**
- Give UI-facing store logic one ledger contract for local and remote sources.
- Keep source-specific concerns such as bearer tokens, HTTP refresh, local IDs, persistence, and sync metadata outside views and panels.
- Preserve existing remote server behavior and response semantics while moving them behind a remote source.
- Make local support possible without later rewriting group and record UI flows.
- Define enough source identity metadata to let the UI distinguish local-only features from account-required features when a later UI change is proposed.

**Non-Goals:**
- Implement local persistence, local launch routing, or App Review UI changes in this proposal.
- Implement local-to-remote upload, conflict resolution, or bidirectional sync.
- Change backend WalkCalc API routes or payload contracts.
- Redesign group, record, settings, or login screens.
- Replace `APIClient` wholesale; the first implementation can wrap it.

## Decisions

1. **Introduce a repository boundary above concrete sources.**
   Add a UI-facing ledger repository that exposes operations in WalkCalc domain terms: load home, load more groups, refresh group, load/search records, load member records, create/update/delete/archive groups, add members, add/update/delete records, and resolve debts.

   Rationale: views and `WalkcalcStore` should not know whether an operation is backed by local storage or remote HTTP. A repository keeps source choice centralized.

   Alternative considered: add `if token == nil` branches to every store method. That would be faster initially but would spread mode-specific behavior across the app and make future sync brittle.

2. **Keep session/account state separate from ledger source mode.**
   Model the app's ledger access as a source mode such as local-only or remote-authenticated, independent from whether an account session exists. The repository should receive the active mode/session context and decide which source can satisfy each operation.

   Rationale: a signed-out user may still have local ledgers. A signed-in user may still keep local-only groups. Login state and ledger availability are related but not equivalent.

   Alternative considered: make `token != nil` the source selector. That would prevent signed-in users from managing unsynced local data and would reintroduce auth coupling.

3. **Use capability-aware operation results.**
   Repository mutations should return structured results that can express success, validation failure, auth-required, source-unavailable, and recoverable network failure. Existing localized messages can continue to be produced at the store/UI boundary.

   Rationale: local and remote operations can fail for different reasons. A single optional message is not enough to guide later login prompts, retry behavior, or sync affordances.

   Alternative considered: keep returning `Bool` plus optional message. That is compatible with current UI but loses important mode information.

4. **Preserve existing remote pagination and search contracts.**
   The remote source should wrap current `APIClient` routes, including server-backed groups, records, structured record search, member records, balances, and settlement suggestions. The repository should expose pagination state without leaking HTTP query details to the UI.

   Rationale: this change is an architectural refactor, not a backend behavior change.

   Alternative considered: redesign pagination around fully loaded collections. That would regress existing server-backed large-list behavior.

5. **Define local IDs and ownership metadata early.**
   Even before local persistence exists, the abstraction should support stable source identity such as local group IDs, local record IDs, remote group codes, and a local owner/member identity.

   Rationale: local ledgers need a current participant for "My balance" and future upload needs a reliable mapping from local IDs to remote IDs.

   Alternative considered: hide IDs until sync work begins. That would make the initial abstraction too vague and likely require another model migration.

## Proposed Shape

The exact Swift names can follow implementation fit, but the layer should separate these roles:

- `LedgerRepository`: UI/store-facing coordinator for ledger operations.
- `LedgerDataSource`: protocol implemented by concrete sources.
- `RemoteLedgerDataSource`: wraps `APIClient` and authenticated session handling.
- `LocalLedgerDataSource`: future local persistence implementation; first implementation may be in-memory/fake for tests.
- `LedgerSessionContext`: describes account session, local owner identity, and active source availability.
- `LedgerOperationResult`: structured operation outcome used by `WalkcalcStore` to preserve current feedback behavior while gaining auth/source metadata.

Expected data flow:

```text
Views / Panels
      |
      v
WalkcalcStore
      |
      v
LedgerRepository
      |
      +--> LocalLedgerDataSource
      |
      +--> RemoteLedgerDataSource -> APIClient
```

## Risks / Trade-offs

- [Risk] Refactoring too much of `WalkcalcStore` at once could regress existing authenticated flows. -> Mitigation: migrate read paths first, then mutations, with fake-source verification and remote regression checks.
- [Risk] A generic repository may hide source-specific UX needs. -> Mitigation: include capability/source metadata in results and loaded group projections rather than pretending all operations are always available.
- [Risk] Local and remote models may diverge later. -> Mitigation: keep domain models shared where possible, but allow source metadata/mapping wrappers outside the core display models.
- [Risk] Settlement logic may require local calculation parity with backend. -> Mitigation: keep repository API for settlement suggestions explicit and verify local/fake behavior before App Review UI changes depend on it.
- [Risk] Existing fixture mode overlaps with local mode. -> Mitigation: treat fixture mode as test/demo data, not the production local source, but reuse its in-memory mutation patterns where useful.
- [Risk] Remote auth refresh failures could be flattened into generic repository failures. -> Mitigation: preserve `APIClientError.kind == .authRefresh` and refreshed-token propagation as first-class remote outcomes, then verify session-expired routing still occurs.
- [Risk] Pagination state could drift when repository response shapes replace direct store updates. -> Mitigation: verify initial page, next page, filtered group search, record pagination, member-record pagination, and totals independently.
- [Risk] Mutation follow-up refreshes could be skipped or duplicated during migration. -> Mitigation: verify create group, add member, add record, edit record, delete record, archive/delete group, and settlement operations update the same home/detail caches as before.
- [Risk] Search behavior could accidentally broaden or narrow when hidden behind the repository. -> Mitigation: verify structured record search still sends note/category OR conditions and local interim matches remain display-only until remote results arrive.

## Verification Strategy

Verification must prove two things separately: the new abstraction has the right behavior, and the existing remote user path has not changed.

1. **Contract-level verification with a fake source.**
   Use an in-memory/fake data source to exercise the repository without network dependency. Cover local-style create group, temporary member management, record create/edit/delete, record search, member-record filtering, balance/settlement entry points, source-unavailable outcomes, and auth-required outcomes for remote-only operations.

2. **Remote source regression verification.**
   With the remote source selected and a valid authenticated session, verify that the repository still calls the existing `APIClient` routes and preserves current response handling for:
   - home summary plus first group page
   - load-more groups
   - group detail plus first records page
   - group balances
   - record pagination
   - structured record search
   - member-specific records
   - create group, invite registered members, add temporary members
   - archive, unarchive, delete, rename group
   - add, edit, delete, and settlement records

3. **Store migration regression verification.**
   After each migrated path, verify `WalkcalcStore` publishes the same state shape as before: `groups`, `recordsByGroup`, `recordTotals`, `groupTotal`, `totalBalanceMinor`, search caches, member-record caches, loading flags, and action feedback messages.

4. **Auth and failure classification verification.**
   Verify missing token for remote-only operations returns auth-required, expired access token can still refresh and retry through the remote source, unrecoverable auth failure still clears session through the existing path, and recoverable transport failures remain quiet/non-auth failures.

5. **Build and debug verification.**
   Keep existing debug verification entry points working and add a repository verification entry point if normal unit tests are not practical in the current project structure.

## Migration Plan

1. Add protocol and result types for unified ledger data access without changing callers.
2. Implement `RemoteLedgerDataSource` as a thin wrapper around current `APIClient` calls.
3. Add an in-memory/fake data source for repository tests and future local behavior validation.
4. Introduce `LedgerRepository` and route a small read path through it while preserving current UI state outputs.
5. Incrementally move group, record, member-record, balance, and settlement operations from direct store/API coupling into repository calls.
6. Keep legacy store methods as compatibility facades until all views call through the same upper-layer store API.
7. Add verification that existing authenticated flows still load, paginate, search, and mutate through the remote source.

Rollback is local to the native app. If the abstraction introduces regressions, callers can temporarily route back to direct `APIClient` calls while keeping the protocol definitions for the next iteration.
