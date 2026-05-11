# intentional-record-editing Specification

## Purpose
Define how record editing separates idle inspection, explicit edit intent, persistence, cancellation, and destructive delete availability.
## Requirements
### Requirement: Existing Record Opens Idle
The system SHALL open an existing record editor in an idle viewing state until the user expresses editing intent.

#### Scenario: Existing record does not auto-focus
- **WHEN** a user opens an existing record from an expense row or member balance record list
- **THEN** no text input is focused automatically
- **AND** the software keyboard is not presented by default

#### Scenario: Existing record hides edit toolbar actions
- **WHEN** an existing record editor first appears
- **THEN** the top cancellation and confirmation edit actions are not visible
- **AND** the record values are visible for inspection

### Requirement: New Expense Remains Editable
The system SHALL preserve the existing new-expense creation behavior as an explicitly editable flow.

#### Scenario: New expense opens ready for input
- **WHEN** a user opens the new expense sheet
- **THEN** the sheet may focus the amount field by default
- **AND** save and cancel actions are available as part of the creation flow

### Requirement: Edit Intent Reveals Actions
The system SHALL enter edit mode for an existing record after the user interacts with an editable control.

#### Scenario: Text input starts editing
- **WHEN** a user focuses the amount field or note field in an existing record editor
- **THEN** the editor enters edit mode
- **AND** cancellation and confirmation edit actions are shown

#### Scenario: Control interaction starts editing
- **WHEN** a user interacts with paid-by, split members, category, or date controls in an existing record editor
- **THEN** the editor enters edit mode
- **AND** cancellation and confirmation edit actions are shown

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
