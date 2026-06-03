## ADDED Requirements

### Requirement: Ledger access is mediated by a unified repository
The native app SHALL route UI-facing ledger reads and mutations through a unified repository contract rather than requiring views or UI-facing store methods to directly choose between local storage and remote API calls.

#### Scenario: Store loads home groups through the repository
- **WHEN** the UI-facing store refreshes the groups home data
- **THEN** it requests the home group collection through the ledger repository
- **AND** it receives domain-level group data, total balance data, pagination metadata, and source metadata
- **AND** it does not directly construct HTTP requests or local persistence queries for that operation

#### Scenario: Store mutates a record through the repository
- **WHEN** the UI-facing store adds, edits, or deletes a ledger record
- **THEN** it sends the mutation to the ledger repository using domain-level input values
- **AND** the repository returns a structured operation outcome
- **AND** the store updates published UI state from that outcome without knowing the concrete source implementation details

### Requirement: Ledger source mode is distinct from account login state
The native app SHALL represent ledger source availability independently from whether an account session is currently authenticated.

#### Scenario: No account session still has a local source
- **WHEN** there is no authenticated account token
- **AND** a local ledger source is available
- **THEN** the repository can satisfy source-agnostic local ledger operations
- **AND** it does not classify all ledger access as login-required solely because no token exists

#### Scenario: Remote-only operation requires authentication
- **WHEN** the user requests a remote-only operation such as joining a shared group by code or searching registered users
- **AND** no authenticated account session is available
- **THEN** the repository returns an authentication-required outcome
- **AND** it does not attempt the remote API call

#### Scenario: Signed-in user can still have local ledgers
- **WHEN** an account session is authenticated
- **AND** local-only ledgers also exist
- **THEN** the repository can expose local source metadata alongside remote-backed group metadata
- **AND** it does not require all local data to be uploaded before it can be displayed

### Requirement: Concrete ledger sources implement a shared contract
The system SHALL define concrete source implementations behind a common data-source contract for remote server access and local ledger access.

#### Scenario: Remote source wraps existing backend APIs
- **WHEN** the repository uses the remote ledger source
- **THEN** the source calls the existing WalkCalc backend API routes for groups, records, balances, members, and settlements
- **AND** it preserves existing pagination and structured search behavior
- **AND** it keeps bearer token and refresh-handling concerns out of views

#### Scenario: Local source can satisfy source-agnostic ledger operations
- **WHEN** the repository uses a local ledger source
- **THEN** the source can create groups, manage temporary members, create/edit/delete records, search loaded or persisted records, and provide balance/settlement data through the same repository-facing shapes
- **AND** it uses stable local identifiers that can later be mapped to remote identifiers

### Requirement: Repository outcomes are structured by failure and capability
The repository SHALL return structured outcomes that distinguish validation failures, authentication-required failures, source-unavailable failures, recoverable network failures, and unrecoverable authentication failures.

#### Scenario: Validation failure is local to the operation
- **WHEN** a mutation input is invalid, such as an invalid amount or missing split participant
- **THEN** the repository returns a validation failure outcome
- **AND** the store can present the existing localized feedback without treating the failure as an auth or network problem

#### Scenario: Remote authentication cannot be recovered
- **WHEN** a remote source operation fails because authentication cannot be refreshed or recovered
- **THEN** the repository returns an unrecoverable authentication outcome
- **AND** the store routes it through the existing session-expired handling path

#### Scenario: Source is unavailable
- **WHEN** an operation requires a source that is not configured or not available
- **THEN** the repository returns a source-unavailable outcome
- **AND** the store does not report it as a successful empty ledger result

### Requirement: Upper UI logic remains source-agnostic for common ledger workflows
Common ledger workflows SHALL keep one upper-layer control flow for local and remote data wherever the business operation is equivalent.

#### Scenario: Create group uses one store method
- **WHEN** the user creates a group from the existing create-group sheet
- **THEN** the UI-facing store uses one create-group method
- **AND** the repository decides whether the group is created locally, remotely, or rejected because the requested capabilities require authentication

#### Scenario: Record editor uses one mutation path
- **WHEN** the user submits the record editor
- **THEN** the editor can call the same store method for local-backed and remote-backed groups
- **AND** the store delegates source-specific persistence to the repository

#### Scenario: Group detail uses source metadata only for capability gating
- **WHEN** group detail renders a local-backed or remote-backed group
- **THEN** shared ledger content such as summary, balances, records, search, and temporary members uses the same UI state shape
- **AND** source metadata is used only where capabilities differ, such as remote invite, share, or sync affordances

### Requirement: Remote-backed behavior is preserved during migration
The repository migration SHALL preserve the current authenticated remote ledger behavior unless a later specification explicitly changes it.

#### Scenario: Authenticated home remote loading is unchanged
- **WHEN** an authenticated user refreshes the groups home screen after this migration
- **THEN** the remote source requests the existing home summary and group collection contracts
- **AND** the store publishes the same group list, group total, pagination state, and total balance semantics as before the migration

#### Scenario: Remote pagination is unchanged
- **WHEN** an authenticated user loads more groups, records, or member-specific records
- **THEN** the remote source uses the same page and page-size semantics as before
- **AND** the store appends or caches returned items in the same order and with the same total-count behavior as before

#### Scenario: Remote record search is unchanged
- **WHEN** an authenticated user searches records in a group
- **THEN** the remote source sends the same structured note/category OR search request as before
- **AND** already-loaded local matches can still provide interim feedback
- **AND** the final displayed results reconcile with the remote response using the same semantics as before

#### Scenario: Remote mutations preserve follow-up refresh behavior
- **WHEN** an authenticated user creates, updates, deletes, archives, unarchives, or settles remote ledger data
- **THEN** the remote source performs the same backend mutation contract as before
- **AND** the store refreshes affected home, group, record, balance, or search caches with the same behavior as before

#### Scenario: Remote auth failure semantics are unchanged
- **WHEN** a remote operation encounters an expired access token, missing token, or unrecoverable authentication failure
- **THEN** the repository preserves the distinction between refreshable auth rejection, authentication-required operation, and unrecoverable authentication loss
- **AND** the store keeps the existing session refresh, session-expired routing, and quiet recoverable-failure behavior

### Requirement: Verification covers abstraction and regression risks
The implementation SHALL include verification that separately exercises repository behavior and existing remote-flow regression risk.

#### Scenario: Fake source verifies repository contract
- **WHEN** repository-level verification runs with an in-memory or fake data source
- **THEN** it covers source-agnostic group, member, record, search, balance, and settlement operations
- **AND** it covers structured validation, authentication-required, source-unavailable, and success outcomes

#### Scenario: Remote source verifies existing backend contracts
- **WHEN** remote-source verification runs with authenticated access
- **THEN** it confirms that home loading, group pagination, group detail, balances, record pagination, record search, member-record loading, and mutations still use the existing backend contracts

#### Scenario: Store migration verifies published state compatibility
- **WHEN** a store method is migrated from direct API calls to repository calls
- **THEN** verification confirms that the relevant published store state and user-facing feedback match the prior behavior for the same successful and failing operation
