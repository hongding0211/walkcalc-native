## Context

The group-detail Balances card currently renders `group.allMembers.prefix(3)` in model order and does not request settlement suggestions until the balances workspace opens. The workspace already has the complete settlement plan and member list, but renders All balances before Suggested settlement. Local and remote sources expose the same `SettlementTransfer` shape through `WalkcalcStore`.

## Goals / Non-Goals

**Goals:**

- Make directly relevant settlement guidance the first balance information shown on group detail.
- Preserve the existing member-preview behavior when the current user has no suggested transfer.
- Keep settlement mutation controls inside the balances workspace.
- Make member-balance ordering deterministic and magnitude-first in both preview and workspace.
- Keep local and remote behavior identical.

**Non-Goals:**

- Changing settlement calculation, backend contracts, or resolve semantics.
- Adding a resolve action to group detail.
- Changing member detail, record navigation, or sheet presentation.

## Decisions

### Resolve current-participant identity through the store

The store will expose the participant identity appropriate for a group: the authenticated user UUID for a remote group and the persisted local-owner UUID for a local group. Views will not infer identity from ownership alone because a remote participant need not own the group.

### Derive personal transfers from the existing settlement plan

The preview will filter `resolvedDebts(for:)` where either `from.uuid` or `to.uuid` matches the current participant. It will preserve the authoritative/fallback plan order and render every matching transfer. No new endpoint or settlement algorithm is introduced.

### Keep the main-page transfer preview informational

Personal transfer rows on group detail will have no button, disclosure indicator, or resolve affordance. The card footer remains the single `View details` entry into the balances workspace. This prevents a destructive accounting action from being triggered from a compact preview.

The prioritized section uses the `Suggested settlement` heading and preserves the group-detail card's original grouped-list container, dividers, and integrated `View details` footer. Within each row it mirrors the workspace transfer hierarchy (payer, transfer direction, receiver, and amount) so the same settlement reads consistently in both places. Action-only details such as `Tap to resolve` and the disclosure chevron remain exclusive to the workspace.

Amounts are presented from the current participant's perspective. A transfer paid by the current participant is red and prefixed with `-`; a transfer received by the current participant is green with no `+` prefix.

### Use a stable absolute-balance order

Fallback member previews and workspace All balances will sort by descending absolute `debtMinor`. Equal magnitudes retain original participant order, avoiding sign-based preference and unnecessary row movement.

### Refresh balance projections on group detail

Group detail will request the existing group-balance projection and settlement suggestion so the preview uses authoritative remote data when available. Existing local repository calls provide the same data without special UI branching. Until refresh completes, the current group projection and deterministic fallback plan remain usable.

### Reorder workspace content without changing actions

The balances workspace will render errors first, Suggested settlement second, and All balances third. Existing single-transfer confirmation, member navigation, and Resolve all behavior remain unchanged.

## Risks / Trade-offs

- [Many personal transfers can make the main page card tall] → This is intentional because the requirement explicitly removes the preview cap for personally relevant transfers.
- [Remote suggestions can update after the initial render] → Use cached/fallback data immediately and replace it with the existing authoritative response without a blocking spinner.
- [Extra group-detail requests increase network work] → Reuse the existing balance and suggestion endpoints, keep failures silent, and refresh alongside the existing group-detail lifecycle.
- [A missing current-participant identity prevents personal filtering] → Fall back to the existing member preview instead of guessing identity.
