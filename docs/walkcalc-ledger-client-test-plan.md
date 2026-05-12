# WalkCalc Ledger Client Test Plan

Date: 2026-05-12
Scope: native iOS client only. Backend endpoint tests are excluded.

## Gates

- Build: `xcodebuild -scheme walkcalc-native -project walkcalc-native.xcodeproj -configuration Debug -destination 'generic/platform=iOS Simulator' build`
- Simulator E2E: run against the migrated backend with a clean test account set and capture request logs for every assertion below.
- UI regression: compare screenshots against the existing UI for home, group detail, record editor, search canvas, balances, member detail, settings, archive, login.

## API Contract Coverage

- Auth: boot with no token shows login; valid token calls `/walkcalc/users/me`; expired token refreshes and retries.
- Home: calls `/walkcalc/home/summary`; total balance must match backend `totalBalance`, including archived and unloaded groups.
- Groups: calls `/walkcalc/groups/my?page=&pageSize=&search=`; pagination appends without losing loaded detail participants.
- Group detail: calls `/walkcalc/groups/:code`; participants use `participantId`, `kind`, `profile` or `tempName`, `balance`, `expenseShare`, `recordCount`.
- Balances workspace: calls `/walkcalc/groups/:code/balances` when opened; participant rows must use backend projection `balance`, `expenseShare`, and `recordCount` instead of deriving from loaded record pages.
- Records: calls `/walkcalc/groups/:code/records`; maps expense `amount/payerId/participantIds/category/note` and settlement `amount/fromId/toId`.
- Member detail: calls `/walkcalc/groups/:code/balances/:participantId/records`; verifies participant projection, filtered totals, record count, balance text, and pagination.
- Settlement: calls `/walkcalc/groups/:code/settlement-suggestion` on balances, and `/walkcalc/groups/:code/settlements/resolve` for resolve all.
- Mutations: add/update sends decimal string `amount`, not minor units; delete uses `/walkcalc/records/drop`.

## Simulator Click Matrix

- Login: open app, tap Login, complete SSO callback, verify home appears.
- Home add menu: tap plus, create group, cancel create, join group, cancel join, invalid empty join disabled, valid join submits.
- Home group list: pull to refresh, scroll to pagination, tap group row, long press row, archive, delete confirmation cancel and confirm.
- Settings: open ellipsis menu, archived groups, unarchive, edit profile, logout confirmation cancel and confirm.
- Group detail: pull to refresh, tap group settings, tap search, tap add expense, tap balance preview, tap view all balances, scroll record pagination.
- Record editor: amount field, paid-by selector, split selector, category selector, date picker, note field, cancel, save disabled states, save success, edit existing record, delete record cancel and confirm.
- Search canvas: focus search, type note query, clear query, search category alias, no-result state, tap result to editor, scroll search pagination.
- Balances workspace: open all balances, tap member detail, scroll member records, return, resolve confirmation cancel, resolve confirmation confirm.
- Member detail: verify balance text, record count, empty records, record row opens editor, member-record pagination.
- Error notices: duplicate join, archive unsettled group, invalid record mutation, settlement limit exceeded.

## UI Point Coverage

Every row below must be checked in simulator screenshots and click logs. UI appearance is regression-only; backend assertions are limited to the client-observed API requests/responses and visible state.

### Login And Bootstrap

- Bootstrapping: launch with stored token and verify the initial progress surface clears into home.
- Logged-out state: clear token, verify Login screen, app icon, title, Login button, SSO sheet presentation, cancel/dismiss, successful callback.
- Auth refresh: expire access token, verify `/auth/refreshToken` retry updates stored token and the original request completes.
- Auth failure: invalid refresh must clear user state and return to login without retaining stale groups or records.

### Home

- Total balance card: verify amount equals `/walkcalc/home/summary.totalBalance`, including archived and unloaded groups.
- Scope label: verify group count uses backend pagination total when available and remains stable after loading more pages.
- Active group row: verify title, avatar stack from `participantPreview`, member count from `participantCount`, current-user balance, positive/negative/zero colors, chevron, tap navigation.
- Empty state: verify create and join actions from the empty state open the same flows as toolbar controls.
- Pull refresh: verify home summary and first page refresh together.
- Pagination: verify final partial page, no duplicate rows, and archived rows stay hidden from active list.
- Context menu: long press row, archive cancel/confirm, delete cancel/confirm.
- Deep link: open `walkingcalc://group/<code>` and verify navigation to the matching group.

### Home Menus And Settings

- Plus menu: create group, cancel create, join group, cancel join, disabled empty join, uppercase conversion, valid join.
- Ellipsis menu: archived groups and settings are reachable.
- Archived groups sheet: empty state, restore button, restore context menu, restore swipe action, delete context menu, delete swipe action, delete alert cancel/confirm.
- Settings sheet: account row, edit profile sheet, archived groups navigation, logout alert cancel/confirm, close button, done button.

### Create And People Setup

