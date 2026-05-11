# complete-balance-member-visibility Specification

## Purpose
TBD - created by archiving change soften-record-edit-and-balance-display. Update Purpose after archive.
## Requirements
### Requirement: Balance Preview Includes All Members
The group detail balance preview SHALL use the complete group participant list as its source, including the current user.

#### Scenario: Current user appears in balance preview source
- **WHEN** a group contains the current user and other participants
- **THEN** the balances section considers the current user eligible for display
- **AND** the preview rows use the same row presentation and record-count behavior as other members

#### Scenario: Preview cap remains available
- **WHEN** the complete participant list is longer than the preview limit
- **THEN** the balances section may continue to show a limited preview
- **AND** the "View details" entry opens the complete participant list

### Requirement: Balance Details Includes All Members
The balances workspace SHALL list every group participant, including the current user, regular members, and temporary members.

#### Scenario: View details uses complete participant list
- **WHEN** a user opens balance details from the group detail page
- **THEN** the list includes every member from the group's complete participant set
- **AND** the current user is not filtered out

#### Scenario: Selecting current user opens detail
- **WHEN** a user selects the current user's balance row
- **THEN** the app opens a member balance detail page for the current user

### Requirement: Member Balance Detail Uses Selected Member
The member balance detail page SHALL filter records according to the selected member, regardless of whether that member is the current user.

#### Scenario: Current user detail filters records consistently
- **WHEN** the selected member is the current user
- **THEN** the records list includes records where the current user paid
- **AND** the records list includes records where the current user is included in `forWhom`

#### Scenario: Other member detail remains unchanged
- **WHEN** the selected member is not the current user
- **THEN** the records list includes records where that member paid
- **AND** the records list includes records where that member is included in `forWhom`

