# swiftdata-local-ledger-source Specification

## ADDED Requirements

### Requirement: Local ledger data is persisted with SwiftData
The native app SHALL provide a production local ledger data source backed by SwiftData and hidden behind the existing ledger repository contract.

#### Scenario: Local source persists ledger data across source recreation
- **WHEN** a local group with participants and records is created through the SwiftData local source
- **AND** the data source is recreated using the same persistent SwiftData store
- **THEN** the group, participants, records, timestamps, archive state, and settlement flags are loaded from persistence
- **AND** projected repository results use the existing `WalkGroup`, `Member`, and `WalkRecord` domain shapes

#### Scenario: SwiftData models do not leak into UI state
- **WHEN** the UI-facing store receives data from the local source
- **THEN** it receives repository/domain structs rather than SwiftData model instances
- **AND** views and panels do not need to import or query SwiftData directly

### Requirement: Local source supports source-agnostic ledger reads
The SwiftData local ledger source SHALL support the same repository read operations as the remote source wherever the operation does not require registered account identity.

#### Scenario: Home groups load locally
- **WHEN** the repository requests local home data with a page, page size, and optional group search
- **THEN** the local source returns a paginated list of local groups
- **AND** the pagination total reflects the filtered local result set
- **AND** the home snapshot includes the local owner's total balance across matching available local groups
- **AND** the snapshot identifies the source as local

#### Scenario: Group detail loads locally
- **WHEN** the repository requests local group detail
- **THEN** the local source returns the projected group and first page of records
- **AND** record pagination total reflects the full local record count for that group
- **AND** records are ordered newest-first consistently with the current local ledger behavior

#### Scenario: Local record search follows structured search semantics
- **WHEN** the repository requests local records with structured search conditions
- **THEN** the local source matches only the supported requested fields
- **AND** note and localized category-name conditions use OR semantics when requested
- **AND** fields not included in the structured request do not broaden the result set

#### Scenario: Member records load locally
- **WHEN** the repository requests records for a local participant
- **THEN** the local source returns only records where that participant paid or appears in `forWhom`
- **AND** pagination total reflects the filtered member-specific record set

### Requirement: Local source supports source-agnostic ledger mutations
The SwiftData local ledger source SHALL persist local mutations equivalent to backend-supported ledger mutations when those mutations can be performed without registered account identity.

#### Scenario: Local group is created with an owner member
- **WHEN** the repository creates a local group
- **THEN** the local source persists a group with a stable local group ID
- **AND** it persists the local owner as the initial non-temporary participant
- **AND** it returns the created local group ID through the repository mutation response

#### Scenario: Temporary members are added locally
- **WHEN** the repository adds a temporary member to a local group
- **THEN** the local source persists a participant with a stable local member ID
- **AND** marks the participant as temporary
- **AND** updates group participant count and preview projections

#### Scenario: Expense records are mutated locally
- **WHEN** the repository adds, updates, or deletes a local expense record
- **THEN** the local source persists the change
- **AND** recomputes member debts, costs, record counts, group modified timestamp, participant summary, and unresolved-balance state

#### Scenario: Settlement records are created locally
- **WHEN** the repository creates a local settlement record or resolves all local debts
- **THEN** the local source persists settlement records using stable local record IDs
- **AND** marks them as debt-resolution records
- **AND** recomputes balances so resolved debts are reflected in subsequent group and home reads

#### Scenario: Local groups are renamed, archived, unarchived, and deleted
- **WHEN** the repository renames, archives, unarchives, or deletes a local group
- **THEN** the local source persists the corresponding group state
- **AND** deleting a group removes its local participants and records from the SwiftData store

### Requirement: Local balance and settlement calculations are deterministic
The SwiftData local source SHALL derive balances and settlement suggestions deterministically from persisted records.

#### Scenario: Expense split updates payer and participants
- **WHEN** a local expense is recorded with a payer, amount, and split participants
- **THEN** the local source increases the payer's paid/cost projection as appropriate
- **AND** distributes participant shares using existing money helper semantics
- **AND** stores balances as minor-unit strings compatible with existing money display logic

#### Scenario: Settlement suggestion balances receivers and payers
- **WHEN** a local group has members with positive and negative balances
- **THEN** the local source returns deterministic transfers from payers to receivers
- **AND** each transfer amount is positive
- **AND** applying all generated settlement records brings local member balances to zero unless rounding or existing data prevents exact settlement

### Requirement: Account-dependent operations remain unavailable locally
The SwiftData local source SHALL not fabricate registered account behavior for operations that require remote identity.

#### Scenario: Joining a shared group requires an account
- **WHEN** the repository asks the local source to join a group by code
- **THEN** the local source returns an authentication-required or capability failure
- **AND** it does not create or mutate any local group

#### Scenario: Searching registered users requires an account
- **WHEN** the repository asks the local source to search registered users
- **THEN** the local source returns an authentication-required or capability failure
- **AND** it does not return local temporary members as registered users

#### Scenario: Inviting registered users requires an account
- **WHEN** the repository asks the local source to invite registered user IDs into a local group
- **THEN** the local source returns an authentication-required or capability failure
- **AND** it does not create local registered participants from remote user IDs

### Requirement: Verification covers SwiftData persistence and local parity
The implementation SHALL include verification for the SwiftData local source separately from remote-source regression checks.

#### Scenario: In-memory SwiftData verification covers local operations
- **WHEN** local source verification runs with an in-memory SwiftData container
- **THEN** it covers local group creation, temporary members, expense mutations, settlement mutations, group mutations, pagination, search, member records, and balance recomputation

#### Scenario: Persistent SwiftData verification covers relaunch behavior
- **WHEN** local source verification writes data to a temporary persistent SwiftData store
- **AND** recreates the container and data source
- **THEN** the same local domain projections are returned from the recreated source

#### Scenario: Capability verification covers account-only operations
- **WHEN** local source verification calls join group, invite registered users, and search registered users
- **THEN** each operation returns an account-required or capability failure
- **AND** persisted local data remains unchanged
