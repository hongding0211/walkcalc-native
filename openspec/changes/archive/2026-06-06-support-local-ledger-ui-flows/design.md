## Context

The prior two changes established the required lower layers:

- `introduce-ledger-data-layer` added `LedgerRepository`, `LedgerDataSource`, `LedgerSourceKind`, `LedgerSessionContext`, source metadata, and structured operation outcomes.
- `implement-swiftdata-local-ledger-source` added `SwiftDataLedgerDataSource.production()` and persisted local support for groups, temporary members, records, balances, search, settlement suggestions, archive/delete/rename, and account-required local failures.

The remaining gap is orchestration. `WalkcalcStore` currently constructs a repository with both remote and local sources, but most production store methods still call the repository with `remoteLedgerContext()`. The existing views are already close to source-agnostic because they call store methods such as `createGroupWithFeedback`, `refreshGroup`, `addMembersWithFeedback`, `addRecordWithFeedback`, and `deleteRecordWithFeedback`.

This change should avoid building a parallel "local mode UI". The UI should mostly continue to call the same store methods, while the store chooses local or remote based on group/source context and operation capability.

## Goals / Non-Goals

**Goals:**

- Make existing group and record UI flows work against persisted local SwiftData ledgers.
- Keep local and remote CRUD behavior aligned at the UI level: create, rename, archive, unarchive, delete, add temporary members, add/edit/delete records, search, balances, and settlement flows.
- Keep source-specific decisions in `WalkcalcStore` and repository context construction, not in individual panels where avoidable.
- Add enough source awareness for capability gating and user clarity without turning the app into two separate modes.
- Let unauthenticated startup enter the existing Groups home in local mode.

**Non-Goals:**

- Implement upload/merge/sync from local data to an account.
- Implement joining remote shared groups while signed out.
- Implement registered-user search or real-account invitation for local-only groups.
- Redesign the home, group detail, group settings, or record editor visual system.

## Decisions

1. **Use source metadata, not a separate view tree.**
   Existing views should render `WalkGroup`, `Member`, and `WalkRecord` regardless of source. Source metadata should be tracked in the store so operations can choose `LedgerSessionContext.local(owner:)` or `LedgerSessionContext.remote(accessToken:)`.

   Rationale: the lower layers already hide SwiftData models. Duplicating `CreateLocalGroupSheet`, `LocalGroupView`, or `LocalRecordEditor` would create drift and make future sync harder.

2. **Add a stable local owner identity at the store boundary.**
   `WalkcalcStore` should provide a local owner member such as `local-user-device` with display name `Me`, persisted or derived consistently, for all local contexts.

   Rationale: local balances need a current participant for "My balance", archive state, and ownership checks. The SwiftData source can default this today, but the UI/store should own the user-facing identity.

3. **Select source by group identity for group-scoped operations.**
   Home-level create can use the active ledger mode. Group-scoped operations should inspect known group source metadata or ID prefix and use the matching context.

   Rationale: once remote and local groups can coexist, a signed-in user may still mutate a local group locally. `token != nil` cannot be the only selector.

4. **Keep remote-only actions explicit.**
   `Join group`, registered `Add member`, registered-user search, and real-account invite should remain remote-only and require authentication. `Add temporary member` should work locally.

   Rationale: these operations depend on account identity or backend lookup. Fabricating local registered users would confuse later upload/merge semantics.

5. **Prefer minimal UI source indicators.**
   Local-backed data can show a quiet `On this device` label in settings or row detail where useful, but common ledger screens should not constantly ask the user to choose local versus online.

   Rationale: the user task is splitting expenses, not managing storage modes. Capability differences should appear only at decision points.

6. **Route unauthenticated startup to local home.**
   When no account token is available, startup should select the local ledger source and present the existing Groups home instead of the login screen. Authenticated startup should continue to select the remote source and preserve current account-backed behavior.

   Rationale: local ledger support is now complete enough to be the signed-out first-run experience, and this avoids blocking account-independent expense splitting behind authentication.

## Proposed Shape

Add store-level state and helpers along these lines:

```text
WalkcalcStore
  - localOwner: Member
  - groupSourceById: [String: LedgerSourceMetadata]
  - activeLedgerSource / preferredCreateSource
  - localLedgerContext() -> LedgerSessionContext
  - context(for groupId) -> LedgerSessionContext
  - sourceMetadata(for groupId) -> LedgerSourceMetadata?
```

