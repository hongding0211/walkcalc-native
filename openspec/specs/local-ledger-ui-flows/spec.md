# local-ledger-ui-flows Specification

## Purpose
Define how native UI workflows create, display, mutate, and gate local-backed ledger data through the existing repository and view surfaces.

## Requirements

### Requirement: UI-facing store can select local ledger contexts
The native app SHALL allow UI-facing store operations to use a local ledger context for source-agnostic ledger workflows.

#### Scenario: Store creates a local group through the repository
- **WHEN** the active or requested ledger source is local
- **AND** the user submits the existing create-group flow
- **THEN** the store calls the ledger repository with a local ledger context
- **AND** the SwiftData local source persists the group
- **AND** the store publishes the created group through the existing home state shape

#### Scenario: Store refreshes a local group through source metadata
- **WHEN** a group is known to be local-backed
- **AND** the UI requests group detail refresh
- **THEN** the store calls the repository with a local context for that group
- **AND** the resulting group, balances, records, and pagination are projected through existing `WalkGroup`, `Member`, and `WalkRecord` state

#### Scenario: Remote group context remains remote
- **WHEN** a group is known to be remote-backed
- **AND** the UI requests a read or mutation for that group
- **THEN** the store calls the repository with a remote context
- **AND** existing authenticated remote behavior is preserved

### Requirement: Existing local-capable UI flows reuse current surfaces
The native app SHALL support local-backed ledger CRUD through the same visible screens and sheets used by remote-backed groups wherever the operation is source-agnostic.

#### Scenario: Local group detail uses existing detail UI
- **WHEN** the user opens a local-backed group
- **THEN** the app shows the existing group detail layout
- **AND** summary, balances, expenses, search, and add-record controls use the same UI state shape as remote groups

#### Scenario: Local records use existing editor
- **WHEN** the user adds, edits, or deletes a record in a local-backed group
- **THEN** the existing record editor and delete confirmation paths are used
- **AND** the mutation is persisted locally
- **AND** affected home, group, record, balance, and search caches are refreshed or invalidated consistently

#### Scenario: Local group settings use existing controls
- **WHEN** the user renames, archives, unarchives, or deletes a local-backed group
- **THEN** the existing group settings or row action controls are used
- **AND** the mutation is persisted locally
- **AND** the visible group list updates without requiring a remote account

### Requirement: Local temporary-member flows remain available
The native app SHALL allow temporary-member management for local-backed groups without requiring an account.

#### Scenario: Temporary member is added to a local group
- **WHEN** the user adds a temporary member from create-group, people setup, or group settings
- **AND** the target group or new group is local-backed
- **THEN** the existing temporary-member UI submits through the store
- **AND** the repository uses the local source
- **AND** the member appears in local balances, split selection, and participant previews

#### Scenario: Registered member search is not treated as local temporary-member creation
- **WHEN** the user attempts to search or invite registered users for a local-backed group without an account
- **THEN** the app returns or presents authentication-required feedback
- **AND** it does not create local registered members from remote user IDs
- **AND** temporary-member creation remains available as the local alternative

### Requirement: Remote-only workflows are capability-gated
The native app SHALL keep account-dependent workflows remote-only and SHALL communicate authentication requirements without mutating local data.

#### Scenario: Join group requires remote authentication
- **WHEN** the user submits a group code while unauthenticated
- **THEN** the join operation returns authentication-required feedback
- **AND** no local group is created as a fallback

#### Scenario: Invite registered users requires remote authentication
- **WHEN** the user attempts to invite registered users while unauthenticated
- **THEN** the invite operation returns authentication-required feedback
- **AND** no local participants are created from registered-user IDs

#### Scenario: Search registered users requires remote authentication
- **WHEN** the user searches registered users while unauthenticated
- **THEN** the search operation returns authentication-required feedback or an empty gated result
- **AND** it does not query or expose local temporary members as registered users

### Requirement: Source awareness is minimal and capability-driven
The native app SHALL expose local-versus-remote state only where it changes available capabilities or prevents user confusion.

#### Scenario: Local group can be identified without changing the main workflow
- **WHEN** a local-backed group is displayed
- **THEN** the app may show a quiet local indicator such as `On this device`
- **AND** the main create, edit, delete, balance, and record workflows remain visually consistent with remote groups

#### Scenario: Source differences do not split the home UI into separate apps
- **WHEN** the Groups home displays local-backed and remote-backed data
- **THEN** it uses the existing Groups page structure
- **AND** it does not require the user to choose a separate local app section before creating or editing source-agnostic ledger data

### Requirement: Unauthenticated launch enters local Groups home
The native app SHALL route unauthenticated startup to the existing Groups home using the local ledger source.

#### Scenario: Startup without token shows local empty state
- **WHEN** the app launches without an authenticated token
- **THEN** the store selects a local ledger context
- **AND** the app shows the existing Groups home structure
- **AND** an empty local ledger appears as the existing no-groups empty state

#### Scenario: Authenticated startup remains remote
- **WHEN** the app launches with a valid authenticated token
- **THEN** the store selects the remote ledger context
- **AND** existing account-backed home loading behavior is preserved

#### Scenario: Logout returns to local home
- **WHEN** the user logs out or an unrecoverable authentication failure clears the token
- **THEN** the app returns to the Groups home in local mode
- **AND** no login screen blocks local group creation

### Requirement: Verification covers local UI parity and remote regression
The implementation SHALL verify that local-backed UI flows work through existing surfaces and that remote-backed behavior is not regressed.

#### Scenario: Local store verification covers source-agnostic CRUD
- **WHEN** local store/UI verification runs
- **THEN** it covers local group creation, temporary member addition, record creation, record editing, record deletion, record search, group rename/archive/delete, balances, and settlement

#### Scenario: Remote-only capability verification protects local data
- **WHEN** unauthenticated remote-only operations are attempted
- **THEN** verification confirms they return authentication-required or capability-gated outcomes
- **AND** local persisted data remains unchanged

#### Scenario: Native app still builds
- **WHEN** implementation is complete
- **THEN** the native iOS app builds successfully
- **AND** existing SwiftData and repository debug verifications still pass where available
