## MODIFIED Requirements

### Requirement: Local ledger data is persisted with SwiftData
The native app SHALL provide a production local ledger data source backed by SwiftData and hidden behind the existing ledger repository contract, with additive optional storage for record currency and participant currency projections.

#### Scenario: Local source persists ledger data across source recreation
- **WHEN** a local group with participants and records in one or more currencies is created through the SwiftData local source
- **AND** the data source is recreated using the same persistent SwiftData store
- **THEN** the group, participants, records, record currencies, currency projections, timestamps, archive state, and settlement flags are loaded from persistence
- **AND** projected repository results use the currency-aware `WalkGroup`, `Member`, and `WalkRecord` domain shapes

#### Scenario: Historical SwiftData rows remain readable
- **WHEN** an existing SwiftData store contains records and participants without the additive currency properties
- **THEN** the local source resolves them using the group's persisted default currency and existing scalar projection values
- **AND** it does not require deleting or recreating the local store

#### Scenario: SwiftData models do not leak into UI state
- **WHEN** the UI-facing store receives data from the local source
- **THEN** it receives repository/domain structs rather than SwiftData model instances
- **AND** views and panels do not need to import or query SwiftData directly

### Requirement: Local balance and settlement calculations are deterministic
The SwiftData local source SHALL derive balances and settlement suggestions deterministically and independently per record currency from persisted records.

#### Scenario: Expense split updates payer and participants
- **WHEN** a local expense is recorded with a payer, amount, split participants, and currency
- **THEN** the local source increases the payer's paid/cost projection in that currency as appropriate
- **AND** distributes participant shares in that currency using existing money helper semantics
- **AND** stores balances as minor-unit strings compatible with existing money display logic

#### Scenario: Settlement suggestion balances receivers and payers
- **WHEN** a local group has members with positive and negative balances in one requested currency
- **THEN** the local source returns deterministic transfers from payers to receivers using only that currency
- **AND** each transfer amount is positive
- **AND** applying all generated settlement records brings that currency's local member balances to zero unless rounding or existing data prevents exact settlement
- **AND** balances in other currencies remain unchanged
