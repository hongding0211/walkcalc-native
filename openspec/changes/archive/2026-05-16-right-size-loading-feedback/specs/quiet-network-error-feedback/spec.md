## MODIFIED Requirements

### Requirement: User-initiated failures stay local to the initiating action
The system SHALL surface failed user-initiated network actions in the local context of the action instead of using a generic global network alert.

#### Scenario: Join group request fails
- **WHEN** the user submits a group ID and the join request fails
- **THEN** the join sheet remains open
- **AND** the system displays concise failure feedback inside the join sheet
- **AND** it does not present a global modal "Network issues" alert

#### Scenario: Sheet mutation request fails
- **WHEN** the user submits a create, rename, archive, delete, member, record, or settlement action from a sheet or detail surface and the request fails
- **THEN** the initiating surface remains in a state where the user can retry or cancel
- **AND** any local progress indicator for that submitted action stops
- **AND** the system does not show generic fallback copy such as "Add fail", "Edit fail", or "Network issues"
- **AND** the system only shows local feedback when the failure contains a specific actionable validation or business-rule message
- **AND** it does not present a generic global network alert

#### Scenario: Business rule failure is not treated as transport failure
- **WHEN** the server rejects a user-initiated action with a validation, authorization, settlement-limit, duplicate, or other business-rule message
- **THEN** the system presents that message in the local action context when it is safe and useful
- **AND** it does not replace the message with a generic "Network issues" alert

#### Scenario: Submitted action fails after local progress was shown
- **WHEN** a user-initiated action fails after displaying local submission progress
- **THEN** the progress indicator is removed from the initiating control or surface
- **AND** the action can be attempted again after the pending state clears
- **AND** the current input, selected record, selected group, or current sheet context is preserved when possible
