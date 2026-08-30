## ADDED Requirements

### Requirement: Records preserve an independent currency
The system SHALL associate each expense and settlement record with one normalized ISO currency code without requiring exchange-rate conversion.

#### Scenario: New client supplies record currency
- **WHEN** a client creates or updates a record with a valid currency code
- **THEN** the server and local ledger persist that currency on the record
- **AND** subsequent reads return the same normalized currency

#### Scenario: Legacy client omits record currency
- **WHEN** a deployed client creates or updates a record without a currency code
- **THEN** the ledger uses the group's current default currency
- **AND** the request remains valid without changing the existing request shape

#### Scenario: Historical record has no stored currency
- **WHEN** the server or local source reads a historical record that predates record currency
- **THEN** it exposes the group currency as the record's effective currency

### Requirement: Participant projections are separated by currency
The system SHALL maintain balance and statistic buckets independently for every currency used by each participant while preserving the existing scalar compatibility fields.

#### Scenario: Expenses in two currencies affect separate buckets
- **WHEN** a participant is involved in CNY and USD expense records
- **THEN** the participant projection contains independent CNY and USD balance/statistic buckets
- **AND** neither currency bucket includes values from the other

#### Scenario: Legacy projection has no currency buckets
- **WHEN** a projection created by an older server has scalar values but no currency buckets
- **THEN** the system interprets those scalar values in the group's persisted default currency
- **AND** a later mutation can materialize that bucket without losing the scalar values

#### Scenario: Legacy scalar projection remains populated
- **WHEN** any currency-specific record mutation succeeds
- **THEN** the server updates both the corresponding currency bucket and the existing scalar projection fields

### Requirement: Settlement is independent per currency
The system SHALL calculate and create settlement transfers for exactly one currency at a time.

#### Scenario: Suggest one currency
- **WHEN** a member requests a settlement suggestion for USD
- **THEN** the backend uses only USD participant balance buckets
- **AND** every returned transfer is denominated in USD

#### Scenario: Legacy settlement request omits currency
- **WHEN** an older client requests or resolves settlement without a currency code
- **THEN** the backend operates only on the group's current default currency
- **AND** balances in every other currency remain unchanged

#### Scenario: Resolve currencies separately
- **WHEN** a group has unsettled CNY and USD balances
- **AND** the group resolves CNY
- **THEN** CNY balances become settled
- **AND** USD balances and USD settlement suggestions remain unchanged

### Requirement: Multi-currency fields are additive
The system MUST preserve existing WalkCalc API field names and types while exposing currency-aware fields for upgraded clients.

#### Scenario: Old client reads a multi-currency response
- **WHEN** a response includes new record or projection currency fields
- **THEN** all previously required scalar fields remain present with their existing types
- **AND** the old client can ignore the additive fields

#### Scenario: Home summary remains compatible
- **WHEN** the backend returns a multi-currency home summary
- **THEN** `totalBalance` remains present with its existing compatibility calculation
- **AND** `balances` reports independent totals by currency for upgraded clients

### Requirement: Unsettled rules inspect every currency
The system SHALL evaluate financial completion rules across all currency buckets without netting one currency against another.

#### Scenario: Equal and opposite currencies remain unsettled
- **WHEN** a participant has a positive CNY balance and an equal numeric negative USD balance
- **THEN** the participant and group remain unsettled

#### Scenario: Archive requires every currency settled
- **WHEN** any participant has a non-zero balance in any currency
- **THEN** group archive is rejected under the existing unsettled-group rule

### Requirement: Record currency selection reuses the shared picker
The native client SHALL let a user select an expense record currency through the existing searchable currency picker.

#### Scenario: New group draft has no cached record currency
- **WHEN** a user opens the first new-expense draft for a group
- **THEN** the selected record currency is the group's default currency

#### Scenario: User selects a different record currency
- **WHEN** the user taps the currency symbol and selects a currency
- **THEN** the draft uses that currency
- **AND** the client caches it locally for the next new-expense draft in the same group

#### Scenario: Existing record is edited
- **WHEN** the user opens an existing record for editing
- **THEN** the editor starts from that record's effective currency instead of the cached draft preference

### Requirement: Default currency does not rewrite draft preference
The group settings screen SHALL describe the existing group currency as `Default currency` and SHALL use it only as the first record-currency selection when no per-group preference exists.

#### Scenario: Default currency changes after a record preference exists
- **WHEN** a group has a locally cached last record currency
- **AND** its default currency changes
- **THEN** the cached record currency and any open draft currency remain unchanged

### Requirement: Client presents currencies independently
The native client SHALL present balance and settlement amounts with their own currency codes and SHALL NOT use the legacy mixed scalar when currency buckets are available.

#### Scenario: Group summary contains multiple currencies
- **WHEN** the current user has balances in multiple currencies inside one group
- **THEN** the group summary card exposes the same per-currency carousel behavior as the home summary card

#### Scenario: Settlement suggestions contain multiple currencies
- **WHEN** a group has settlement transfers in multiple currencies
- **THEN** each transfer is displayed as an independent row using its own currency
- **AND** rows are sorted by absolute numeric amount without currency conversion
- **AND** resolving a row creates a settlement only in that row's currency
