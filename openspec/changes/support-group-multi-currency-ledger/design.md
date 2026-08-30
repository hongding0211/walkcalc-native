## Context

The server stores one scalar participant projection per group participant and the native app mirrors that shape with scalar `debtMinor` and `costMinor` values. Records do not carry currency; every display and calculation inherits `WalkGroup.currencyCode`. Deployed clients therefore depend on existing scalar request/response fields and on record mutations that omit currency.

The group currency is already selected by the client during group creation and persisted by the server. It remains the group's default currency, not the only allowed currency.

## Goals / Non-Goals

**Goals:**

- Preserve a currency code on every new remote and local expense or settlement record.
- Keep balances, statistics, suggestions, settlements, and transfers independent per currency.
- Add currency-aware data without removing or changing the type of any deployed API field.
- Let old records, old projection documents, and old SwiftData stores remain readable without a mandatory destructive migration.
- Keep remote and local ledger sources aligned behind the same repository contract.

**Non-Goals:**

- Exchange-rate conversion, base-currency valuation, or foreign-exchange gain/loss tracking.
- Currency-change push notifications.
- Removing or redefining legacy scalar totals such as `totalBalance`.
- Supporting currency-specific fractional scales; existing two-decimal money semantics remain unchanged.

## Decisions

### Keep group currency as an existing client-selected default

`WalkcalcGroup.currencyCode` and `WalkGroup.currencyCode` remain unchanged. Old create-record requests that omit currency inherit the group's current default. New clients send a record currency explicitly. Changing the group currency changes only the default for later omitted/new records; records that already have a currency retain it.

This is preferred over adding a second group default field because the existing field already has the desired creation and settings behavior.

### Add record currency as an optional wire/storage field

The server and SwiftData record schemas add optional `currencyCode`. API responses always expose an effective normalized currency. Historical records with no stored value resolve to the group currency. Before a group default changes locally or remotely, missing historical record currencies are materialized to the previous default so the change cannot relabel history.

Optional storage is preferred over a required migration because it keeps old documents and old SwiftData stores readable during rollout.

### Extend each participant projection with additive currency buckets

The existing projection document and scalar fields remain authoritative for legacy clients. An additive `currencyBalances` array stores the same projection statistics per ISO currency:

```text
participant projection
├── balanceValue / expenseShareValue / ...       legacy aggregate
└── currencyBalances[]
    ├── CNY: balance / expenseShare / ...
    └── USD: balance / expenseShare / ...
```

Every mutation applies a delta to both the legacy scalar fields and exactly one normalized currency bucket. When an old projection has no buckets, the server/native source bootstraps one bucket from the scalar values using the group's current default before applying the next mutation. Rebuild logic derives both shapes from records.

This nested additive shape avoids changing the existing projection collection's uniqueness and keeps reads/writes local to one participant document. A separate per-currency projection collection was considered but rejected because it requires coordinated backfill before correct reads and complicates rollback.

### Add currency-aware response fields and retain legacy fields

- Records add `currencyCode`.
- Participant projection DTOs add `currencyBalances` while retaining scalar fields.
- Group summaries add `currentUserCurrencyBalances` while retaining scalar summaries.
- Home summary keeps `totalBalance` and uses the existing `balances` array for correct per-currency totals.
- Settlement responses add `currencyCode`; the existing route and `transfers` shape remain.

Unknown additive fields are ignored by old decoders, while new clients use the currency-aware fields.

### Settle one currency per request

Settlement suggestion and resolve routes accept an optional `currencyCode`. Omission falls back to the group default, preserving old client requests. Suggestions, generated transfers, and settlement records operate only on that currency bucket. New clients call the same route separately for each currency. Internal group dismissal may iterate all non-zero currencies to resolve every bucket.

This is preferred over returning or resolving all currencies in one operation because the product model requires independent settlement and transfer workflows.

### Reuse the currency picker and cache record currency per group

The amount currency symbol in the expense editor is an explicit navigation control to the existing searchable currency picker. A new draft first uses the most recently selected record currency cached locally for that group; when no preference exists, it uses the group's default currency. Editing an existing record always starts from that record's currency.

The preference is intentionally per group: the group default remains the first selection for a group, while using USD in one group does not unexpectedly change the next draft in another group. Changing `Default currency` does not overwrite an existing preference or an open draft.

### Present balances and settlements using their own currencies

The group summary card uses the same per-currency carousel behavior as the home summary card. Balance rows avoid the legacy mixed scalar whenever currency buckets are available. Settlement suggestions are requested for every currency bucket, merged only for presentation, and sorted by the absolute numeric amount without exchange-rate conversion. Each rendered row and resolve action retains its own currency code.

### Preserve legacy aggregates mechanically

Legacy scalar projections and `totalBalance` continue to sum numeric minor values across all records exactly as compatibility fields. They are not used by the new multi-currency UI or settlement logic. This preserves wire behavior without pretending the aggregate has exchange-rate meaning.

## Risks / Trade-offs

- **Old clients cannot present foreign-currency buckets** → They continue to operate on the group default currency and cannot corrupt other currency buckets; new fields remain additive.
- **Legacy scalar aggregates are financially meaningless for mixed currencies** → Keep them only for compatibility and ensure all new calculations use currency buckets.
- **Old records have no immutable currency** → Resolve them to the persisted group default and materialize that currency before changing the default or rebuilding data.
- **Dual projection updates can diverge** → Apply both updates in the same existing transaction/compensation path and extend rebuild verification.
- **SwiftData schema evolution may encounter missing values** → New persisted properties are optional and domain mapping supplies group-default fallbacks.

## Migration Plan

1. Deploy additive server schema/DTO support that reads absent currency fields and absent currency buckets.
2. Rebuild or lazily bootstrap currency buckets from existing scalar projections and group defaults; new mutations dual-write both shapes.
3. Release the native client with additive domain/network/SwiftData fields and fallback decoding.
4. Enable record-currency selection, per-currency group cards, and independent settlement presentation after model verification.

Rollback keeps all old scalar fields populated, so the previous server/client can ignore additive fields. Records written with explicit non-default currencies remain readable as numeric legacy records after rollback, although the old UI cannot distinguish their currency.

## Open Questions

None.