- Create group: name field, disabled create for empty name, member avatar stack, add formal member search, select/deselect user, empty user search result, add temporary member alert, disabled empty temporary add, duplicate local temporary name ignored, cancel, create success.
- Group settings: rename field, group id text selection, member avatar stack, add formal member, add temporary member, archive alert cancel/confirm, delete alert cancel/confirm, done without changes.
- People setup sheet: add formal member, add temporary member, cancel, successful add closes only where current flow expects it.

### Group Detail

- Header summary: current-user balance uses backend summary/projection and updates after every mutation.
- Balance preview: first three rows, record counts, positive/negative/zero colors, view all button, member row tap opens balances with selected member.
- Expense list: newest-first order, row category icon/title, payer name, amount, timestamp, edit on row tap, pagination load footer.
- Bottom search/add bar: search field opens search canvas, add expense opens editor.
- Pull refresh: refreshes group detail and first records page without changing navigation stack.

### Record Editor

- Create mode: empty amount, positive amount, zero/negative/malformed amount disabled, payer selector, split selector, category selector, date picker, note field, cancel, save success.
- Edit expense mode: prefilled amount/payer/split/category/date/note, amount update, payer change, split change, category change, occurred-at date change without record reordering, note update, save, delete cancel/confirm.
- Edit settlement mode: prefilled from/to/amount/date/note, date change remains supported, save sends settlement update shape.
- Location fields: when empty, `long` and `lat` are omitted; when populated by existing data, row display and edit persistence remain intact.

### Search Canvas

- Initial state: search field focus and normal list behavior before remote result arrives.
- Query cases: note match, category alias match, mixed Chinese/English category query, unsupported field never sent, no-result state, clear query.
- Pagination: search page 2 appends without duplicates; local visible matches merge with remote results.
- Result action: tapping a result opens the existing record editor and returns to search after cancel/save.

### Balances And Member Detail

- Balances root: opening sheet calls `/walkcalc/groups/:code/balances`; rows use backend `balance`, `expenseShare`, and `recordCount`; all participants are shown.
- Settlement suggestion: opening balances calls `/walkcalc/groups/:code/settlement-suggestion`; plan rows match backend transfers exactly.
- Resolve all: confirmation cancel does nothing; confirm calls `/walkcalc/groups/:code/settlements/resolve` with no trusted client transfer plan and refreshes group/home.
- Settlement limit: `walkcalc.settlementLimitExceeded` shows the existing notice flow and includes backend-provided `nonZeroParticipantCount/limit` detail when present.
- Member detail: opening a member calls `/walkcalc/groups/:code/balances/:participantId/records`; projection updates member balance and record count; records are filtered and paginated.
- Member record row: tapping opens editor; returning preserves balances navigation.

## Money And Ledger Assertions

Use backend-created users A, B, C and temporary member T. All displayed values are client assertions after each refresh, not backend unit tests.

- Add expense `100.00`, payer A, split A/B/T. Expected balances: A `+66.66`, B `-33.33`, T `-33.33`; sum `0.00`; record amount displays `¥100.00`.
- Add expense `10.00`, payer B, split A/B/C. Expected exact split totals sum to `10.00`; total group balances remain zero-sum after rounding.
- Update the second expense payer from B to C while keeping amount and split unchanged. Expected paid totals move from B to C, all participant balances recalculate, recordId stays stable, and home total balance matches each registered user's group balance.
- Update the second expense split from A/B/C to A/C while keeping payer C and amount unchanged. Expected B is removed from that record's projection, shares recalculate to A/C only, all participant balances remain zero-sum, and home total balance follows the new projection.
- Restore the second expense to payer B split A/B/C before continuing later mutation steps, proving update rollback behavior is exact.
- Update first expense from `100.00` to `120.00`, payer B, split B/T. Expected old projection is reversed before new projection applies; no stale A balance remains from the edited record.
- Delete the updated record. Expected balances equal the state before that record was created; record disappears from normal list and member detail lists.
- Add settlement `C -> B 3.33` through a single-settlement path if exposed; expected C balance increases to `0.00`, B decreases to `3.34`, and expenseShare/paidTotal remain unchanged. If no single-settlement entry is currently reachable, verify the same settlement semantics on records created by resolve.
- Resolve all through balances. Expected client calls backend resolve endpoint without sending trusted client balances; after refresh every participant balance is `0.00`.
- Verify settlement records count toward `recordCount`, but do not change `expenseShare` or `paidTotal`.
- Home total balance must equal the backend summary after every add, payer edit, split edit, amount edit, delete, archive, unarchive, and resolve.

### Ledger Calculation Table

For each step, verify both visible UI amounts and backend projection values surfaced through client API responses. All balance columns must sum to `0.00`. The table assumes backend split remainder is assigned in `participantIds` order, matching the documented `100.00` split example where the first participant receives `33.34`.

