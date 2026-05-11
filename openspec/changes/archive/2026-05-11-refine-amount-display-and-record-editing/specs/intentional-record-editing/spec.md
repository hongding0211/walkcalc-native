## ADDED Requirements

### Requirement: Existing Record Delete Remains Available
The system SHALL show the delete action for an existing record even when the editor is opened in idle viewing state.

#### Scenario: Existing record opens with delete action
- **WHEN** a user opens an existing record editor
- **THEN** the top cancellation and confirmation edit actions are not visible
- **AND** the delete action is visible for that record
- **AND** the record values are visible for inspection

#### Scenario: Delete confirmation remains explicit
- **WHEN** a user taps the delete action from an existing record editor
- **THEN** the system asks for delete confirmation before deleting the record
- **AND** no record update request is sent as part of showing the delete confirmation

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
- **AND** the editor closes after a successful update
