## ADDED Requirements

### Requirement: Personal Settlement Preview Takes Priority
The group-detail Balances section SHALL prioritize every suggested settlement transfer involving the current participant over the member-balance preview.

#### Scenario: Current participant has suggested transfers
- **WHEN** one or more suggested settlement transfers name the current participant as payer or receiver
- **THEN** the Balances section displays every matching transfer without a preview limit
- **AND** it does not display member-balance preview rows in the same card
- **AND** the bottom entry is labeled `View details`

#### Scenario: Personal transfer rows are informational
- **WHEN** a current-participant transfer is displayed on group detail
- **THEN** the row has no direct resolve action or disclosure affordance
- **AND** settlement actions remain inside the balances workspace

#### Scenario: Personal transfer preview uses settlement presentation
- **WHEN** at least one current-participant transfer is displayed on group detail
- **THEN** the section heading is `Suggested settlement`
- **AND** the section preserves the group-detail preview's grouped-list container, row dividers, and integrated `View details` footer
- **AND** each informational row uses the same payer, receiver, direction, and content hierarchy as the balances workspace
- **AND** action-only labels and controls are omitted

#### Scenario: Current participant pays a transfer
- **WHEN** the current participant is the payer of a displayed transfer
- **THEN** the amount is red
- **AND** the amount has a `-` prefix

#### Scenario: Current participant receives a transfer
- **WHEN** the current participant is the receiver of a displayed transfer
- **THEN** the amount is green
- **AND** the amount has no `+` prefix

#### Scenario: Current participant has no suggested transfer
- **WHEN** no suggested settlement transfer involves the current participant
- **THEN** the Balances section uses the existing capped member-balance preview behavior

#### Scenario: Remote current participant identity
- **WHEN** the group is remote-backed
- **THEN** personal transfers are matched with the authenticated user UUID

#### Scenario: Local current participant identity
- **WHEN** the group is local-backed
- **THEN** personal transfers are matched with the persisted local-owner UUID

### Requirement: Balances Workspace Prioritizes Feedback And Settlement
The balances workspace SHALL present actionable context before the complete member list.

#### Scenario: Workspace has an error and settlement suggestions
- **WHEN** a balances-workspace error and suggested settlement transfers are present
- **THEN** the error appears first
- **AND** Suggested settlement appears after the error
- **AND** All balances appears after Suggested settlement

#### Scenario: Workspace has no error or suggestions
- **WHEN** no error or suggested settlement transfer is present
- **THEN** absent sections are omitted
- **AND** All balances remains available

## MODIFIED Requirements

### Requirement: Balance Preview Includes All Members
The group detail balance preview SHALL use the complete group participant list as its fallback source, including the current user, and SHALL prioritize the highest absolute balances when no personal settlement transfer is displayed.

#### Scenario: Current user appears in balance preview source
- **WHEN** a group contains the current user and other participants
- **AND** no suggested settlement transfer involving the current user is displayed
- **THEN** the balances section considers the current user eligible for display
- **AND** the preview rows use the same row presentation and record-count behavior as other members

#### Scenario: Preview cap remains available
- **WHEN** the complete participant list is longer than the preview limit
- **AND** no suggested settlement transfer involving the current user is displayed
- **THEN** the balances section shows the limited member preview
- **AND** the `View all` entry opens the complete participant list

#### Scenario: Preview orders balances by magnitude
- **WHEN** the member-balance fallback preview is displayed
- **THEN** participants are ordered by descending absolute balance regardless of sign
- **AND** equal absolute balances retain their original participant order

### Requirement: Balance Details Includes All Members
The balances workspace SHALL list every group participant, including the current user, regular members, and temporary members, ordered by descending absolute balance.

#### Scenario: View details uses complete participant list
- **WHEN** a user opens balance details from the group detail page
- **THEN** the list includes every member from the group's complete participant set
- **AND** the current user is not filtered out

#### Scenario: Selecting current user opens detail
- **WHEN** a user selects the current user's balance row
- **THEN** the app opens a member balance detail page for the current user

#### Scenario: Complete balances are ordered by magnitude
- **WHEN** All balances is displayed
- **THEN** participants are ordered by descending absolute balance regardless of sign
- **AND** equal absolute balances retain their original participant order