Expected data flow for local creation:

```text
CreateGroupSheet
      |
      v
WalkcalcStore.createGroupWithFeedback(...)
      |
      v
LedgerRepository.createGroup(context: localLedgerContext())
      |
      v
SwiftDataLedgerDataSource
      |
      v
WalkcalcStore refreshes local home/group state
```

Expected data flow for local record editing:

```text
RecordEditorView
      |
      v
WalkcalcStore.add/edit/deleteRecord(groupId)
      |
      v
context(for: groupId) == local
      |
      v
LedgerRepository -> SwiftDataLedgerDataSource
      |
      v
refreshGroup(groupId), refreshHome(), clear search/member caches
```

Remote-only capability gating:

```text
Join group by code      -> remote context, auth required if no token
Search registered users -> remote context, auth required if no token
Invite registered users -> remote context, auth required if no token
Add temporary member    -> source for group, local allowed
```

## UX Notes

- `GroupsEmptyState` can continue to present `Create group` and `Join group`.
- `Create group` should create a local group when the active/preferred source is local, while keeping the same sheet.
- `Join group` should remain remote-only. If unauthenticated, show existing login-required feedback or a login prompt entry point, not a local fallback.
- In group settings, local groups should support rename, archive/unarchive, and delete using the same controls.
- Registered member search on local groups should either be hidden, disabled with sign-in-required messaging, or route to login. Temporary member creation remains available.
- Record editor, record search, balances, and settlement sheets should not need special local copies.

## Risks / Trade-offs

- [Risk] Source selection by ID prefix can become brittle. -> Mitigation: record `LedgerSourceMetadata` when home/group data is loaded and only use ID prefix as a fallback.
- [Risk] Local and remote groups shown together could confuse archive totals and home balance. -> Mitigation: keep local and remote snapshots explicit and verify totals/source caches separately.
- [Risk] Mutations may refresh the wrong source after a write. -> Mitigation: route follow-up `refreshHome` and `refreshGroup` through the same source context used for the mutation.
- [Risk] Existing sheets may expose registered-user search for local groups. -> Mitigation: add capability checks at the store boundary and hide/disable remote-only rows in the people flows where needed.
- [Risk] Signed-out users may still see remote-only entry points such as join-by-code. -> Mitigation: keep join and registered invite/search gated or disabled when no account token is available, while leaving local create and temporary-member flows available.
- [Risk] Current store caches are keyed only by group ID. -> Mitigation: local IDs use `local-` prefixes, and source metadata should be tracked to avoid collisions with remote group codes.

## Verification Strategy

1. **Store/source selection verification.**
   Verify local create group, local home refresh, local group refresh, local add temporary member, local record add/edit/delete, local search, local balances, local archive/delete, and local settlement all call the local source and publish expected state.

2. **UI-flow verification.**
   Exercise the existing `CreateGroupSheet`, group detail, group settings, people setup, record editor, record search canvas, and settlement panels against a local group. The verification can be debug-driven if full UI automation is not practical.

3. **Capability-gating verification.**
   Verify join group, registered-user search, and registered invite return authentication-required/source-appropriate feedback when unauthenticated, while temporary-member flows remain available.

4. **Remote regression verification.**
   Build the app and verify authenticated remote paths still call remote contexts and preserve current behavior for home, group detail, record CRUD, member records, and settlement.

5. **Persistence smoke verification.**
   Create local data through store/UI-facing methods, recreate the store/source if practical, and confirm SwiftData-backed data reappears through home and group reads.

## Migration Plan

1. Add store helpers for local owner identity, source metadata tracking, and local/group-specific context construction.
2. Route home-level local operations through local context where the active UI source is local.
3. Capture source metadata from repository responses when groups and group details load.
4. Update group-scoped store methods to use `context(for: groupId)` instead of always using `remoteLedgerContext()`.
5. Adjust create group and add temporary member flows so they can create/mutate local data through the existing sheets.
6. Gate remote-only people/join/search actions cleanly in existing UI surfaces.
7. Add debug verification for local UI/store flows.
8. Build the native app and run existing ledger verifications.

Rollback is local to the native app. If local UI routing regresses remote behavior, source selection can be temporarily forced back to remote while leaving SwiftData and repository layers intact.
