## MODIFIED Requirements

### Requirement: Concrete ledger sources implement a shared contract
The system SHALL define concrete source implementations behind a common data-source contract for remote server access and local ledger access, including additive record-currency, currency-balance, and currency-settlement data.

#### Scenario: Remote source wraps existing backend APIs
- **WHEN** the repository uses the remote ledger source
- **THEN** the source calls the existing WalkCalc backend API routes for groups, records, balances, members, and settlements
- **AND** it preserves existing pagination and structured search behavior
- **AND** it decodes additive record currency and participant currency-balance fields while retaining scalar fallbacks
- **AND** it keeps bearer token and refresh-handling concerns out of views

#### Scenario: Local source can satisfy source-agnostic ledger operations
- **WHEN** the repository uses a local ledger source
- **THEN** the source can create groups, manage temporary members, create/edit/delete currency-denominated records, search loaded or persisted records, and provide currency-specific balance/settlement data through the same repository-facing shapes
- **AND** it uses stable local identifiers that can later be mapped to remote identifiers

#### Scenario: Existing callers omit record currency
- **WHEN** an existing repository caller creates or updates a record without supplying the additive currency input
- **THEN** the source uses the group's default currency
- **AND** the existing source-agnostic call remains valid