| Step | Operation | A balance / share / paid / count | B balance / share / paid / count | C balance / share / paid / count | T balance / share / paid / count |
| --- | --- | --- | --- | --- | --- |
| 1 | Expense `100.00`, payer A, split A/B/T | `66.66 / 33.34 / 100.00 / 1` | `-33.33 / 33.33 / 0.00 / 1` | `0.00 / 0.00 / 0.00 / 0` | `-33.33 / 33.33 / 0.00 / 1` |
| 2 | Expense `10.00`, payer B, split A/B/C | `63.32 / 36.68 / 100.00 / 2` | `-26.66 / 36.66 / 10.00 / 2` | `-3.33 / 3.33 / 0.00 / 1` | `-33.33 / 33.33 / 0.00 / 1` |
| 3 | Update step 2 payer B -> C, keep split A/B/C | `63.32 / 36.68 / 100.00 / 2` | `-36.66 / 36.66 / 0.00 / 2` | `6.67 / 3.33 / 10.00 / 1` | `-33.33 / 33.33 / 0.00 / 1` |
| 4 | Update step 2 split A/B/C -> A/C, keep payer C | `61.66 / 38.34 / 100.00 / 2` | `-33.33 / 33.33 / 0.00 / 1` | `5.00 / 5.00 / 10.00 / 1` | `-33.33 / 33.33 / 0.00 / 1` |
| 5 | Restore step 2 to payer B, split A/B/C | `63.32 / 36.68 / 100.00 / 2` | `-26.66 / 36.66 / 10.00 / 2` | `-3.33 / 3.33 / 0.00 / 1` | `-33.33 / 33.33 / 0.00 / 1` |
| 6 | Update step 1 to `120.00`, payer B, split B/T | `-3.34 / 3.34 / 0.00 / 1` | `66.67 / 63.33 / 130.00 / 2` | `-3.33 / 3.33 / 0.00 / 1` | `-60.00 / 60.00 / 0.00 / 1` |
| 7 | Delete updated step 1 | `-3.34 / 3.34 / 0.00 / 1` | `6.67 / 3.33 / 10.00 / 1` | `-3.33 / 3.33 / 0.00 / 1` | `0.00 / 0.00 / 0.00 / 0` |
| 8 | Settlement C -> B `3.33` | `-3.34 / 3.34 / 0.00 / 1` | `3.34 / 3.33 / 10.00 / 2` | `0.00 / 3.33 / 0.00 / 2` | `0.00 / 0.00 / 0.00 / 0` |
| 9 | Resolve all | `0.00 / 3.34 / 0.00 / 2` | `0.00 / 3.33 / 10.00 / 3` | `0.00 / 3.33 / 0.00 / 2` | `0.00 / 0.00 / 0.00 / 0` |

In step 9, the table assumes the prior single settlement in step 8 has already cleared C, so resolve-all creates only A -> B `3.34`. Every created settlement must only affect `balance`, `settlementIn`, `settlementOut`, and `recordCount`; it must not change `expenseShare` or `paidTotal`.

### Local Dev E2E Evidence

Executed against `http://127.0.0.1:3500` on 2026-05-12 using newly registered local users.

Passing run after backend update fix:

- `stamp`: `20260512085322`
- `groupCode`: `IO1H`
- users: A `80dd7df4-4ca1-4c24-8145-dc44aadd0500`, B `442d1104-9130-4818-bbbd-9f99aff09f4b`, C `a1572148-0267-4921-b477-6b0e09e7dad6`
- records: updated then deleted expense `1d8315fa-62d4-4391-9f09-deb1c938d3c6`, kept expense `ad6d2b31-c6fa-4bc2-b702-1d913aa5262f`, manual settlement `510e82f0-5f28-4478-a587-a460235c9dc1`
- verified: account registration/login, create/join group, temp participant, group detail, balances, home summary, expense add, unsettled archive rejection, structured duplicate participant rejection, zero amount rejection, expense update with recordId preserved, exact post-update A/B/C/T projection, participant detail, search, drop updated record with exact rollback projection, manual settlement, settlement suggestion, backend resolve ignoring bogus client transfers, final zero balances, final home summaries, settled archive, `/groups/my` `participantCount=4`, formal user preview profile, and temporary user preview name.

## Boundary Cases

- Amount input rejects empty, `0`, `0.00`, negative values, more than two decimals, leading-zero malformed values, and non-numeric text.
- Amount input accepts `0.01`, `1`, `1.2`, `1.23`, and large values within client display limits.
- Split requires at least one participant; payer may be outside split for expense if backend allows it.
- Temporary user names: empty rejected by UI; duplicate name returns backend error and preserves UI state.
- Invite: empty search result, already joined user skipped, unknown user ignored by backend.
- Archive: unsettled group shows error and remains visible; settled group archives for current user; unarchive restores it.
- Search: note match, category alias match, mixed Chinese/English category query, no match, unsupported fields never sent by native client.
- Pagination: empty first page, final partial page, duplicate records across pages are not duplicated in UI.
- Offline/network error: mutation failure keeps editor open and shows existing notice/error text.

## Regression Checks

- UI style must not change: colors, card surfaces, typography scale, toolbar icons, sheet detents, row heights, and form layout remain as before.
- Interaction routes must not change: existing buttons, sheets, alerts, search entry, navigation destinations, and context menus remain reachable in the same order.
- No old backend compatibility is required: `paidMinor`, `debtMinor`, `costMinor`, and `isDebtResolve` are internal client names only and are not sent as new backend contract fields.
