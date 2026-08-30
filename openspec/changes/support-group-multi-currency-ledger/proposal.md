## Why

WalkCalc currently treats every record and participant projection in a group as if it shares the group's single currency. A group must support records, balances, settlements, and transfers in multiple independent currencies without converting or combining them, while remaining compatible with deployed clients that only understand the existing scalar fields.

## What Changes

- Add an optional per-record currency field; omitted values continue to inherit the group's client-selected default currency.
- Maintain participant balances and statistics independently for each currency and calculate settlement transfers independently per currency.
- Add multi-currency response fields while preserving existing request fields, response fields, routes, and legacy scalar totals.
- Adapt the native domain, networking, repository, in-memory, and SwiftData models so local and remote ledgers preserve record currency and currency-specific projections.
- Backfill or lazily interpret historical records and projections using their group's persisted currency, with no exchange-rate conversion.
- Keep group currency mutation as a change to the default for future records; historical record currencies remain unchanged.
- Add record currency selection by making the amount currency icon open the shared currency picker, seeded from a per-group locally cached last selection or the group default.
- Align the group summary balance card with the home balance card's per-currency presentation and render settlement suggestions as independent currency-denominated rows.
- Rename the group setting to `Default currency`; changing it does not replace an open draft's currency or a group's cached last record currency.
- Leave cross-device currency-change push behavior outside this change.

## Capabilities

### New Capabilities

- `group-multi-currency-ledger`: Defines additive multi-currency record, projection, balance, settlement, migration, and compatibility behavior across the server and native client.

### Modified Capabilities

- `unified-ledger-data-access`: Repository-facing record, balance, and settlement shapes gain additive currency-aware data while preserving legacy call compatibility.
- `swiftdata-local-ledger-source`: Persisted local records and derived balances become currency-aware and remain readable after model evolution.

## Impact

- Backend: WalkCalc record/projection schemas, DTOs, service calculations, settlement responses, indexes, migration compatibility, and tests in `/Users/hong/Projects/hong97-ltd-next`.
- Native: domain models, API mapping, ledger protocols/data layer, remote source, in-memory source, SwiftData models/source, store state, record editor, balance cards, settlement presentation, settings copy, and verification coverage in `/Users/hong/Projects/walkcalc-native`.
- API compatibility: existing fields such as group `currencyCode`, participant scalar balances, settlement `transfers`, and home `totalBalance` remain present; new clients consume additive currency-aware fields.
- No exchange-rate dependency is introduced.
