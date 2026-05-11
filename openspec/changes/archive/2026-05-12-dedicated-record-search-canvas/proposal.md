## Why

Record search currently behaves like an inline filter inside group detail, which keeps the full ledger surface visible while the user is trying to search. iOS search patterns work better here as a dedicated, lightweight search canvas that gives the query and results their own focused context without turning search into a heavyweight navigation destination.

## What Changes

- Replace the current in-place group detail record search behavior with a dedicated record search canvas opened from the group detail search control.
- Present the record search canvas without using a `NavigationLink`/navigation push; it should feel transient and focused, while still giving results enough room.
- Keep the group detail page itself stable while searching; summary, balances, and normal expense sections should not be repurposed as search results.
- Add a structured record search contract so the client can explicitly pass which fields and operator the backend should use.
- Make the first native record search request an OR match across record notes and localized category names.
- Do not request payer, participants, amount, raw category id, dates, location, or other metadata from the native record search canvas.
- Preserve existing server-backed pagination and local loaded-record fallback, but align both fallback and backend matching to the same note/category-name rule.

## Capabilities

### New Capabilities
- `dedicated-record-search-canvas`: Covers the native group record search presentation, transient canvas behavior, focused search state, and result selection flow.

### Modified Capabilities
- `walkcalc-server-backed-collection-access`: Add structured record search conditions while preserving paginated server-backed record loading.

## Impact

- Affected native surfaces: `GroupView`, record list/search presentation components, localization strings, and design playground previews if they model group detail search.
- Affected native state: `WalkcalcStore` record search cache, local fallback matching, search debouncing, and result pagination.
- Affected API contract: `GET /walkcalc/groups/:code/records` must accept structured search conditions, apply them before pagination, and let the native record search canvas request note/category-name OR matching explicitly.
- No new third-party dependencies are expected.
