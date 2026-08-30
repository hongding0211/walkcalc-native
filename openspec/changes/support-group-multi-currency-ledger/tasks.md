## 1. Backend additive data contract

- [x] 1.1 Add optional record currency and nested participant currency-projection schema fields without removing legacy fields
- [x] 1.2 Add request/response DTO fields for record currency, participant currency balances, group-summary currency balances, and settlement currency
- [x] 1.3 Resolve omitted/historical record currency from the group default and preserve historical currency when that default changes

## 2. Backend currency-aware ledger behavior

- [x] 2.1 Dual-write legacy scalar projections and the affected currency bucket for create, update, delete, rebuild, and compensation paths
- [x] 2.2 Calculate home/group balances, unresolved checks, member removal, and archive eligibility across independent currency buckets
- [x] 2.3 Calculate and resolve settlement suggestions for one requested/default currency at a time and create currency-denominated transfers
- [x] 2.4 Add backend regression tests for old requests/documents, mixed-currency projections, and independent settlement

## 3. Native additive models and remote mapping

- [x] 3.1 Add record currency, member currency balances, and currency settlement metadata to domain shapes with legacy defaults
- [x] 3.2 Extend API request/response mapping and repository/source contracts with optional currency inputs
- [x] 3.3 Preserve existing store and call-site compilation while allowing upgraded callers to consume currency-specific data

## 4. Native local-source parity

- [x] 4.1 Add optional SwiftData record currency and participant currency-projection persistence compatible with existing stores
- [x] 4.2 Update SwiftData and in-memory record mutations, projection rebuilds, balances, and settlement calculations to operate per currency
- [x] 4.3 Materialize historical local record currencies before changing the group default
- [x] 4.4 Extend local and remote verification coverage for legacy fallback and independent multi-currency settlement

## 5. Verification

- [x] 5.1 Run focused backend WalkCalc tests and build/type checks
- [x] 5.2 Run native project build and ledger verification checks without starting frontend or backend services
- [x] 5.3 Validate the OpenSpec change and review both worktrees for unintended changes

## 6. Native multi-currency interaction

- [x] 6.1 Reuse the currency picker from the amount symbol and persist the last selected record currency per group with group-default fallback
- [x] 6.2 Pass the selected currency through create/edit record mutations and label the group setting as Default currency without resetting draft preference
- [x] 6.3 Align the group summary card and balance rows with the home card's currency-aware presentation
- [x] 6.4 Fetch, merge, sort, display, and resolve settlement suggestions independently by currency
- [x] 6.5 Add client verification coverage and run native build, simulator checks, and strict OpenSpec validation
