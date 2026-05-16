## ADDED Requirements

### Requirement: Record Save Shows Local Submission Progress
The system SHALL show local submission progress in the record editor while a valid new or edited record is being saved.

#### Scenario: New expense save is pending
- **WHEN** a user creates a new expense with valid values and taps save
- **THEN** the save confirmation action replaces its `checkmark` with an indeterminate progress indicator
- **AND** the editor remains open until the save request succeeds
- **AND** duplicate save submissions are prevented while the request is pending

#### Scenario: Existing record save is pending
- **WHEN** a user edits an existing record with valid values and taps save
- **THEN** the save confirmation action replaces its `checkmark` with an indeterminate progress indicator
- **AND** the editor remains open until the update request succeeds
- **AND** duplicate save submissions are prevented while the request is pending

#### Scenario: Record save fails
- **WHEN** a new or edited record save request fails
- **THEN** the record editor remains open
- **AND** the user's draft values remain visible
- **AND** the save progress indicator stops
- **AND** retry remains available after the pending state clears

## MODIFIED Requirements

### Requirement: Existing Record Persists Only On Save
The system MUST NOT persist existing-record changes until the user confirms the edit.

#### Scenario: Idle view has no persistence
- **WHEN** a user opens and dismisses an existing record without confirming an edit
- **THEN** no record update request is sent

#### Scenario: Cancel does not persist
- **WHEN** a user enters edit mode on an existing record and chooses cancel
- **THEN** unsaved local changes are discarded
- **AND** no record update request is sent
- **AND** the editor closes

#### Scenario: Save persists valid edit
- **WHEN** a user enters edit mode on an existing record, provides valid values, and chooses save
- **THEN** the existing record update request is sent with the edited values
- **AND** local save progress is visible while the request is pending
- **AND** the editor closes after a successful update
- **AND** the editor remains open with the draft preserved if the update fails
